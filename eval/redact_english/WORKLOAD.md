# Operational CPU protocol v1

Frozen before measured workload runs. Run fast, efficient, balanced and Redact
CPU on each host, sequentially per host, with 1, 2, 3 and 4 independent worker
processes. Redact's Apple default is excluded from CPU performance comparisons.

Each worker is a reusable NDJSON process, using the same driver and request text.
Obscura runs in the isolated Elixir consumer; Redact uses its official native Node
SDK. This measures an external process pool, including RPC overhead, not maximum
in-process library throughput. Obscura's optional evaluation dependencies are
installed for all three baseline profiles; memory is not a minimal fast install.
Worker count means process count, not a cap on runtime/BLAS internal threads.

Use development IDs 00-0, 01-0, 05-0, 08-0, 14-0, 18-0 and 19-0, covering short,
structured, negative, address and longer inputs. Each worker completes entire
seven-request cycles. This preserves the same mixture across algorithms despite
different speeds. No test outcome influences the workload selection.

Record fresh-process startup with cached assets, first inference, and a full
warmup cycle. This is not a machine reboot or a purged filesystem-cache test.
Then saturate the pool with one outstanding RPC per worker for at least **300
seconds**. Record complete request count, errors, throughput, p50/p95/p99 and
per-input counts. Capture total worker-tree RSS every ten seconds, plus Linux
PSS where available, load average, start/end/peak and growth. RSS sums shared
pages more than once; compare within each host and do not confuse RSS with PSS.

After sustained traffic, submit a burst of eight requests per worker through
the same worker pool. Record completion latency including queue wait and errors.
The queue belongs to this harness; it is not evidence of an SDK admission policy.
Finally kill one owned worker process group, verify that its failure is observable,
restart it, and compare its canary predictions with its own pre-failure result.
Record recovery time and check surviving workers. This tests process-pool recovery,
not automatic recovery from every possible internal native failure.

The canary is a short English name/location/email sentence. Its transport
recovery and name detection are separate observations. The known nonfinite Apple
CPU result makes Redact's Mac CPU run **ineligible as successful NER performance**,
even if the SDK returns valid JSON rapidly. Preserve its operational results and
invalid-quality status instead of presenting them as a speed advantage.

The machines are development hosts, not dedicated laboratory servers. Report
hardware, runtime versions, load, dataset and source hashes, and retain this
limitation. Five minutes can reveal growth during that interval; it cannot prove
the absence of leaks over days or production reliability.
