defmodule Obscura.PrivacyFilter.Weights.MXFP4Test do
  use ExUnit.Case, async: true

  alias Obscura.PrivacyFilter.Weights.MXFP4

  test "decodes low nibble before high nibble using exponent scales" do
    blocks = Nx.tensor([[0x21, 0xFE]], type: {:u, 8})
    scales = Nx.tensor([127], type: {:u, 8})

    assert {:ok, decoded} = MXFP4.decode(blocks, scales)
    assert Nx.shape(decoded) == {4}
    assert_close(decoded, [0.5, 1.0, -4.0, -6.0])
  end

  test "applies exponent scale bias" do
    blocks = Nx.tensor([[0x21]], type: {:u, 8})
    scales = Nx.tensor([128], type: {:u, 8})

    assert {:ok, decoded} = MXFP4.decode(blocks, scales)
    assert_close(decoded, [1.0, 2.0])
  end

  test "rejects incompatible block and scale shapes" do
    blocks = Nx.tensor([[0x21, 0x43]], type: {:u, 8})
    scales = Nx.tensor([127, 127], type: {:u, 8})

    assert {:error, {:mxfp4_shape_mismatch, [1, 2], [2]}} = MXFP4.decode(blocks, scales)
  end

  defp assert_close(left, right) do
    assert Nx.all_close(left, Nx.tensor(right), atol: 1.0e-5, rtol: 1.0e-5)
  end
end
