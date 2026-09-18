# Integration implications

Redact is a separate native inference stack. The evaluated official path is
Python benchmark driver → NDJSON Node worker → official native SDK/C ABI → Swift
pipeline → Core ML on Apple or LiteRT/XNNPACK on Linux. Python is an evaluation
dependency, not an inference requirement. The existing efficient path is an
Elixir process supervising a Rust executable through an Erlang Port.

The benchmark adapter is not a production Elixir integration. It proves that a
reusable external worker can expose typed UTF-8 spans from the official pipeline.
It does not establish production supervision, release packaging, queue limits or
multi-tenant behavior for a new Obscura backend.

If a later decision favors integration, an external worker fits Obscura's current
architecture. Elixir can send text and receive spans, retaining Obscura's vault,
replacement policy and diagnostics. There is no need to transfer placeholder
maps to Redact or adopt a second vault. A native crash can remain outside the
BEAM. Calling this SDK through Rustler would add another runtime boundary and
bring native failure into the VM without resolving the model's accuracy or
license questions.

An initial adapter could use the official Node entry point. A dedicated Swift
executable might avoid Node and the npm installation, but its build, footprint
and operational behavior have not been benchmarked as a production worker.
The SDK also exposes C ABI functions; a Rust executable could potentially wrap
that ABI while retaining the Swift inference runtime. That path would need its
own lifecycle, ABI compatibility and packaging checks. It is not the existing
spaCy weights loader and has not been implemented or measured here.
These unmeasured alternatives should not be presented as smaller installations.
Reusing the current Rust spaCy weights loader is not a direct option: Redact
ships different model formats and a different tokenizer/postprocessing pipeline.

The installed SDK package contains native artifact directories for Apple Silicon
macOS, Linux x86-64 and Linux ARM64. This evaluation runs the first two; artifact
presence does not establish compatibility on an untested host or OS version.

Required implementation work would include:

- Explicit versioned asset provisioning and checksums, separate from inference;
  platform-specific runtime packaging with approved distribution terms.
- Fixed entity mapping and UTF-16/UTF-8 conversion, tested across full names,
  addresses, Unicode and overlapping spans. The frozen evaluation mapping is a
  candidate policy, not a public contract.
- Bounded requests, timeouts, queue admission and worker lifecycle handling.
  This evaluation kills/restarts owned processes; it does not implement a new
  production supervisor or validate an SDK admission policy.
- A health check that detects neural failure, rather than accepting successful
  JSON or regex-only output. Mac CPU currently fails this gate.
- Decisions about unsupported types, model upgrades and the offline contract.
  Preserving required usage reporting must remain part of that decision.

Sentence splitting would be an additional behavior change. Its diagnostic
success on repetitive passages does not justify silently adding it to the
published pipeline or inferring its effect on accuracy and throughput.

Licensing requirements also exist for existing models: Obscura's balanced
documentation identifies conditions for commercial use of its TNER checkpoint.
This evaluation does not imply that every alternative model is unrestricted.
Redact adds the distinct public-SDK distribution and mandatory-telemetry questions
recorded in [LICENSING.md](LICENSING.md).
