defmodule Obscura.Recognizer.GLiNER.RealModelTest do
  use ExUnit.Case, async: false

  alias Obscura.Recognizer.GLiNER.Ortex

  @tag :gliner_ortex
  test "knowledgator GLiNER runs through Ortex adapter" do
    model_dir = System.fetch_env!("OBSCURA_GLINER_MODEL_DIR")

    assert {:ok, serving} = Ortex.build(model_dir: model_dir)
    assert {:ok, spans} = Ortex.run(serving, "Rachel works at Google in Paris.")
    assert is_list(spans)
  end
end
