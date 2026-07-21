defmodule Obscura.Eval.Operational.Metadata do
  @moduledoc false

  alias Obscura.Eval.RuntimeMetadata

  @spec runtime() :: map()
  def runtime do
    %{
      elixir: System.version(),
      otp: System.otp_release(),
      obscura_dependencies: RuntimeMetadata.dependency_versions()
    }
  end

  @spec hardware() :: map()
  def hardware do
    %{
      os: os_name(),
      os_version: command(["uname", "-r"]),
      architecture: :erlang.system_info(:system_architecture) |> to_string(),
      cpu: cpu_name(),
      logical_processors: :erlang.system_info(:logical_processors_available),
      memory_bytes: memory_bytes(),
      host_fingerprint: host_fingerprint()
    }
  end

  @spec git() :: map()
  def git do
    %{
      source_commit: command(["git", "rev-parse", "HEAD"]),
      dirty_worktree: dirty_worktree?()
    }
  end

  @spec environment(atom(), map()) :: map()
  def environment(profile, backend_metadata) do
    %{
      profile: profile,
      requested_backend: if(profile == :fast, do: :beam_cpu, else: requested_backend()),
      requested_device: if(profile == :fast, do: :cpu, else: requested_device()),
      emily_fallback: if(profile == :fast, do: :not_applicable, else: emily_fallback()),
      actual: backend_metadata,
      linux_exla: linux_exla_status()
    }
  end

  defp requested_backend do
    System.get_env("OBSCURA_REAL_MODEL_BACKEND") ||
      System.get_env("OBSCURA_PRIVACY_FILTER_BACKEND") ||
      "default"
  end

  defp requested_device, do: System.get_env("OBSCURA_EMILY_DEVICE", "gpu")
  defp emily_fallback, do: System.get_env("OBSCURA_EMILY_FALLBACK", "raise")

  defp linux_exla_status do
    case :os.type() do
      {:unix, :linux} ->
        %{status: :available_for_validation, measured: false}

      _other ->
        %{status: :unavailable, reason: :not_a_linux_runner, measured: false}
    end
  end

  defp dirty_worktree? do
    ["git", "status", "--porcelain", "--untracked-files=no"]
    |> command()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.contains?(&1, "eval/reports/operational/"))
    |> Enum.any?()
  end

  defp os_name do
    case :os.type() do
      {:unix, name} -> Atom.to_string(name)
      {family, name} -> "#{family}-#{name}"
    end
  end

  defp cpu_name do
    case :os.type() do
      {:unix, :darwin} -> command(["sysctl", "-n", "machdep.cpu.brand_string"])
      {:unix, :linux} -> command(["sh", "-c", "lscpu | sed -n 's/^Model name:[[:space:]]*//p'"])
      _other -> "unavailable"
    end
  end

  defp memory_bytes do
    value =
      case :os.type() do
        {:unix, :darwin} ->
          command(["sysctl", "-n", "hw.memsize"])

        {:unix, :linux} ->
          command(["sh", "-c", "awk '/MemTotal/ {print $2 * 1024}' /proc/meminfo"])

        _other ->
          ""
      end

    case Float.parse(value) do
      {number, _rest} -> round(number)
      :error -> nil
    end
  end

  defp host_fingerprint do
    [
      os_name(),
      cpu_name(),
      to_string(memory_bytes()),
      to_string(:erlang.system_info(:system_architecture))
    ]
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp command([executable | args]) do
    case System.cmd(executable, args, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      _other -> "unavailable"
    end
  rescue
    _error -> "unavailable"
  end
end
