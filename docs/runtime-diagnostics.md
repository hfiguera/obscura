# Runtime Diagnostics

Optional runtimes fail through `%Obscura.Diagnostic{}` at the product profile
boundary. The struct carries a machine-readable code, safe message,
remediation, profile/component context, and report-safe metadata. Its `Inspect`
implementation omits local paths and nested causes and redacts sensitive
metadata keys.

Use the API without processing source text:

```elixir
case Obscura.Profile.preflight(:balanced, backend: :emily) do
  {:ok, report} -> report
  {:error, diagnostic, report} -> {diagnostic.code, report}
end
```

Use the Mix task for deployment checks:

```sh
mix obscura.profile.check --profile fast
mix obscura.profile.check --profile balanced --backend emily --json
```

The task exits non-zero on failure. `--prepare` is intentionally separate
because preparation may load large local assets or consult a model repository.
It remains cache-only unless `--allow-download` is also present. Prefer the
dedicated progress task for first-time provisioning:

```sh
mix obscura.profile.prepare \
  --profile balanced \
  --backend emily \
  --allow-download \
  --timeout 1800000 \
  --inactivity-timeout 300000
```

API callers receive the same lifecycle with `progress: fn event -> ... end`.
Events and telemetry identify profile, model alias/index, stage, elapsed time,
cache state, backend, and byte progress when observable. They intentionally
omit repository credentials, source text, HTTP payloads, and local paths.

## Stable Codes

`Obscura.Diagnostic.codes/0` is the machine-readable source for this stable
vocabulary:

- `unknown_profile`
- `profile_requirements_unsatisfied`
- `missing_optional_dependency`
- `missing_model_asset`
- `missing_tokenizer_asset`
- `model_asset_incomplete`
- `model_cache_failure`
- `model_download_interrupted`
- `model_download_not_allowed`
- `missing_model_config`
- `missing_checkpoint`
- `checkpoint_incomplete`
- `checkpoint_layout_mismatch`
- `checkpoint_hash_mismatch`
- `unsupported_model_architecture`
- `unsupported_backend`
- `backend_unavailable`
- `backend_device_unavailable`
- `backend_fallback_forbidden`
- `model_load_failed`
- `preparation_inactivity_timeout`
- `preparation_timeout`
- `tokenizer_load_failed`
- `serving_build_failed`
- `inference_timeout`

Not every low-level adapter has migrated to the struct. Existing atom and tuple
reasons remain supported internally; every known code above is preserved when
normalized at a stable public boundary. Unknown reasons become
`profile_requirements_unsatisfied` and retain their cause only inside the
in-memory diagnostic.

## Backend Proof

An accelerator claim requires runtime metadata, not dependency presence.
Authoritative model reports record requested backend, selected device, fallback
policy, compile settings, model/checkpoint identity, and source. Emily benchmark
runs use `OBSCURA_EMILY_FALLBACK=raise`; a failed GPU operation cannot silently
be presented as GPU evidence.

EXLA is not synonymous with GPU. A run that cannot identify an actual device
must report CPU or unknown.

ONNX Runtime CoreML requires the same distinction. A CoreML profile can prove
that ONNX Runtime assigned nodes to `CoreMLExecutionProvider`; it cannot prove
GPU-only execution because CoreML's applicable mode is `CPUAndGPU`. Reports
must also disclose CPU fallback and compare latency against the CPU provider.

## Safe Output

`Obscura.Diagnostic.to_map/1` omits `path` and `cause` and recursively redacts
metadata keys associated with paths, tokens, passwords, credentials, secrets,
or authorization. Messages and telemetry
must never include analyzed text, detected values, credentials, HTTP headers,
tokens, or complete provider payloads. A remediation may name an environment
variable or command, but not its secret value.
