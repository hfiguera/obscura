defmodule Mix.Tasks.Obscura.Operational.Diagnose do
  @moduledoc """
  Runs one sustained-latency diagnostic experiment.

      mix obscura.operational.diagnose \
        --profile balanced \
        --concurrency 4 \
        --duration-ms 120000 \
        --run-id balanced_probe_r1
  """

  use Mix.Task

  alias Obscura.Eval.Operational.Diagnostic.Runner

  @shortdoc "Diagnoses product-profile sustained latency"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    opts = parse(args)

    case Runner.run(opts[:profile], opts) do
      {:ok, result} ->
        Mix.shell().info("Wrote #{result.paths.json} and #{result.paths.markdown}")

      {:error, reason} ->
        Mix.raise("Operational diagnostic failed: #{inspect(reason)}")
    end
  end

  defp parse(args) do
    {parsed, remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          profile: :string,
          concurrency: :integer,
          duration_ms: :integer,
          authoritative: :boolean,
          diagnostics: :boolean,
          kind: :string,
          run_id: :string,
          repetition: :integer,
          sample_mode: :string,
          control_report: :string,
          sample_interval_ms: :integer,
          window_ms: :integer,
          idle_ms: :integer,
          request_timeout: :integer,
          output_root: :string,
          privacy_filter_checkpoint: :string
        ]
      )

    if remaining != [] or invalid != [], do: Mix.raise("Invalid operational diagnostic options.")

    profile = parse_profile(Keyword.get(parsed, :profile))
    authoritative? = Keyword.get(parsed, :authoritative, false)
    diagnostics? = Keyword.get(parsed, :diagnostics, true)
    concurrency = Keyword.get(parsed, :concurrency, 4)

    duration_ms =
      if authoritative?,
        do: canonical_duration(profile, concurrency),
        else: Keyword.get(parsed, :duration_ms) || Mix.raise("Expected --duration-ms.")

    if authoritative? and not diagnostics?,
      do: Mix.raise("Authoritative diagnostics cannot disable instrumentation.")

    run_id = Keyword.get(parsed, :run_id) || Mix.raise("Expected --run-id.")
    validate_run_id!(run_id)
    sample_interval = Keyword.get(parsed, :sample_interval_ms, 1_000)
    validate_positive!(:concurrency, concurrency)
    validate_positive!(:duration_ms, duration_ms)
    validate_positive!(:repetition, Keyword.get(parsed, :repetition, 1))
    validate_sample_interval!(sample_interval)

    [
      profile: profile,
      concurrency: concurrency,
      duration_ms: duration_ms,
      authoritative: authoritative?,
      diagnostics: diagnostics?,
      kind: parse_kind(Keyword.get(parsed, :kind, "instrumented")),
      run_id: run_id,
      repetition: Keyword.get(parsed, :repetition, 1),
      sample_mode: parse_sample_mode(Keyword.get(parsed, :sample_mode, "mixed")),
      control_report: Keyword.get(parsed, :control_report),
      sample_interval: sample_interval,
      window_ms: Keyword.get(parsed, :window_ms, 60_000),
      idle_ms: Keyword.get(parsed, :idle_ms, 10_000),
      request_timeout: Keyword.get(parsed, :request_timeout, 300_000),
      output_root: Keyword.get(parsed, :output_root, "eval/reports/operational/diagnostics"),
      privacy_filter_checkpoint:
        Keyword.get(parsed, :privacy_filter_checkpoint) ||
          System.get_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")
    ]
  end

  defp parse_profile(nil), do: Mix.raise("Expected --profile.")
  defp parse_profile("balanced"), do: :balanced
  defp parse_profile("openmed_pii"), do: :openmed_pii
  defp parse_profile(_value), do: Mix.raise("Diagnostic profile must be balanced or openmed_pii.")

  defp parse_kind("control"), do: :control
  defp parse_kind("instrumented"), do: :instrumented
  defp parse_kind(_value), do: Mix.raise("Diagnostic kind must be control or instrumented.")
  defp parse_sample_mode("mixed"), do: :mixed
  defp parse_sample_mode("fixed_triplet"), do: :fixed_triplet

  defp parse_sample_mode(_value),
    do: Mix.raise("sample_mode must be mixed or fixed_triplet.")

  defp canonical_duration(:balanced, 4), do: 600_000
  defp canonical_duration(:openmed_pii, 4), do: 1_800_000

  defp canonical_duration(_profile, _concurrency),
    do: Mix.raise("Unsupported canonical diagnostic.")

  defp validate_run_id!(value) do
    if Regex.match?(~r/^[a-z0-9][a-z0-9_-]{0,79}$/, value),
      do: :ok,
      else: Mix.raise("run_id must match [a-z0-9][a-z0-9_-]{0,79}.")
  end

  defp validate_positive!(_name, value) when is_integer(value) and value > 0, do: :ok
  defp validate_positive!(name, _value), do: Mix.raise("#{name} must be positive.")
  defp validate_sample_interval!(value) when value in 100..1_000, do: :ok
  defp validate_sample_interval!(_value), do: Mix.raise("sample_interval_ms must be 100..1000.")
end
