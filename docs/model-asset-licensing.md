# Third-Party Dependency And Model Asset Review

This document records the release licensing review for Obscura as of
2026-07-22. It is an engineering inventory and release decision, not legal
advice. A deployer remains responsible for determining whether a dependency,
model, tokenizer, dataset, or generated output is permitted for its use.

## Release Decision

- Obscura source and the Hex package are released under MIT.
- The resolved software dependency graph uses permissive MIT, Apache-2.0, or
  BSD-2-Clause licenses. No GPL, AGPL, SSPL, source-available, or
  non-commercial software dependency was found.
- The Hex package bundles the four pinned `tiktoken` vocabulary files and now
  includes `THIRD_PARTY_NOTICES.md` with the upstream OpenAI/Shantanu Jain MIT
  notice.
- Presidio-Research snapshots and the vendored Ortex fork retain their own
  notices in the repository and are excluded from the Hex package.
- Optional model weights, tokenizers, caches, and ONNX exports are not bundled
  or sublicensed by Obscura.
- Software licensing does not block the base `:fast` release. The optional
  model-backed profiles remain subject to the asset decisions below.

## Software Dependencies

The review used `mix.lock`, each fetched Hex package's
`hex_metadata.config`, included license files, and the vendored Ortex notice.
Versions are the versions resolved by the release worktree.

### Direct Runtime And Optional Dependencies

| Dependency | Version | Use | Declared license | Decision |
| --- | --- | --- | --- | --- |
| `jason` | 1.4.5 | Base JSON handling | Apache-2.0 | Approved |
| `telemetry` | 1.4.2 | Base telemetry | Apache-2.0 | Approved |
| `plug` | 1.20.3 | Optional Plug integration | Apache-2.0 | Approved |
| `nx` | 0.12.1 | Optional tensor runtime | Apache-2.0 | Approved |
| `bumblebee` | 0.7.0 | Optional token classification | Apache-2.0 | Approved |
| `safetensors` | 0.1.3 | Optional checkpoint loading | Apache-2.0 | Approved |
| `ex_phone_number` | 0.4.11 | Optional phone parsing | MIT | Approved |
| `exla` | 0.12.0 | Development/test accelerator | Apache-2.0 | Approved |
| `emily` | 0.7.2 | Development/test Apple GPU backend | MIT | Approved |
| `tokenizers` | 0.5.1 | Optional GLiNER tokenizer | Apache-2.0 | Approved |
| vendored `ortex` | 0.1.10-obscura.1 | Repository-only GLiNER adapter | MIT | Approved; excluded from Hex package |

The resolved runtime transitive packages are also permissive:

- Apache-2.0: `axon`, `castore`, `complex`, `decimal`, `elixir_make`, `fine`,
  `hpax`, `mime`, `mint`, `nimble_options`, `nimble_pool`, `nx_image`,
  `nx_signal`, `plug_crypto`, `polaris`, `req`, `rustler_precompiled`,
  `unpickler`, and `xla`.
- MIT: `finch`, `progress_bar`, `sweet_xml`, and `unzip`.
- Dual MIT/Apache-2.0: `rustler`.

Development and test packages (`bunt`, `credence`, `credo`, `dialyxir`,
`earmark_parser`, `erlex`, `ex_dna`, `ex_doc`, `ex_slop`, `file_system`,
`makeup`, `makeup_elixir`, `makeup_erlang`, `nimble_parsec`, `sourceror`, and
`stream_data`) are MIT, Apache-2.0, or BSD-2-Clause and are not shipped as
runtime dependencies of Obscura.

Native upstream components follow the same permissive boundary: EXLA/XLA and
Hugging Face Tokenizers are Apache-2.0; Emily/MLX, Ortex/ONNX Runtime, and the
Elixir phone integration are MIT or consume Apache-2.0 upstream components.
Binary artifact notices must continue to be preserved by the package which
distributes each artifact.

## Bundled Tiktoken Vocabularies

Obscura bundles `r50k_base.tiktoken`, `p50k_base.tiktoken`,
`cl100k_base.tiktoken`, and `o200k_base.tiktoken`. Their source URLs and
SHA-256 hashes match the official `openai/tiktoken` encoding definitions.
The upstream project is MIT and its copyright/permission notice is preserved
in `THIRD_PARTY_NOTICES.md`.

The files are package data, not model weights. They must remain hash-pinned;
changing their source, bytes, or attribution requires a new review. If a
future upstream notice separates vocabulary-data terms from the tiktoken MIT
license, Obscura must either adopt those terms or stop bundling the files.

## Model And Dataset Assets

Stable profile contracts do not grant rights to their external assets.
Obscura downloads assets only during explicit preparation, pins immutable
revisions where available, and never bundles them in the Hex package.

