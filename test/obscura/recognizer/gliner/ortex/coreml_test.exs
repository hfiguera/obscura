defmodule Obscura.Recognizer.GLiNER.Ortex.CoreMLTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.GLiNER.Ortex.CoreML

  test "defaults request MLProgram with CPU and GPU compute units" do
    assert {:ok, options} = CoreML.validate_options([])

    assert options == [
             model_format: :ml_program,
             compute_units: :cpu_and_gpu,
             require_static_input_shapes: false,
             enable_on_subgraphs: false
           ]
  end

  test "rejects unknown and invalid CoreML options" do
    assert {:error, {:unknown_coreml_options, [:fallback]}} =
             CoreML.validate_options(fallback: :cpu)

    assert {:error, {:invalid_coreml_compute_units, :gpu_only}} =
             CoreML.validate_options(compute_units: :gpu_only)

    assert {:error, {:invalid_coreml_require_static_input_shapes, :yes}} =
             CoreML.validate_options(require_static_input_shapes: :yes)
  end

  test "profile summary proves CoreML participation while retaining GPU-only limitation" do
    events = [
      node_event("CoreMLExecutionProvider", 40),
      node_event("CPUExecutionProvider", 10),
      %{"cat" => "Session", "dur" => 100}
    ]

    assert %{
             status: :coreml_participation_verified,
             coreml_event_count: 1,
             cpu_event_count: 1,
             coreml_participated: true,
             cpu_fallback_observed: true,
             gpu_only_proven: false,
             provider_duration_us: %{
               "CoreMLExecutionProvider" => 40,
               "CPUExecutionProvider" => 10
             }
           } = CoreML.summarize_events(events)
  end

  test "profile summary rejects a CPU-only trace as CoreML evidence" do
    summary = CoreML.summarize_events([node_event("CPUExecutionProvider", 10)])

    assert summary.status == :coreml_not_assigned
    refute summary.coreml_participated
    assert summary.cpu_fallback_observed
  end

  test "profile summary is inconclusive when provider fields are absent" do
    summary =
      CoreML.summarize_events([
        %{"cat" => "Node", "dur" => 10, "args" => %{"op_name" => "MatMul"}}
      ])

    assert summary.status == :provider_assignment_unavailable
    assert summary.unassigned_node_event_count == 1
    refute summary.coreml_participated
  end

  test "reads both raw event arrays and traceEvents objects" do
    path = Path.join(System.tmp_dir!(), "obscura-coreml-profile-#{System.unique_integer()}.json")
    on_exit(fn -> File.rm(path) end)

    File.write!(
      path,
      Jason.encode!(%{"traceEvents" => [node_event("CoreMLExecutionProvider", 1)]})
    )

    assert {:ok, %{profile_path: ^path, coreml_participated: true}} =
             CoreML.summarize_profile(path)
  end

  defp node_event(provider, duration) do
    %{
      "cat" => "Node",
      "dur" => duration,
      "args" => %{"provider" => provider}
    }
  end
end
