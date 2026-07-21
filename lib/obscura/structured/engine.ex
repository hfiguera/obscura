defmodule Obscura.Structured.Engine do
  @moduledoc """
  Recursive structured redaction engine.
  """

  alias Obscura.Anonymizer
  alias Obscura.Anonymizer.Error
  alias Obscura.Anonymizer.Operator
  alias Obscura.Input
  alias Obscura.Structured.Item
  alias Obscura.Structured.Path
  alias Obscura.Structured.Result
  alias Obscura.Telemetry

  @default_sensitive_keys [
    :password,
    :password_hash,
    :token,
    :authorization,
    :api_key,
    :secret,
    :ssn,
    :credit_card,
    "password",
    "password_hash",
    "token",
    "authorization",
    "api_key",
    "secret",
    "ssn",
    "credit_card"
  ]

  @opaque_structs [Date, Time, NaiveDateTime, DateTime, URI, Regex, MapSet, Range]

  @doc """
  Redacts structured data.
  """
  @spec redact(term(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def redact(data, opts) when is_list(opts) do
    start = System.monotonic_time()
    telemetry? = Keyword.get(opts, :telemetry, true)

    result =
      with {:ok, opts} <- normalize_opts(opts),
           :ok <- validate_operator_options(opts) do
        walk(data, [], opts, 0)
      end

    case result do
      {:ok, redacted, items} ->
        Telemetry.execute(
          telemetry?,
          [:obscura, :structured, :redact, :stop],
          %{duration: System.monotonic_time() - start},
          %{status: :ok, input_type: input_type(data), result_count: length(items)}
        )

        {:ok, %Result{data: redacted, items: items, status: :ran}}

      {:error, reason} ->
        Telemetry.execute(
          telemetry?,
          [:obscura, :structured, :redact, :stop],
          %{duration: System.monotonic_time() - start},
          %{status: :error, input_type: input_type(data), result_count: 0}
        )

        {:error, reason}
    end
  end

  defp normalize_opts(opts) do
    field_policies = Keyword.get(opts, :field_policies, %{})

    with :ok <- validate_field_policies(field_policies),
         :ok <- validate_boolean_option(opts, :traverse_structs, false),
         :ok <- validate_boolean_option(opts, :preserve_structs, true),
         :ok <- validate_boolean_option(opts, :dry_run, false),
         :ok <- validate_boolean_option(opts, :skip_protocol, false),
         :ok <- validate_max_depth(Keyword.get(opts, :max_depth, 20)) do
      {:ok,
       opts
       |> Keyword.put(:field_policies, Map.new(field_policies))
       |> Keyword.put_new(:traverse_structs, false)
       |> Keyword.put_new(:preserve_structs, true)
       |> Keyword.put_new(:max_depth, 20)
       |> Keyword.put_new(:dry_run, false)}
    end
  end

  defp validate_field_policies(policies)
       when is_map(policies),
       do: :ok

  defp validate_field_policies(policies) when is_list(policies) do
    if not List.improper?(policies) and Keyword.keyword?(policies) do
      :ok
    else
      invalid_structured_option(:field_policies, :expected_map)
    end
  end

  defp validate_field_policies(_policies),
    do: invalid_structured_option(:field_policies, :expected_map)

  defp validate_boolean_option(opts, key, default) do
    if is_boolean(Keyword.get(opts, key, default)) do
      :ok
    else
      invalid_structured_option(key, :expected_boolean)
    end
  end

  defp validate_max_depth(max_depth) when is_integer(max_depth) and max_depth >= 0, do: :ok

  defp validate_max_depth(_max_depth),
    do: invalid_structured_option(:max_depth, :expected_non_negative_integer)

  defp invalid_structured_option(field, reason) do
    {:error, Error.new(:invalid_operator_option, field: field, reason: reason)}
  end

  defp validate_operator_options(opts) do
    with {:ok, _operators} <- Anonymizer.validate_options(anonymizer_opts(opts)) do
      validate_field_operator_configs(opts[:field_policies], operator_validation_context(opts))
    end
  end

  defp validate_field_operator_configs(policies, context) do
    Enum.reduce_while(policies, :ok, &validate_field_operator_config(&1, &2, context))
  end

  defp validate_field_operator_config({_key, {:operator, config}}, :ok, context) do
    case Operator.validate_config(config, context) do
      :ok -> {:cont, :ok}
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp validate_field_operator_config({_key, _policy}, :ok, _context), do: {:cont, :ok}

  defp operator_validation_context(opts) do
    %{
      vault: Keyword.get(opts, :vault),
      token_options:
        Keyword.take(opts, [
          :token_prefix,
          :token_suffix,
          :token_separator,
          :token_width,
          :token_case,
          :token_strategy
        ])
    }
  end

  defp walk(value, path, opts, depth) do
    if depth > opts[:max_depth] do
      {:error, :max_depth_exceeded}
    else
      walk_value(value, path, opts, depth)
    end
  end

  defp walk_value(value, path, opts, depth) when is_binary(value) do
    with :ok <- Input.validate_text(value) do
      redact_string(value, path, opts, depth)
    end
  end

  defp walk_value(value, path, opts, depth) when is_list(value) do
    cond do
      List.improper?(value) -> {:error, :improper_list}
      Keyword.keyword?(value) -> walk_keyword(value, path, opts, depth)
      true -> walk_list(value, path, opts, depth)
    end
  end

  defp walk_value(%module{} = value, path, opts, depth) do
    cond do
      module in @opaque_structs ->
        {:ok, value, []}

      Keyword.get(opts, :skip_protocol, false) ->
        maybe_walk_struct(value, path, opts, depth)

      true ->
        case Obscura.Redactable.redact(value, Keyword.put(opts, :path, path))
             |> normalize_protocol_result() do
          {:ok, ^value, []} ->
            maybe_walk_struct(value, path, opts, depth)

          result ->
            result
        end
    end
  end

  defp walk_value(value, path, opts, depth) when is_map(value),
    do: walk_map(value, path, opts, depth)

  defp walk_value(value, _path, _opts, _depth), do: {:ok, value, []}

  defp redact_string(value, path, opts, _depth) do
    case policy_for(path, opts) do
      :keep ->
        {:ok, value, []}

      {:replace, replacement} ->
        item = full_value_item(path, :field, :replace, value, replacement, %{})
        {:ok, maybe_replace(value, replacement, opts), [item]}

      {:operator, operator_config} ->
        apply_full_operator(value, path, operator_config, opts)

      {:entity, entity} ->
        redact_leaf(value, path, Keyword.put(opts, :entities, [entity]))

      _policy ->
        redact_leaf(value, path, opts)
    end
  end

  defp redact_leaf(value, path, opts) do
    redact_opts = analyzer_opts(opts)

    with {:ok, detections} <- Obscura.Analyzer.analyze(value, redact_opts),
         {:ok, result} <- Anonymizer.anonymize(value, detections, anonymizer_opts(opts)) do
      items = Enum.map(result.items, &structured_item(path, &1))
      {:ok, maybe_replace(value, result.text, opts), items}
    end
  end

  defp apply_full_operator(value, path, operator_config, opts) do
    span = %{
      entity: Map.get(operator_config, :entity, :field),
      byte_start: 0,
      byte_end: byte_size(value),
      value: value,
      metadata: %{}
    }

    with {:ok, result} <-
           Anonymizer.anonymize(value, [span], operators: %{default: operator_config}) do
      items = Enum.map(result.items, &structured_item(path, &1))
      {:ok, maybe_replace(value, result.text, opts), items}
    end
  end

  defp walk_keyword(keyword, path, opts, depth) do
    keyword
    |> Enum.reduce_while({:ok, [], []}, fn {key, value}, {:ok, acc, items} ->
      child_path = Path.append(path, key)

      case map_field(key, value, child_path, opts, depth) do
        {:ok, :drop, child_items} ->
          {:cont, {:ok, acc, items ++ child_items}}

        {:ok, redacted, child_items} ->
          {:cont, {:ok, acc ++ [{key, redacted}], items ++ child_items}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp walk_list(list, path, opts, depth) do
    list
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], []}, fn {value, index}, {:ok, acc, items} ->
      case walk(value, Path.append(path, index), opts, depth + 1) do
        {:ok, redacted, child_items} -> {:cont, {:ok, acc ++ [redacted], items ++ child_items}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp walk_map(map, path, opts, depth) do
    map
    |> Enum.reduce_while({:ok, %{}, []}, fn {key, value}, {:ok, acc, items} ->
      child_path = Path.append(path, key)

      case map_field(key, value, child_path, opts, depth) do
        {:ok, :drop, child_items} ->
          {:cont, {:ok, acc, items ++ child_items}}

        {:ok, redacted, child_items} ->
          {:cont, {:ok, Map.put(acc, key, redacted), items ++ child_items}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp walk_struct(struct, path, opts, depth) do
    with {:ok, redacted, items} <- walk_map(Map.from_struct(struct), path, opts, depth) do
      if opts[:preserve_structs] do
        {:ok, struct(struct.__struct__, redacted), items}
      else
        {:ok, redacted, items}
      end
    end
  end

  defp maybe_walk_struct(value, path, opts, depth) do
    if opts[:traverse_structs] do
      walk_struct(value, path, opts, depth)
    else
      {:ok, value, []}
    end
  end

  defp map_field(key, value, path, opts, depth) do
    case policy_for_key(key, opts) do
      :drop ->
        {:ok, :drop,
         [full_value_item(path, :field, :drop, inspect_type(value), "", %{dropped: true})]}

      :keep ->
        {:ok, value, []}

      {:replace, replacement} ->
        {:ok, replacement,
         [full_value_item(path, :field, :replace, inspect_type(value), replacement, %{})]}

      {:operator, operator_config} when is_binary(value) ->
        apply_full_operator(value, path, operator_config, opts)

      {:entity, entity} when is_binary(value) ->
        redact_leaf(value, path, Keyword.put(opts, :entities, [entity]))

      _policy ->
        walk(value, path, opts, depth + 1)
    end
  end

  defp policy_for(path, opts) do
    path
    |> List.last()
    |> policy_for_key(opts)
  end

  defp policy_for_key(key, opts) do
    policies = opts[:field_policies]

    cond do
      Map.has_key?(policies, key) -> Map.fetch!(policies, key)
      sensitive_key?(key) -> {:replace, "[REDACTED]"}
      true -> :traverse
    end
  end

  defp sensitive_key?(key), do: key in @default_sensitive_keys

  defp structured_item(path, item) do
    %Item{
      path: path,
      entity: item.entity,
      operator: item.operator,
      source_byte_start: item.source_byte_start,
      source_byte_end: item.source_byte_end,
      replacement: item.replacement,
      metadata: item.metadata
    }
  end

  defp full_value_item(path, entity, operator, source_value, replacement, metadata) do
    %Item{
      path: path,
      entity: entity,
      operator: operator,
      source_byte_start: 0,
      source_byte_end: byte_size(source_value),
      replacement: replacement,
      metadata: metadata
    }
  end

  defp analyzer_opts(opts) do
    opts
    |> Keyword.take([
      :entities,
      :profile,
      :profile_runtime,
      :language,
      :score_threshold,
      :explain,
      :include_text,
      :conflict_strategy,
      :recognizers,
      :built_ins,
      :deny_lists,
      :allow_list,
      :context,
      :context_window,
      :context_boost,
      :detect_language,
      :language_detector,
      :ner,
      :serving,
      :servings,
      :primary_serving,
      :location_serving,
      :privacy_filter_serving,
      :batch_size,
      :recognizer_timeout,
      :parallel_recognizers,
      :phone_parser,
      :phone_validator,
      :phone_regions,
      :nlp_artifacts,
      :nlp_engine,
      :nlp_engine_opts,
      :telemetry
    ])
    |> Keyword.put_new(:telemetry, false)
  end

  defp anonymizer_opts(opts) do
    opts
    |> Keyword.take([
      :operators,
      :conflict_strategy,
      :merge_whitespace,
      :vault,
      :token_prefix,
      :token_suffix,
      :token_separator,
      :token_width,
      :token_case,
      :token_strategy
    ])
  end

  defp maybe_replace(original, replacement, opts) do
    if opts[:dry_run], do: original, else: replacement
  end

  defp normalize_protocol_result({:ok, value, items}), do: {:ok, value, items}
  defp normalize_protocol_result({:error, reason}), do: {:error, reason}

  defp inspect_type(value) when is_binary(value), do: value
  defp inspect_type(_value), do: ""

  defp input_type(value) when is_map(value), do: :map
  defp input_type(value) when is_list(value), do: :list
  defp input_type(value) when is_binary(value), do: :string
  defp input_type(_value), do: :term
end
