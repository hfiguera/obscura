defmodule Mix.Tasks.Obscura.Operational.Soak do
  @moduledoc """
  Runs one long-duration operational soak.

      mix obscura.operational.soak --profile openmed_pii --concurrency 4 --authoritative
  """

  use Mix.Task

  alias Obscura.Eval.Operational.Soak.Runner

  @shortdoc "Runs a product-profile operational soak"
  @profiles ~w(fast balanced openmed_pii)

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    opts = parse(args)

    case Runner.run(opts[:profile], opts) do
      {:ok, result} ->
        Mix.shell().info("Wrote #{result.paths.json} and #{result.paths.markdown}")

      {:error, reason} ->
        Mix.raise("Operational soak failed: #{inspect(reason)}")
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
          sample_interval_ms: :integer,
          window_ms: :integer,
          idle_ms: :integer,
          request_timeout: :integer,
          output_root: :string,
          privacy_filter_checkpoint: :string
        ]
      )

    if remaining != [] or invalid != [], do: Mix.raise("Invalid operational soak options.")

    profile = parse_profile(Keyword.get(parsed, :profile))
    concurrency = Keyword.get(parsed, :concurrency, canonical_concurrency(profile))
    authoritative? = Keyword.get(parsed, :authoritative, false)

    duration_ms =
      if authoritative?,
        do: canonical_duration(profile, concurrency),
        else: Keyword.get(parsed, :duration_ms) || Mix.raise("Expected --duration-ms.")

    sample_interval = Keyword.get(parsed, :sample_interval_ms, 1_000)
    validate_positive!(:concurrency, concurrency)
    validate_positive!(:duration_ms, duration_ms)
    validate_sample_interval!(sample_interval)

    [
      profile: profile,
      concurrency: concurrency,
      duration_ms: duration_ms,
      authoritative: authoritative?,
      sample_interval: sample_interval,
      window_ms: Keyword.get(parsed, :window_ms, 60_000),
      idle_ms: Keyword.get(parsed, :idle_ms, 10_000),
      request_timeout: Keyword.get(parsed, :request_timeout, 300_000),
      output_root: Keyword.get(parsed, :output_root, "eval/reports/operational/soak"),
      privacy_filter_checkpoint:
        Keyword.get(parsed, :privacy_filter_checkpoint) ||
          System.get_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")
    ]
  end

  defp parse_profile(nil), do: Mix.raise("Expected --profile.")

  defp parse_profile(value) do
    case Enum.find(@profiles, &(&1 == value)) do
      nil -> Mix.raise("Unknown soak profile.")
      profile -> String.to_existing_atom(profile)
    end
  end

  defp canonical_concurrency(:openmed_pii), do: 4
  defp canonical_concurrency(_profile), do: 4
  defp canonical_duration(:openmed_pii, 4), do: 1_800_000
  defp canonical_duration(:openmed_pii, 1), do: 600_000
  defp canonical_duration(profile, 4) when profile in [:fast, :balanced], do: 600_000
  defp canonical_duration(_profile, _concurrency), do: Mix.raise("Unsupported canonical soak.")

  defp validate_positive!(_name, value) when is_integer(value) and value > 0, do: :ok
  defp validate_positive!(name, _value), do: Mix.raise("#{name} must be positive.")

  defp validate_sample_interval!(value) when is_integer(value) and value in 1..1_000, do: :ok
  defp validate_sample_interval!(_value), do: Mix.raise("sample_interval_ms must be 1..1000.")
end
