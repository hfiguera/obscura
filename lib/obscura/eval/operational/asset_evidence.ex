defmodule Obscura.Eval.Operational.AssetEvidence do
  @moduledoc false

  alias Obscura.Eval.AuthoritativeManifest

  @spec for_profile_dataset(atom(), map()) :: {:ok, map()} | {:error, term()}
  def for_profile_dataset(profile, selection) do
    with {:ok, manifest} <- AuthoritativeManifest.load(),
         {:ok, entry} <- find_entry(manifest["reports"], profile, selection) do
      {:ok,
       %{
         source: "eval/authoritative/manifest.json",
         source_manifest_sha256: sha256_file(AuthoritativeManifest.path()),
         source_entry_id: entry["id"],
         models: entry["models"],
         asset_hashes: entry["asset_hashes"],
         dependencies: entry["dependencies"]
       }}
    end
  end

  defp find_entry(reports, profile, selection) do
    dataset = selection["dataset"]
    split = get_in(dataset, ["template_split", "name"])

    case Enum.find(reports, fn entry ->
           entry["stable_profile"] == Atom.to_string(profile) and
             get_in(entry, ["dataset", "name"]) == dataset["name"] and
             get_in(entry, ["dataset", "template_split", "name"]) == split
         end) do
      nil -> {:error, {:missing_authoritative_asset_evidence, profile, dataset["name"], split}}
      entry -> {:ok, entry}
    end
  end

  defp sha256_file(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
