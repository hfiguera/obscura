defmodule Obscura.Recognizer.NER.RealModelTest do
  use ExUnit.Case, async: false

  alias Obscura.Recognizer.NER
  alias Obscura.Recognizer.NER.Serving
  alias Obscura.Vault.Memory

  @moduletag :real_model
  @moduletag timeout: 300_000

  test "dslim bert base NER runs through Obscura analyze, redaction, and vault flow" do
    text = "Rachel works at Google in Paris."

    assert {:ok, serving} =
             Serving.build(
               model: :dslim_bert_base_ner,
               compile: [batch_size: 1, sequence_length: 32],
               defn_options: defn_options(),
               recognizer_timeout: 60_000
             )

    opts = [
      entities: [:person, :organization, :location],
      recognizers: [{NER, serving: serving, label_map: serving.model_spec.label_map}],
      recognizer_timeout: 60_000
    ]

    assert {:ok, results} = Obscura.analyze(text, opts)
    entities = Enum.map(results, & &1.entity)
    assert :person in entities
    assert :organization in entities
    assert :location in entities

    assert {:ok, redacted} =
             Obscura.redact(text,
               entities: [:person, :organization, :location],
               recognizers: [{NER, serving: serving, label_map: serving.model_spec.label_map}],
               operators: %{default: %{type: :replace, new_value: "[REDACTED]"}},
               recognizer_timeout: 60_000
             )

    assert redacted.text != text

    assert {:ok, vault} = Memory.start_link()

    assert {:ok, pseudonymized} =
             Obscura.redact(text,
               entities: [:person, :organization, :location],
               recognizers: [{NER, serving: serving, label_map: serving.model_spec.label_map}],
               operators: %{default: %{type: :pseudonymize}},
               vault: vault,
               recognizer_timeout: 60_000
             )

    assert pseudonymized.text != text
    assert {:ok, ^text} = Obscura.rehydrate(pseudonymized.text, vault: vault)

    assert {:ok, structured} =
             Obscura.redact(%{message: text},
               entities: [:person, :organization, :location],
               recognizers: [{NER, serving: serving, label_map: serving.model_spec.label_map}],
               operators: %{default: %{type: :replace, new_value: "[REDACTED]"}}
             )

    assert structured.data.message != text

    assert {:ok, messages, llm_vault} =
             Obscura.LLM.redact_messages(
               [%{role: "user", content: text}],
               entities: [:person, :organization, :location],
               recognizers: [{NER, serving: serving, label_map: serving.model_spec.label_map}],
               create_vault: true
             )

    assert [%{content: safe_content}] = messages
    assert safe_content != text
    assert {:ok, ^text} = Obscura.LLM.rehydrate_response(safe_content, vault: llm_vault)
  end

  defp defn_options do
    exla = Module.concat(["EXLA"])

    if Code.ensure_loaded?(exla) do
      [compiler: exla]
    else
      []
    end
  end
end
