defmodule Obscura.Internal.ResultText do
  @moduledoc false

  alias Obscura.Analyzer.Result

  @max_callback_term_depth 256

  @spec maybe_materialize(String.t(), keyword()) :: String.t() | nil
  def maybe_materialize(value, opts) when is_binary(value) and is_list(opts) do
    if materialize?(opts), do: value, else: nil
  end

  @spec maybe_materialize_slice(String.t(), non_neg_integer(), non_neg_integer(), keyword()) ::
          String.t() | nil
  def maybe_materialize_slice(source, byte_start, byte_end, opts)
      when is_binary(source) and is_integer(byte_start) and is_integer(byte_end) and
             is_list(opts) do
    if materialize?(opts) do
      borrowed_slice(source, byte_start, byte_end)
    end
  end

  @spec finalize([Result.t()], String.t(), boolean()) :: [Result.t()]
  def finalize(results, _source, false) do
    Enum.map(results, &finalize_result(&1, false))
  end

  def finalize(results, _source, true) do
    Enum.map(results, &finalize_result(&1, true))
  end

  @spec borrowed_slice(String.t(), non_neg_integer(), non_neg_integer()) :: String.t()
  def borrowed_slice(source, byte_start, byte_end)
      when is_binary(source) and is_integer(byte_start) and is_integer(byte_end) do
    binary_part(source, byte_start, byte_end - byte_start)
  end

  @spec owned_slice(String.t(), non_neg_integer(), non_neg_integer()) :: String.t()
  def owned_slice(source, byte_start, byte_end) do
    source
    |> borrowed_slice(byte_start, byte_end)
    |> own()
  end

  @doc false
  @spec own_term(term()) :: term()
  def own_term(value) when is_binary(value), do: own(value)
  def own_term(value) when is_map(value), do: own_map(value)
  def own_term([]), do: []
  def own_term([head | tail]), do: [own_term(head) | own_term(tail)]

  def own_term(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&own_term/1)
    |> List.to_tuple()
  end

  def own_term(value), do: value

  @doc false
  @spec safe_callback_term?(term()) :: boolean()
  def safe_callback_term?(value), do: safe_callback_term?(value, 0)

  defp finalize_result(%Result{} = result, include_text?) do
    text =
      case {include_text?, result.text} do
        {true, text} when is_binary(text) -> own(text)
        _other -> nil
      end

    %{
      result
      | text: text,
        source_entity: own_term(result.source_entity),
        explanation: own_term(result.explanation),
        metadata: own_term(result.metadata)
    }
  end

  defp own_map(value) do
    value
    |> Map.to_list()
    |> Map.new(fn {key, nested} -> {own_term(key), own_term(nested)} end)
  end

  defp own(value) do
    if :binary.referenced_byte_size(value) > byte_size(value) do
      :binary.copy(value)
    else
      value
    end
  end

  defp materialize?(opts) do
    Keyword.get(opts, :include_text, true) or
      Keyword.get(opts, :allow_list) not in [nil, []]
  end

  defp safe_callback_term?(_value, depth) when depth > @max_callback_term_depth, do: false

  defp safe_callback_term?(value, _depth)
       when is_atom(value) or is_number(value) or is_binary(value) or is_pid(value) or
              is_port(value) or is_reference(value),
       do: true

  defp safe_callback_term?(value, _depth) when is_function(value), do: false
  defp safe_callback_term?([], _depth), do: true

  defp safe_callback_term?([head | tail], depth) when is_list(tail) do
    safe_callback_term?(head, depth + 1) and safe_callback_term?(tail, depth + 1)
  end

  defp safe_callback_term?([_head | _tail], _depth), do: false

  defp safe_callback_term?(value, depth) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.all?(&safe_callback_term?(&1, depth + 1))
  end

  defp safe_callback_term?(value, depth) when is_map(value) do
    value
    |> Map.to_list()
    |> Enum.all?(fn {key, nested} ->
      safe_callback_term?(key, depth + 1) and safe_callback_term?(nested, depth + 1)
    end)
  end

  defp safe_callback_term?(_value, _depth), do: false
end
