defmodule Obscura.PrivacyFilter.Checkpoint.LayoutTest do
  use ExUnit.Case, async: true

  alias Obscura.PrivacyFilter.Checkpoint.Layout

  test "normalizes supported checkpoint layout names" do
    assert Layout.normalize(nil) == {:ok, :native}
    assert Layout.normalize(:native) == {:ok, :native}
    assert Layout.normalize("native") == {:ok, :native}
    assert Layout.normalize(:python_original) == {:ok, :python_original}
    assert Layout.normalize("python_original") == {:ok, :python_original}
    assert Layout.normalize("python-original") == {:ok, :python_original}
  end

  test "rejects unsupported checkpoint layout names" do
    assert {:error, {:unsupported_privacy_filter_checkpoint_layout, :other, supported}} =
             Layout.normalize(:other)

    assert supported == [:native, :python_original]
  end

  test "native layout rejects Python original artifacts unless explicitly requested" do
    path = checkpoint_dir!(["config.json", "model.safetensors", "dtypes.json"])

    assert {:error, {:python_original_layout_requires_explicit_opt_in, ^path}} =
             Layout.validate(path, :native)
  end

  test "python original layout requires all original checkpoint files" do
    path = checkpoint_dir!(["config.json", "model.safetensors", "dtypes.json"])

    assert {:error, {:missing_python_original_checkpoint_files, ^path, missing}} =
             Layout.validate(path, :python_original)

    assert missing == [Path.join(path, "viterbi_calibration.json")]
  end

  test "python original layout accepts the complete original file contract" do
    path =
      checkpoint_dir!([
        "config.json",
        "model.safetensors",
        "dtypes.json",
        "viterbi_calibration.json"
      ])

    assert :ok = Layout.validate(path, :python_original)
  end

  defp checkpoint_dir!(files) do
    path =
      Path.join(
        System.tmp_dir!(),
        "obscura-privacy-filter-layout-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    Enum.each(files, &File.write!(Path.join(path, &1), "stub"))
    path
  end
end
