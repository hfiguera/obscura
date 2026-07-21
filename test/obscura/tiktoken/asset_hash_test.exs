defmodule Obscura.Tiktoken.AssetHashTest do
  use ExUnit.Case, async: true

  @fixture_path Path.expand("../../fixtures/tiktoken/parity/generated.json", __DIR__)

  test "vendored tiktoken assets match fixture metadata hashes" do
    %{"metadata" => %{"asset_hashes" => hashes}} =
      @fixture_path
      |> File.read!()
      |> Jason.decode!()

    for {filename, expected_hash} <- hashes do
      path = Path.join(tiktoken_priv_dir(), filename)

      assert File.exists?(path), "missing vendored tiktoken asset #{filename}"

      actual_hash =
        path
        |> File.read!()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      assert actual_hash == expected_hash, "hash mismatch for #{filename}"
    end
  end

  defp tiktoken_priv_dir do
    Application.app_dir(:obscura, "priv/tiktoken")
  end
end
