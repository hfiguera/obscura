defmodule Obscura.Efficient.Workload do
  @moduledoc false
  alias Obscura.Spacy.{Assets, Serving}

  def main do
    seconds = String.to_integer(System.get_env("EFFICIENT_SOAK_SECONDS") || "300")
    output = System.fetch_env!("EFFICIENT_REPORT")
    source_hashes = runtime_sources()
    runner_hash = sha(__ENV__.file)
    binary_hash = sha(Assets.paths([]).native_binary)
    reports = Enum.map(1..4, &run(&1, seconds))

    unchanged =
      source_hashes == runtime_sources() and runner_hash == sha(__ENV__.file) and
        binary_hash == sha(Assets.paths([]).native_binary)

    report = %{
      schema_version: 1,
      profile: :efficient,
      created_at: DateTime.utc_now(),
      environment: System.get_env("EFFICIENT_ENVIRONMENT") || "unspecified",
      architecture: to_string(:erlang.system_info(:system_architecture)),
      elixir: System.version(),
      otp: to_string(:erlang.system_info(:otp_release)),
      binary_sha256: binary_hash,
      model_hashes: Assets.hashes(),
      runner_sha256: runner_hash,
      runtime_source_sha256: source_hashes,
      source_and_binary_unchanged_during_measurement: unchanged,
      sustained_seconds_per_configuration: seconds,
      passed: seconds >= 300 and unchanged and Enum.all?(reports, & &1.passed),
      configurations: reports
    }

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, Jason.encode!(report, pretty: true) <> "\n")
    IO.puts(Jason.encode!(Map.take(report, [:passed, :environment])))
  end

  defp runtime_sources do
    Map.new(
      Path.wildcard("lib/obscura/spacy/*.ex") ++
        [
          "lib/obscura/recognizer/spacy.ex",
          "lib/obscura/profile/runtime.ex",
          "lib/obscura/profile.ex"
        ],
      &{&1, sha(&1)}
    )
  end

  defp run(workers, seconds) do
    {:ok, runtime} = Obscura.Profile.prepare(:efficient, workers: workers)
    pool = runtime.resources.spacy

    try do
      # Warm every worker before sampling. Histograms are bounded (0.1 ms bins).
      batch(runtime, workers, 10)
      slices = max(div(seconds, 10), 1)

      samples =
        Enum.map(1..slices, fn index ->
          started = now()
          rows = batch(runtime, workers, min(seconds, 10))

          sample = %{
            elapsed_seconds: index * min(seconds, 10),
            interval_seconds: (now() - started) / 1_000,
            successful_requests: Enum.sum(Enum.map(rows, & &1.count)),
            errors: Enum.reduce(rows, %{}, &merge(&1.errors, &2)),
            latency_histogram: Enum.reduce(rows, %{}, &merge(&1.histogram, &2)),
            native_rss_bytes: rss(native_pids(pool)),
            beam_rss_bytes: rss([System.pid()]),
            status: Serving.status(pool)
          }

          IO.puts(
            Jason.encode!(
              Map.take(sample, [:elapsed_seconds, :successful_requests, :native_rss_bytes])
              |> Map.put(:workers, workers)
            )
          )

          sample
        end)

      before_failure = Serving.status(pool)
      checks = failure_checks(runtime, workers)
      stable_samples = Enum.drop(samples, div(length(samples), 3))
      first = hd(stable_samples)
      last = List.last(stable_samples)
      native_growth = last.native_rss_bytes - first.native_rss_bytes
      beam_growth = last.beam_rss_bytes - first.beam_rss_bytes
      elapsed_minutes = max((last.elapsed_seconds - first.elapsed_seconds) / 60, 1 / 60)
      errors = Enum.reduce(samples, %{}, &merge(&1.errors, &2))
      histogram = Enum.reduce(samples, %{}, &merge(&1.latency_histogram, &2))
      total = Enum.sum(Enum.map(samples, & &1.successful_requests))

      %{
        workers: workers,
        successful_requests: total,
        requests_per_second: total / Enum.sum(Enum.map(samples, & &1.interval_seconds)),
        p50_ms: percentile(histogram, 0.5),
        p95_ms: percentile(histogram, 0.95),
        p99_ms: percentile(histogram, 0.99),
        errors: errors,
        native_growth_bytes_after_first_third: native_growth,
        beam_growth_bytes_after_first_third: beam_growth,
        native_growth_mib_per_minute: native_growth / 1_048_576 / elapsed_minutes,
        checks: checks,
        passed:
          errors == %{} and before_failure.failures == 0 and
            native_growth <= workers * 32 * 1_048_576 and beam_growth <= 64 * 1_048_576 and
            Enum.all?(checks, fn {_, value} -> value == true end),
        samples: Enum.map(samples, &Map.delete(&1, :latency_histogram))
      }
    after
      Serving.stop(pool)
    end
  end

  defp batch(runtime, workers, seconds) do
    deadline = now() + seconds * 1_000

    1..workers
    |> Enum.map(fn worker ->
      Task.async(fn ->
        traffic(runtime, deadline, worker, %{count: 0, errors: %{}, histogram: %{}})
      end)
    end)
    |> Enum.map(&Task.await(&1, (seconds + 60) * 1_000))
  end

  defp traffic(runtime, deadline, index, acc) do
    if now() >= deadline do
      acc
    else
      text = text(index)
      started = System.monotonic_time(:microsecond)
      result = Obscura.analyze(text, profile: runtime, include_text: false)
      bin = min(div(System.monotonic_time(:microsecond) - started, 100), 600_000)

      next =
        case result do
          {:ok, _} ->
            %{acc | count: acc.count + 1, histogram: Map.update(acc.histogram, bin, 1, &(&1 + 1))}

          {:error, reason} ->
            %{acc | errors: Map.update(acc.errors, error_code(reason), 1, &(&1 + 1))}
        end

      traffic(runtime, deadline, index + 1, next)
    end
  end

  defp text(index) do
    names = [
      "Alice Smith",
      "José García",
      "Amelia Jones",
      "Mohammed Ali",
      "Sofia Rossi",
      "David Chen"
    ]

    cities = ["London", "São Paulo", "Paris", "New York", "San Francisco", "Tokyo"]

    sentence =
      "Case #{rem(index, 10_000)}: #{Enum.at(names, rem(index, 6))} moved to #{Enum.at(cities, rem(div(index, 6), 6))}. Contact user#{rem(index, 1_000)}@example.com. "

    repeats =
      cond do
        rem(index, 50) == 0 -> 250
        rem(index, 5) == 0 -> 25
        true -> 1
      end

    String.duplicate(sentence, repeats)
  end

  defp failure_checks(runtime, workers) do
    pool = runtime.resources.spacy
    parent = self()

    holders =
      Enum.map(1..workers, fn _ ->
        spawn(fn ->
          send(parent, {:reserved, GenServer.call(pool, :reserve)})

          receive do
            :release -> :ok
          end
        end)
      end)

    Enum.each(holders, fn _ ->
      receive do
        {:reserved, {:ok, _}} -> :ok
      after
        5_000 -> raise "reservation failed"
      end
    end)

    saturated = match?({:error, :spacy_busy}, Serving.predict(pool, "Alice Smith"))
    no_queue = Serving.status(pool).queued_inputs == 0
    Enum.each(holders, &send(&1, :release))
    released = eventually(fn -> Serving.status(pool)[:busy] == 0 end)
    # Exercise an actual native-process crash and replacement, not a fake port.
    [pid | _] = native_pids(pool)
    failures_before_kill = Serving.status(pool).failures
    {_output, 0} = System.cmd("sh", ["-c", "kill -KILL \"$1\"", "kill", to_string(pid)])

    recovered =
      eventually(fn ->
        status = Serving.status(pool)
        status[:workers] == workers and status[:failures] > failures_before_kill
      end)

    valid_after_failure =
      match?({:ok, [_ | _]}, Obscura.analyze("Alice Smith lives in London.", profile: runtime))

    byte_limit =
      match?(
        {:error, :spacy_input_limit},
        Serving.predict(pool, String.duplicate("x", 1_048_577))
      )

    invalid_utf8 = match?({:error, :spacy_invalid_input}, Serving.predict(pool, <<255>>))
    token_limit = match?({:error, _}, Serving.predict(pool, String.duplicate("word ", 10_001)))
    eventually(fn -> Serving.status(pool)[:workers] == workers end)
    valid_after_limit = match?({:ok, _}, Obscura.analyze("Alice Smith", profile: runtime))
    Serving.stop(pool)
    closed = match?({:error, _}, Obscura.analyze("Alice Smith", profile: runtime))

    %{
      saturation_rejected: saturated,
      no_text_queue: no_queue,
      caller_death_releases: released,
      native_crash_recovers: recovered and valid_after_failure,
      byte_limit_rejected: byte_limit,
      invalid_utf8_rejected: invalid_utf8,
      token_limit_rejected: token_limit,
      valid_after_limit: valid_after_limit,
      stopped_runtime_fails_closed: closed
    }
  end

  defp native_pids(pool) do
    :sys.get_state(pool).slots
    |> Enum.flat_map(fn {_, slot} ->
      case Port.info(slot.port, :os_pid) do
        {:os_pid, pid} -> [pid]
        _ -> []
      end
    end)
  end

  defp rss([]), do: 0

  defp rss(pids) do
    if :os.type() == {:unix, :linux} do
      Enum.sum(
        Enum.map(pids, fn pid ->
          status = File.read!("/proc/#{pid}/status")
          [_, kib] = Regex.run(~r/^VmRSS:\s+(\d+) kB$/m, status)
          String.to_integer(kib) * 1024
        end)
      )
    else
      {output, 0} = System.cmd("ps", ["-o", "rss=", "-p", Enum.join(pids, ",")])
      output |> String.split() |> Enum.map(&String.to_integer/1) |> Enum.sum() |> Kernel.*(1024)
    end
  end

  defp eventually(fun, attempts \\ 200)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.(),
      do: true,
      else:
        (
          Process.sleep(25)
          eventually(fun, attempts - 1)
        )
  end

  defp merge(left, right), do: Map.merge(left, right, fn _, a, b -> a + b end)
  defp error_code(%{code: code}), do: to_string(code)
  defp error_code(reason) when is_atom(reason), do: to_string(reason)
  defp error_code(_), do: "other_error"

  defp percentile(histogram, quantile) do
    target = ceil(Enum.sum(Map.values(histogram)) * quantile)

    histogram
    |> Enum.sort()
    |> Enum.reduce_while(0, fn {bin, count}, acc ->
      if acc + count >= target, do: {:halt, {:found, (bin + 1) / 10}}, else: {:cont, acc + count}
    end)
    |> case do
      {:found, value} -> value
      _ -> nil
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp sha(file), do: file |> Assets.sha256() |> elem(1)
end

Obscura.Efficient.Workload.main()
