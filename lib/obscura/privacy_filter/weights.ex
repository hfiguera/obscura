defmodule Obscura.PrivacyFilter.Weights do
  @moduledoc """
  Safetensors-backed checkpoint loader for privacy-filter models.
  """

  alias Obscura.PrivacyFilter.Checkpoint.Files
  alias Obscura.PrivacyFilter.Weights.MXFP4

  @enforce_keys [:path, :tensor_name_to_file, :tensor_metadata]
  defstruct [:path, :tensor_name_to_file, :tensor_metadata]

  @type tensor_metadata :: %{
          shape: tuple(),
          type: Nx.Type.t(),
          byte_offset: non_neg_integer(),
          byte_size: non_neg_integer()
        }
  @type t :: %__MODULE__{
          path: Path.t(),
          tensor_name_to_file: %{String.t() => Path.t()},
          tensor_metadata: %{String.t() => tensor_metadata()}
        }

  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) when is_binary(path) do
    with :ok <- ensure_dependency(Safetensors, :safetensors),
         :ok <- Files.validate_common(path),
         {:ok, {tensor_name_to_file, tensor_metadata}} <- index_safetensors(path) do
      {:ok,
       %__MODULE__{
         path: path,
         tensor_name_to_file: tensor_name_to_file,
         tensor_metadata: tensor_metadata
       }}
    end
  end

  @spec get(t(), String.t()) :: {:ok, Nx.Tensor.t()} | {:error, term()}
  def get(%__MODULE__{} = checkpoint, name) when is_binary(name) do
    case mapped_name(name) do
      {blocks_name, scales_name} ->
        get_expert_weight(checkpoint, name, blocks_name, scales_name)

      mapped ->
        get_raw(checkpoint, mapped)
    end
  end

  defp get_expert_weight(checkpoint, name, blocks_name, scales_name) do
    dense_name = String.replace_suffix(blocks_name, ".blocks", "")

    cond do
      has?(checkpoint, dense_name) ->
        get_raw(checkpoint, dense_name)

      has?(checkpoint, blocks_name) and has?(checkpoint, scales_name) ->
        decode_expert_weight(checkpoint, blocks_name, scales_name)

      true ->
        {:error, {:missing_tensor, name}}
    end
  end

  defp decode_expert_weight(checkpoint, blocks_name, scales_name) do
    with {:ok, blocks} <- get_raw(checkpoint, blocks_name),
         {:ok, scales} <- get_raw(checkpoint, scales_name) do
      decode_mxfp4(blocks, scales)
    end
  end

  @spec has?(t(), String.t()) :: boolean()
  def has?(%__MODULE__{} = checkpoint, name) when is_binary(name) do
    Map.has_key?(checkpoint.tensor_name_to_file, name)
  end

  @spec metadata(t(), String.t()) :: {:ok, tensor_metadata()} | {:error, term()}
  def metadata(%__MODULE__{} = checkpoint, name) when is_binary(name) do
    case Map.fetch(checkpoint.tensor_metadata, name) do
      {:ok, metadata} -> {:ok, metadata}
      :error -> {:error, {:missing_tensor, name}}
    end
  end

  @spec decode_mxfp4(Nx.Tensor.t(), Nx.Tensor.t()) :: {:ok, Nx.Tensor.t()} | {:error, term()}
  defdelegate decode_mxfp4(blocks, scales), to: MXFP4, as: :decode

  defp index_safetensors(path) do
    path
    |> Path.join("*.safetensors")
    |> Path.wildcard()
    |> Enum.reduce_while({:ok, {%{}, %{}}}, fn file, {:ok, {name_acc, metadata_acc}} ->
      file
      |> index_safetensors_file(name_acc, metadata_acc)
      |> case do
        {:ok, next_acc} -> {:cont, {:ok, next_acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  rescue
    error -> {:error, {:safetensors_index_failed, error.__struct__}}
  end

  defp index_safetensors_file(file, name_acc, metadata_acc) do
    tensors = Safetensors.read!(file, lazy: true)

    with :ok <- validate_file_complete(file, tensors) do
      Enum.reduce_while(tensors, {:ok, {name_acc, metadata_acc}}, fn entry, {:ok, acc} ->
        index_tensor(entry, acc, file)
      end)
    end
  end

  defp index_tensor({tensor_name, tensor}, {names, metadata}, file) do
    if Map.has_key?(names, tensor_name) do
      {:halt, {:error, {:duplicate_tensor_name, tensor_name}}}
    else
      next =
        {Map.put(names, tensor_name, file), Map.put(metadata, tensor_name, lazy_metadata(tensor))}

      {:cont, {:ok, next}}
    end
  end

  defp lazy_metadata(tensor) when is_struct(tensor, Safetensors.FileTensor) do
    %{
      shape: tensor.shape,
      type: tensor.type,
      byte_offset: tensor.byte_offset,
      byte_size: tensor.byte_size
    }
  end

  defp validate_file_complete(file, tensors) do
    actual_size = File.stat!(file).size

    expected_size =
      tensors
      |> Enum.map(fn {_name, tensor} when is_struct(tensor, Safetensors.FileTensor) ->
        tensor.byte_offset + tensor.byte_size
      end)
      |> Enum.max(fn -> 0 end)

    if actual_size >= expected_size do
      :ok
    else
      {:error, {:incomplete_safetensors_file, file, actual_size, expected_size}}
    end
  end

  defp get_raw(%__MODULE__{} = checkpoint, tensor_name) do
    case Map.fetch(checkpoint.tensor_name_to_file, tensor_name) do
      {:ok, file} ->
        {:ok, file |> Safetensors.read!() |> Map.fetch!(tensor_name)}

      :error ->
        {:error, {:missing_tensor, tensor_name}}
    end
  rescue
    error -> {:error, {:safetensors_load_failed, tensor_name, error.__struct__}}
  end

  defp mapped_name(name) do
    case Regex.run(~r/^block\.(\d+)\.mlp\.(mlp[12])_(weight|bias)$/, name) do
      [_, layer, mlp, "bias"] when mlp == "mlp1" ->
        "block.#{layer}.mlp.swiglu.bias"

      [_, layer, mlp, "bias"] when mlp == "mlp2" ->
        "block.#{layer}.mlp.out.bias"

      [_, layer, mlp, "weight"] when mlp == "mlp1" ->
        {"block.#{layer}.mlp.swiglu.weight.blocks", "block.#{layer}.mlp.swiglu.weight.scales"}

      [_, layer, mlp, "weight"] when mlp == "mlp2" ->
        {"block.#{layer}.mlp.out.weight.blocks", "block.#{layer}.mlp.out.weight.scales"}

      _other ->
        name
    end
  end

  defp ensure_dependency(module, app) do
    if Code.ensure_loaded?(module), do: :ok, else: {:error, {:missing_optional_dependency, app}}
  end
end
