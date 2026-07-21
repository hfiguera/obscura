defmodule Obscura.Diagnostic do
  @moduledoc """
  Structured, report-safe diagnostic returned by optional runtime setup paths.

  Diagnostics keep a stable machine-readable code while giving callers an
  actionable message and remediation. They never contain analyzed source text.
  """

  @enforce_keys [:code, :message, :remediation]
  defstruct [
    :code,
    :message,
    :remediation,
    :component,
    :profile,
    :dependency,
    :backend,
    :asset,
    :path,
    :cause,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          code: atom(),
          message: String.t(),
          remediation: String.t(),
          component: atom() | nil,
          profile: atom() | nil,
          dependency: atom() | nil,
          backend: atom() | nil,
          asset: atom() | nil,
          path: String.t() | nil,
          cause: term(),
          metadata: map()
        }

  @remediations %{
    unknown_profile: "Use one of the profiles returned by Obscura.Profile.names/0.",
    profile_requirements_unsatisfied:
      "Run Obscura.Profile.validate_runtime/2 and satisfy every reported requirement.",
    missing_optional_dependency:
      "Install and enable the optional dependency documented for this profile.",
    missing_model_asset: "Prepare the model assets and pass a reusable serving.",
    missing_tokenizer_asset: "Prepare the tokenizer assets required by the selected model.",
    model_asset_incomplete:
      "Retry explicit online preparation so Obscura can quarantine and replace partial assets.",
    model_cache_failure:
      "Verify cache permissions and available disk space, then retry preparation.",
    model_download_interrupted:
      "Retry explicit preparation; incomplete unreferenced cache files are quarantined automatically.",
    model_download_not_allowed:
      "Review the third-party asset terms, then pass allow_download: true explicitly or provision the cache offline.",
    missing_model_config: "Prepare the model configuration file required by the selected model.",
    missing_checkpoint: "Prepare a local checkpoint and pass its directory explicitly.",
    checkpoint_incomplete: "Run the checkpoint setup/validation command again.",
    checkpoint_layout_mismatch: "Use a checkpoint layout supported by this model adapter.",
    checkpoint_hash_mismatch: "Remove the invalid asset and fetch the pinned revision again.",
    unsupported_model_architecture: "Choose a model supported by the selected adapter.",
    unsupported_backend: "Select one of the backends listed in the diagnostic metadata.",
    backend_unavailable: "Install and configure the requested backend explicitly.",
    backend_device_unavailable: "Select an available device or use a supported backend.",
    backend_fallback_forbidden:
      "Configure the requested backend without fallback or choose another backend.",
    model_load_failed: "Validate the model revision, architecture, and local asset files.",
    preparation_inactivity_timeout:
      "Check network, disk, and backend activity, then increase inactivity_timeout or retry.",
    preparation_timeout:
      "Increase the explicit preparation timeout or provision model assets before startup.",
    tokenizer_load_failed: "Validate that the tokenizer matches the selected model.",
    serving_build_failed: "Run profile preflight and correct the reported runtime requirements.",
    inference_timeout: "Increase the explicit timeout or reduce the request/model workload."
  }

  @supported_codes @remediations |> Map.keys() |> Enum.sort()
  @sensitive_metadata_fragments [
    "authorization",
    "credential",
    "password",
    "path",
    "raw_text",
    "secret",
    "token"
  ]

  @doc "Returns the stable diagnostic codes supported by public setup boundaries."
  @spec codes() :: [atom()]
  def codes, do: @supported_codes

  @doc """
  Builds a diagnostic with a default remediation for the code.
  """
  @spec new(atom(), keyword()) :: t()
  def new(code, attrs \\ []) when is_atom(code) and is_list(attrs) do
    %__MODULE__{
      code: code,
      message: default_message(code),
      remediation: remediation(code),
      component: safe_identifier(Keyword.get(attrs, :component)),
      profile: safe_identifier(Keyword.get(attrs, :profile)),
      dependency: safe_identifier(Keyword.get(attrs, :dependency)),
      backend: safe_identifier(Keyword.get(attrs, :backend)),
      asset: safe_identifier(Keyword.get(attrs, :asset)),
      path: nil,
      cause: safe_cause(Keyword.get(attrs, :cause)),
      metadata: safe_metadata(Keyword.get(attrs, :metadata, %{}))
    }
  end

  @doc """
  Converts common legacy reasons into a structured diagnostic.
  """
  @spec normalize(term(), keyword()) :: t()
  def normalize(%__MODULE__{} = diagnostic, _attrs), do: diagnostic

  def normalize({:missing_optional_dependency, dependency}, attrs) do
    new(:missing_optional_dependency, Keyword.put(attrs, :dependency, dependency))
  end

  def normalize({:unknown_profile, profile}, attrs) do
    new(:unknown_profile, Keyword.put(attrs, :profile, profile))
  end

  def normalize(code, attrs) when code in @supported_codes do
    new(code, Keyword.put_new(attrs, :cause, code))
  end

  def normalize(reason, attrs) when is_tuple(reason) and tuple_size(reason) > 0 do
    code = elem(reason, 0)

    if code in @supported_codes do
      new(code, Keyword.put_new(attrs, :cause, reason))
    else
      fallback(reason, attrs)
    end
  end

  def normalize(reason, attrs) do
    fallback(reason, attrs)
  end

  @doc """
  Returns a concise human-readable diagnostic without rendering the nested cause.
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = diagnostic) do
    context =
      [
        diagnostic.profile && "profile=#{diagnostic.profile}",
        diagnostic.component && "component=#{diagnostic.component}",
        diagnostic.dependency && "dependency=#{diagnostic.dependency}",
        diagnostic.backend && "backend=#{diagnostic.backend}",
        diagnostic.asset && "asset=#{diagnostic.asset}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    prefix =
      if context == "",
        do: Atom.to_string(diagnostic.code),
        else: "#{diagnostic.code} (#{context})"

    "#{prefix}: #{safe_message(diagnostic)} Remediation: #{safe_remediation(diagnostic)}"
  end

  @doc """
  Converts a diagnostic to a JSON-safe map without path or nested-cause data.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = diagnostic) do
    %{
      code: diagnostic.code,
      message: safe_message(diagnostic),
      remediation: safe_remediation(diagnostic),
      component: diagnostic.component,
      profile: diagnostic.profile,
      dependency: diagnostic.dependency,
      backend: diagnostic.backend,
      asset: diagnostic.asset,
      metadata: safe_metadata(diagnostic.metadata)
    }
  end

  @doc false
  @spec safe_metadata(term()) :: term()
  def safe_metadata(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      safe_key = if is_atom(key), do: key, else: :redacted_key

      safe_value =
        if sensitive_metadata_key?(key) do
          "[REDACTED]"
        else
          safe_metadata(nested_value)
        end

      Map.put(acc, safe_key, safe_value)
    end)
  end

  def safe_metadata(value) when is_list(value), do: Enum.map(value, &safe_metadata/1)
  def safe_metadata(value) when is_tuple(value), do: value |> Tuple.to_list() |> safe_metadata()
  def safe_metadata(value) when is_binary(value), do: "[REDACTED]"
  def safe_metadata(value), do: value

  @doc """
  Returns the default remediation for a diagnostic code.
  """
  @spec remediation(atom()) :: String.t()
  def remediation(code) when is_atom(code) do
    Map.get(
      @remediations,
      code,
      "Inspect the diagnostic metadata and validate the configuration."
    )
  end

  defp default_message(code) do
    code
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp fallback(reason, attrs) do
    attrs = Keyword.put_new(attrs, :cause, reason)
    new(:profile_requirements_unsatisfied, attrs)
  end

  defp safe_identifier(value) when is_atom(value), do: value
  defp safe_identifier(_value), do: nil

  defp safe_cause(value) when is_atom(value), do: value

  defp safe_cause(value) when is_tuple(value) and tuple_size(value) > 0 do
    case elem(value, 0) do
      code when is_atom(code) -> code
      _value -> :operation_failed
    end
  end

  defp safe_cause(_value), do: :operation_failed

  defp safe_message(%__MODULE__{code: code}), do: default_message(code)
  defp safe_remediation(%__MODULE__{code: code}), do: remediation(code)

  defp sensitive_metadata_key?(key) do
    normalized = key |> to_string() |> String.downcase()
    Enum.any?(@sensitive_metadata_fragments, &String.contains?(normalized, &1))
  end
end

defimpl Inspect, for: Obscura.Diagnostic do
  import Inspect.Algebra

  def inspect(diagnostic, opts) do
    safe = %{
      code: diagnostic.code,
      message:
        diagnostic.code |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize(),
      remediation: Obscura.Diagnostic.remediation(diagnostic.code),
      component: diagnostic.component,
      profile: diagnostic.profile,
      dependency: diagnostic.dependency,
      backend: diagnostic.backend,
      asset: diagnostic.asset,
      metadata: Obscura.Diagnostic.safe_metadata(diagnostic.metadata)
    }

    concat(["#Obscura.Diagnostic<", to_doc(safe, opts), ">"])
  end
end
