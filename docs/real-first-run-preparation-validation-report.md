# Real First-Run Preparation Validation

Date: 2026-07-21

## Purpose

This report validates the real first-run behavior of the stable model-backed
profiles. It covers an empty cache, multi-gigabyte downloads, visible progress,
an interrupted download, quarantine and recovery, network-denied cache reuse,
Emily GPU selection, cache size, and warm runtime readiness.

This is operational evidence, not model-accuracy evidence. No model weights,
tokenizer assets, cache files, or raw PII are committed to the repository.

## Environment

| Item | Value |
| --- | --- |
| Host | Apple M4 Max MacBook Pro |
| Memory | 128 GiB |
| OS | macOS 26.5.2 |
| Backend | Emily 0.7.2 |
| Requested device | Apple GPU |
| Fallback policy | `:raise` |
| Starting source revision | `38736ab60730` |
| Cache | Isolated temporary `BUMBLEBEE_CACHE_DIR` |

`mix emily.doctor` passed before the acceptance run. Runtime metadata for every
loaded serving reported `actual_backend: :emily`, `actual_device: :gpu`,
`backend_proven: true`, and `fallback_occurred: false`.

## Procedure

The validation used this sequence:

1. Create an empty, isolated cache.
2. Prepare `:balanced` online with explicit download authorization.
3. Prepare `:accurate`, interrupt the second model download, and terminate the
   Erlang VM.
4. Inspect the incomplete cache and run preparation again.
5. Confirm the unreferenced fragment moved under `.obscura-quarantine` and the
   second model downloaded cleanly.
6. Prepare both profiles with `--offline` while macOS denied outbound network
   access through `sandbox-exec`.
7. Run real inference with the retained `:accurate` runtime.
8. Repeat `:balanced` from a second empty cache after fixing issues discovered
   by the first run.

The relevant environment and command shape was:

```sh
BUMBLEBEE_CACHE_DIR=/tmp/isolated-obscura-cache \
OBSCURA_REAL_MODEL_BACKEND=emily \
OBSCURA_EMILY_FALLBACK=raise \
mix obscura.profile.prepare \
  --profile balanced \
  --backend emily \
  --allow-download \
  --timeout 1800000 \
  --inactivity-timeout 600000 \
  --json
```

Offline proof used an operating-system network policy, not only Obscura's
offline option. Local inbound TCP remained allowed because Mix uses a local
lock socket; all other network operations were denied.

## Results

### Cold Balanced Preparation

The final clean-cache repetition passed end to end.

| Measurement | Result |
| --- | ---: |
| Wall time | 182.55 s |
| Model load/download stage | 180.551 s |
| Reported model download bytes | 1,417,630,478 |
| Tokenizer load/download stage | 1.478 s |
| Serving construction | 2.770 ms |
| Cache disk usage | 1,394,076 KiB (`du`) |
| Cache file count | 12 |
| Backend proof | Emily GPU, no fallback |

Progress began at 1,483 observed bytes and increased throughout the real
multi-gigabyte transfer. Events included profile, model index, stage, elapsed
time, cache state, and cumulative observed bytes. The task therefore remained
visibly active instead of appearing hung. Upstream download metadata did not
provide a reliable total length, so `total_bytes` and percentage remained
unknown; observed byte growth and stage transitions were still available.

### Interrupted Accurate Preparation

The cache already contained the `:balanced` model when `:accurate` preparation
started. The second, Jean-Baptiste model was interrupted after approximately
105.9 MB had been reported. The incomplete cache contained an unreferenced
108,122,522-byte file and no matching metadata.

Cache inspection classified the state as `:partial` with one incomplete entry.
The next authorized online preparation moved that file under
`.obscura-quarantine`, then downloaded the second model from a clean active
cache location. It did not treat the fragment as complete.

