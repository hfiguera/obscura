# Linux :spacy_cpu validation

Validated on 2026-09-05 UTC using Docker Desktop on Apple M4 Max. Both Linux ARM64 and x86-64 passed 174 tests with the real pinned model enabled. Each architecture reproduced every final profile prediction from the macOS native baseline on all 2,648 selected documents in two repetitions. No model weights, entity policy, threshold, or authoritative benchmark changed.

| Architecture | Dataset | Documents | Strict F1 | Mean latency | p95 latency |
|---|---|---:|---:|---:|---:|
| ARM64 | generated_large | 648 | 0.7190 | 0.679 ms | 1.190 ms |
| ARM64 | synth_dataset_v2 | 1500 | 0.7315 | 0.679 ms | 1.283 ms |
| ARM64 | nemotron_pii_test_subset | 500 | 0.5403 | 3.717 ms | 9.285 ms |
| x86-64 (emulated) | generated_large | 648 | 0.7190 | 1.150 ms | 2.002 ms |
| x86-64 (emulated) | synth_dataset_v2 | 1500 | 0.7315 | 1.179 ms | 2.235 ms |
| x86-64 (emulated) | nemotron_pii_test_subset | 500 | 0.5403 | 7.223 ms | 17.822 ms |

The x86-64 image runs through emulation on Apple Silicon. ARM64 runs in the Docker Linux VM. These measurements validate operation and prediction parity; they do not rank physical ARM64 versus Intel/AMD hardware or establish a deployment SLO. Latency covers live Obscura.analyze, including deterministic recognition, worker reservation, IPC, native inference, and conflict handling. One worker and one in-flight request; five warmups before each repetition. Means and p95s are averaged across the two repetitions.

| Architecture | Preparation, including asset hashing | Native worker peak RSS |
|---|---:|---:|
| ARM64 | 473.2 ms | 285.9 MiB |
| x86-64 (emulated) | 1054.4 ms | 293.2 MiB |

Preparation uses a warm filesystem cache. RSS is normalized to bytes on Linux, excludes BEAM, and depends on mapped vector pages touched and host accounting. Assets remain approximately 408 MiB.

The validation images use Debian 12/glibc, Elixir 1.18.4 / OTP 27.3.4.15, Rust 1.90.0, OpenBLAS 0.3.21, and PCRE2 10.42. Both native builds passed Clippy with warnings denied. Readiness and inference ran with Docker networking disabled and model/dataset mounts read-only. No Python interpreter is installed in the validation image. The readiness handshake and public runtime status identify openblas_cpu.

Tests cover UTF-8 spans, redaction, batch analysis, concurrent native calls, supervised ownership, native worker loss/recovery, corrupt assets, saturation, timeout, caller death, wrong-backend handshakes, and one-thread math environment settings. Linux validation exposed an OTP 27 normal-shutdown wrapper that now receives the same idempotent stop handling as newer OTP versions. The macOS regression suite also passed all 174 tests after these changes.

The Docker x86-64 lane requires ERL_FLAGS="+JMsingle true" to avoid Erlang JIT dual-mapping failures under emulation. This is an image-only validation setting, not a change to the library or a requirement for physical Linux hosts. See [Erlang emulator flags](https://www.erlang.org/doc/apps/erts/erl_cmd.html).

Linux support is limited to glibc ARM64 and x86-64 with matching LP64 OpenBLAS/PCRE2 libraries. Alpine/musl, Windows, Intel macOS, and other CPU architectures remain unsupported. Cross-platform parity here covers final profile detections after label filtering and conflict resolution, not every intermediate floating-point activation or every possible input. Balanced remains the general accuracy recommendation; Nemotron strict F1 remains 0.5403 versus 0.5659.

Reproduce using [Docker instructions](../linux/README.md). [ARM64 results](linux-arm64.json), [x86-64 results](linux-amd64.json), and [environment and image identities](linux-environment.json) record source/model/binary hashes, fingerprints, counts, and timings without raw input text. The historical [macOS profile report](PROFILE.md) remains unchanged.
