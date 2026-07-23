defmodule Obscura.Profile.PreflightTest do
  use ExUnit.Case, async: true

  alias Obscura.Diagnostic
  alias Obscura.Profile

  test "fast preflight succeeds without dependencies or assets" do
    assert {:ok, report} = Profile.preflight(:fast)
    assert report.status == :ready
    assert report.stability == :stable
    assert report.implementation_profile == :deterministic_plus
    assert report.effective_configuration.automatic_download == false
    assert report.effective_configuration.network_may_be_used == false
  end

  test "balanced preflight distinguishes an unavailable backend" do
    assert {:error, %Diagnostic{code: :backend_unavailable}, report} =
             Profile.preflight(:balanced,
               backend: :emily,
               module_checker: fn _module -> false end
             )

    assert report.status == :error
    assert report.diagnostic.code == :backend_unavailable
    refute Map.has_key?(report.diagnostic, :path)
    refute Map.has_key?(report.diagnostic, :cause)
  end

  test "balanced local preflight requires a reusable serving" do
    checker = fn dependency -> dependency in [:nx, :bumblebee] end

    assert {:error, %Diagnostic{code: :missing_model_asset}, report} =
             Profile.preflight(:balanced,
               dependency_checker: checker,
               backend: :default
             )

    assert report.diagnostic.asset == :primary_serving
  end

  test "stable model profiles retain third-party asset warnings" do
    checker = fn dependency -> dependency in [:nx, :bumblebee] end

    assert {:ok, balanced} =
             Profile.preflight(:balanced,
               dependency_checker: checker,
               backend: :default,
               primary_serving: :serving
             )

    assert balanced.stability == :stable
    assert Enum.any?(balanced.warnings, &String.contains?(&1, "Commercial use"))
    assert Enum.any?(balanced.warnings, &String.contains?(&1, "LDC for-profit membership"))
    assert [balanced_licensing] = balanced.requirements.asset_licensing
    assert balanced_licensing["commercial_use"] == "requires_ldc_for_profit_membership"

    assert {:ok, accurate} =
             Profile.preflight(:accurate,
               dependency_checker: checker,
               backend: :default,
               primary_serving: :primary,
               location_serving: :location
             )

    assert accurate.stability == :stable
    assert Enum.any?(accurate.warnings, &String.contains?(&1, "LDC for-profit membership"))

    assert Enum.any?(
             accurate.requirements.asset_licensing,
             &(&1["commercial_use"] == "requires_ldc_for_profit_membership")
           )
  end

  test "fast preflight contains no TNER licensing restriction" do
    assert {:ok, report} = Profile.preflight(:fast)

    assert report.requirements.asset_licensing == []
    refute Enum.any?(report.warnings, &String.contains?(&1, "LDC"))
    refute Enum.any?(report.warnings, &String.contains?(&1, "TNER"))
  end

  test "OpenMed preflight distinguishes a missing checkpoint config" do
    root = Path.join(System.tmp_dir!(), "obscura-preflight-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    assert {:error, %Diagnostic{code: :missing_model_config}, report} =
             Profile.preflight(:openmed_pii,
               checkpoint: root,
               dependency_checker: fn _dependency -> true end,
               backend: :default
             )

    assert report.diagnostic.code == :missing_model_config
    assert report.stability == :experimental
  end

  test "Urchade preflight reports its CPU-only experimental contract" do
    checker = fn dependency -> dependency in [:ortex, :tokenizers] end

    assert {:ok, report} =
             Profile.preflight(:hybrid_gliner_urchade,
               dependency_checker: checker,
               gliner_serving: :serving
             )

    assert report.stability == :experimental
    assert report.implementation_profile == :hybrid_gliner_urchade
    assert report.effective_configuration.backend == :ortex_cpu
    assert report.effective_configuration.network_may_be_used == false
    assert Enum.any?(report.warnings, &String.contains?(&1, "CPU-only"))
    assert Enum.any?(report.warnings, &String.contains?(&1, "lower than balanced"))
  end

  test "unknown profile produces a JSON-safe report" do
    assert {:error, %Diagnostic{code: :unknown_profile}, report} =
             Profile.preflight("missing")

    assert report.status == :error
    assert report.profile == "missing"
    assert Jason.encode!(report) =~ "unknown_profile"
  end
end
