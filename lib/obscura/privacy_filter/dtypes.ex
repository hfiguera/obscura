defmodule Obscura.PrivacyFilter.DTypes do
  @moduledoc """
  Parser and validator for Python OPF `dtypes.json` artifacts.
  """

  alias Obscura.PrivacyFilter.Weights

  @torch_to_nx %{
    "torch.bfloat16" => {:bf, 16},
    "torch.float32" => {:f, 32},
    "torch.float" => {:f, 32},
    "torch.float16" => {:f, 16},
    "torch.uint8" => {:u, 8},
    "torch.int8" => {:s, 8},
    "torch.int16" => {:s, 16},
    "torch.int32" => {:s, 32},
    "torch.int64" => {:s, 64}
  }

  @spec load(Path.t()) :: {:ok, map()} | {:error, term()}
  def load(path) when is_binary(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, payload} <- Jason.decode(contents),
         do: parse(payload)
  end

  @spec parse(map()) :: {:ok, map()} | {:error, term()}
  def parse(payload) when is_map(payload) do
    payload
    |> Enum.reduce_while({:ok, %{}}, fn {name, dtype}, {:ok, acc} ->
      cond do
        not is_binary(name) or String.trim(name) == "" ->
          {:halt, {:error, {:invalid_dtype_tensor_name, name}}}

        not is_binary(dtype) ->
          {:halt, {:error, {:invalid_dtype_value, name, dtype}}}

        not Map.has_key?(@torch_to_nx, dtype) ->
          {:halt, {:error, {:unsupported_dtype_value, name, dtype}}}

        true ->
          {:cont, {:ok, Map.put(acc, name, dtype)}}
      end
    end)
  end

  def parse(_payload), do: {:error, :invalid_dtypes_artifact}

  @spec validate_against_weights(map(), Weights.t()) :: {:ok, map()} | {:error, term()}
  def validate_against_weights(dtypes, %Weights{} = weights) when is_map(dtypes) do
    tensor_names = weights.tensor_name_to_file |> Map.keys() |> MapSet.new()
    dtype_names = dtypes |> Map.keys() |> MapSet.new()
    missing = MapSet.difference(tensor_names, dtype_names) |> MapSet.to_list() |> Enum.sort()
    extra = MapSet.difference(dtype_names, tensor_names) |> MapSet.to_list() |> Enum.sort()

    if extra != [] do
      {:error, {:unknown_dtype_entries, extra}}
    else
      with :ok <- validate_tensor_types(dtypes, weights) do
        {:ok,
         %{
           declared_count: map_size(dtypes),
           tensor_count: map_size(weights.tensor_name_to_file),
           missing_entries: missing
         }}
      end
    end
  end

  defp validate_tensor_types(dtypes, weights) do
    Enum.reduce_while(dtypes, :ok, fn {name, dtype}, :ok ->
      expected_type = Map.fetch!(@torch_to_nx, dtype)

      case Weights.metadata(weights, name) do
        {:ok, %{type: ^expected_type}} ->
          {:cont, :ok}

        {:ok, %{type: actual_type}} ->
          {:halt, {:error, {:dtype_mismatch, name, dtype, expected_type, actual_type}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end
end
