defmodule Obscura.Recognizer.GLiNER.UrchadeRealModelTest do
  use ExUnit.Case, async: false

  alias Obscura.Recognizer.GLiNER.Ortex

  @tag :gliner_urchade
  test "Urchade GLiNER runs through Ortex with exact byte offsets" do
    model_dir = System.fetch_env!("OBSCURA_GLINER_URCHADE_MODEL_DIR")

    assert {:ok, serving} =
             Ortex.build(model: :urchade_gliner_multi_pii_v1, model_dir: model_dir)

    text = "José Álvarez joined Acme GmbH in München."
    assert {:ok, spans} = Ortex.run(serving, text)

    assert Enum.any?(spans, fn span ->
             span.entity == :person and span.byte_start == 0 and span.byte_end == 14
           end)

    assert Enum.all?(spans, fn span ->
             binary_part(text, span.byte_start, span.byte_end - span.byte_start) == span.text
           end)
  end
end
