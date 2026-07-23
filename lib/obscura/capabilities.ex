defmodule Obscura.Capabilities do
  @moduledoc """
  Machine-readable optional dependency and model asset contracts.

  The manifests are shipped in `priv/obscura` and contain no credentials,
  machine-specific absolute paths, or bundled model weights.
  """

  @capabilities_file "obscura/capabilities.json"
  @assets_file "obscura/model_assets.json"
  @required_capability_fields ~w(id status profiles dependencies environment_variables platforms backends network_during_setup network_during_inference setup_command readiness_command smoke_command failure_codes)
  @required_asset_fields ~w(id status profiles adapter model_repository tokenizer_repository revision_policy required_files hashes license license_review_status license_reviewed_at license_review_revision commercial_use commercial_use_reviewed_at license_sources network_on_explicit_prepare bundled)
  @commercial_use_values ~w(requires_ldc_for_profit_membership deployer_review_required not_cleared_by_obscura permissive_chain_documented)

  @doc """
  Loads and validates the capability manifest.
  """
  @spec load() :: {:ok, map()} | {:error, term()}
  def load do
    with {:ok, manifest} <- decode_manifest(@capabilities_file),
         :ok <- validate_capability_manifest(manifest) do
      {:ok, manifest}
    end
  end

  @doc """
  Loads and validates the model asset manifest.
  """
  @spec load_assets() :: {:ok, map()} | {:error, term()}
  def load_assets do
    with {:ok, manifest} <- decode_manifest(@assets_file),
         :ok <- validate_asset_manifest(manifest) do
      {:ok, manifest}
    end
  end

  @doc """
  Fetches one capability by its string or atom ID.
  """
  @spec fetch(String.t() | atom()) :: {:ok, map()} | {:error, term()}
  def fetch(id) do
    id = to_string(id)

    with {:ok, manifest} <- load() do
      case Enum.find(manifest["capabilities"], &(&1["id"] == id)) do
        nil -> {:error, {:unknown_capability, id}}
        capability -> {:ok, capability}
      end
    end
  end

  @doc """
  Returns capability rows associated with a product or implementation profile.
  """
  @spec for_profile(atom() | String.t()) :: {:ok, [map()]} | {:error, term()}
  def for_profile(profile) do
    profile = to_string(profile)

    with {:ok, manifest} <- load() do
      {:ok,
       Enum.filter(manifest["capabilities"], fn capability ->
         profile in capability["profiles"]
       end)}
    end
  end

  @doc """
  Returns model asset rows associated with a product or implementation profile.
  """
  @spec assets_for_profile(atom() | String.t()) :: {:ok, [map()]} | {:error, term()}
  def assets_for_profile(profile) do
    profile = to_string(profile)

    with {:ok, manifest} <- load_assets() do
      {:ok, Enum.filter(manifest["assets"], &(profile in &1["profiles"]))}
    end
  end

  @doc """
  Returns the package path to a manifest.
  """
  @spec path(:capabilities | :assets) :: Path.t()
  def path(:capabilities), do: Application.app_dir(:obscura, "priv/#{@capabilities_file}")
  def path(:assets), do: Application.app_dir(:obscura, "priv/#{@assets_file}")

  defp decode_manifest(file) do
    path = Application.app_dir(:obscura, "priv/#{file}")

    with {:ok, body} <- File.read(path),
         {:ok, manifest} <- Jason.decode(body) do
      {:ok, manifest}
    else
      {:error, reason} -> {:error, {:invalid_capability_manifest, path, reason}}
    end
  end

  defp validate_capability_manifest(%{
         "schema_version" => 1,
         "capabilities" => capabilities
       })
       when is_list(capabilities) do
    validate_rows(capabilities, @required_capability_fields, :capability)
  end

  defp validate_capability_manifest(_manifest),
    do: {:error, :invalid_capability_manifest_schema}

  defp validate_asset_manifest(%{"schema_version" => 2, "assets" => assets})
       when is_list(assets) do
    with :ok <- validate_rows(assets, @required_asset_fields, :asset) do
      validate_commercial_use(assets)
    end
  end

  defp validate_asset_manifest(_manifest), do: {:error, :invalid_asset_manifest_schema}

  defp validate_rows(rows, required_fields, kind) do
    with :ok <- validate_unique_ids(rows, kind) do
      validate_required_fields(rows, required_fields, kind)
    end
  end

  defp validate_unique_ids(rows, kind) do
    ids = Enum.map(rows, &Map.get(&1, "id"))

    if Enum.uniq(ids) == ids and Enum.all?(ids, &is_binary/1) do
      :ok
    else
      {:error, {:invalid_or_duplicate_manifest_ids, kind}}
    end
  end

  defp validate_required_fields(rows, required_fields, kind) do
    Enum.find_value(rows, :ok, fn row ->
      case Enum.reject(required_fields, &Map.has_key?(row, &1)) do
        [] -> false
        missing -> {:error, {:missing_manifest_fields, kind, row["id"], missing}}
      end
    end)
  end

  defp validate_commercial_use(assets) do
    case Enum.find(assets, &(&1["commercial_use"] not in @commercial_use_values)) do
      nil -> :ok
      asset -> {:error, {:invalid_commercial_use, asset["id"], asset["commercial_use"]}}
    end
  end
end
