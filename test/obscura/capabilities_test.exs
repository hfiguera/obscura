defmodule Obscura.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias Obscura.Capabilities
  alias Obscura.Profile

  @conditional_dependencies ~w(exla emily ortex tokenizers)
  @license_review_statuses ~w(conditional_deployer_review permissive_chain_documented unresolved_external_asset)

  test "capability and model asset manifests are valid" do
    assert {:ok, %{"schema_version" => 1, "capabilities" => capabilities}} =
             Capabilities.load()

    assert {:ok, %{"schema_version" => 1, "assets" => assets}} =
             Capabilities.load_assets()

    assert capabilities != []
    assert assets != []
  end

  test "every stable profile has capabilities and model-backed aliases have assets" do
    for profile <- Profile.names() do
      assert {:ok, [_ | _]} = Capabilities.for_profile(profile)
    end

    for profile <- [:balanced, :accurate, :hybrid_gliner_urchade, :openmed_pii] do
      assert {:ok, [_ | _]} = Capabilities.assets_for_profile(profile)
    end

    assert {:ok, []} = Capabilities.assets_for_profile(:fast)
  end

  test "manifest dependency names and requirements agree with mix.exs" do
    {:ok, manifest} = Capabilities.load()
    mix_source = File.read!(Path.expand("../../mix.exs", __DIR__))

    manifest["capabilities"]
    |> Enum.flat_map(& &1["dependencies"])
    |> Enum.uniq_by(& &1["name"])
    |> Enum.each(fn dependency ->
      assert mix_source =~ "{:#{dependency["name"]},"
      assert mix_source =~ dependency["requirement"]
    end)

    for dependency <- @conditional_dependencies do
      assert mix_source =~ "{:#{dependency},"
    end
  end

  test "documented environment variables exist in project code" do
    {:ok, manifest} = Capabilities.load()

    source =
      [Path.expand("../../mix.exs", __DIR__) | Path.wildcard("lib/**/*.ex")]
      |> Enum.map_join("\n", &File.read!/1)

    manifest["capabilities"]
    |> Enum.flat_map(& &1["environment_variables"])
    |> Enum.uniq()
    |> Enum.each(fn variable -> assert source =~ variable end)
  end

  test "manifests contain no machine-specific paths or credential material" do
    for kind <- [:capabilities, :assets] do
      body = kind |> Capabilities.path() |> File.read!()

      refute body =~ "/Users/"
      refute body =~ "/home/"
      refute body =~ "hf_"
      refute body =~ "api_key\""
      refute body =~ "access_token"
    end
  end

  test "product profile dependencies and model IDs agree with manifests" do
    for profile <- Profile.names() ++ Profile.experimental_names() do
      {:ok, descriptor} = Profile.fetch(profile)
      {:ok, capabilities} = Capabilities.for_profile(profile)
      {:ok, assets} = Capabilities.assets_for_profile(profile)

      dependency_names =
        capabilities
        |> Enum.flat_map(& &1["dependencies"])
        |> Enum.map(&String.to_existing_atom(&1["name"]))

      assert Enum.all?(descriptor.required_dependencies, &(&1 in dependency_names))
      assert Enum.all?(descriptor.optional_dependencies, &(&1 in dependency_names))

      asset_ids = Enum.map(assets, &String.to_existing_atom(&1["id"]))
      assert Enum.all?(descriptor.default_models, &(&1 in asset_ids))
    end
  end

  test "accurate capability and asset roles describe the output-aware cascade" do
    assert {:ok, capability} = Capabilities.fetch(:bumblebee_ner)

    assert capability["profile_contracts"]["accurate"] ==
             "TNER primary plus conditional Jean-Baptiste location cascade"

    assert {:ok, assets} = Capabilities.assets_for_profile(:accurate)
    roles = Map.new(assets, &{&1["id"], &1["profile_roles"]["accurate"]})

    assert roles == %{
             "jean_baptiste_roberta_large_ner_english" => "conditional location recovery",
             "tner_roberta_large_ontonotes5" => "cascade primary NER"
           }
  end

  test "stable model profiles keep external asset licensing explicit" do
    assert {:ok, capability} = Capabilities.fetch(:bumblebee_ner)
    assert capability["status"] == "stable_optional_model_runtime"

    for profile <- [:balanced, :accurate] do
      assert {:ok, assets} = Capabilities.assets_for_profile(profile)

      assert Enum.all?(assets, fn asset ->
               asset["status"] == "stable_profile_external_asset" and
                 asset["bundled"] == false and
                 asset["license_review_status"] in [
                   "conditional_deployer_review",
                   "unresolved_external_asset"
                 ] and
                 String.contains?(asset["license"], "not distributed or sublicensed by Obscura")
             end)
    end
  end

  test "every external model asset records a reproducible license review" do
    assert {:ok, %{"assets" => assets}} = Capabilities.load_assets()

    for asset <- assets do
      assert asset["license_review_status"] in @license_review_statuses
      assert asset["license_reviewed_at"] == "2026-07-21"
      assert is_binary(asset["license_review_revision"])
      assert asset["license_review_revision"] != ""
      assert [_ | _] = asset["license_sources"]
      assert Enum.all?(asset["license_sources"], &String.starts_with?(&1, "https://"))
      assert asset["bundled"] == false
    end
  end
end