| Measurement | Result |
| --- | ---: |
| Accurate recovery wall time | 167.37 s |
| Jean model load/download stage | 163.479 s |
| Jean tokenizer fallback load | 2.279 s |
| Quarantined fragment | 108,122,522 bytes |
| Final active cache | 2,837,783,230 bytes |
| Final quarantine | 108,122,522 bytes |
| Final total cache | 2,945,905,752 bytes |
| Final file count | 27 |
| Backend proof | Both servings on Emily GPU, no fallback |

The interruption test also found that recovery progress used the pre-quarantine
cache size as its baseline. This underreported replacement download bytes by
the size of the quarantined fragment. Preparation now sends an explicit cache
recovery event and resets the observer baseline to the post-quarantine size.
A deterministic regression test proves that a 128-byte replacement is reported
as 128 bytes, independent of polling timing.

Quarantine is deliberately retained for diagnosis and manual cleanup. It is
included in total disk usage but excluded from the active cache measurement.

### Offline Cache Reuse

Both profiles passed while macOS denied outbound network access.

| Profile | Internal preparation | Wall time | Model load stages | Result |
| --- | ---: | ---: | --- | --- |
| `:balanced` | 0.676 s | 1.03 s | 614.458 ms | Complete, Emily GPU |
| `:accurate` | 1.359 s | 1.71 s | 611.602 ms + 648.452 ms | Complete, both on Emily GPU |

For the second clean `:balanced` cache, disk usage remained 1,394,076 KiB and
the file count remained 12 before and after the network-denied run. This proves
cache reuse without network access or replacement downloads.

The `:accurate` runtime was also exercised with:

```text
Rachel works at Google in Paris.
```

It returned exact person, organization, and location detections. Runtime
preparation took 1.397 seconds and first inference took 75.591 ms. Both the
primary TNER serving and Jean location serving reported Emily GPU with fallback
disabled.

## Defects Found And Fixed

### Transient Tokenizer Load After A Completed Model Download

The first cold `:balanced` attempt downloaded and loaded the 1.4 GB model, then
received a transient tokenizer repository/load failure. An immediate direct
load of the same pinned tokenizer revision succeeded, and a separate clean
tokenizer-only probe also succeeded. The pinned tokenizer and revision were
therefore valid.

Online model and tokenizer asset loads now retry one sanitized dependency or
interruption failure. The retry is a separately observable
`model_load_retry` or `tokenizer_load_retry` stage. Offline preparation never
retries and therefore cannot turn a cache miss into network activity. Focused
tests prove both behaviors. The second genuine empty-cache run passed without
needing the retry.

### Recovery Progress Baseline

The real interruption showed that the observer could preserve the old partial
file size after quarantine and underreport replacement bytes. Cache recovery
now communicates the post-quarantine byte baseline directly from the worker to
the caller before model loading starts. Polling-based byte-decrease detection
remains a defensive fallback.

## Acceptance Decision

| Requirement | Decision | Evidence |
| --- | --- | --- |
| Start from an empty cache | Pass | Two isolated clean-cache `:balanced` runs |
| Prepare `:balanced` on Emily GPU | Pass | Real cold and network-denied warm runs |
| Prepare `:accurate` on Emily GPU | Pass | Two model servings, GPU proven, fallback false |
| Visible multi-GB progress | Pass | Continuous observed-byte and stage events |
| Interrupt preparation | Pass | VM terminated during Jean download |
| Quarantine incomplete data | Pass | 108,122,522-byte fragment retained outside active cache |
| Recover after interruption | Pass | Clean redownload and complete accurate runtime |
| Offline zero-network operation | Pass | OS-denied outbound network for both profiles |
| Cache reuse | Pass | Stable file count/size and sub-two-second preparation |
| Warm runtime readiness | Pass | Real accurate inference in 75.591 ms |

Real first-run preparation is accepted for the measured Apple/Emily path. It is
bounded, observable, recoverable, and reusable offline. This does not establish
Linux/EXLA behavior, universal download throughput, or model-license approval.
Cold duration remains network-dependent, and retained quarantine files require
an operator disk-retention policy.
