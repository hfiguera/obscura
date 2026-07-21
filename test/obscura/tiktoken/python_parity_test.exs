defmodule Obscura.Tiktoken.PythonParityTest do
  use ExUnit.Case, async: true

  alias Obscura.Tiktoken
  alias Obscura.Tiktoken.Encoding

  @fixture_path Path.expand("../../fixtures/tiktoken/parity/generated.json", __DIR__)

  test "fixture metadata records deterministic Python tiktoken generation inputs" do
    %{"metadata" => metadata, "cases" => cases} = load_fixtures()

    assert metadata["generator"] == "eval/tiktoken/generate_tiktoken_fixtures.py"
    assert is_binary(metadata["python_version"])
    assert is_binary(metadata["tiktoken_version"])
    assert is_integer(metadata["seed"])
    assert Enum.sort(metadata["encodings"]) == Tiktoken.list_encoding_names()
    assert metadata["case_count"] == length(cases)
    assert metadata["case_count"] > 300

    assert %{
             "cl100k_base.tiktoken" => _,
             "o200k_base.tiktoken" => _,
             "p50k_base.tiktoken" => _,
             "r50k_base.tiktoken" => _
           } = metadata["asset_hashes"]
  end

  test "matches generated Python tiktoken fixtures" do
    %{"cases" => fixtures} = load_fixtures()

    for fixture <- fixtures do
      enc = Tiktoken.get_encoding!(fixture["encoding"])
      opts = encode_opts(fixture)

      if expected_error = fixture["expected_error"] do
        assert Encoding.encode(enc, fixture["text"], opts) ==
                 {:error, {:disallowed_special_token, expected_error["special"]}},
               "expected disallowed special token for #{fixture_id(fixture)}"
      else
        assert Encoding.encode!(enc, fixture["text"], opts) == fixture["tokens"],
               "token mismatch for #{fixture_id(fixture)}"

        assert Encoding.encode_ordinary!(enc, fixture["text"]) == fixture["ordinary_tokens"],
               "ordinary token mismatch for #{fixture_id(fixture)}"

        assert Encoding.decode_bytes!(enc, fixture["tokens"]) ==
                 Base.decode64!(fixture["decoded_bytes_b64"]),
               "decoded bytes mismatch for #{fixture_id(fixture)}"

        assert Encoding.decode!(enc, fixture["tokens"], errors: :strict) ==
                 fixture["decoded_text"],
               "decoded text mismatch for #{fixture_id(fixture)}"

        assert {:ok, {fixture["decoded_text"], fixture["offsets"]}} ==
                 Encoding.decode_with_offsets(enc, fixture["tokens"]),
               "offset mismatch for #{fixture_id(fixture)}"

        token_bytes =
          Enum.map(fixture["tokens"], fn token ->
            {:ok, bytes} = Encoding.decode_single_token_bytes(enc, token)
            Base.encode64(bytes)
          end)

        assert token_bytes == fixture["token_bytes_b64"],
               "token byte mismatch for #{fixture_id(fixture)}"
      end
    end
  end

  test "fixture suite covers privacy-filter o200k_base and offset-focused cases" do
    %{"cases" => fixtures} = load_fixtures()

    privacy_filter_cases =
      Enum.filter(fixtures, &(&1["privacy_filter_focus"] and &1["encoding"] == "o200k_base"))

    offset_cases = Enum.filter(fixtures, & &1["offset_focus"])
    expected_error_cases = Enum.filter(fixtures, &Map.has_key?(&1, "expected_error"))

    assert Enum.count_until(privacy_filter_cases, 3) == 3
    assert Enum.count_until(offset_cases, 100) == 100
    assert [_expected_error | _rest] = expected_error_cases
  end

  defp load_fixtures do
    @fixture_path
    |> File.read!()
    |> Jason.decode!()
  end

  defp encode_opts(%{"allowed_special" => "all"}), do: [allowed_special: :all]

  defp encode_opts(%{"allowed_special" => allowed, "disallowed_special" => disallowed})
       when is_list(allowed) do
    [allowed_special: allowed] ++ disallowed_opts(disallowed)
  end

  defp encode_opts(%{"disallowed_special" => disallowed}), do: disallowed_opts(disallowed)
  defp encode_opts(_fixture), do: []

  defp disallowed_opts("empty"), do: [disallowed_special: []]
  defp disallowed_opts("all"), do: [disallowed_special: :all]
  defp disallowed_opts(values) when is_list(values), do: [disallowed_special: values]
  defp disallowed_opts(_other), do: []

  defp fixture_id(fixture) do
    "#{fixture["encoding"]}/#{fixture["category"]}/#{fixture["case"]}"
  end
end
