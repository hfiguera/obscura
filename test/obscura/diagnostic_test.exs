defmodule Obscura.DiagnosticTest do
  use ExUnit.Case, async: true

  alias Obscura.Diagnostic

  @required_codes [
    :backend_device_unavailable,
    :backend_fallback_forbidden,
    :backend_unavailable,
    :checkpoint_hash_mismatch,
    :checkpoint_incomplete,
    :checkpoint_layout_mismatch,
    :inference_timeout,
    :missing_checkpoint,
    :missing_model_asset,
    :missing_model_config,
    :missing_optional_dependency,
    :missing_tokenizer_asset,
    :model_asset_incomplete,
    :model_cache_failure,
    :model_download_interrupted,
    :model_download_not_allowed,
    :model_load_failed,
    :preparation_inactivity_timeout,
    :preparation_timeout,
    :profile_requirements_unsatisfied,
    :serving_build_failed,
    :tokenizer_load_failed,
    :unknown_profile,
    :unsupported_backend,
    :unsupported_model_architecture
  ]

  test "exposes every required code with a stable message and remediation" do
    assert Diagnostic.codes() == @required_codes

    Enum.each(@required_codes, fn code ->
      diagnostic = Diagnostic.new(code)

      assert diagnostic.code == code
      assert diagnostic.message != ""
      assert diagnostic.remediation != ""

      refute diagnostic.remediation ==
               "Inspect the diagnostic metadata and validate the configuration."
    end)
  end

  test "normalizes every known atom and tuple reason without collapsing its code" do
    Enum.each(@required_codes, fn expected_code ->
      atom_diagnostic = Diagnostic.normalize(expected_code, component: :test)
      tuple_diagnostic = Diagnostic.normalize({expected_code, :detail}, component: :test)

      assert atom_diagnostic.code == expected_code
      assert tuple_diagnostic.code == expected_code
    end)
  end

  test "normalizes missing optional dependencies" do
    diagnostic = Diagnostic.normalize({:missing_optional_dependency, :emily}, profile: :balanced)

    assert diagnostic.code == :missing_optional_dependency
    assert diagnostic.dependency == :emily
    assert diagnostic.profile == :balanced
    assert Diagnostic.format(diagnostic) =~ "Install and enable"
  end

  test "inspect omits paths and nested causes" do
    diagnostic =
      Diagnostic.new(:missing_checkpoint,
        path: "/Users/example/private/checkpoint",
        cause: {:provider_response, "private input"}
      )

    rendered = inspect(diagnostic)

    refute rendered =~ "/Users/example"
    refute rendered =~ "private input"
    assert rendered =~ "missing_checkpoint"
  end

  test "inspect and JSON-safe maps redact sensitive metadata" do
    diagnostic =
      Diagnostic.new(:missing_checkpoint,
        metadata: %{
          api_token: "hf-secret",
          checkpoint_path: "/Users/example/private/checkpoint",
          nested: %{"password" => "provider-secret", supported: [:nx]}
        }
      )

    rendered = inspect(diagnostic)
    encoded = diagnostic |> Diagnostic.to_map() |> Jason.encode!()

    for sensitive <- ["hf-secret", "/Users/example", "provider-secret"] do
      refute rendered =~ sensitive
      refute encoded =~ sensitive
    end

    assert encoded =~ "[REDACTED]"
    assert encoded =~ "nx"
  end
end
