defmodule Obscura.PrivacyFilter.WeightsTest do
  use ExUnit.Case, async: true

  alias Obscura.PrivacyFilter.Weights

  test "load indexes tensor metadata across safetensors shards" do
    path = tmp_dir!()
    File.write!(Path.join(path, "config.json"), "{}")

    Safetensors.write!(Path.join(path, "model-00001-of-00002.safetensors"), %{
      "embedding.weight" => Nx.tensor([[1.0, 2.0]])
    })

    Safetensors.write!(Path.join(path, "model-00002-of-00002.safetensors"), %{
      "score.weight" => Nx.tensor([[3.0, 4.0]])
    })

    assert {:ok, weights} = Weights.load(path)
    assert map_size(weights.tensor_name_to_file) == 2

    assert {:ok, embedding_metadata} = Weights.metadata(weights, "embedding.weight")
    assert embedding_metadata.shape == {1, 2}
    assert embedding_metadata.byte_size > 0

    assert {:ok, score} = Weights.get(weights, "score.weight")
    assert Nx.to_flat_list(score) == [3.0, 4.0]
  end

  test "load rejects duplicate tensor names across safetensors shards" do
    path = tmp_dir!()
    File.write!(Path.join(path, "config.json"), "{}")

    Safetensors.write!(Path.join(path, "model-00001-of-00002.safetensors"), %{
      "duplicate.weight" => Nx.tensor([1.0])
    })

    Safetensors.write!(Path.join(path, "model-00002-of-00002.safetensors"), %{
      "duplicate.weight" => Nx.tensor([2.0])
    })

    assert {:error, {:duplicate_tensor_name, "duplicate.weight"}} = Weights.load(path)
  end

  test "load rejects safetensors files whose payload is shorter than indexed tensor ranges" do
    path = tmp_dir!()
    File.write!(Path.join(path, "config.json"), "{}")
    safetensors_path = Path.join(path, "model.safetensors")

    Safetensors.write!(safetensors_path, %{"x" => Nx.tensor([[1.0, 2.0]])})

    contents = File.read!(safetensors_path)
    File.write!(safetensors_path, binary_part(contents, 0, byte_size(contents) - 1))

    assert {:error, {:incomplete_safetensors_file, ^safetensors_path, actual, expected}} =
             Weights.load(path)

    assert actual == byte_size(contents) - 1
    assert expected == byte_size(contents)
  end

  defp tmp_dir! do
    path =
      Path.join(
        System.tmp_dir!(),
        "obscura-privacy-filter-weights-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end
end
