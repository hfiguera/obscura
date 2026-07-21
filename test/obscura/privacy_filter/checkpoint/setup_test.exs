defmodule Obscura.PrivacyFilter.Checkpoint.SetupTest do
  use ExUnit.Case, async: true

  alias Obscura.PrivacyFilter.Checkpoint.Setup

  test "builds a Hugging Face download plan for the default checkpoint" do
    assert {:ok, plan} = Setup.plan([])

    assert plan.repo == "openai/privacy-filter"
    assert plan.revision == "main"
    assert plan.layout == :native
    assert plan.checkpoint == ".cache/privacy-filter/openai"

    assert [
             %{
               file: "config.json",
               source: "config.json",
               output: ".cache/privacy-filter/openai/config.json",
               url: "https://huggingface.co/openai/privacy-filter/resolve/main/config.json"
             },
             %{
               file: "model.safetensors",
               source: "model.safetensors",
               output: ".cache/privacy-filter/openai/model.safetensors",
               url: "https://huggingface.co/openai/privacy-filter/resolve/main/model.safetensors"
             }
           ] = plan.files
  end

  test "builds a Python original checkpoint plan" do
    assert {:ok, plan} =
             Setup.plan(
               layout: "python-original",
               checkpoint: ".cache/privacy-filter/openai-original"
             )

    assert plan.layout == :python_original

    assert [
             %{
               file: "config.json",
               source: "original/config.json",
               output: ".cache/privacy-filter/openai-original/config.json",
               url:
                 "https://huggingface.co/openai/privacy-filter/resolve/main/original/config.json"
             },
             %{file: "dtypes.json", source: "original/dtypes.json"},
             %{file: "model.safetensors", source: "original/model.safetensors"},
             %{file: "viterbi_calibration.json", source: "original/viterbi_calibration.json"}
           ] = plan.files
  end

  test "rejects unsupported layouts" do
    assert {:error, {:unsupported_privacy_filter_checkpoint_layout, "other"}} =
             Setup.plan(layout: "other")
  end

  test "rejects nested file paths" do
    assert {:error, {:invalid_privacy_filter_files, ["nested/config.json"]}} =
             Setup.plan(files: ["nested/config.json"])
  end

  test "rejects unsupported download tools" do
    assert {:error, {:unsupported_privacy_filter_download_tool, "other"}} =
             Setup.plan(download_tool: "other")
  end

  test "uses resumable curl arguments" do
    assert {:ok, plan} = Setup.plan(files: ["config.json"], checkpoint: "tmp/checkpoint")
    [file_plan] = plan.files

    assert {"curl",
            [
              "--silent",
              "--show-error",
              "-L",
              "--fail",
              "--continue-at",
              "-",
              "--create-dirs",
              "--output",
              "tmp/checkpoint/config.json",
              "https://huggingface.co/openai/privacy-filter/resolve/main/config.json"
            ]} = Setup.curl_command(file_plan)
  end

  test "builds Hugging Face CLI download arguments" do
    assert {:ok, plan} =
             Setup.plan(files: ["model.safetensors"], checkpoint: "tmp/checkpoint")

    [file_plan] = plan.files

    assert {"hf",
            [
              "download",
              "openai/privacy-filter",
              "model.safetensors",
              "--revision",
              "main",
              "--local-dir",
              "tmp/checkpoint",
              "--max-workers",
              "1"
            ]} = Setup.hf_command(plan, file_plan, download_tool: :hf, hf_max_workers: 1)
  end

  test "run can download selected files without validation" do
    path =
      Path.join(
        System.tmp_dir!(),
        "obscura-privacy-filter-setup-#{System.unique_integer([:positive])}"
      )

    runner = fn _cmd, args, _opts ->
      output = output_arg(args)
      File.mkdir_p!(Path.dirname(output))
      File.write!(output, "downloaded")
      {"", 0}
    end

    assert {:ok, summary} =
             Setup.run(
               checkpoint: path,
               files: ["config.json"],
               validate: false,
               runner: runner
             )

    assert summary.checkpoint == path
    assert summary.layout == :native
    assert summary.files == ["config.json"]
    assert summary.validation == :skipped
    assert summary.validation_reason == :disabled
    assert File.read!(Path.join(path, "config.json")) == "downloaded"
  end

  test "run can use Hugging Face CLI downloads without validation" do
    path = tmp_dir!("obscura-privacy-filter-setup-hf")

    runner = fn "hf", args, _opts ->
      source = Enum.at(args, 2)
      local_dir = Enum.at(args, 6)
      output = Path.join(local_dir, source)
      File.mkdir_p!(Path.dirname(output))
      File.write!(output, "downloaded with hf")
      {"", 0}
    end

    assert {:ok, summary} =
             Setup.run(
               checkpoint: path,
               files: ["config.json"],
               download_tool: :hf,
               validate: false,
               runner: runner
             )

    assert summary.validation == :skipped
    assert File.read!(Path.join(path, "config.json")) == "downloaded with hf"
  end

  test "run refuses Hugging Face CLI over existing partial safetensors targets" do
    path = tmp_dir!("obscura-privacy-filter-setup-hf-partial")
    output = Path.join(path, "model.safetensors")
    File.write!(output, "partial")

    runner = fn _cmd, _args, _opts ->
      flunk("hf downloader should not run over a partial safetensors target")
    end

    assert {:error, {:privacy_filter_hf_partial_safetensors_unsafe, error}} =
             Setup.run(
               checkpoint: path,
               files: ["model.safetensors"],
               download_tool: :hf,
               validate: false,
               runner: runner
             )

    assert error.file == output
    assert error.actual_size == 7
    assert error.reason =~ "may replace an existing partial safetensors file"
    assert error.resume_curl_command =~ "curl --silent --show-error -L --fail --continue-at -"
    assert error.resume_curl_command =~ output
  end

  test "run still allows curl over existing partial safetensors targets" do
    path = tmp_dir!("obscura-privacy-filter-setup-curl-partial")
    output = Path.join(path, "model.safetensors")
    File.write!(output, "partial")

    runner = fn "curl", args, _opts ->
      output = output_arg(args)
      File.write!(output, "resumed")
      {"", 0}
    end

    assert {:ok, summary} =
             Setup.run(
               checkpoint: path,
               files: ["model.safetensors"],
               validate: false,
               runner: runner
             )

    assert summary.validation == :skipped
    assert File.read!(output) == "resumed"
  end

  test "run skips native validation for Python original layout" do
    path =
      Path.join(
        System.tmp_dir!(),
        "obscura-privacy-filter-python-original-#{System.unique_integer([:positive])}"
      )

    runner = fn _cmd, args, _opts ->
      output = output_arg(args)
      File.mkdir_p!(Path.dirname(output))
      File.write!(output, "downloaded")
      {"", 0}
    end

    assert {:ok, summary} =
             Setup.run(
               checkpoint: path,
               layout: :python_original,
               files: ["config.json"],
               runner: runner
             )

    assert summary.layout == :python_original
    assert summary.validation == :skipped
    assert summary.validation_reason == :python_original_layout
    assert File.read!(Path.join(path, "config.json")) == "downloaded"
  end

  test "run flattens Hugging Face CLI downloads for Python original layout" do
    path = tmp_dir!("obscura-privacy-filter-python-original-hf")

    runner = fn "hf", args, _opts ->
      source = Enum.at(args, 2)
      local_dir = Enum.at(args, 6)
      output = Path.join(local_dir, source)
      File.mkdir_p!(Path.dirname(output))
      File.write!(output, "downloaded from #{source}")
      {"", 0}
    end

    assert {:ok, summary} =
             Setup.run(
               checkpoint: path,
               layout: :python_original,
               files: ["config.json"],
               download_tool: :hf,
               runner: runner
             )

    assert summary.layout == :python_original
    assert File.read!(Path.join(path, "config.json")) == "downloaded from original/config.json"
    refute File.exists?(Path.join([path, "original", "config.json"]))
  end

  test "run returns download errors with file and exit status" do
    runner = fn _cmd, _args, _opts -> {"forbidden", 22} end

    assert {:error, {:privacy_filter_download_failed, "config.json", 22, "forbidden"}} =
             Setup.run(
               checkpoint: Path.join(System.tmp_dir!(), "obscura-privacy-filter-setup-failure"),
               files: ["config.json"],
               validate: false,
               runner: runner
             )
  end

  test "run can time out slow download commands" do
    script = slow_script!()

    assert {:error, {:privacy_filter_download_timed_out, "config.json", 20, _output}} =
             Setup.run(
               checkpoint: tmp_dir!("obscura-privacy-filter-setup-timeout"),
               files: ["config.json"],
               validate: false,
               curl: script,
               download_timeout: 20
             )
  end

  test "run treats download_timeout as total wall time, not idle output time" do
    script = noisy_script!()

    assert {:error, {:privacy_filter_download_timed_out, "config.json", 2000, output}} =
             Setup.run(
               checkpoint: tmp_dir!("obscura-privacy-filter-setup-noisy-timeout"),
               files: ["config.json"],
               validate: false,
               curl: script,
               download_timeout: 2000
             )

    assert output =~ "tick"
  end

  test "run caps captured downloader output on timeout" do
    script = burst_then_sleep_script!()

    assert {:error, {:privacy_filter_download_timed_out, "config.json", 1000, output}} =
             Setup.run(
               checkpoint: tmp_dir!("obscura-privacy-filter-setup-output-limit"),
               files: ["config.json"],
               validate: false,
               curl: script,
               download_timeout: 1000,
               download_output_limit: 32
             )

    assert output =~ "[download output truncated to last 32 bytes]"
    refute output =~ "line-0"
    assert output =~ "line-19"
  end

  test "run explains incomplete native checkpoint downloads with resume commands" do
    path = tmp_dir!("obscura-privacy-filter-setup-incomplete")

    runner = fn _cmd, args, _opts ->
      output = output_arg(args)
      File.mkdir_p!(Path.dirname(output))

      case Path.basename(output) do
        "config.json" ->
          File.write!(output, Jason.encode!(config()))

        "model.safetensors" ->
          Safetensors.write!(output, %{"x" => Nx.tensor([[1.0, 2.0]])})
          contents = File.read!(output)
          File.write!(output, binary_part(contents, 0, byte_size(contents) - 1))
      end

      {"", 0}
    end

    assert {:error, {:incomplete_privacy_filter_checkpoint, error}} =
             Setup.run(
               checkpoint: path,
               files: ["config.json", "model.safetensors"],
               runner: runner
             )

    assert error.checkpoint == path
    assert error.file == Path.join(path, "model.safetensors")
    assert error.actual_size == error.expected_size - 1
    assert error.missing_bytes == 1
    assert error.progress_percent > 0.0
    assert error.resume_setup_command =~ "mix obscura.privacy_filter.setup"
    assert error.resume_setup_command =~ "--checkpoint #{path}"
    assert error.resume_setup_command =~ "--file model.safetensors"
    assert error.resume_curl_command =~ "curl --silent --show-error -L --fail --continue-at -"
    assert error.resume_curl_command =~ Path.join(path, "model.safetensors")
    assert error.resume_hf_command =~ "hf download openai/privacy-filter model.safetensors"
    assert error.resume_hf_command =~ "--local-dir #{path}"
  end

  defp tmp_dir!(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end

  defp output_arg(args) do
    args
    |> Enum.drop_while(&(&1 != "--output"))
    |> Enum.at(1)
  end

  defp slow_script! do
    path = Path.join(tmp_dir!("obscura-privacy-filter-slow-script"), "slow-download")

    File.write!(path, """
    #!/bin/sh
    exec sleep 5
    """)

    File.chmod!(path, 0o755)
    path
  end

  defp noisy_script! do
    path = Path.join(tmp_dir!("obscura-privacy-filter-noisy-script"), "noisy-download")

    File.write!(path, """
    #!/bin/sh
    while true
    do
      echo tick
      sleep 0.01
    done
    """)

    File.chmod!(path, 0o755)
    path
  end

  defp burst_then_sleep_script! do
    path = Path.join(tmp_dir!("obscura-privacy-filter-burst-script"), "burst-download")

    File.write!(path, """
    #!/bin/sh
    i=0
    while [ "$i" -lt 20 ]
    do
      echo "line-$i"
      i=$((i + 1))
    done
    exec sleep 5
    """)

    File.chmod!(path, 0o755)
    path
  end

  defp config do
    %{
      model_type: "privacy_filter",
      encoding: "o200k_base",
      num_hidden_layers: 1,
      num_experts: 1,
      experts_per_token: 1,
      vocab_size: 10,
      num_labels: 5,
      hidden_size: 2,
      intermediate_size: 2,
      head_dim: 2,
      num_attention_heads: 2,
      num_key_value_heads: 1,
      sliding_window: 3,
      bidirectional_context: true,
      bidirectional_left_context: 1,
      bidirectional_right_context: 1,
      initial_context_length: 16,
      rope_theta: 10_000.0,
      rope_scaling_factor: 1.0,
      rope_ntk_alpha: 1.0,
      rope_ntk_beta: 32.0,
      param_dtype: "bfloat16",
      ner_class_names: [
        "O",
        "B-private_person",
        "I-private_person",
        "E-private_person",
        "S-private_person"
      ]
    }
  end
end
