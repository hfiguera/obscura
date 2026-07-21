defmodule Obscura.PrivacyFilter.LabelSpace do
  @moduledoc """
  Privacy-filter label-space resolution.
  """

  @background "O"
  @boundaries ["B", "I", "E", "S"]

  @span_class_names_by_version %{
    "v2" => [
      "O",
      "account_number",
      "private_address",
      "private_date",
      "private_email",
      "private_person",
      "private_phone",
      "private_url",
      "secret"
    ],
    "v4" => [
      "O",
      "private_person",
      "other_person",
      "personal_url",
      "other_url",
      "personal_location",
      "other_location",
      "personal_email",
      "other_email",
      "personal_phone",
      "other_phone",
      "personal_date",
      "other_date",
      "personal_id",
      "secret"
    ],
    "v7" => [
      "O",
      "personal_name",
      "personal_handle",
      "other_person",
      "personal_email",
      "other_email",
      "personal_phone",
      "other_phone",
      "personal_location",
      "other_location",
      "personal_url",
      "other_url",
      "personal_org",
      "personal_gov_id",
      "personal_fin_id",
      "personal_health_id",
      "personal_device_id",
      "personal_vehicle_id",
      "personal_property_id",
      "personal_edu_id",
      "personal_emp_id",
      "personal_membership_id",
      "personal_registry_id",
      "personal_date",
      "secret",
      "secret_url"
    ]
  }

  @ner_class_names_by_version Map.new(@span_class_names_by_version, fn {version, spans} ->
                                labels = [
                                  @background
                                  | for(
                                      label <- spans,
                                      label != @background,
                                      boundary <- @boundaries,
                                      do: "#{boundary}-#{label}"
                                    )
                                ]

                                {version, labels}
                              end)

  @version_by_num_labels Map.new(@ner_class_names_by_version, fn {version, labels} ->
                           {length(labels), version}
                         end)

  @spec resolve_from_config(map(), keyword()) ::
          {:ok, String.t(), [String.t()], [String.t()]} | {:error, term()}
  def resolve_from_config(config, opts \\ []) when is_map(config) do
    context = Keyword.get(opts, :context, "privacy-filter config")

    case resolve_custom(config, context) do
      {:ok, _version, _span, _ner} = ok -> ok
      :none -> resolve_builtin(config, context)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec expand_with_boundaries([String.t()]) :: [String.t()]
  def expand_with_boundaries(span_class_names) do
    [
      @background
      | for(
          label <- span_class_names,
          label != @background,
          boundary <- @boundaries,
          do: "#{boundary}-#{label}"
        )
    ]
  end

  defp resolve_custom(config, context) do
    custom_span = Map.get(config, "span_class_names")
    custom_ner = Map.get(config, "ner_class_names")

    if is_nil(custom_span) and is_nil(custom_ner) do
      :none
    else
      with {:ok, span_class_names} <- parse_span_class_names(custom_span, custom_ner, context),
           {:ok, ner_class_names} <- parse_ner_class_names(custom_ner, span_class_names, context),
           {:ok, span_class_names} <-
             ensure_span_class_names(span_class_names, ner_class_names, context),
           :ok <- validate_num_labels(config, ner_class_names, context),
           {:ok, version} <-
             custom_category_version(config, span_class_names, ner_class_names, context) do
        {:ok, version, span_class_names, ner_class_names}
      end
    end
  end

  defp resolve_builtin(config, context) do
    configured_version =
      config
      |> Map.get("category_version")
      |> normalize_optional_version()

    inferred_version =
      config
      |> Map.get("num_labels")
      |> infer_version(context)

    with {:ok, inferred_version} <- inferred_version,
         {:ok, version} <- choose_version(configured_version, inferred_version, context),
         {:ok, span_class_names} <- Map.fetch(@span_class_names_by_version, version),
         {:ok, ner_class_names} <- Map.fetch(@ner_class_names_by_version, version) do
      {:ok, version, span_class_names, ner_class_names}
    else
      :error -> {:error, {:unknown_label_category_version, configured_version}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_span_class_names(nil, nil, context),
    do: {:error, {:missing_custom_label_space, context}}

  defp parse_span_class_names(nil, _custom_ner, _context), do: {:ok, []}

  defp parse_span_class_names(value, _custom_ner, context) do
    with {:ok, values} <- parse_string_list(value, "span_class_names", context),
         :ok <- ensure_unique(values, "span_class_names", context) do
      if @background in values do
        {:ok, [@background | Enum.reject(values, &(&1 == @background))]}
      else
        {:error, {:missing_background_label, context, "span_class_names"}}
      end
    end
  end

  defp parse_ner_class_names(nil, span_class_names, _context) when span_class_names != [] do
    {:ok, expand_with_boundaries(span_class_names)}
  end

  defp parse_ner_class_names(nil, _span_class_names, context),
    do: {:error, {:missing_custom_label_space, context}}

  defp parse_ner_class_names(value, _span_class_names, context) do
    with {:ok, values} <- parse_string_list(value, "ner_class_names", context),
         :ok <- ensure_unique(values, "ner_class_names", context),
         :ok <- validate_ner_labels(values, context) do
      {:ok, values}
    end
  end

  defp ensure_span_class_names([], ner_class_names, _context) do
    span_class_names =
      ner_class_names
      |> Enum.reject(&(&1 == @background))
      |> Enum.map(fn label -> label |> String.split("-", parts: 2) |> List.last() end)
      |> Enum.uniq()

    {:ok, [@background | span_class_names]}
  end

  defp ensure_span_class_names(span_class_names, ner_class_names, context) do
    expected = expand_with_boundaries(span_class_names)

    if expected == ner_class_names do
      {:ok, span_class_names}
    else
      {:error, {:custom_ner_class_names_do_not_match_span_class_names, context}}
    end
  end

  defp custom_category_version(config, span_class_names, ner_class_names, context) do
    version =
      config
      |> Map.get("category_version")
      |> normalize_optional_version()

    cond do
      is_nil(version) ->
        {:ok, "custom"}

      Map.has_key?(@span_class_names_by_version, version) and
          (@span_class_names_by_version[version] != span_class_names or
             @ner_class_names_by_version[version] != ner_class_names) ->
        {:error, {:custom_label_space_conflicts_with_builtin_version, context, version}}

      true ->
        {:ok, version}
    end
  end

  defp validate_num_labels(config, ner_class_names, context) do
    case Map.get(config, "num_labels") do
      nil -> :ok
      value when is_integer(value) and value == length(ner_class_names) -> :ok
      value -> {:error, {:num_labels_mismatch, context, value, length(ner_class_names)}}
    end
  end

  defp parse_string_list(value, field, context) when is_list(value) do
    values = Enum.map(value, &if(is_binary(&1), do: String.trim(&1), else: &1))

    if Enum.all?(values, &(is_binary(&1) and &1 != "")) do
      {:ok, values}
    else
      {:error, {:invalid_string_sequence, context, field}}
    end
  end

  defp parse_string_list(_value, field, context),
    do: {:error, {:invalid_string_sequence, context, field}}

  defp ensure_unique(values, field, context) do
    duplicates =
      values
      |> Enum.frequencies()
      |> Enum.filter(fn {_value, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))

    if duplicates == [] do
      :ok
    else
      {:error, {:duplicate_labels, context, field, duplicates}}
    end
  end

  defp validate_ner_labels(values, context) do
    if @background in values do
      values
      |> Enum.reject(&(&1 == @background))
      |> build_boundary_map(context)
      |> validate_boundary_map(context)
    else
      {:error, {:missing_background_label, context, "ner_class_names"}}
    end
  end

  defp build_boundary_map(values, context) do
    Enum.reduce_while(values, %{}, fn label, acc ->
      case String.split(label, "-", parts: 2) do
        [boundary, base_label] when boundary in @boundaries and base_label != "" ->
          {:cont, Map.update(acc, base_label, MapSet.new([boundary]), &MapSet.put(&1, boundary))}

        _other ->
          {:halt, {:error, {:invalid_bioes_label, context, label}}}
      end
    end)
  end

  defp validate_boundary_map({:error, reason}, _context), do: {:error, reason}

  defp validate_boundary_map(boundary_map, context),
    do: validate_boundary_completeness(boundary_map, context)

  defp validate_boundary_completeness(boundary_map, context) do
    missing =
      boundary_map
      |> Enum.flat_map(fn {label, boundaries} ->
        @boundaries
        |> Enum.reject(&MapSet.member?(boundaries, &1))
        |> Enum.map(&{label, &1})
      end)

    if missing == [] do
      :ok
    else
      {:error, {:missing_bioes_boundaries, context, missing}}
    end
  end

  defp normalize_optional_version(nil), do: nil

  defp normalize_optional_version(value),
    do: value |> to_string() |> String.trim() |> String.downcase()

  defp infer_version(nil, _context), do: {:ok, nil}

  defp infer_version(value, context) when is_integer(value) do
    case Map.fetch(@version_by_num_labels, value) do
      {:ok, version} -> {:ok, version}
      :error -> {:error, {:unknown_num_labels_for_label_space, context, value}}
    end
  end

  defp infer_version(value, context), do: {:error, {:invalid_num_labels, context, value}}

  defp choose_version(nil, nil, _context), do: {:ok, "v2"}
  defp choose_version(version, nil, _context), do: {:ok, version}
  defp choose_version(nil, inferred, _context), do: {:ok, inferred}
  defp choose_version(version, version, _context), do: {:ok, version}

  defp choose_version(version, inferred, context),
    do: {:error, {:conflicting_label_space_hints, context, version, inferred}}
end
