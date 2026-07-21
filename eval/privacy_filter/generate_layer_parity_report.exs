defmodule Obscura.Eval.PrivacyFilter.LayerParityReport do
  alias Obscura.PrivacyFilter.Checkpoint
  alias Obscura.PrivacyFilter.LabelInfo
  alias Obscura.PrivacyFilter.Model
  alias Obscura.PrivacyFilter.Model.Linear
  alias Obscura.PrivacyFilter.Model.Parameters
  alias Obscura.PrivacyFilter.SequenceLabeling
  alias Obscura.PrivacyFilter.SequenceLabeling.TokenizedExample
  alias Obscura.PrivacyFilter.Serving
  alias Obscura.PrivacyFilter.Spans
  alias Obscura.PrivacyFilter.Tokenization
  alias Obscura.PrivacyFilter.Viterbi

  @fixture_path "eval/privacy_filter/fixtures/tiny_model_parity.json"
  @out_json "eval/reports/privacy_filter_layer_parity.json"
  @out_md "eval/reports/privacy_filter_layer_parity.md"

  def run do
    backend = configure_backend!()
    fixture = @fixture_path |> File.read!() |> Jason.decode!()
    tolerance = fixture["tolerance"]
    config = Map.new(fixture["config"], fn {key, value} -> {String.to_atom(key), value} end)

    params =
      Map.new(fixture["params"], fn {name, value} -> {name, Nx.tensor(value, type: {:f, 32})} end)

    token_ids = Nx.tensor(fixture["token_ids"], type: {:s, 64})
    {:ok, model_params} = Parameters.from_map(params, config)
    actual = Model.debug(token_ids, model_params, config)

    stages = tensor_stages(actual, fixture, tolerance)

    expert_indices =
      exact_stage(
        "mlp.expert_indices",
        hd(actual.blocks).mlp.expert_indices |> Nx.to_list(),
        fetch_path(fixture["python_stages"], ["blocks", 0, "mlp", "expert_indices"])
      )

    postprocessing = postprocessing_report(fixture["postprocessing"])
    window_report = tiny_window_report(fixture)
    real_checkpoint = real_checkpoint_report(fixture["real_checkpoint_reference"])

    python_original =
      python_original_report(fixture["python_original_reference"], backend, tolerance)

    all_entries =
      stages ++
        [expert_indices, window_report] ++
        postprocessing["checks"] ++
        python_original_model_checks(python_original) ++ python_original_checks(python_original)

    first_divergence = Enum.find(all_entries, &(not &1["passed"]))

    report = %{
      "run_id" => "privacy_filter_layer_parity",
      "fixture" => @fixture_path,
      "source" => fixture["source"],
      "tolerance" => tolerance,
      "backend" => backend,
      "tiny_model" => %{
        "stages" => stages,
        "exact_stages" => [expert_indices],
        "window_construction" => window_report,
        "postprocessing" => postprocessing
      },
      "real_checkpoint" => real_checkpoint,
      "python_original_checkpoint" => python_original,
      "first_divergence" => first_divergence,
      "conclusion" => conclusion(first_divergence, real_checkpoint, python_original)
    }

    File.mkdir_p!(Path.dirname(@out_json))
    File.write!(@out_json, Jason.encode!(report, pretty: true) <> "\n")
    File.write!(@out_md, render_markdown(report))
    IO.puts(@out_json)
    IO.puts(@out_md)
  end

  defp configure_backend! do
    case System.get_env("OBSCURA_PRIVACY_FILTER_BACKEND", "default") do
      value when value in ["", "default"] ->
        %{"requested_backend" => "default", "exla_enabled" => false}

      "binary" ->
        Nx.global_default_backend(Nx.BinaryBackend)
        %{"requested_backend" => "binary", "exla_enabled" => false}

      "exla" ->
        unless Code.ensure_loaded?(EXLA) and Code.ensure_loaded?(EXLA.Backend) do
          raise "EXLA is not available; fetch optional deps with OBSCURA_REAL_MODEL=1 mix deps.get"
        end

        {:ok, _started} = Application.ensure_all_started(:exla)
        Nx.global_default_backend(EXLA.Backend)
        %{"requested_backend" => "exla", "exla_enabled" => true}

      "emily" ->
        unless Code.ensure_loaded?(Emily) and Code.ensure_loaded?(Emily.Backend) and
                 Code.ensure_loaded?(Emily.Compiler) do
          raise "Emily is not available; fetch optional deps with OBSCURA_REAL_MODEL_BACKEND=emily mix deps.get"
        end

        fallback = System.get_env("OBSCURA_EMILY_FALLBACK", "raise")
        device = System.get_env("OBSCURA_EMILY_DEVICE", "gpu")
        fallback = String.to_atom(fallback)
        device = String.to_atom(device)
        Application.put_env(:emily, :fallback, fallback)
        {:ok, _started} = Application.ensure_all_started(:emily)
        Nx.global_default_backend({Emily.Backend, device: device})
        Nx.Defn.global_default_options(compiler: Emily.Compiler)

        %{
          "requested_backend" => "emily",
          "emily_device" => to_string(device),
          "emily_fallback" => to_string(fallback),
          "exla_enabled" => false
        }

      other ->
        raise "Unsupported OBSCURA_PRIVACY_FILTER_BACKEND=#{inspect(other)}"
    end
  end

  defp tensor_stages(actual, fixture, tolerance) do
    [
      {"embedding", actual.embedding, ["embedding"]},
      {"attention.normalized", hd(actual.blocks).attention.normalized,
       ["blocks", 0, "attention", "normalized"]},
      {"attention.qkv", hd(actual.blocks).attention.qkv, ["blocks", 0, "attention", "qkv"]},
      {"attention.query_rotary", hd(actual.blocks).attention.query_rotary,
       ["blocks", 0, "attention", "query_rotary"]},
      {"attention.key_rotary", hd(actual.blocks).attention.key_rotary,
       ["blocks", 0, "attention", "key_rotary"]},
      {"attention.value", hd(actual.blocks).attention.value, ["blocks", 0, "attention", "value"]},
      {"attention.query_scaled", hd(actual.blocks).attention.query_scaled,
       ["blocks", 0, "attention", "query_scaled"]},
      {"attention.key_scaled", hd(actual.blocks).attention.key_scaled,
       ["blocks", 0, "attention", "key_scaled"]},
      {"attention.attention", hd(actual.blocks).attention.attention,
       ["blocks", 0, "attention", "attention"]},
      {"attention.projection", hd(actual.blocks).attention.projection,
       ["blocks", 0, "attention", "projection"]},
      {"attention.output", hd(actual.blocks).attention.output,
       ["blocks", 0, "attention", "output"]},
      {"mlp.normalized", hd(actual.blocks).mlp.normalized, ["blocks", 0, "mlp", "normalized"]},
      {"mlp.flat", hd(actual.blocks).mlp.flat, ["blocks", 0, "mlp", "flat"]},
      {"mlp.gate_logits", hd(actual.blocks).mlp.gate_logits, ["blocks", 0, "mlp", "gate_logits"]},
      {"mlp.expert_scores", hd(actual.blocks).mlp.expert_scores,
       ["blocks", 0, "mlp", "expert_scores"]},
      {"mlp.expert_weights", hd(actual.blocks).mlp.expert_weights,
       ["blocks", 0, "mlp", "expert_weights"]},
      {"mlp.expert_output", hd(actual.blocks).mlp.expert_output,
       ["blocks", 0, "mlp", "expert_output"]},
      {"mlp.output", hd(actual.blocks).mlp.output, ["blocks", 0, "mlp", "output"]},
      {"block.output", hd(actual.blocks).output, ["blocks", 0, "output"]},
      {"final_norm", actual.final_norm, ["final_norm"]},
      {"logits", actual.logits, ["logits"]}
    ]
    |> Enum.map(fn {name, actual_tensor, path} ->
      expected = fixture["python_stages"] |> fetch_path(path) |> Nx.tensor(type: {:f, 32})
      tensor_diff(name, actual_tensor, expected, tolerance)
    end)
  end

  defp fetch_path(value, []), do: value

  defp fetch_path(value, [key | rest]) when is_map(value),
    do: value |> Map.fetch!(key) |> fetch_path(rest)

  defp fetch_path(value, [index | rest]) when is_list(value) and is_integer(index),
    do: value |> Enum.at(index) |> fetch_path(rest)

  defp tensor_diff(name, actual, expected, tolerance) do
    diff = Nx.abs(Nx.subtract(Nx.as_type(actual, {:f, 32}), expected))
    abs_expected = Nx.abs(expected)
    rel = Nx.divide(diff, Nx.max(abs_expected, 1.0e-12))

    %{
      "stage" => name,
      "kind" => "tensor",
      "actual_shape" => actual |> Nx.shape() |> Tuple.to_list(),
      "expected_shape" => expected |> Nx.shape() |> Tuple.to_list(),
      "actual_type" => inspect(Nx.type(actual)),
      "expected_type" => inspect(Nx.type(expected)),
      "max_abs_diff" => Nx.reduce_max(diff) |> Nx.to_number(),
      "mean_abs_diff" => Nx.mean(diff) |> Nx.to_number(),
      "max_rel_diff" => Nx.reduce_max(rel) |> Nx.to_number(),
      "passed" =>
        actual
        |> Nx.all_close(expected, atol: tolerance["atol"], rtol: tolerance["rtol"])
        |> Nx.to_number()
        |> Kernel.==(1)
    }
  end

  defp first_mismatch(actual, expected, tolerance) do
    shape = expected |> Nx.shape() |> Tuple.to_list()
    actual_values = actual |> Nx.as_type({:f, 32}) |> Nx.to_flat_list()
    expected_values = expected |> Nx.as_type({:f, 32}) |> Nx.to_flat_list()

    actual_values
    |> Enum.zip(expected_values)
    |> Enum.with_index()
    |> Enum.find_value(fn {{actual_value, expected_value}, flat_index} ->
      allowed = tolerance["atol"] + tolerance["rtol"] * abs(expected_value)
      diff = abs(actual_value - expected_value)

      if diff > allowed do
        %{
          "flat_index" => flat_index,
          "index" => flat_index_to_index(flat_index, shape),
          "actual" => actual_value,
          "expected" => expected_value,
          "abs_diff" => diff,
          "allowed_diff" => allowed
        }
      end
    end)
  end

  defp flat_index_to_index(flat_index, shape) do
    shape
    |> Enum.reverse()
    |> Enum.reduce({flat_index, []}, fn dimension, {remaining, coords} ->
      {div(remaining, dimension), [rem(remaining, dimension) | coords]}
    end)
    |> elem(1)
  end

  defp exact_stage(name, actual, expected) do
    %{"stage" => name, "kind" => "exact", "passed" => actual == expected}
  end

  defp tiny_window_report(fixture) do
    [token_ids] = fixture["token_ids"]

    example = %TokenizedExample{
      tokens: List.to_tuple(token_ids),
      labels: token_ids |> Enum.map(fn _ -> 0 end) |> List.to_tuple(),
      example_id: "tiny-model",
      text: "tiny"
    }

    {:ok, windows} = SequenceLabeling.example_to_windows(example, 2)
    exact_stage("window_construction", Enum.map(windows, &window_to_json/1), fixture["windows"])
  end

  defp postprocessing_report(postprocessing) do
    {:ok, label_info} = LabelInfo.build(postprocessing["class_names"])
    decoded_labels = Viterbi.decode(Viterbi.new(label_info), postprocessing["token_logprobs"])

    labels_by_index =
      decoded_labels |> Enum.with_index() |> Map.new(fn {label, index} -> {index, label} end)

    token_spans = Spans.labels_to_spans(labels_by_index, label_info)

    char_spans =
      Spans.token_spans_to_char_spans(
        token_spans,
        postprocessing["char_starts"],
        postprocessing["char_ends"]
      )

    trimmed = Spans.trim_char_spans_whitespace(char_spans, postprocessing["text"])
    kept = Spans.discard_overlapping_spans_by_label(trimmed)
    {:ok, detected} = Spans.char_spans_to_detected_spans(kept, postprocessing["text"], label_info)

    mapped_entities =
      Enum.map(detected, fn span ->
        %{
          "label" => span.label,
          "entity" => Atom.to_string(span.entity),
          "start" => span.start,
          "end" => span.end,
          "text" => span.text
        }
      end)

    %{
      "checks" => [
        exact_stage("viterbi_labels", decoded_labels, postprocessing["decoded_labels"]),
        exact_stage(
          "token_spans",
          tuple_spans_to_lists(token_spans),
          postprocessing["token_spans"]
        ),
        exact_stage("char_spans", tuple_spans_to_lists(char_spans), postprocessing["char_spans"]),
        exact_stage(
          "trimmed_char_spans",
          tuple_spans_to_lists(trimmed),
          postprocessing["trimmed_char_spans"]
        ),
        exact_stage(
          "kept_char_spans",
          tuple_spans_to_lists(kept),
          postprocessing["kept_char_spans"]
        ),
        exact_stage("entity_mapping", mapped_entities, postprocessing["mapped_entities"])
      ]
    }
  end

  defp real_checkpoint_report(reference) do
    checkpoint = reference["checkpoint"]
    config = %{"encoding" => reference["encoding"]}
    {:ok, tokenization} = Tokenization.from_config(config, reference["text"])

    example = %TokenizedExample{
      tokens: List.to_tuple(tokenization.token_ids),
      labels: tokenization.token_ids |> Enum.map(fn _ -> 0 end) |> List.to_tuple(),
      example_id: "tiny-model",
      text: reference["text"]
    }

    {:ok, windows} = SequenceLabeling.example_to_windows(example, reference["n_ctx"])

    checkpoint_status =
      case Checkpoint.validate(checkpoint) do
        {:ok, summary} ->
          %{
            "status" => "completed",
            "summary" => stringify_atoms(summary),
            "file_hashes" => checkpoint_hashes(checkpoint)
          }

        {:error, reason} ->
          %{"status" => "skipped", "reason" => inspect(reason)}
      end

    %{
      "checkpoint" => checkpoint,
      "encoding" => reference["encoding"],
      "n_ctx" => reference["n_ctx"],
      "token_ids" =>
        exact_stage("real_checkpoint.token_ids", tokenization.token_ids, reference["token_ids"]),
      "windows" =>
        exact_stage(
          "real_checkpoint.windows",
          Enum.map(windows, &window_to_json/1),
          reference["windows"]
        ),
      "checkpoint_metadata" => checkpoint_status,
      "final_logits" => %{
        "status" => reference["full_logits_status"],
        "reason" => reference["full_logits_reason"]
      }
    }
  end

  defp python_original_report(%{"status" => status} = reference, _backend, _tolerance)
       when status != "completed" do
    %{
      "status" => "skipped",
      "checkpoint" => reference["checkpoint"],
      "reason" =>
        Map.get(reference, "reason", "Python-original reference fixture was not generated")
    }
  end

  defp python_original_report(reference, backend, tolerance) do
    checkpoint = reference["checkpoint"]
    n_ctx = reference["n_ctx"]
    text = reference["text"]

    with {:ok, serving} <-
           Serving.build(
             checkpoint: checkpoint,
             layout: :python_original,
             n_ctx: n_ctx,
             backend: report_backend(backend),
             decoder: :viterbi
           ),
         {:ok, tokenization} <- Tokenization.from_config(serving.config, text),
         {:ok, windows} <-
           example_windows(
             tokenization,
             serving.label_info.background_token_label,
             n_ctx,
             "python-original-reference"
           ),
         logprob_rows <- reference["log_probs"],
         decoded_labels <-
           Viterbi.decode(Viterbi.new(serving.label_info, serving.viterbi_biases), logprob_rows),
         labels_by_index <-
           decoded_labels |> Enum.with_index() |> Map.new(fn {label, index} -> {index, label} end),
         token_spans <- Spans.labels_to_spans(labels_by_index, serving.label_info),
         char_spans <-
           Spans.token_spans_to_char_spans(
             token_spans,
             tokenization.char_starts,
             tokenization.char_ends
           ),
         trimmed <- Spans.trim_char_spans_whitespace(char_spans, text),
         kept <- Spans.discard_overlapping_spans_by_label(trimmed),
         {:ok, detected} <- Spans.char_spans_to_detected_spans(kept, text, serving.label_info) do
      model_stage_checks =
        python_original_model_stage_checks(serving, tokenization.token_ids, reference, tolerance)

      qkv_micro = python_original_qkv_micro_report(reference, backend, serving, tolerance)
      first_model_divergence = Enum.find(model_stage_checks, &(not &1["passed"]))
      logits_check = python_original_logits_status(first_model_divergence)

      checks = [
        exact_stage("python_original.token_ids", tokenization.token_ids, reference["token_ids"]),
        exact_stage(
          "python_original.windows",
          Enum.map(windows, &window_to_json/1),
          reference["windows"]
        ),
        logits_check,
        exact_stage(
          "python_original.decoded_labels",
          decoded_labels,
          reference["decoded_labels"]
        ),
        exact_stage(
          "python_original.token_spans",
          tuple_spans_to_lists(token_spans),
          reference["token_spans"]
        ),
        exact_stage(
          "python_original.char_spans",
          tuple_spans_to_lists(char_spans),
          reference["char_spans"]
        ),
        exact_stage(
          "python_original.trimmed_char_spans",
          tuple_spans_to_lists(trimmed),
          reference["trimmed_char_spans"]
        ),
        exact_stage(
          "python_original.kept_char_spans",
          tuple_spans_to_lists(kept),
          reference["kept_char_spans"]
        ),
        exact_stage(
          "python_original.detected_spans",
          detected_spans_to_json(detected),
          reference["detected_spans"]
        )
      ]

      %{
        "status" => "completed",
        "checkpoint" => checkpoint,
        "layout" => "python_original",
        "encoding" => reference["encoding"],
        "n_ctx" => n_ctx,
        "checks" => checks,
        "model_stage_checks" => model_stage_checks,
        "qkv_micro" => qkv_micro,
        "first_model_divergence" => first_model_divergence,
        "checkpoint_metadata" => python_original_checkpoint_metadata(checkpoint),
        "dtypes" => stringify_atoms(serving.dtypes),
        "detected_spans" => detected_spans_to_json(detected),
        "python_detected_spans" => reference["detected_spans"],
        "all_checks_passed" =>
          Enum.all?(checks ++ model_stage_checks ++ qkv_micro_checks(qkv_micro), & &1["passed"])
      }
    else
      {:error, reason} ->
        %{
          "status" => "failed",
          "checkpoint" => checkpoint,
          "layout" => "python_original",
          "reason" => inspect(reason)
        }
    end
  end

  defp python_original_checks(%{"status" => "completed", "checks" => checks}), do: checks
  defp python_original_checks(_report), do: []

  defp python_original_model_checks(%{"status" => "completed", "model_stage_checks" => checks}),
    do: checks

  defp python_original_model_checks(_report), do: []

  defp qkv_micro_checks(%{"status" => "completed", "checks" => checks}), do: checks
  defp qkv_micro_checks(_report), do: []

  defp report_backend(%{"requested_backend" => "binary"}), do: :binary
  defp report_backend(%{"requested_backend" => "exla"}), do: :exla
  defp report_backend(%{"requested_backend" => "emily"}), do: :emily
  defp report_backend(_backend), do: :default

  defp python_original_qkv_micro_report(
         %{"qkv_micro_fixture" => fixture_path},
         backend,
         serving,
         tolerance
       ) do
    if File.exists?(fixture_path) do
      micro = fixture_path |> File.read!() |> Jason.decode!()
      first_block = hd(serving.params.blocks)

      loaded_weight =
        tensor_diff(
          "python_original.qkv_micro.loaded_weight",
          first_block.attn.qkv_weight,
          Nx.tensor(micro["weight"], type: {:f, 32}),
          tolerance
        )

      loaded_bias =
        tensor_diff(
          "python_original.qkv_micro.loaded_bias",
          first_block.attn.qkv_bias,
          Nx.tensor(micro["bias"], type: {:f, 32}),
          tolerance
        )

      current_backend =
        qkv_micro_replay("python_original.qkv_micro.current_backend", micro, backend, tolerance)

      binary_backend =
        qkv_micro_replay(
          "python_original.qkv_micro.binary_backend",
          micro,
          %{"requested_backend" => "binary"},
          tolerance
        )

      scalar_probes = qkv_scalar_probe_checks(micro, tolerance)

      %{
        "status" => "completed",
        "fixture" => fixture_path,
        "operation" => micro["operation"],
        "torch" => micro["torch"],
        "shapes" => micro["shapes"],
        "checks" =>
          [loaded_weight, loaded_bias, current_backend, binary_backend] ++ scalar_probes,
        "diagnosis" =>
          qkv_micro_diagnosis(loaded_weight, loaded_bias, current_backend, binary_backend)
      }
    else
      %{
        "status" => "skipped",
        "fixture" => fixture_path,
        "reason" => "QKV micro-fixture was not generated"
      }
    end
  end

  defp python_original_qkv_micro_report(_reference, _backend, _serving, _tolerance) do
    %{
      "status" => "skipped",
      "reason" => "Python-original reference does not point to a QKV micro-fixture"
    }
  end

  defp qkv_micro_replay(stage, micro, backend, tolerance) do
    backend_option = qkv_backend_option(backend)
    input = qkv_tensor(micro["input"], {:f, 32}, backend_option)
    weight = qkv_tensor(micro["weight"], {:bf, 16}, backend_option)

    bias =
      if is_nil(micro["bias"]),
        do: nil,
        else: qkv_tensor(micro["bias"], {:bf, 16}, backend_option)

    expected = qkv_tensor(micro["output"], {:f, 32}, backend_option)
    actual = Linear.apply(input, weight, bias, torch_bf16_parity: true)

    stage
    |> tensor_diff(actual, expected, tolerance)
    |> Map.put("backend", backend["requested_backend"])
    |> Map.put("first_mismatch", first_mismatch(actual, expected, tolerance))
  end

  defp qkv_tensor(value, type, nil), do: Nx.tensor(value, type: type)
  defp qkv_tensor(value, type, backend), do: Nx.tensor(value, type: type, backend: backend)

  defp qkv_backend_option(%{"requested_backend" => "binary"}), do: Nx.BinaryBackend

  defp qkv_backend_option(%{"requested_backend" => "emily"} = backend) do
    device = backend |> Map.get("emily_device", "gpu") |> String.to_atom()
    {Module.concat(["Emily", "Backend"]), device: device}
  end

  defp qkv_backend_option(%{"requested_backend" => "exla"}), do: EXLA.Backend
  defp qkv_backend_option(_backend), do: nil

  defp qkv_scalar_probe_checks(micro, tolerance) do
    micro
    |> Map.get("scalar_probes", [])
    |> Enum.with_index()
    |> Enum.map(fn {probe, index} ->
      actual =
        probe["input_values"]
        |> Enum.zip(probe["weight_values"])
        |> Enum.reduce(0.0, fn {left, right}, acc -> acc + left * right end)
        |> Kernel.+(probe["bias_value"])

      expected = probe["manual_f32_sum_with_bias"]
      diff = abs(actual - expected)

      %{
        "stage" => "python_original.qkv_micro.scalar_probe.#{index}",
        "kind" => "scalar",
        "index" => probe["index"],
        "actual" => actual,
        "expected" => expected,
        "torch_single_linear_value" => probe["torch_single_linear_value"],
        "torch_output_value" => probe["torch_output_value"],
        "max_abs_diff" => diff,
        "mean_abs_diff" => diff,
        "max_rel_diff" => diff / max(abs(expected), 1.0e-12),
        "passed" => diff <= tolerance["atol"] + tolerance["rtol"] * abs(expected)
      }
    end)
  end

  defp qkv_micro_diagnosis(loaded_weight, loaded_bias, current_backend, binary_backend) do
    cond do
      not loaded_weight["passed"] ->
        "QKV weight loading/layout differs from Python."

      not loaded_bias["passed"] ->
        "QKV bias loading/layout differs from Python."

      binary_backend["passed"] and not current_backend["passed"] ->
        "QKV replay matches Python on BinaryBackend but diverges on the active backend, which points to backend dot/matmul semantics rather than Obscura tensor loading or layout."

      not binary_backend["passed"] ->
        "QKV replay diverges on BinaryBackend, so the issue is in Obscura math, dtype handling, or the micro-fixture contract."

      true ->
        "QKV micro replay matches Python on both BinaryBackend and the active backend."
    end
  end

  defp example_windows(tokenization, background, n_ctx, example_id) do
    token_ids = Map.fetch!(tokenization, :token_ids)

    example = %TokenizedExample{
      tokens: List.to_tuple(token_ids),
      labels: List.duplicate(background, length(token_ids)) |> List.to_tuple(),
      example_id: example_id,
      text: Map.fetch!(tokenization, :text)
    }

    SequenceLabeling.example_to_windows(example, n_ctx)
  end

  defp python_original_model_stage_checks(serving, token_ids, reference, tolerance) do
    model_stages = Map.fetch!(reference, "model_stages")
    token_tensor = Nx.tensor([token_ids])
    attention_mask = Nx.tensor([List.duplicate(1, length(token_ids))])
    embedding = Nx.take(serving.params.embedding, token_tensor)
    first_block = hd(serving.params.blocks)

    attention =
      Model.Attention.debug(embedding, first_block.attn, serving.config,
        attention_mask: attention_mask,
        torch_bf16_parity: true
      )

    [
      {"embedding", embedding, ["embedding"]},
      {"blocks.0.input", embedding, ["blocks", 0, "input"]},
      {"blocks.0.attention.normalized", attention.normalized,
       ["blocks", 0, "attention", "normalized"]},
      {"blocks.0.attention.qkv", attention.qkv, ["blocks", 0, "attention", "qkv"]},
      {"blocks.0.attention.query_rotary", attention.query_rotary,
       ["blocks", 0, "attention", "query_rotary"]},
      {"blocks.0.attention.key_rotary", attention.key_rotary,
       ["blocks", 0, "attention", "key_rotary"]},
      {"blocks.0.attention.value", attention.value, ["blocks", 0, "attention", "value"]},
      {"blocks.0.attention.query_scaled", attention.query_scaled,
       ["blocks", 0, "attention", "query_scaled"]},
      {"blocks.0.attention.key_scaled", attention.key_scaled,
       ["blocks", 0, "attention", "key_scaled"]},
      {"blocks.0.attention.attention_scores", attention.attention_scores,
       ["blocks", 0, "attention", "attention_scores"]},
      {"blocks.0.attention.attention_weights", attention.attention_weights,
       ["blocks", 0, "attention", "attention_weights"]},
      {"blocks.0.attention.attention", attention.attention,
       ["blocks", 0, "attention", "attention"]},
      {"blocks.0.attention.projection", attention.projection,
       ["blocks", 0, "attention", "projection"]},
      {"blocks.0.attention.output", attention.output, ["blocks", 0, "attention", "output"]}
    ]
    |> Enum.reduce_while([], fn {name, actual_tensor, path}, acc ->
      expected = model_stages |> fetch_path(path) |> Nx.tensor(type: {:f, 32})
      check = tensor_diff("python_original.model.#{name}", actual_tensor, expected, tolerance)

      if check["passed"] do
        {:cont, [check | acc]}
      else
        {:halt, [check | acc]}
      end
    end)
    |> Enum.reverse()
  end

  defp python_original_logits_status(nil) do
    %{
      "stage" => "python_original.logits",
      "kind" => "status",
      "status" => "not_recomputed",
      "passed" => false,
      "reason" =>
        "Focused report did not rerun full logits because no model-stage divergence was found before logits."
    }
  end

  defp python_original_logits_status(first_model_divergence) do
    %{
      "stage" => "python_original.logits",
      "kind" => "status",
      "status" => "blocked_by_first_model_divergence",
      "passed" => false,
      "reason" => "Full logits parity remains blocked by #{first_model_divergence["stage"]}."
    }
  end

  defp detected_spans_to_json(spans) do
    Enum.map(spans, fn span ->
      %{
        "label" => span.label,
        "start" => span.start,
        "end" => span.end,
        "text" => span.text
      }
    end)
  end

  defp python_original_checkpoint_metadata(checkpoint) do
    case Checkpoint.validate(checkpoint, layout: :python_original) do
      {:ok, summary} ->
        %{
          "status" => "completed",
          "summary" => stringify_atoms(summary),
          "file_hashes" =>
            checkpoint_hashes(checkpoint, [
              "config.json",
              "dtypes.json",
              "model.safetensors",
              "viterbi_calibration.json"
            ])
        }

      {:error, reason} ->
        %{"status" => "failed", "reason" => inspect(reason)}
    end
  end

  defp window_to_json(window) do
    %{
      "example_id" => window.example_id,
      "tokens" => Tuple.to_list(window.tokens),
      "labels" => Tuple.to_list(window.labels),
      "offsets" => Tuple.to_list(window.offsets),
      "token_example_ids" => Tuple.to_list(window.token_example_ids),
      "mask" => Tuple.to_list(window.mask)
    }
  end

  defp tuple_spans_to_lists(spans), do: Enum.map(spans, &Tuple.to_list/1)

  defp checkpoint_hashes(checkpoint, filenames \\ ["config.json", "model.safetensors"]) do
    for filename <- filenames, into: %{} do
      path = Path.join(checkpoint, filename)

      value =
        if File.exists?(path) do
          path
          |> File.stream!(1_048_576, [])
          |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
          |> :crypto.hash_final()
          |> Base.encode16(case: :lower)
        end

      {filename, value}
    end
  end

  defp stringify_atoms(value) when is_map(value),
    do: Map.new(value, fn {key, child} -> {to_string(key), stringify_atoms(child)} end)

  defp stringify_atoms(value) when is_list(value), do: Enum.map(value, &stringify_atoms/1)
  defp stringify_atoms(value), do: value

  defp conclusion(nil, real_checkpoint, %{"status" => "completed"} = python_original) do
    "Tiny-model model math and postprocessing parity pass. HF-root token/window/checkpoint metadata parity pass status: token_ids=#{real_checkpoint["token_ids"]["passed"]}, windows=#{real_checkpoint["windows"]["passed"]}. Python-original checkpoint parity status: all_checks_passed=#{python_original["all_checks_passed"]}."
  end

  defp conclusion(nil, real_checkpoint, python_original) do
    "Tiny-model model math and postprocessing parity pass. HF-root token/window/checkpoint metadata parity pass status: token_ids=#{real_checkpoint["token_ids"]["passed"]}, windows=#{real_checkpoint["windows"]["passed"]}. Python-original checkpoint parity status: #{python_original["status"]}."
  end

  defp conclusion(first_divergence, _real_checkpoint, _python_original) do
    "First parity divergence: #{first_divergence["stage"]}."
  end

  defp render_markdown(report) do
    rows =
      report["tiny_model"]["stages"]
      |> Enum.map(fn stage ->
        "| #{stage["stage"]} | #{stage["passed"]} | #{fmt(stage["max_abs_diff"])} | #{fmt(stage["mean_abs_diff"])} | #{fmt(stage["max_rel_diff"])} |"
      end)
      |> Enum.join("\n")

    exact_rows =
      (report["tiny_model"]["exact_stages"] ++
         [report["tiny_model"]["window_construction"]] ++
         report["tiny_model"]["postprocessing"]["checks"])
      |> Enum.map(fn stage -> "| #{stage["stage"]} | #{stage["passed"]} |" end)
      |> Enum.join("\n")

    python_original_rows =
      case report["python_original_checkpoint"] do
        %{"status" => "completed", "checks" => checks} ->
          checks
          |> Enum.map(fn
            %{"kind" => "tensor"} = stage ->
              "| #{stage["stage"]} | #{stage["passed"]} | #{fmt(stage["max_abs_diff"])} | #{fmt(stage["mean_abs_diff"])} | #{fmt(stage["max_rel_diff"])} |"

            stage ->
              "| #{stage["stage"]} | #{stage["passed"]} | | | |"
          end)
          |> Enum.join("\n")

        other ->
          "| status | #{other["status"]} | | | |"
      end

    python_original_model_rows =
      case report["python_original_checkpoint"] do
        %{"status" => "completed", "model_stage_checks" => checks} ->
          checks
          |> Enum.map(fn stage ->
            "| #{stage["stage"]} | #{stage["passed"]} | #{inspect(stage["actual_shape"])} | #{inspect(stage["expected_shape"])} | #{stage["actual_type"]} | #{stage["expected_type"]} | #{fmt(stage["max_abs_diff"])} | #{fmt(stage["mean_abs_diff"])} | #{fmt(stage["max_rel_diff"])} |"
          end)
          |> Enum.join("\n")

        other ->
          "| status | #{other["status"]} | | | | | | | |"
      end

    qkv_micro_rows =
      case report["python_original_checkpoint"] do
        %{"qkv_micro" => %{"status" => "completed", "checks" => checks}} ->
          checks
          |> Enum.map(fn
            %{"kind" => "tensor"} = stage ->
              mismatch = format_first_mismatch(stage["first_mismatch"])

              "| #{stage["stage"]} | #{stage["passed"]} | #{Map.get(stage, "backend", "")} | #{fmt(stage["max_abs_diff"])} | #{fmt(stage["mean_abs_diff"])} | #{fmt(stage["max_rel_diff"])} | #{mismatch} |"

            %{"kind" => "scalar"} = stage ->
              "| #{stage["stage"]} | #{stage["passed"]} | scalar | #{fmt(stage["max_abs_diff"])} | #{fmt(stage["mean_abs_diff"])} | #{fmt(stage["max_rel_diff"])} | #{inspect(stage["index"])} |"
          end)
          |> Enum.join("\n")

        other ->
          status = get_in(other, ["qkv_micro", "status"]) || "skipped"
          "| status | #{status} | | | | | |"
      end

    qkv_micro_diagnosis =
      get_in(report, ["python_original_checkpoint", "qkv_micro", "diagnosis"]) || "not available"

    """
    # Privacy-Filter Layer Parity Report

    - Run ID: #{report["run_id"]}
    - Fixture: #{report["fixture"]}
    - Backend: #{inspect(report["backend"])}
    - Tolerance: atol=#{report["tolerance"]["atol"]}, rtol=#{report["tolerance"]["rtol"]}
    - First divergence: #{if report["first_divergence"], do: report["first_divergence"]["stage"], else: "none"}

    ## Tensor Stages

    | Stage | Passed | Max Abs Diff | Mean Abs Diff | Max Rel Diff |
    | --- | --- | ---: | ---: | ---: |
    #{rows}

    ## Exact Stages

    | Stage | Passed |
    | --- | --- |
    #{exact_rows}

    ## Real Checkpoint

    - Checkpoint: #{report["real_checkpoint"]["checkpoint"]}
    - Encoding: #{report["real_checkpoint"]["encoding"]}
    - Token IDs match Python: #{report["real_checkpoint"]["token_ids"]["passed"]}
    - Windows match Python: #{report["real_checkpoint"]["windows"]["passed"]}
    - Checkpoint metadata status: #{report["real_checkpoint"]["checkpoint_metadata"]["status"]}
    - Final logits status: #{report["real_checkpoint"]["final_logits"]["status"]}
    - Final logits reason: #{report["real_checkpoint"]["final_logits"]["reason"]}

    ## Python Original Checkpoint

    - Checkpoint: #{report["python_original_checkpoint"]["checkpoint"]}
    - Status: #{report["python_original_checkpoint"]["status"]}
    - Layout: #{report["python_original_checkpoint"]["layout"]}
    - All checks passed: #{report["python_original_checkpoint"]["all_checks_passed"]}
    - First model divergence: #{if report["python_original_checkpoint"]["first_model_divergence"], do: report["python_original_checkpoint"]["first_model_divergence"]["stage"], else: "none"}

    | Check | Passed | Max Abs Diff | Mean Abs Diff | Max Rel Diff |
    | --- | --- | ---: | ---: | ---: |
    #{python_original_rows}

    ### Python Original Model Stages

    | Stage | Passed | Actual Shape | Expected Shape | Actual Type | Expected Type | Max Abs Diff | Mean Abs Diff | Max Rel Diff |
    | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: |
    #{python_original_model_rows}

    ### Python Original QKV Micro-Replay

    - Diagnosis: #{qkv_micro_diagnosis}

    | Stage | Passed | Backend | Max Abs Diff | Mean Abs Diff | Max Rel Diff | First Mismatch |
    | --- | --- | --- | ---: | ---: | ---: | --- |
    #{qkv_micro_rows}

    ## Conclusion

    #{report["conclusion"]}
    """
  end

  defp fmt(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 8)
  defp fmt(value), do: to_string(value)

  defp format_first_mismatch(nil), do: ""

  defp format_first_mismatch(mismatch) do
    "#{inspect(mismatch["index"])} actual=#{fmt(mismatch["actual"])} expected=#{fmt(mismatch["expected"])} diff=#{fmt(mismatch["abs_diff"])} allowed=#{fmt(mismatch["allowed_diff"])}"
  end
end

Obscura.Eval.PrivacyFilter.LayerParityReport.run()
