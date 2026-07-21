defmodule Obscura.Recognizer.NER.Ortex do
  @moduledoc """
  Experimental Ortex-backed adapter for exported token-classification models.

  This is intentionally separate from `Obscura.Recognizer.GLiNER.Ortex`.
  GLiNER uses a prompt/span-scoring ONNX contract, while this module expects a
  standard token-classification graph with `input_ids`, `attention_mask`, and a
  `logits` output shaped as `{batch, sequence, labels}`.
  """

  alias Obscura.Analyzer.ModelOutput

  @behaviour Obscura.Recognizer

  @supported_entities [
    :credit_card,
    :date_time,
    :email,
    :id,
    :ip_address,
    :location,
    :organization,
    :password,
    :patient_id,
    :person,
    :phone,
    :street_address,
    :url,
    :us_driver_license,
    :us_ssn,
    :username,
    :zip_code
  ]

  defstruct [
    :model,
    :tokenizer,
    :id_to_label,
    :model_dir,
    execution_providers: [:cpu],
    input_names: ["input_ids", "attention_mask"],
    max_length: nil,
    trim_boundaries: true
  ]

  @type t :: %__MODULE__{}

  @impl Obscura.Recognizer
  def name, do: :ner_ortex

  @impl Obscura.Recognizer
  def supported_entities, do: @supported_entities

  @doc """
  Builds an experimental token-classification serving from local ONNX assets.
  """
  @spec build(keyword()) :: {:ok, t()} | {:error, term()}
  def build(opts \\ []) do
    deps = Keyword.get(opts, :dependency_checker, &Code.ensure_loaded?/1)

    with :ok <- ensure_dependency(deps, Module.concat([Ortex]), :ortex),
         :ok <- ensure_dependency(deps, Module.concat([Tokenizers, Tokenizer]), :tokenizers),
         {:ok, model_dir} <- model_dir(opts),
         {:ok, id_to_label} <- load_id_to_label(Path.join(model_dir, "config.json")),
         {:ok, tokenizer} <- load_tokenizer(Path.join(model_dir, "tokenizer.json")),
         {:ok, tokenizer} <- configure_tokenizer(tokenizer, Keyword.get(opts, :max_length)),
         {:ok, model} <-
           load_model(
             Path.join(model_dir, "model.onnx"),
             Keyword.get(opts, :execution_providers, [:cpu])
           ) do
      {:ok,
       %__MODULE__{
         model: model,
         tokenizer: tokenizer,
         id_to_label: id_to_label,
         model_dir: model_dir,
         execution_providers: Keyword.get(opts, :execution_providers, [:cpu]),
         input_names: Keyword.get(opts, :input_names, ["input_ids", "attention_mask"]),
         max_length: Keyword.get(opts, :max_length),
         trim_boundaries: Keyword.get(opts, :trim_boundaries, true)
       }}
    end
  end

  @doc """
  Runs token classification and returns raw model outputs suitable for
  `Obscura.Analyzer.ModelOutput.normalize/3`.
  """
  @spec run(t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def run(%__MODULE__{} = serving, text, opts \\ []) when is_binary(text) do
    with {:ok, encoded} <- encode(serving.tokenizer, text),
         {:ok, tensors} <- tensors(encoded, serving.input_names),
         {:ok, output} <- run_model(serving.model, tensors),
         {:ok, logits} <- output_logits(output),
         {:ok, rows} <- decode(logits, encoded, serving, text) do
      {:ok, maybe_filter_rows(rows, opts)}
    end
  end

  @doc false
  @spec debug_inputs(t(), String.t()) :: {:ok, map()} | {:error, term()}
  def debug_inputs(%__MODULE__{} = serving, text) when is_binary(text) do
    encode(serving.tokenizer, text)
  end

  @doc false
  @spec debug_aggregate_tokens([map()], String.t(), keyword()) :: [map()]
  def debug_aggregate_tokens(tokens, text, opts \\ []) do
    aggregate_tokens(tokens, text, Keyword.get(opts, :trim_boundaries, true))
  end

  @doc """
  Runs token classification and normalizes directly to analyzer results.
  """
  @spec analyze(t() | String.t(), String.t() | keyword()) ::
          {:ok, [Obscura.Analyzer.Result.t()]} | {:error, term()}
  def analyze(%__MODULE__{} = subject, input) when is_binary(input) do
    analyze(subject, input, [])
  end

  @impl Obscura.Recognizer
  def analyze(subject, input) when is_binary(subject) and is_list(input) do
    with {:ok, serving} <- analyzer_serving(input) do
      analyze(
        serving,
        subject,
        input
        |> Keyword.put_new(:label_map, :openmed_pii_superclinical_small)
        |> Keyword.put_new(:include_text, false)
      )
    end
  end

  @spec analyze(t(), String.t(), keyword()) ::
          {:ok, [Obscura.Analyzer.Result.t()]} | {:error, term()}
  def analyze(%__MODULE__{} = serving, text, opts) when is_binary(text) do
    with {:ok, outputs} <- run(serving, text, opts) do
      ModelOutput.normalize(text, outputs, opts)
    end
  end

  defp analyzer_serving(opts) do
    case Keyword.get(opts, :serving) do
      %__MODULE__{} = serving -> {:ok, serving}
      nil -> {:error, :missing_ner_ortex_serving}
      _other -> {:error, :invalid_ner_ortex_serving}
    end
  end

  defp ensure_dependency(checker, module, app) do
    if checker.(module), do: :ok, else: {:error, {:missing_optional_dependency, app}}
  end

  defp model_dir(opts) do
    case Keyword.get(opts, :model_dir) || System.get_env("OBSCURA_NER_ORTEX_MODEL_DIR") do
      path when is_binary(path) -> {:ok, path}
      _other -> {:error, :missing_ner_ortex_model_dir}
    end
  end

  defp load_id_to_label(path) do
    with {:ok, raw} <- File.read(path),
         {:ok, config} <- Jason.decode(raw),
         %{} = id_to_label <- Map.get(config, "id2label") do
      {:ok, Map.new(id_to_label, fn {id, label} -> {String.to_integer(id), label} end)}
    else
      nil -> {:error, :missing_id_to_label}
      {:error, reason} -> {:error, {:invalid_model_config, reason}}
    end
  end

  defp load_tokenizer(path) do
    Tokenizers.Tokenizer.from_file(path)
  rescue
    error -> {:error, {:ner_ortex_tokenizer_load_failed, error.__struct__}}
  end

  defp configure_tokenizer(tokenizer, nil), do: {:ok, tokenizer}

  defp configure_tokenizer(tokenizer, max_length)
       when is_integer(max_length) and max_length > 0 do
    {:ok, Tokenizers.Tokenizer.set_truncation(tokenizer, max_length: max_length)}
  rescue
    error -> {:error, {:ner_ortex_tokenizer_configuration_failed, error.__struct__}}
  end

  defp configure_tokenizer(_tokenizer, max_length),
    do: {:error, {:invalid_ner_ortex_max_length, max_length}}

  defp load_model(path, execution_providers) do
    ortex = Module.concat([Ortex])
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    {:ok, apply(ortex, :load, [path, execution_providers])}
  rescue
    error -> {:error, {:ner_ortex_onnx_load_failed, error.__struct__}}
  end

  defp encode(tokenizer, text) do
    {:ok, encoding} = Tokenizers.Tokenizer.encode(tokenizer, text)

    {:ok,
     %{
       ids: Tokenizers.Encoding.get_ids(encoding),
       attention_mask: Tokenizers.Encoding.get_attention_mask(encoding),
       offsets: Tokenizers.Encoding.get_offsets(encoding)
     }}
  rescue
    error -> {:error, {:ner_ortex_tokenizer_encode_failed, error.__struct__}}
  end

  defp tensors(encoded, input_names) do
    values = %{
      "input_ids" => encoded.ids,
      "attention_mask" => encoded.attention_mask
    }

    tensors =
      input_names
      |> Enum.map(fn name -> Nx.tensor([Map.fetch!(values, name)], type: {:s, 64}) end)
      |> List.to_tuple()

    {:ok, tensors}
  rescue
    error -> {:error, {:ner_ortex_input_pack_failed, error.__struct__}}
  end

  defp run_model(model, tensors) do
    ortex = Module.concat([Ortex])
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    {:ok, apply(ortex, :run, [model, tensors])}
  rescue
    error -> {:error, {:ner_ortex_onnx_run_failed, error.__struct__}}
  end

  defp output_logits({logits}), do: {:ok, logits}
  defp output_logits(logits) when is_struct(logits, Nx.Tensor), do: {:ok, logits}
  defp output_logits(_other), do: {:error, :unsupported_ner_ortex_output}

  defp decode(logits, encoded, serving, text) do
    logits
    |> Nx.squeeze(axes: [0])
    |> Nx.to_list()
    |> Enum.zip(encoded.offsets)
    |> Enum.map(&token_prediction(&1, serving.id_to_label))
    |> aggregate_tokens(text, serving.trim_boundaries)
    |> then(&{:ok, &1})
  rescue
    error -> {:error, {:ner_ortex_decode_failed, error.__struct__}}
  end

  defp token_prediction({scores, {start, ending}}, id_to_label) do
    {logit, label_id} =
      scores
      |> Enum.with_index()
      |> Enum.max_by(fn {score, _index} -> score end)

    %{
      label: Map.fetch!(id_to_label, label_id),
      score: softmax_score(scores, label_id, logit),
      start: start,
      end: ending
    }
  end

  defp softmax_score(scores, label_id, logit) do
    max_score = Enum.max(scores)

    denominator =
      Enum.reduce(scores, 0.0, fn score, acc ->
        acc + :math.exp(score - max_score)
      end)

    :math.exp(logit - max_score) / denominator
  rescue
    _error -> if label_id, do: 1.0, else: 0.0
  end

  defp aggregate_tokens(tokens, text, trim_boundaries) do
    tokens
    |> Enum.reduce([], fn token, acc ->
      if ignored_token?(token), do: add_boundary(acc), else: merge_token(acc, token)
    end)
    |> Enum.reject(&(&1 == :boundary))
    |> Enum.reverse()
    |> Enum.map(&finalize_span(&1, text, trim_boundaries))
    |> Enum.reject(fn row -> row.start >= row.end end)
  end

  defp ignored_token?(%{label: "O"}), do: true
  defp ignored_token?(%{start: start, end: ending}), do: start == ending

  defp add_boundary([]), do: []
  defp add_boundary([:boundary | _rest] = acc), do: acc
  defp add_boundary(acc), do: [:boundary | acc]

  defp merge_token([], token), do: [new_span(token)]
  defp merge_token([:boundary | rest], token), do: [new_span(token) | rest]

  defp merge_token([current | rest], token) do
    label = base_label(token.label)

    if continuation?(token.label) and current.base_label == label do
      [%{current | end: token.end, scores: [token.score | current.scores]} | rest]
    else
      [new_span(token), current | rest]
    end
  end

  defp continuation?(label), do: String.starts_with?(label, ["I-", "E-"])

  defp new_span(token) do
    %{
      label: token.label,
      base_label: base_label(token.label),
      start: token.start,
      end: token.end,
      raw_start: token.start,
      raw_end: token.end,
      scores: [token.score]
    }
  end

  defp finalize_span(span, text, true) do
    {start, ending} = trim_boundaries(text, span.start, span.end)
    finalize_span(%{span | start: start, end: ending}, text, false)
  end

  defp finalize_span(span, _text, false) do
    %{
      label: span.base_label,
      start: span.start,
      end: span.end,
      score: Enum.sum(span.scores) / length(span.scores),
      offset_unit: :byte,
      metadata: %{
        adapter: "Obscura.Recognizer.NER.Ortex",
        raw_label: span.label,
        boundary_trimmed: span.start != span.raw_start or span.end != span.raw_end
      }
    }
  end

  defp trim_boundaries(text, start, ending) do
    trim_chars = [
      ?\s,
      ?\n,
      ?\r,
      ?\t,
      ?.,
      ?,,
      ?;,
      ?:,
      ?!,
      ??,
      ?(,
      ?),
      ?[,
      ?],
      ?{,
      ?},
      ?<,
      ?>,
      ?",
      ?',
      ?`
    ]

    ending = min(ending, byte_size(text))

    start =
      Stream.iterate(start, &(&1 + 1))
      |> Enum.find(start, fn index ->
        index >= ending or :binary.at(text, index) not in trim_chars
      end)

    ending =
      Stream.iterate(ending, &(&1 - 1))
      |> Enum.find(ending, fn index ->
        index <= start or :binary.at(text, index - 1) not in trim_chars
      end)

    {start, ending}
  end

  defp base_label(label) do
    String.replace(label, ~r/^(B|I|E|S|L|U)-/, "")
  end

  defp maybe_filter_rows(rows, opts) do
    case Keyword.get(opts, :labels) do
      labels when is_list(labels) -> Enum.filter(rows, &(&1.label in labels))
      _other -> rows
    end
  end
end
