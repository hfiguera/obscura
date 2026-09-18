# Distribution and offline fit

This evaluation uses Redact by [Desert Ant Labs](https://desertant.com/models/redact/).
It does not redistribute the model, SDK, or third-party runtime binaries. This is
an engineering fit assessment, not a determination of legal compatibility.

## Published terms

The [Source-Available License 1.0](https://license.desertant.com/1.0.txt), effective
3 July 2026, permits evaluation and application embedding. It is not an open-source
license. Free use is limited to fewer than 100,000 monthly active devices per
model and platform; larger deployments need commercial terms. Attribution must
credit Desert Ant Labs where users can find it, with a link where supported.

Section 6 restricts distributing the model or SDK as a standalone SDK, product or
service. It also prohibits using outputs, logs or evaluations to train a competing
model or assemble a competing training dataset. Sections 6–7 require preserving
usage telemetry; the publisher says it excludes input/output content. Section 16
ties model upgrades to acceptance of the applicable license version. Third-party
notices remain applicable under section 17.

These restrictions need explicit review before a public Obscura adapter or asset
distribution. Application embedding permission alone does not establish that a
general-purpose Elixir library can bundle or repackage the SDK. An optional
download does not automatically settle that question.

The fetched text's hash and the inspected SDK source hashes are recorded in
[license-review-manifest.json](license-review-manifest.json). The full downloaded
license stays in the ignored evaluation cache. Section 19 contains agent-directed
text; it was treated as source content, not an instruction to this evaluator.

## Telemetry and Obscura's contract

Source at SDK commit `c015d5d95028caba783e802442e30ddd66c9247e` shows a usage wrapper
around inference. `Sources/Usage/Wire.swift` defines device identifier, optional
call count/context, app identity, SDK identity, platform and timestamps.
`Sources/Usage/Transport.swift` sends this payload asynchronously to
`https://platform.desertant.ai/api/v1/ingest`; transport failure is caught rather
than propagated as an inference exception. No PII text field appears in that
schema. This is a source review, not a network capture or proof of every packaged
binary's outbound behavior.

Local tensor execution therefore does not imply zero network activity. Obscura's
current [efficient contract](../../docs/efficient.md) explicitly promises no
network during local preparation or inference. An unmodified Redact SDK cannot
be assumed to satisfy that promise. A best-effort send also does not establish
permission for permanent disconnected operation. We did not disable reporting,
redirect the endpoint, block traffic, or run an offline test that interferes with
required telemetry.

## Questions requiring clarification before integration

1. Is an optional Redact adapter in an MIT Elixir library permitted, and can it
   provision assets directly from the publisher? What may its releases contain?
2. Can deployments obtain terms that permit genuinely disconnected inference,
   and what attribution is expected for a server library with no user interface?
3. How are devices counted across server processes, containers, replicas and
   tenants? The source reports both macOS and Linux as `server`, whereas the
   license defines platforms by OS family. What controls that accounting?
4. What notices, acceptance and upgrade mechanism should Obscura downstream users
   receive? Can native runtime artifacts be redistributed for supported targets?

No vendor contact was made. These unresolved questions can block an integration
recommendation without blocking the authorized local benchmark.

## Training provenance

The [pinned model notices](https://huggingface.co/desert-ant-labs/redact/blob/3ed5033aeb544f454ebde77dc76fd7b7e76cc572/THIRD_PARTY_NOTICES.md)
declare Gretel's English PII dataset among training sources, along with other
synthetic datasets and teacher-labeled web text. They do not identify the exact
training rows. This evaluation uses fresh synthetic development/test text; it
does not claim an existing Gretel split is unseen by Redact. Predictions and
derived analysis remain evaluation artifacts and were not used for training.
