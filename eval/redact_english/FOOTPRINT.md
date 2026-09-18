# Model assets, installed files and memory are different measurements

Redact's inference assets are much smaller than efficient's vectors or balanced's
checkpoint. The evaluated Node installation does not inherit the same size ratio.
Its dependencies and language runtime are substantial, especially when Node is
added to an Elixir deployment that already has Erlang/Elixir.

`footprint.py` measures apparent file bytes and allocated blocks, counting hardlinks
once within each group. It records the efficient install receipt and verified
native executable hash, and selects only the pinned TNER revision from the cache.
Redact and efficient preparation verify model hashes. Bumblebee identifies TNER
cache entries by revision and publisher tags; a separate byte-level integrity
check verifies that cache against immutable publisher metadata. This check passed
on both hosts after timing, including the complete 1.42 GB checkpoint bytes and
the five efficient model files. See `results/{macos,linux}/baseline-integrity.json`.
The size collector itself does not read large model contents. Size reports are
`results/{macos,linux}/footprint.json`.

## Measured apparent disk size

MiB means 1,048,576 bytes. These groups overlap; do not sum every row.

| Component | Mac MiB | Linux MiB |
| --- | ---: | ---: |
| Redact weight file / LiteRT model file alone | 11.01 | 23.39 |
| Redact platform inference assets, including tokenizer/labels | 11.47 | 23.77 |
| Redact installed npm dependency tree | 193.71 | 193.71 |
| Current-platform Redact native directory, already inside npm tree | 0.72 | 62.10 |
| Installed Node prefix, including bundled tools/headers | 67.05 | 213.95 |
| Installed Homebrew dependency prefixes for Node | 152.87 | not applicable |
| Redact Node stack, selecting only platform inference assets | 425.10 | 431.44 |
| Entire observed Redact Node stack and downloaded model cache | 450.70 | 431.44 |
| Efficient five native model files | 407.83 | 407.83 |
| Efficient installed assets, executable and notices | 408.45 | 408.52 |
| Balanced selected checkpoint, tokenizer and configuration | 1353.25 | 1353.25 |
| All compiled libraries in the evaluation's Obscura consumer | 327.45 | 467.59 |
| Installed Erlang prefix | 113.55 | 28.67 |
| Installed Elixir prefix | 24.57 | 12.77 |

Mac's model cache includes both platform exports and diagnostic configuration
files. Linux's SDK cache contains its Linux assets only. The platform-subset row
is an arithmetic subset of measured files, not a newly built distribution.
The npm tree contains other platforms and browser support as shipped. The Node
prefixes are installed distributions, not minimal executable-only bundles.
Homebrew dependencies include their installed tools and headers too; they are
not all newly attributable to this experiment if already used by other software.

The consumer has every optional dependency used by the three Obscura baselines.
Its total must not be called the minimum installation of fast or efficient.
Fast adds no NER weights. Efficient's native installation does not require Node,
Nx, EXLA, or a Python environment at inference. Redact through the tested Node
adapter would add its Node stack to an Elixir application; Erlang/Elixir remain
common application requirements. Balanced needs its checkpoint plus the applicable
Nx/Bumblebee/native execution dependencies, not just the checkpoint bytes.

OS frameworks and shared system libraries are excluded from these private-file
totals. In particular Linux efficient requires OpenBLAS and PCRE2, which may
already be installed; this comparison does not assign a zero size to them. Mac
uses Accelerate and PCRE2. These measurements are not compressed container sizes,
dependency-minimized releases, or proof of a universally smaller installation.

The useful measured distinction is that Redact's model assets are small, whereas
the whole tested Node stack is roughly the same order of size as efficient's
installed native assets. If Node is already available, Redact's incremental cost
is lower. A dedicated Swift worker or a carefully pruned package could change
the comparison, but neither deployment has been built and measured here.

## Runtime memory

Model file bytes do not determine resident memory. Efficient memory maps vectors;
Redact and EXLA allocate runtime state; each language runtime also consumes memory.
The sustained workload reports therefore sample the complete worker process tree's
RSS and Linux PSS independently of these disk measurements. RSS can count shared
pages repeatedly across workers; PSS apportions them. Five-minute growth and sampled
peaks do not establish long-term leak freedom or an absolute peak between samples.

The complete 1–4 worker comparison is in [WORKLOAD_RESULTS.md](WORKLOAD_RESULTS.md).
On Linux with one worker, sampled peak RSS was 186.7 MiB for Redact, 145.1 MiB
for efficient and 2,083.9 MiB for balanced. Redact's smaller model does not provide
a measured resident-memory advantage over efficient in this deployment.
