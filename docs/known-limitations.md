# Known Limitations

Obscura is an early-release library. Its stable profiles have governed contracts
and current benchmark evidence, but the project does not yet claim universal
production readiness, regulatory compliance, or complete Presidio parity.

The `0.1.x` compatibility promise applies only to modules and functions listed
in `docs/public-api-stability.md`. Low-level model adapters, evaluation
tooling, and internal implementation modules can change independently of that
surface.

## Detection

- `:fast` is precise but misses arbitrary prose names, locations,
  organizations, and free-form addresses.
- Stable `:balanced` and `:accurate` depend on general NER models. They
  still miss entity types outside their label taxonomies and can produce
  model-specific false positives.
- Experimental `:hybrid_gliner_urchade` is the public CPU-only general NER
  option, but it has lower exact F1 than `:balanced` on all three shared
  datasets. Its recommendation is for CPU portability and a clearer model
  provenance chain, not superior accuracy.
- Stable `:accurate` has slightly higher exact F1 than `:balanced` on all three
  authoritative datasets, but uses two models and has materially higher
  latency and memory cost.
- Experimental `:openmed_pii` is specialized for Nemotron/OpenMed-style PII. It performs
  substantially worse on broad Presidio-style datasets and has high/tail-heavy
  latency. On the refreshed Apple/Emily host, Nemotron p95 reached roughly
  `6.67 seconds` at concurrency `4`, and warm runs observed transient process
  RSS up to `48.303 GiB` and Emily allocator statistics up to `41.293 GiB`.
  These peaks occurred in different runs and must not be summed.
- The historical soak classifier labels the 30-minute OpenMed C4 run as
  allocator caching rather than a probable leak: live Emily memory returned
  to baseline and cache clearing succeeded. That finite result does not prove
  bounded production-duration growth. OpenMed memory remains **inconclusive**
  for release decisions. Large headroom and strict admission control remain
  required.
- Ten-minute `:fast` and `:balanced` memory results are inconclusive under the
  conservative growth classifier. `:fast` latency is stable; `:balanced`
  throughput and tail latency degrade in later windows. The slowdown is
  localized to fixed-shape Emily model serving, but direct GPU
  power/frequency/utilization evidence is unavailable without privileged
  macOS tooling.
- Exact byte spans remain the anonymization contract. IoU metrics can identify
  near-boundary model matches but do not make an incorrect exact span safe.
- Context enhancement changes scores or gates existing candidates; it does not
  create broad NER coverage.
- Parser-backed phone detection is optional and region-dependent.
- Built-ins do not cover every jurisdiction, secret type, or industry ID.

## Models, Assets, and Licensing

- No model weights or external datasets ship in the Hex package.
- Analyzer/redaction calls never download models. Preparation is explicit.
- In direct correspondence on 2026-07-22, LDC confirmed that commercial use of
  `tner/roberta-large-ontonotes5` requires an LDC for-profit membership. Stable
  profile status does not grant or verify that authorization. Noncommercial use
  remains subject to the applicable LDC and upstream terms.
- The Apache-licensed Urchade GLiNER candidate has reproducible native Ortex
  support, but exact F1 is lower than `:balanced` on all three authoritative
  datasets. The Obscura Ortex fork can verify CoreML provider assignment, but
  the dynamic Urchade graph falls back heavily to CPU and measured `57.10x`
  slower warm inference than the CPU provider. CoreML does not expose a strict
  GPU-only mode. The candidate and its CoreML path remain experimental.
- Jean-Baptiste uses a tokenizer fallback from `FacebookAI/roberta-large`; both
  model and tokenizer terms must be reviewed.
- OpenMed Privacy Filter license metadata is not a clear production grant.
- Emily is validated on Apple Silicon for development/benchmarking, not as a
  universal deployment backend.
- EXLA presence does not prove GPU execution.
- Linux/EXLA operational load evidence has not been executed. Current capacity
  recommendations apply only to the measured Apple M4 Max/Emily environment.
- Advanced GLiNER, Ortex, and historical NER profiles are not stable product
  profiles. `:hybrid_gliner_urchade` is the only public experimental GLiNER
  product profile.
- `:balanced` and `:accurate` are stable profile contracts with external asset
  licensing delegated to the deployer. `:hybrid_gliner_urchade` and
  `:openmed_pii` remain experimental.
- Model preparation is bounded and observable, but byte totals are unavailable
  when an upstream response omits content length or while work is CPU/GPU model
  deserialization rather than file transfer. Stage transitions remain visible,
  and callers must size the overall and inactivity timeouts for their hardware.
- Interrupted unreferenced files are retained under `.obscura-quarantine` for
  diagnosis. They are excluded from the active cache but continue to consume
  disk until an operator removes them under an appropriate retention policy.
- Per-profile preparation is serialized within the connected Erlang node set.
  Independent disconnected nodes still require deployment-level coordination
  when they share a writable model cache.

## Privacy and Operations

- Reports and telemetry omit raw values by default, but callers remain
  responsible for logs produced before Obscura receives data.
- Analyzer results contain detected source text when `include_text: true`.
  Value-safe default inspection does not change explicit field access or
  serialization through `Map.from_struct/1`.
- Vault rehydration intentionally stores raw values in memory or ETS until the
  caller clears/stops the vault.
- Clearing/stopping a vault drops accessible references and removes private ETS
  tables, but BEAM and native memory cannot be guaranteed zeroized.
- Memory and ETS vaults are reversible, session-scoped stores. They are not
  encrypted persistent secret stores and do not protect against VM
  administrators, tracing tools, debuggers, or hostile code running in the
  same VM.
- Custom recognizers, operators, language detectors, telemetry handlers, and
  model dependencies are trusted application/runtime code and can independently
  log or transmit values they receive.
- Logger and Plug helpers cannot redact entities that configured recognizers
  miss. Callers must evaluate their own data and downstream sinks.
- Security reports use GitHub Private Vulnerability Reporting. Reporters need
  a GitHub account, and the project does not promise a response or remediation
  SLA. See `SECURITY.md`.
- No encrypted persistent vault or Ecto storage backend is provided.
- Obscura does not ship Google, Azure, Ollama, or generic HTTP recognizers.
  Applications needing an external service must implement and validate a custom
  `Obscura.Recognizer` integration, including retention, authentication,
  failure, and compliance policies.
- Stream support covers token rehydration, not a complete distributed stream
  processing system.

## Scope

- No OCR, image, PDF, DICOM, or document-layout redaction is implemented.
- No standalone HTTP service or Phoenix application is required or bundled.
- No provider-specific LLM SDK is bundled.
- No encryption anonymizer operator is implemented.
- Secure hash mode prevents identical replacements by using a fresh random
  salt, but hashing remains irreversible and low-entropy inputs may still be
  guessed. Deterministic hash mode intentionally reveals equality and requires
  an explicit salt of at least 16 bytes.
- Structured offsets are byte offsets within each string leaf, not offsets in
  a serialized document.

Current metrics and dataset-specific caveats are in
`docs/benchmark-status.md`. Optional setup is in
`docs/optional-dependencies-and-assets.md`. Security boundaries and accepted
risks are in `docs/security-threat-model.md`. Operational capacity, memory,
latency, and sustained-load conclusions are summarized in
`docs/benchmark-status.md`.
