defmodule Obscura.Internal.ResultText do
  @moduledoc false

  alias Obscura.Analyzer.Result

  @spec maybe_materialize(String.t(), keyword()) :: String.t() | nil
  def maybe_materialize(value, opts) when is_binary(value) and is_list(opts) do
    if Keyword.get(opts, :include_text, true), do: value, else: nil
  end

  @spec maybe_materialize_slice(String.t(), non_neg_integer(), non_neg_integer(), keyword()) ::
          String.t() | nil
  def maybe_materialize_slice(source, byte_start, byte_end, opts)
      when is_binary(source) and is_integer(byte_start) and is_integer(byte_end) and
             is_list(opts) do
    if Keyword.get(opts, :include_text, true) do
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

  def own_term(%_{} = value) do
    module = value.__struct__

    value
    |> Map.from_struct()
    |> own_map()
    |> then(&struct(module, &1))
  end

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
    Map.new(value, fn {key, nested} -> {own_term(key), own_term(nested)} end)
  end

  defp own(value) do
    if :binary.referenced_byte_size(value) > byte_size(value) do
      :binary.copy(value)
    else
      value
    end
  end
end
