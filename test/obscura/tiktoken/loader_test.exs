defmodule Obscura.Tiktoken.LoaderTest do
  use ExUnit.Case, async: true

  alias Obscura.Tiktoken.Loader

  test "loads a tiktoken BPE file and validates hash" do
    path = fixture_path("toy.tiktoken")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "YQ== 0\nYg== 1\nYWI= 2\n")
    hash = :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

    assert {:ok, ranks} = Loader.load_tiktoken_bpe(path, expected_hash: hash)
    assert ranks == %{"a" => 0, "b" => 1, "ab" => 2}
  end

  test "rejects hash mismatches" do
    path = fixture_path("hash_mismatch.tiktoken")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "YQ== 0\n")

    assert {:error, {:hash_mismatch, _expected, _actual}} =
             Loader.load_tiktoken_bpe(path, expected_hash: String.duplicate("0", 64))
  end

  test "rejects duplicate ranks and malformed lines" do
    duplicate_path = fixture_path("duplicate.tiktoken")
    malformed_path = fixture_path("malformed.tiktoken")
    File.mkdir_p!(Path.dirname(duplicate_path))
    File.write!(duplicate_path, "YQ== 0\nYg== 0\n")
    File.write!(malformed_path, "not-valid\n")

    assert {:error, {:duplicate_bpe_rank, 2, 0}} =
             Loader.load_tiktoken_bpe(duplicate_path)

    assert {:error, {:invalid_bpe_line, 1, :invalid_column_count}} =
             Loader.load_tiktoken_bpe(malformed_path)
  end

  defp fixture_path(name) do
    Path.join([System.tmp_dir!(), "obscura_tiktoken_loader_test", name])
  end
end
