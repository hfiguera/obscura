defmodule Obscura.Tiktoken.OffsetPythonParityTest do
  use ExUnit.Case, async: true

  alias Obscura.Tiktoken
  alias Obscura.Tiktoken.Encoding

  @fixture_path Path.expand("../../fixtures/tiktoken/parity/generated.json", __DIR__)

  test "offset-focused fixtures match Python tiktoken decode_with_offsets" do
    fixtures =
      @fixture_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("cases")
      |> Enum.filter(&(&1["offset_focus"] and not Map.has_key?(&1, "expected_error")))

    assert Enum.count_until(fixtures, 100) == 100

    for fixture <- fixtures do
      enc = Tiktoken.get_encoding!(fixture["encoding"])

      assert {:ok, {fixture["decoded_text"], fixture["offsets"]}} ==
               Encoding.decode_with_offsets(enc, fixture["tokens"]),
             "offset mismatch for #{fixture_id(fixture)}"
    end
  end

  test "privacy-filter o200k_base fixtures include offset parity evidence" do
    fixtures =
      @fixture_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("cases")
      |> Enum.filter(fn fixture ->
        fixture["encoding"] == "o200k_base" and fixture["privacy_filter_focus"] and
          fixture["offset_focus"]
      end)

    assert Enum.count_until(fixtures, 2) == 2

    for fixture <- fixtures do
      enc = Tiktoken.get_encoding!("o200k_base")

      assert {:ok, {fixture["decoded_text"], fixture["offsets"]}} ==
               Encoding.decode_with_offsets(enc, fixture["tokens"]),
             "privacy-filter offset mismatch for #{fixture["case"]}"
    end
  end

  defp fixture_id(fixture) do
    "#{fixture["encoding"]}/#{fixture["category"]}/#{fixture["case"]}"
  end
end
