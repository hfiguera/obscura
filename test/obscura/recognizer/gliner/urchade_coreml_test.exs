defmodule Obscura.Recognizer.GLiNER.UrchadeCoreMLTest do
  use ExUnit.Case, async: false

  alias Obscura.Recognizer.GLiNER.Ortex

  @tag :gliner_urchade
  @tag :gliner_ortex
  test "CoreML preserves Urchade spans and records provider participation" do
    model_dir = System.fetch_env!("OBSCURA_GLINER_URCHADE_MODEL_DIR")

    profile_prefix =
      Path.join(
        System.tmp_dir!(),
        "obscura-urchade-coreml-#{System.unique_integer([:positive])}"
      )

    assert {:ok, serving} =
             Ortex.build(
               model: :urchade_gliner_multi_pii_v1,
               model_dir: model_dir,
               execution_providers: [:coreml],
               profile_prefix: profile_prefix
             )

    assert {:ok, spans} = Ortex.run(serving, "Rachel works at Google in Paris.")

    assert Enum.map(spans, &{&1.entity, &1.text, &1.byte_start, &1.byte_end}) == [
             {:person, "Rachel", 0, 6},
             {:organization, "Google", 16, 22},
             {:location, "Paris", 26, 31}
           ]

    assert {:ok, evidence} = Ortex.finish_profiling(serving)
    assert evidence.status == :coreml_participation_verified
    assert evidence.coreml_event_count > 0
    assert evidence.cpu_fallback_observed
    refute evidence.gpu_only_proven

    on_exit(fn -> File.rm(evidence.profile_path) end)
  end
end