| Asset | Reviewed chain | Decision |
| --- | --- | --- |
| `tner/roberta-large-ontonotes5` at `0bce50f7...` | Checkpoint has no license metadata; TNER code is MIT; dataset card says `other`; OntoNotes is governed by an LDC agreement | **Commercial use requires LDC for-profit membership.** LDC directly confirmed this requirement on 2026-07-22. Obscura does not grant or verify authorization and does not redistribute the checkpoint. LDC did not conclusively answer the separate checkpoint-redistribution question. |
| `Jean-Baptiste/roberta-large-ner-english` at `8f3abc1e...` | Checkpoint MIT; `FacebookAI/roberta-large` tokenizer/base at `722cf37b...` MIT; trained on CoNLL-2003 | **Conditional deployer review.** Model/base grants are permissive, but training-data rights are not granted by Obscura. |
| `OpenMed/privacy-filter-nemotron-v2` at reviewed revision `96824732...` | Checkpoint declares `license: other`; base `openai/privacy-filter` is Apache-2.0; Nemotron data is CC-BY-4.0; Gretel data is Apache-2.0; AI4Privacy data identifies CC-BY-4.0 | **Unresolved external asset.** The permissive base/data chain does not replace a checkpoint license grant. Keep experimental and do not redistribute. |
| `urchade/gliner_multi_pii-v1` at `1fcf13e8...` | Checkpoint Apache-2.0; `gliner_multi-v2.1` Apache-2.0; synthetic PII dataset Apache-2.0; `microsoft/mdeberta-v3-base` tokenizer/encoder MIT | **Permissive chain documented.** Experimental status remains based on product quality and exported-asset support, not an identified license blocker. |

### Stable Profile Consequences

The `:balanced` and `:accurate` names, option schemas, preparation behavior,
and result contracts are stable Obscura APIs. In direct correspondence dated
2026-07-22, LDC confirmed that commercial use of their default
`tner/roberta-large-ontonotes5` asset requires an LDC for-profit membership.
Stable therefore means API compatibility and measured technical behavior, not
permission to use a checkpoint. Noncommercial use remains subject to the
applicable LDC and upstream terms.

`:accurate` adds the Jean-Baptiste model. Its model and base-model metadata are
MIT, but users must still make their own CoNLL-2003 provenance decision.

The Urchade chain is the cleanest reviewed optional model chain, but its lower
measured quality and CPU-oriented supported path keep it experimental.
OpenMed v2 remains experimental and license-blocked for redistribution because
the checkpoint itself declares `other` without supplying terms.

## Deployment Contract

Before preparing an external model, deployers must:

1. Record the exact model, tokenizer, base model, datasets, and immutable
   revisions.
2. Review all applicable checkpoint, tokenizer, dataset, hosting, and output
   terms for the intended use and jurisdiction.
3. Preserve required copyright, attribution, and license notices.
4. Avoid redistributing cached or converted assets unless that right is
   explicit.
5. Retain the organization's approval decision with the deployed artifact.
6. Re-run accuracy, privacy, memory, latency, and failure validation for any
   substituted model or converted checkpoint.

For `tner/roberta-large-ontonotes5`, commercial deployers must additionally
obtain and document the required LDC for-profit membership. Obscura cannot
verify membership or confer checkpoint rights, and membership does not resolve
the unanswered checkpoint-redistribution question on Obscura's behalf.

`Obscura.Profile.preflight/2` reports third-party asset warnings. Passing
preflight proves runtime readiness only; it does not prove legal authorization,
regulatory compliance, or universal model quality.

## Review Renewal Triggers

Repeat this review when any dependency version, model revision, tokenizer,
training dataset, asset source, conversion path, package contents, or upstream
license metadata changes. Do not silently replace an unresolved asset with a
new revision under the same profile name.

## Primary References

- [Obscura source repository](https://github.com/hfiguera/obscura)
- [OpenAI tiktoken](https://github.com/openai/tiktoken)
- [TNER checkpoint](https://huggingface.co/tner/roberta-large-ontonotes5)
- [TNER dataset card](https://huggingface.co/datasets/tner/ontonotes5)
- [OntoNotes Release 5.0](https://catalog.ldc.upenn.edu/LDC2013T19)
- [LDC User Agreement for Non-Members](https://catalog.ldc.upenn.edu/license/ldc-non-members-agreement.pdf)
- [LDC For-Profit Membership Agreement](https://catalog.ldc.upenn.edu/license/ldc-for-profit-membership.pdf)
- [Jean-Baptiste checkpoint](https://huggingface.co/Jean-Baptiste/roberta-large-ner-english)
- [FacebookAI RoBERTa large](https://huggingface.co/FacebookAI/roberta-large)
- [OpenMed Privacy Filter Nemotron v2](https://huggingface.co/OpenMed/privacy-filter-nemotron-v2)
- [OpenAI Privacy Filter](https://huggingface.co/openai/privacy-filter)
- [NVIDIA Nemotron-PII](https://huggingface.co/datasets/nvidia/Nemotron-PII)
- [Gretel PII masking dataset](https://huggingface.co/datasets/gretelai/gretel-pii-masking-en-v1)
- [AI4Privacy OpenPII dataset](https://huggingface.co/datasets/ai4privacy/pii-masking-openpii-1m)
- [Urchade GLiNER PII](https://huggingface.co/urchade/gliner_multi_pii-v1)
- [Urchade synthetic PII dataset](https://huggingface.co/datasets/urchade/synthetic-pii-ner-mistral-v1)
- [Microsoft mDeBERTa v3 base](https://huggingface.co/microsoft/mdeberta-v3-base)
