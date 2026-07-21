defmodule Obscura.ProfileTest do
  use ExUnit.Case, async: true

  alias Obscura.Diagnostic
  alias Obscura.Profile

  test "lists stable profiles separately from experimental aliases" do
    assert Profile.names() == [:fast, :balanced, :accurate]

    assert Profile.experimental_names() == [
             :hybrid_gliner_urchade,
             :openmed_pii
           ]

    assert Profile.resolve(:fast) == {:ok, :deterministic_plus}
    assert Profile.resolve("balanced") == {:ok, :hybrid_ner_tner_conservative}
    assert Profile.resolve(:accurate) == {:ok, :hybrid_ner_tner_jean_location_cascade}
    assert Profile.resolve(:openmed_pii) == {:ok, :privacy_filter_native}
    assert Profile.resolve(:hybrid_gliner_urchade) == {:ok, :hybrid_gliner_urchade}

    assert Profile.classification(:fast) == {:ok, :stable}
    assert Profile.classification(:balanced) == {:ok, :stable}
    assert Profile.classification(:accurate) == {:ok, :stable}
    assert Profile.classification(:openmed_pii) == {:ok, :experimental}
    assert Profile.classification(:hybrid_gliner_urchade) == {:ok, :experimental}
  end

  test "preserves known implementation profiles" do
    assert Profile.resolve(:hybrid_ner_tner_jean_location) ==
             {:ok, :hybrid_ner_tner_jean_location}

    assert Profile.resolve(:hybrid_ner_tner_jean_location_cascade) ==
             {:ok, :hybrid_ner_tner_jean_location_cascade}

    assert Profile.resolve(:hybrid_gliner_ortex) == {:ok, :hybrid_gliner_ortex}
    assert Profile.classification(:hybrid_gliner_ortex) == {:ok, :experimental}
    assert Profile.resolve(:hybrid_gliner_urchade) == {:ok, :hybrid_gliner_urchade}
    assert Profile.classification(:hybrid_gliner_urchade) == {:ok, :experimental}

    assert Profile.resolve(:hybrid_gliner_urchade_native) ==
             {:ok, :hybrid_gliner_urchade_native}

    assert Profile.classification(:hybrid_gliner_urchade_native) == {:ok, :experimental}
    assert Profile.classification(:hybrid_ner_tner_conservative) == {:ok, :advanced}

    assert Profile.classification(:hybrid_ner_tner_jean_location) ==
             {:ok, :experimental}

    assert Profile.classification(:privacy_filter_native) == {:ok, :experimental}
  end

  test "unknown profiles return a structured diagnostic" do
    assert {:error, %Diagnostic{code: :unknown_profile} = diagnostic} =
             Profile.resolve(:typo_profile)

    assert diagnostic.metadata.supported == Profile.names()
    assert diagnostic.metadata.experimental == Profile.experimental_names()
  end

  test "removed remote profiles stay rejected" do
    for profile <- [
          :remote_google_dlp,
          :remote_azure_pii,
          :remote_azure_phi,
          :remote_ollama,
          :hybrid_remote
        ] do
      assert {:error, %Diagnostic{code: :unknown_profile}} = Profile.resolve(profile)
    end
  end

  test "fast is dependency and asset free" do
    assert :ok = Profile.validate_runtime(:fast, dependency_checker: fn _ -> false end)
    assert Profile.available?(:fast)
  end

  test "balanced requires dependencies and a reusable serving" do
    assert {:error, %Diagnostic{code: :missing_optional_dependency, dependency: :nx}} =
             Profile.validate_runtime(:balanced, dependency_checker: fn _ -> false end)

    checker = fn dependency -> dependency in [:nx, :bumblebee] end

    assert {:error, %Diagnostic{code: :missing_model_asset, asset: :primary_serving}} =
             Profile.validate_runtime(:balanced, dependency_checker: checker)

    assert :ok =
             Profile.validate_runtime(:balanced,
               dependency_checker: checker,
               serving: :reusable_serving
             )
  end

  test "stable accurate requires both model servings" do
    checker = fn dependency -> dependency in [:nx, :bumblebee] end

    assert {:error, %Diagnostic{asset: :primary_serving}} =
             Profile.validate_runtime(:accurate, dependency_checker: checker)

    assert {:error, %Diagnostic{asset: :location_serving}} =
             Profile.validate_runtime(:accurate,
               dependency_checker: checker,
               servings: %{primary: :primary}
             )

    assert :ok =
             Profile.validate_runtime(:accurate,
               dependency_checker: checker,
               servings: %{primary: :primary, location: :location}
             )
  end

  test "experimental openmed pii requires a serving or checkpoint" do
    checker = fn dependency -> dependency in [:nx, :safetensors] end

    assert {:error, %Diagnostic{code: :missing_checkpoint}} =
             Profile.validate_runtime(:openmed_pii, dependency_checker: checker)

    assert :ok =
             Profile.validate_runtime(:openmed_pii,
               dependency_checker: checker,
               privacy_filter_serving: :serving
             )
  end

  test "experimental Urchade GLiNER requires Ortex dependencies and local assets" do
    assert {:error, %Diagnostic{code: :missing_optional_dependency, dependency: :ortex}} =
             Profile.validate_runtime(:hybrid_gliner_urchade,
               dependency_checker: fn _ -> false end
             )

    checker = fn dependency -> dependency in [:ortex, :tokenizers] end

    assert {:error, %Diagnostic{code: :missing_model_asset, asset: :gliner_model_dir}} =
             Profile.validate_runtime(:hybrid_gliner_urchade, dependency_checker: checker)

    assert :ok =
             Profile.validate_runtime(:hybrid_gliner_urchade,
               dependency_checker: checker,
               gliner_serving: :reusable_serving
             )
  end

  test "profile descriptors do not permit automatic downloads" do
    for name <- Profile.names() do
      assert {:ok, descriptor} = Profile.fetch(name)
      refute descriptor.automatic_download
      assert descriptor.stability == :stable
    end

    for name <- Profile.experimental_names() do
      assert {:ok, descriptor} = Profile.fetch(name)
      refute descriptor.automatic_download
      assert descriptor.stability == :experimental
    end
  end

  test "requirements expose stability for automation" do
    assert {:ok, %{stability: :stable}} = Profile.requirements(:balanced)
    assert {:ok, %{stability: :stable}} = Profile.requirements(:accurate)
    assert {:ok, %{stability: :experimental}} = Profile.requirements(:openmed_pii)

    assert {:ok, %{stability: :experimental}} =
             Profile.requirements(:hybrid_gliner_urchade)
  end
end
