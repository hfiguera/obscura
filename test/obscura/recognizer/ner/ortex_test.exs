defmodule Obscura.Recognizer.NER.OrtexTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.NER.Ortex

  test "exposes analyzer recognizer callbacks" do
    assert Ortex.name() == :ner_ortex

    assert Ortex.supported_entities() == [
             :credit_card,
             :date_time,
             :email,
             :id,
             :ip_address,
             :location,
             :organization,
             :password,
             :patient_id,
             :person,
             :phone,
             :street_address,
             :url,
             :us_driver_license,
             :us_ssn,
             :username,
             :zip_code
           ]
  end

  test "returns clear missing Ortex dependency error" do
    assert {:error, {:missing_optional_dependency, :ortex}} =
             Ortex.build(dependency_checker: fn _module -> false end)
  end

  test "returns clear missing Tokenizers dependency error" do
    assert {:error, {:missing_optional_dependency, :tokenizers}} =
             Ortex.build(dependency_checker: fn module -> module == :"Elixir.Ortex" end)
  end

  test "requires a local model directory" do
    checker = fn
      :"Elixir.Ortex" -> true
      :"Elixir.Tokenizers.Tokenizer" -> true
      _module -> false
    end

    assert {:error, :missing_ner_ortex_model_dir} =
             Ortex.build(dependency_checker: checker)
  end

  test "analyzer callback requires an explicit serving" do
    assert {:error, :missing_ner_ortex_serving} = Ortex.analyze("Alice", [])
    assert {:error, :invalid_ner_ortex_serving} = Ortex.analyze("Alice", serving: :bad)
  end

  test "outside tokens break equal-label groups" do
    tokens = [
      %{label: "I-CITY", score: 0.9, start: 0, end: 5},
      %{label: "O", score: 0.99, start: 6, end: 9},
      %{label: "I-CITY", score: 0.8, start: 10, end: 15}
    ]

    assert [first, second] =
             Ortex.debug_aggregate_tokens(tokens, "Paris and Tokyo", trim_boundaries: false)

    assert %{label: "CITY", start: 0, end: 5} = first
    assert %{label: "CITY", start: 10, end: 15} = second
  end
end
