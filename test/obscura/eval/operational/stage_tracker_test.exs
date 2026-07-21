defmodule Obscura.Eval.Operational.StageTrackerTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Operational.StageTracker
  alias Obscura.Recognizer.NER.Serving

  defmodule BumblebeeStub do
    def load_model(model, _opts) do
      send(self(), {:model_source, model})
      {:ok, :model}
    end

    def load_tokenizer(tokenizer, _opts) do
      send(self(), {:tokenizer_source, tokenizer})
      {:ok, :tokenizer}
    end
  end

  defmodule TextStub do
    def token_classification(_model, _tokenizer, _opts), do: :serving
  end

  test "NER construction reports each lifecycle stage exactly once" do
    {:ok, tracker} = StageTracker.start_link()

    assert {:ok, _serving} =
             Serving.build(
               model: :dslim_bert_base_ner,
               stage_observer: StageTracker.observer(tracker),
               offline: true,
               bumblebee_module: BumblebeeStub,
               bumblebee_text_module: TextStub,
               dependency_checker: fn _module -> true end
             )

    assert_received {:model_source, {:hf, "dslim/bert-base-NER", [offline: true]}}
    assert_received {:tokenizer_source, {:hf, "google-bert/bert-base-cased", [offline: true]}}

    snapshot = StageTracker.snapshot(tracker)

    for stage <- [
          :model_registry,
          :backend_configuration,
          :dependency_validation,
          :compiler_start,
          :model_load,
          :tokenizer_load,
          :serving_construction
        ] do
      assert snapshot.counts[stage] == 1
    end
  end
end
