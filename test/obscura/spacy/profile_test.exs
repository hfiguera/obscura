defmodule Obscura.Spacy.ProfileTest do
  use ExUnit.Case, async: true
  alias Obscura.{Diagnostic, Profile}
  alias Obscura.Spacy.{Assets, Serving}

  test "opt-in CPU profile is separate from stable aliases" do
    assert {:ok, descriptor} = Profile.fetch("spacy_cpu")
    assert descriptor.stability == :experimental
    assert descriptor.backend_policy == :native_cpu
    assert descriptor.required_dependencies == []
    assert :person in descriptor.supported_entities
    assert :location in descriptor.supported_entities
    refute :organization in descriptor.supported_entities
    assert {:ok, :deterministic_plus} = Profile.resolve(:spacy_cpu)
    refute :spacy_cpu in Profile.names()
    assert {:ok, :spacy_cpu} = Obscura.Eval.Profile.from_string("spacy_cpu")
  end

  test "selecting a profile never implicitly prepares assets" do
    assert {:error, %Diagnostic{code: :missing_model_asset, asset: :spacy_serving}} =
             Obscura.analyze("Alice lives in London.", profile: :spacy_cpu)

    assert {:error, %Diagnostic{code: :missing_model_asset}} =
             Obscura.analyze("Alice", profile: "spacy_cpu")
  end

  test "invalid pool configuration is rejected" do
    for opts <- [[workers: 0], [workers: 5], [request_timeout: 0], [request_timeout: :infinity]] do
      assert {:error, %Diagnostic{code: :profile_requirements_unsatisfied}} = Serving.build(opts)
    end
  end

  test "missing local executable gives a safe preflight failure" do
    {:error, diagnostic, report} =
      Profile.preflight(:spacy_cpu,
        native_binary: "/no/such/PRIVATE_EXECUTABLE",
        model_dir: "/no/such/PRIVATE_MODEL"
      )

    assert diagnostic.code in [:missing_model_asset, :unsupported_backend]
    refute Jason.encode!(report) =~ "PRIVATE"
    refute report.effective_configuration.network_may_be_used
  end

  test "asset hashes cover the entire pinned export" do
    assert map_size(Assets.hashes()) == 5
    assert Enum.all?(Assets.hashes(), fn {_, digest} -> byte_size(digest) == 64 end)
  end

  test "native targets accept supported ABIs and reject unsupported platforms" do
    assert Assets.build_target({:unix, :darwin}, "aarch64-apple-darwin25.5.0") ==
             "aarch64-apple-darwin"

    assert Assets.build_target({:unix, :linux}, "aarch64-unknown-linux-gnu") ==
             "aarch64-unknown-linux-gnu"

    assert Assets.build_target({:unix, :linux}, "x86_64-pc-linux-gnu") ==
             "x86_64-unknown-linux-gnu"

    for {os, arch} <- [
          {{:unix, :linux}, "x86_64-pc-linux-musl"},
          {{:unix, :linux}, "i686-pc-linux-gnu"},
          {{:unix, :linux}, "s390x-unknown-linux-gnu"},
          {{:unix, :darwin}, "x86_64-apple-darwin"},
          {{:win32, :nt}, "x86_64-pc-windows-msvc"}
        ] do
      assert is_nil(Assets.build_target(os, arch))
    end
  end

  test "CPU backend options agree with the host math library" do
    assert :ok = Assets.validate_backend(backend: :cpu)
    assert :ok = Assets.validate_backend(backend: Assets.backend())
    assert :ok = Assets.validate_backend(backend: to_string(Assets.backend()))
    other = if Assets.backend() == :openblas_cpu, do: :accelerate_cpu, else: :openblas_cpu
    assert {:error, %{code: :unsupported_backend}} = Assets.validate_backend(backend: other)
    assert {:error, %{code: :unsupported_backend}} = Assets.validate_backend(backend: :emily)
  end
end
