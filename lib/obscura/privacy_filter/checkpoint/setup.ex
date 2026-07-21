defmodule Obscura.PrivacyFilter.Checkpoint.Setup do
  @moduledoc """
  Development setup helper for local native privacy-filter checkpoints.

  This module is intentionally outside the analyzer runtime. It downloads model
  assets only when called explicitly by a Mix task or by developer tooling.
  """

  alias Obscura.PrivacyFilter.Checkpoint

  @default_repo "openai/privacy-filter"
  @default_revision "main"
  @default_checkpoint ".cache/privacy-filter/openai"
  @default_layout :native
  @native_files ["config.json", "model.safetensors"]
  @default_download_output_limit 16_384
  @python_original_files [
    "config.json",
    "dtypes.json",
    "model.safetensors",
    "viterbi_calibration.json"
  ]
  @base_url "https://huggingface.co"

  @type file_plan :: %{
          file: String.t(),
          source: String.t(),
          url: String.t(),
          output: Path.t()
        }

  @type plan :: %{
          repo: String.t(),
          revision: String.t(),
          layout: :native | :python_original,
          checkpoint: Path.t(),
          files: [file_plan()]
        }
  @type download_tool :: :curl | :hf
  @type incomplete_checkpoint_error :: %{
          checkpoint: Path.t(),
          repo: String.t(),
          revision: String.t(),
          layout: :native | :python_original,
          file: Path.t(),
          actual_size: non_neg_integer(),
          expected_size: non_neg_integer(),
          missing_bytes: non_neg_integer(),
          progress_percent: float(),
          resume_setup_command: String.t(),
          resume_curl_command: String.t() | nil,
          resume_hf_command: String.t() | nil
        }

  @spec plan(keyword()) :: {:ok, plan()} | {:error, term()}
  def plan(opts \\ []) when is_list(opts) do
    repo = Keyword.get(opts, :repo, @default_repo)
    revision = Keyword.get(opts, :revision, @default_revision)
    checkpoint = Keyword.get(opts, :checkpoint, @default_checkpoint)
    requested_layout = Keyword.get(opts, :layout, @default_layout)
    requested_tool = Keyword.get(opts, :download_tool, :curl)

    with {:ok, layout} <- validate_layout(requested_layout),
         :ok <- validate_download_tool(requested_tool),
         :ok <- validate_plan_path_part(repo, :repo),
         :ok <- validate_plan_path_part(revision, :revision),
         :ok <- validate_checkpoint_path(checkpoint),
         {:ok, files} <- validate_files(Keyword.get(opts, :files, default_files(layout))) do
      {:ok,
       %{
         repo: repo,
         revision: revision,
         layout: layout,
         checkpoint: checkpoint,
         files: Enum.map(files, &file_plan(repo, revision, checkpoint, layout, &1))
       }}
    end
  end

  defp validate_layout(value) do
    case normalize_layout(value) do
      nil -> {:error, {:unsupported_privacy_filter_checkpoint_layout, value}}
      layout -> {:ok, layout}
    end
  end

  defp validate_download_tool(value) do
    if normalize_download_tool(value),
      do: :ok,
      else: {:error, {:unsupported_privacy_filter_download_tool, value}}
  end

  defp validate_plan_path_part(value, kind) do
    if valid_path_part?(value), do: :ok, else: {:error, {invalid_path_reason(kind), value}}
  end

  defp invalid_path_reason(:repo), do: :invalid_privacy_filter_repo
  defp invalid_path_reason(:revision), do: :invalid_privacy_filter_revision

  defp validate_checkpoint_path(path) when is_binary(path) and path != "", do: :ok
  defp validate_checkpoint_path(_path), do: {:error, :invalid_privacy_filter_checkpoint_path}

  defp validate_files(files) when not is_list(files) or files == [],
    do: {:error, :missing_privacy_filter_files}

  defp validate_files(files) do
    if Enum.all?(files, &valid_file?/1),
      do: {:ok, files},
      else: {:error, {:invalid_privacy_filter_files, files}}
  end

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) when is_list(opts) do
    with {:ok, setup_plan} <- plan(opts),
         :ok <- File.mkdir_p(setup_plan.checkpoint),
         :ok <- download_files(setup_plan, opts) do
      case maybe_validate(setup_plan, opts) do
        {:error, {:incomplete_safetensors_file, file, actual_size, expected_size}} ->
          {:error,
           {:incomplete_privacy_filter_checkpoint,
            incomplete_checkpoint_error(setup_plan, file, actual_size, expected_size, opts)}}

        result ->
          result
      end
    end
  end

  @spec curl_command(file_plan(), keyword()) :: {String.t(), [String.t()]}
  def curl_command(file_plan, opts \\ []) do
    curl = Keyword.get(opts, :curl, "curl")

    args =
      [
        "--silent",
        "--show-error",
        "-L",
        "--fail",
        "--continue-at",
        "-",
        "--create-dirs",
        "--output",
        file_plan.output,
        file_plan.url
      ] ++ extra_curl_args(opts)

    {curl, args}
  end

  @spec hf_command(plan(), file_plan(), keyword()) :: {String.t(), [String.t()]}
  def hf_command(setup_plan, file_plan, opts \\ []) do
    hf = Keyword.get(opts, :hf, "hf")

    args =
      [
        "download",
        setup_plan.repo,
        file_plan.source,
        "--revision",
        setup_plan.revision,
        "--local-dir",
        setup_plan.checkpoint
      ] ++ extra_hf_args(opts)

    {hf, args}
  end

  defp file_plan(repo, revision, checkpoint, layout, file) do
    source = source_file(layout, file)

    %{
      file: file,
      source: source,
      url: "#{@base_url}/#{repo}/resolve/#{revision}/#{source}",
      output: Path.join(checkpoint, file)
    }
  end

  defp source_file(:native, file), do: file
  defp source_file(:python_original, file), do: "original/#{file}"

  defp download_files(setup_plan, opts) do
    Enum.reduce_while(setup_plan.files, :ok, fn file_plan, :ok ->
      case download_file(setup_plan, file_plan, opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp download_file(setup_plan, file_plan, opts) do
    case guard_hf_partial_safetensors(setup_plan, file_plan, opts) do
      :ok ->
        {cmd, args} = download_command(setup_plan, file_plan, opts)
        runner = Keyword.get(opts, :runner)

        case run_download_command(runner, cmd, args, opts) do
          {_output, 0} ->
            after_download(setup_plan, file_plan, opts)

          {output, :timeout} ->
            {:error,
             {:privacy_filter_download_timed_out, file_plan.file,
              Keyword.fetch!(opts, :download_timeout), output}}

          {output, status} ->
            {:error, {:privacy_filter_download_failed, file_plan.file, status, output}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_download_command(runner, cmd, args, opts) do
    cond do
      not is_nil(runner) ->
        runner.(cmd, args, stderr_to_stdout: true)

      timeout = Keyword.get(opts, :download_timeout) ->
        run_command_with_timeout(cmd, args, timeout, download_output_limit(opts))

      true ->
        System.cmd(cmd, args, stderr_to_stdout: true)
    end
  end

  defp run_command_with_timeout(cmd, args, timeout, output_limit)
       when is_binary(cmd) and is_list(args) and is_integer(timeout) and timeout > 0 do
    case executable(cmd) do
      {:ok, executable} ->
        port =
          Port.open({:spawn_executable, executable}, [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            {:args, args}
          ])

        collect_command_output(port, "", timeout_deadline(timeout), output_limit)

      {:error, reason} ->
        {"", reason}
    end
  end

  defp run_command_with_timeout(_cmd, _args, timeout, _output_limit),
    do: {"", {:invalid_timeout, timeout}}

  defp collect_command_output(port, output, deadline, output_limit) do
    case remaining_timeout(deadline) do
      0 ->
        terminate_port(port)
        {output, :timeout}

      timeout ->
        receive do
          {^port, {:data, data}} ->
            output =
              output
              |> Kernel.<>(data)
              |> cap_output(output_limit)

            collect_command_output(port, output, deadline, output_limit)

          {^port, {:exit_status, status}} ->
            {output, status}
        after
          timeout ->
            terminate_port(port)
            {output, :timeout}
        end
    end
  end

  defp cap_output(output, :infinity), do: output

  defp cap_output(output, limit) when is_integer(limit) and byte_size(output) > limit do
    marker = "\n[download output truncated to last #{limit} bytes]\n"
    marker <> binary_part(output, byte_size(output), -limit)
  end

  defp cap_output(output, _limit), do: output

  defp download_output_limit(opts) do
    case Keyword.get(opts, :download_output_limit, @default_download_output_limit) do
      :infinity -> :infinity
      value when is_integer(value) and value > 0 -> value
      _other -> @default_download_output_limit
    end
  end

  defp timeout_deadline(timeout) do
    System.monotonic_time(:millisecond) + timeout
  end

  defp remaining_timeout(deadline) do
    max(deadline - System.monotonic_time(:millisecond), 0)
  end

  defp terminate_port(port) do
    os_pid = port_os_pid(port)

    if is_integer(os_pid) do
      System.cmd("kill", ["-TERM", to_string(os_pid)], stderr_to_stdout: true)
    end

    close_port(port)

    if is_integer(os_pid) do
      receive do
        {^port, {:exit_status, _status}} ->
          :ok
      after
        250 ->
          System.cmd("kill", ["-KILL", to_string(os_pid)], stderr_to_stdout: true)
          :ok
      end
    end

    :ok
  end

  defp port_os_pid(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> pid
      nil -> nil
    end
  end

  defp close_port(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  defp executable(cmd) do
    cond do
      executable = System.find_executable(cmd) ->
        {:ok, executable}

      Path.type(cmd) == :absolute and File.exists?(cmd) ->
        {:ok, cmd}

      true ->
        {:error, :enoent}
    end
  end

  defp download_command(setup_plan, file_plan, opts) do
    case download_tool(opts) do
      :curl -> curl_command(file_plan, opts)
      :hf -> hf_command(setup_plan, file_plan, opts)
    end
  end

  defp after_download(setup_plan, file_plan, opts) do
    case download_tool(opts) do
      :curl -> :ok
      :hf -> normalize_hf_output(setup_plan, file_plan)
    end
  end

  defp download_tool(opts) do
    opts
    |> Keyword.get(:download_tool, :curl)
    |> normalize_download_tool()
  end

  defp guard_hf_partial_safetensors(setup_plan, file_plan, opts) do
    if download_tool(opts) == :hf and String.ends_with?(file_plan.file, ".safetensors") and
         File.exists?(file_plan.output) do
      case File.stat(file_plan.output) do
        {:ok, %{size: size}} when size > 0 ->
          {:error,
           {:privacy_filter_hf_partial_safetensors_unsafe,
            %{
              file: file_plan.output,
              actual_size: size,
              resume_curl_command: resume_curl_command(setup_plan, file_plan.output, opts),
              reason:
                "hf download writes through the Hugging Face cache/local-dir flow and may replace an existing partial safetensors file; use the default curl downloader to resume this target file"
            }}}

        _other ->
          :ok
      end
    else
      :ok
    end
  end

  defp maybe_validate(setup_plan, opts) do
    if setup_plan.layout == :native and Keyword.get(opts, :validate, true) do
      Checkpoint.validate(setup_plan.checkpoint,
        encoding: Keyword.get(opts, :encoding),
        metadata_only: not Keyword.get(opts, :materialize, false)
      )
    else
      {:ok,
       %{
         checkpoint: setup_plan.checkpoint,
         repo: setup_plan.repo,
         revision: setup_plan.revision,
         layout: setup_plan.layout,
         files: Enum.map(setup_plan.files, & &1.file),
         validation: :skipped,
         validation_reason: validation_reason(setup_plan, opts)
       }}
    end
  end

  defp validation_reason(%{layout: :python_original}, _opts), do: :python_original_layout

  defp validation_reason(_setup_plan, opts),
    do: if(Keyword.get(opts, :validate, true), do: :none, else: :disabled)

  defp incomplete_checkpoint_error(setup_plan, file, actual_size, expected_size, opts) do
    %{
      checkpoint: setup_plan.checkpoint,
      repo: setup_plan.repo,
      revision: setup_plan.revision,
      layout: setup_plan.layout,
      file: file,
      actual_size: actual_size,
      expected_size: expected_size,
      missing_bytes: max(expected_size - actual_size, 0),
      progress_percent: progress_percent(actual_size, expected_size),
      resume_setup_command: resume_setup_command(setup_plan, opts),
      resume_curl_command: resume_curl_command(setup_plan, file, opts),
      resume_hf_command: resume_hf_command(setup_plan, file, opts)
    }
  end

  defp progress_percent(_actual_size, 0), do: 100.0

  defp progress_percent(actual_size, expected_size) do
    actual_size
    |> Kernel./(expected_size)
    |> Kernel.*(100.0)
    |> Float.round(4)
  end

  defp resume_setup_command(setup_plan, opts) do
    [
      "mix",
      "obscura.privacy_filter.setup",
      "--checkpoint",
      setup_plan.checkpoint,
      "--repo",
      setup_plan.repo,
      "--revision",
      setup_plan.revision,
      "--layout",
      layout_arg(setup_plan.layout)
    ]
    |> Enum.concat(download_tool_args(opts))
    |> Enum.concat(file_args(setup_plan.files))
    |> Enum.map_join(" ", &shell_quote/1)
  end

  defp resume_curl_command(setup_plan, file, opts) do
    case Enum.find(setup_plan.files, &(Path.expand(&1.output) == Path.expand(file))) do
      nil ->
        nil

      file_plan ->
        {cmd, args} = curl_command(file_plan, opts)

        [cmd | args]
        |> Enum.map_join(" ", &shell_quote/1)
    end
  end

  defp resume_hf_command(setup_plan, file, opts) do
    case Enum.find(setup_plan.files, &(Path.expand(&1.output) == Path.expand(file))) do
      nil ->
        nil

      file_plan ->
        {cmd, args} = hf_command(setup_plan, file_plan, opts)

        [cmd | args]
        |> Enum.map_join(" ", &shell_quote/1)
    end
  end

  defp file_args(files) do
    Enum.flat_map(files, fn file_plan -> ["--file", file_plan.file] end)
  end

  defp download_tool_args(opts) do
    case download_tool(opts) do
      :curl -> []
      :hf -> ["--download-tool", "hf"]
    end
  end

  defp layout_arg(:python_original), do: "python-original"
  defp layout_arg(:native), do: "native"

  defp shell_quote(value) do
    value = to_string(value)

    if Regex.match?(~r|^[A-Za-z0-9_@%+=:,./-]+$|, value) do
      value
    else
      "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
    end
  end

  defp extra_curl_args(opts) do
    case Keyword.get(opts, :connect_timeout) do
      nil -> []
      timeout -> ["--connect-timeout", to_string(timeout)]
    end
  end

  defp extra_hf_args(opts) do
    []
    |> maybe_append_hf_token(opts)
    |> maybe_append_hf_max_workers(opts)
  end

  defp maybe_append_hf_token(args, opts) do
    case Keyword.get(opts, :hf_token) do
      nil -> args
      token -> args ++ ["--token", to_string(token)]
    end
  end

  defp maybe_append_hf_max_workers(args, opts) do
    case Keyword.get(opts, :hf_max_workers) do
      nil -> args
      max_workers -> args ++ ["--max-workers", to_string(max_workers)]
    end
  end

  defp valid_file?(file) do
    is_binary(file) and file != "" and file == Path.basename(file)
  end

  defp valid_path_part?(value) do
    is_binary(value) and value != "" and not String.contains?(value, ["..", "://"])
  end

  defp normalize_layout(layout) when layout in [:native, "native"], do: :native

  defp normalize_layout(layout)
       when layout in [:python_original, "python_original", "python-original"],
       do: :python_original

  defp normalize_layout(_layout), do: nil

  defp normalize_hf_output(_setup_plan, %{source: source, file: file}) when source == file,
    do: :ok

  defp normalize_hf_output(setup_plan, file_plan) do
    source_path = Path.join(setup_plan.checkpoint, file_plan.source)

    cond do
      File.exists?(file_plan.output) ->
        :ok

      File.exists?(source_path) ->
        with :ok <- File.mkdir_p(Path.dirname(file_plan.output)),
             :ok <- File.rename(source_path, file_plan.output) do
          cleanup_empty_parent(source_path, setup_plan.checkpoint)
        end

      true ->
        {:error, {:privacy_filter_download_output_missing, file_plan.file, file_plan.output}}
    end
  end

  defp cleanup_empty_parent(path, stop_path) do
    parent = Path.dirname(path)

    if Path.expand(parent) != Path.expand(stop_path) do
      case File.rmdir(parent) do
        :ok -> :ok
        {:error, :eexist} -> :ok
        {:error, :enoent} -> :ok
        {:error, _reason} -> :ok
      end
    else
      :ok
    end
  end

  defp default_files(:native), do: @native_files
  defp default_files(:python_original), do: @python_original_files

  defp normalize_download_tool(tool) when tool in [:curl, "curl"], do: :curl
  defp normalize_download_tool(tool) when tool in [:hf, "hf"], do: :hf
  defp normalize_download_tool(_tool), do: nil
end
