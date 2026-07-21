defmodule Obscura.Eval.RuntimeMetadata do
  @moduledoc false

  @dependency_apps ~w(obscura jason req nx axon bumblebee exla emily ortex ex_phone_number safetensors)a

  @spec dependency_versions() :: map()
  def dependency_versions do
    versions =
      Map.new(@dependency_apps, fn app ->
        version = Application.spec(app, :vsn)
        {Atom.to_string(app), if(version, do: to_string(version), else: "not_loaded")}
      end)

    Map.put(versions, "mix_lock_sha256", lockfile_hash())
  end

  defp lockfile_hash do
    if File.regular?("mix.lock") do
      "mix.lock"
      |> File.read!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
    else
      "missing"
    end
  end
end
