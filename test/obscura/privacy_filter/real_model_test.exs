defmodule Obscura.PrivacyFilter.RealModelTest do
  use ExUnit.Case, async: false

  alias Obscura.Recognizer.PrivacyFilter.Native
  alias Obscura.Vault.Memory

  @moduletag :real_model
  @moduletag :privacy_filter
  @moduletag timeout: 900_000

  test "native privacy-filter checkpoint runs through analyze, redaction, and vault flow" do
    checkpoint = checkpoint!()
    text = "Ada Lovelace can be reached at ada@example.com or 415-555-0199."

    assert {:ok, serving} =
             Native.new(
               checkpoint: checkpoint,
               backend: backend!(),
               n_ctx: 128,
               decoder: :viterbi,
               trim_span_whitespace: true,
               discard_overlapping_spans: true
             )

    recognizers = [{Native, serving: serving}]
    entities = Native.supported_entities()

    assert {:ok, results} = Obscura.analyze(text, entities: entities, recognizers: recognizers)
    assert [_result | _rest] = results
    assert Enum.any?(results, &(&1.entity in [:person, :email, :phone]))

    assert {:ok, redacted} =
             Obscura.redact(text,
               entities: entities,
               recognizers: recognizers,
               operators: %{default: %{type: :replace, new_value: "[REDACTED]"}}
             )

    assert redacted.text != text

    assert {:ok, vault} = Memory.start_link()

    assert {:ok, pseudonymized} =
             Obscura.redact(text,
               entities: entities,
               recognizers: recognizers,
               operators: %{default: %{type: :pseudonymize}},
               vault: vault
             )

    assert pseudonymized.text != text
    assert {:ok, ^text} = Obscura.rehydrate(pseudonymized.text, vault: vault)
  end

  defp checkpoint! do
    case System.fetch_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT") do
      {:ok, checkpoint} when checkpoint != "" ->
        checkpoint

      _other ->
        flunk("""
        Set OBSCURA_PRIVACY_FILTER_CHECKPOINT to a local privacy-filter checkpoint directory.

        Example:
          hf download openai/privacy-filter config.json model.safetensors --local-dir .cache/privacy-filter/openai
          OBSCURA_PRIVACY_FILTER_CHECKPOINT=.cache/privacy-filter/openai mix test --include real_model test/obscura/privacy_filter/real_model_test.exs
        """)
    end
  end

  defp backend! do
    case System.get_env("OBSCURA_PRIVACY_FILTER_BACKEND", "exla") do
      "exla" -> exla_backend!()
      "binary" -> :binary
      "emily" -> emily_backend!()
      other -> flunk("Unsupported OBSCURA_PRIVACY_FILTER_BACKEND=#{inspect(other)}")
    end
  end

  defp exla_backend! do
    unless Code.ensure_loaded?(EXLA) and Code.ensure_loaded?(EXLA.Backend) do
      flunk("""
      Native privacy-filter real checkpoint tests require EXLA by default.

      Run with:
        OBSCURA_REAL_MODEL=1 OBSCURA_PRIVACY_FILTER_BACKEND=exla OBSCURA_PRIVACY_FILTER_CHECKPOINT=.cache/privacy-filter/openai mix test --include real_model test/obscura/privacy_filter/real_model_test.exs

      Or explicitly set OBSCURA_PRIVACY_FILTER_BACKEND=binary to exercise the slow CPU BinaryBackend path.
      """)
    end

    :exla
  end

  defp emily_backend! do
    unless Code.ensure_loaded?(Emily) and Code.ensure_loaded?(Emily.Backend) and
             Code.ensure_loaded?(Emily.Compiler) do
      flunk("""
      Native privacy-filter Emily real checkpoint tests require the optional Emily dependency.

      Run with:
        OBSCURA_REAL_MODEL=1 OBSCURA_REAL_MODEL_BACKEND=emily OBSCURA_PRIVACY_FILTER_BACKEND=emily OBSCURA_EMILY_FALLBACK=raise OBSCURA_PRIVACY_FILTER_CHECKPOINT=.cache/privacy-filter/openai mix test --include real_model test/obscura/privacy_filter/real_model_test.exs
      """)
    end

    :emily
  end
end
