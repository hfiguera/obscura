defmodule Obscura.PrivacyFilter.LabelInfo do
  @moduledoc """
  Lookup tables for privacy-filter BIOES labels.
  """

  @background "O"
  @boundaries ["B", "I", "E", "S"]

  @enforce_keys [
    :boundary_label_lookup,
    :token_to_span_label,
    :token_boundary_tags,
    :span_class_names,
    :span_label_lookup,
    :background_token_label,
    :background_span_label
  ]
  defstruct [
    :boundary_label_lookup,
    :token_to_span_label,
    :token_boundary_tags,
    :span_class_names,
    :span_label_lookup,
    :background_token_label,
    :background_span_label
  ]

  @type t :: %__MODULE__{}

  @spec build([String.t()]) :: {:ok, t()} | {:error, term()}
  def build(class_names) when is_list(class_names) do
    class_names
    |> Enum.with_index()
    |> Enum.reduce_while(initial_state(), &collect_label/2)
    |> case do
      {:error, reason} ->
        {:error, reason}

      state ->
        with {:ok, state} <- ensure_background(state),
             :ok <- ensure_complete_boundaries(state.boundary_label_lookup) do
          {:ok,
           %__MODULE__{
             boundary_label_lookup: freeze_boundary_lookup(state.boundary_label_lookup),
             token_to_span_label: state.token_to_span_label,
             token_boundary_tags: state.token_boundary_tags,
             span_class_names: Enum.reverse(state.span_class_names),
             span_label_lookup: state.span_label_lookup,
             background_token_label: state.background_token_label,
             background_span_label: Map.fetch!(state.span_label_lookup, @background)
           }}
        end
    end
  end

  defp initial_state do
    %{
      boundary_label_lookup: %{},
      token_to_span_label: %{},
      token_boundary_tags: %{},
      span_class_names: [@background],
      span_label_lookup: %{@background => 0},
      background_token_label: nil
    }
  end

  defp collect_label({@background, index}, state) do
    {:cont,
     %{
       state
       | background_token_label: index,
         token_to_span_label: Map.put(state.token_to_span_label, index, 0),
         token_boundary_tags: Map.put(state.token_boundary_tags, index, nil)
     }}
  end

  defp collect_label({class_name, index}, state) do
    case String.split(class_name, "-", parts: 2) do
      [boundary, base_label] when boundary in @boundaries and base_label != "" ->
        {span_index, state} = span_index(state, base_label)

        state = %{
          state
          | token_to_span_label: Map.put(state.token_to_span_label, index, span_index),
            token_boundary_tags: Map.put(state.token_boundary_tags, index, boundary),
            boundary_label_lookup:
              Map.update(
                state.boundary_label_lookup,
                base_label,
                %{boundary => index},
                &Map.put(&1, boundary, index)
              )
        }

        {:cont, state}

      _other ->
        {:halt, {:error, {:invalid_bioes_label, class_name}}}
    end
  end

  defp span_index(state, base_label) do
    case Map.fetch(state.span_label_lookup, base_label) do
      {:ok, index} ->
        {index, state}

      :error ->
        index = map_size(state.span_label_lookup)

        {index,
         %{
           state
           | span_label_lookup: Map.put(state.span_label_lookup, base_label, index),
             span_class_names: [base_label | state.span_class_names]
         }}
    end
  end

  defp ensure_background(%{background_token_label: nil}),
    do: {:error, :missing_background_token_label}

  defp ensure_background(state), do: {:ok, state}

  defp ensure_complete_boundaries(boundary_label_lookup) do
    missing =
      boundary_label_lookup
      |> Enum.flat_map(fn {label, lookup} ->
        @boundaries
        |> Enum.reject(&Map.has_key?(lookup, &1))
        |> Enum.map(&{label, &1})
      end)

    if missing == [], do: :ok, else: {:error, {:missing_bioes_boundaries, missing}}
  end

  defp freeze_boundary_lookup(lookup) do
    Map.new(lookup, fn {key, value} -> {key, Map.new(value)} end)
  end
end
