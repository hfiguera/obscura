defmodule Obscura.PrivacyFilter.DTypesTest do
  use ExUnit.Case, async: true

  alias Obscura.PrivacyFilter.DTypes
  alias Obscura.PrivacyFilter.Weights

  test "parses supported Python torch dtype names" do
    assert {:ok,
            %{
              "embedding.weight" => "torch.bfloat16",
              "classifier.bias" => "torch.float32"
            }} =
             DTypes.parse(%{
               "embedding.weight" => "torch.bfloat16",
               "classifier.bias" => "torch.float32"
             })
  end

  test "rejects unsupported dtype names" do
    assert {:error, {:unsupported_dtype_value, "tensor", "torch.complex64"}} =
             DTypes.parse(%{"tensor" => "torch.complex64"})
  end

  test "validates declared dtype entries against safetensors metadata" do
    weights =
      weights!(%{
        "embedding.weight" => {:bf, 16},
        "classifier.bias" => {:f, 32},
        "norm.scale" => {:f, 32}
      })

    assert {:ok, summary} =
             DTypes.validate_against_weights(
               %{
                 "embedding.weight" => "torch.bfloat16",
                 "classifier.bias" => "torch.float32"
               },
               weights
             )

    assert summary.declared_count == 2
    assert summary.tensor_count == 3
    assert summary.missing_entries == ["norm.scale"]
  end

  test "rejects extra dtype entries" do
    weights = weights!(%{"embedding.weight" => {:bf, 16}})

    assert {:error, {:unknown_dtype_entries, ["missing.weight"]}} =
             DTypes.validate_against_weights(
               %{
                 "embedding.weight" => "torch.bfloat16",
                 "missing.weight" => "torch.float32"
               },
               weights
             )
  end

  test "rejects dtype mismatches" do
    weights = weights!(%{"embedding.weight" => {:f, 32}})

    assert {:error, {:dtype_mismatch, "embedding.weight", "torch.bfloat16", {:bf, 16}, {:f, 32}}} =
             DTypes.validate_against_weights(%{"embedding.weight" => "torch.bfloat16"}, weights)
  end

  defp weights!(types) do
    %Weights{
      path: "memory",
      tensor_name_to_file: Map.new(types, fn {name, _type} -> {name, "memory.safetensors"} end),
      tensor_metadata:
        Map.new(types, fn {name, type} ->
          {name, %{shape: {1}, type: type, byte_offset: 0, byte_size: 1}}
        end)
    }
  end
end
