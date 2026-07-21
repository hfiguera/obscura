defmodule Mix.Tasks.ObscuraExportPredictionsTest do
  use ExUnit.Case, async: false

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(previous_shell)
    end)

    :ok
  end

  test "export predictions task writes JSONL without raw text" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "obscura_phase5_predictions_#{System.unique_integer([:positive])}"
      )

    out = Path.join(dir, "predictions.jsonl")

    Mix.Task.rerun("obscura.export.predictions", [
      "--dataset",
      "synth_dataset_v2",
      "--profile",
      "regex_only",
      "--limit",
      "1",
      "--out",
      out
    ])

    assert_receive {:mix_shell, :info, [_message]}
    assert [line] = out |> File.read!() |> String.split("\n", trim: true)
    assert {:ok, decoded} = Jason.decode(line)
    refute Map.has_key?(decoded, "text")
    assert is_list(decoded["predictions"])
  end
end
