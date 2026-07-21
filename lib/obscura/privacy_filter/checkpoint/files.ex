defmodule Obscura.PrivacyFilter.Checkpoint.Files do
  @moduledoc false

  @spec validate_common(Path.t()) :: :ok | {:error, term()}
  def validate_common(path) do
    cond do
      not File.dir?(path) ->
        {:error, {:checkpoint_dir_not_found, path}}

      not File.exists?(Path.join(path, "config.json")) ->
        {:error, {:missing_checkpoint_config, Path.join(path, "config.json")}}

      path |> Path.join("*.safetensors") |> Path.wildcard() |> Enum.empty?() ->
        {:error, {:missing_safetensors_files, path}}

      true ->
        :ok
    end
  end
end
