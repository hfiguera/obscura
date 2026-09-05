# Beyond Regex: Why We Shipped a CPU Profile for PII Detection

*Bringing spaCy NER to Elixir—and measuring what it finds, what it misses,
and what it costs.*

Consider a support assistant receiving this synthetic request:

```text
Find rachel.chen@example.test for Rachel Chen in London and summarize her support cases.
```

With Obscura's `:fast` profile, asking it to pseudonymize emails, people, and
locations produces:

```text
Find <<EMAIL_001>> for Rachel Chen in London and summarize her support cases.
```

With the new `:efficient` profile, the same request becomes:

```text
Find <<EMAIL_001>> for <<PERSON_001>> in <<LOCATION_001>> and summarize her support cases.
```

The email has an identifiable structure. Recognizing a person's name and a
place in ordinary prose needs more context. `:fast` already has contextual
recognizers, so it can detect some people and locations. It does not detect
those two spans in this example. These are actual outputs from Obscura 0.2.0,
using the same three-entity request and a fresh vault for each profile.

That gap is why we added `:efficient`: English name and location recognition
for applications that want a local CPU runtime with modest operating costs.

![On one synthetic support request, fast masks the email and efficient also
masks the name and location. On the heldout evaluation, efficient has 1,993
fewer missed exact spans and 3,044 more false positives than fast.](media/beyond-regex-why-we-shipped-a-cpu-profile-for-pii-detection/efficient-cpu-tradeoff.png)

*The example shows a useful capability. The evaluation shows its price.*

In the [previous model experiment](an-ai-hybrid-improved-pii-detection-we-still-did-not-ship-it.md),
an improved score did not justify another runtime dependency. Deterministic
recognizers could recover the useful gains. This time, the additional name
and location signal justified shipping an option, with its limitations made
explicit.

## What We Borrowed from spaCy

Obscura 0.2.0 combines its existing deterministic recognizers with a native
port of the NER component from spaCy's `en_core_web_lg` **3.8.0** model.
NER means named entity recognition: identifying spans such as people and
places from their context. We did not train a new model or fine-tune its
weights.

Presidio's [spaCy integration](https://presidio.dataprivacystack.org/analyzer/nlp_engines/spacy_stanza/)
also uses `en_core_web_lg` in its default English configuration. Presidio can
use other NLP engines and models, so “the Presidio model” is shorthand for a
particular configuration. Our comparison pins that model version and
Presidio Analyzer **2.2.363**; it does not track a moving latest release.

Sharing weights does not make the complete detectors equivalent. Obscura
maps spaCy's `PERSON` label to `:person`, and `GPE`, `LOC`, and `FAC` to
`:location`. It combines those spans with its own recognizers, resolves
overlaps, and applies the versioned `efficient_v1` boundary policy. Other
supported entities, including emails, cards, and phone numbers, continue to
use deterministic recognition. This profile does not add organization NER.

The boundary policy handles details such as surrounding form punctuation,
following field labels, honorifics, and bounded expansion inside labeled
address fields. Those decisions affect what gets replaced, even when the
underlying model weights are identical.

The [initial native implementation](https://github.com/hfiguera/obscura/blob/v0.2.0/eval/spacy_native/results/RESULTS.md)
was checked against Python spaCy for NER output parity. The public profile's
boundary changes were then developed and evaluated separately. Porting
inference and improving application spans are different claims, and we
measured them separately.

## More Recall Has a Precision Cost

We selected 5,000 development documents and 5,000 previously unused test
documents from [Gretel's synthetic English PII dataset](https://huggingface.co/datasets/gretelai/gretel-pii-masking-en-v1).
The boundary policy was frozen before observing the final test predictions.
We did not tune rules on that test set.

The test contains 13,039 annotated spans across eight requested entities:
person, location, email, phone, SSN, credit card, IP address, and date/time.
These are synthetic application-like documents, not a human-audited sample
of production traffic. Their annotations can be incomplete or inconsistent.
The [frozen protocol and selection](https://github.com/hfiguera/obscura/tree/v0.2.0/eval/efficient)
document how literal annotation values become offsets, including 28 supported
annotation values that could not be located in the test text.

Here, a correct prediction must match both the entity type and the **exact
span**. Precision measures how many predictions are correct; recall measures
how many annotated spans are recovered. F1 balances those two measures.

| Detector | Precision | Recall | Exact F1 | False positives | Missed exact spans |
| --- | ---: | ---: | ---: | ---: | ---: |
| Obscura `:fast` | 0.8425 | 0.5096 | 0.6351 | 1,242 | 6,394 |
| Original native spaCy hybrid | 0.6416 | 0.6395 | 0.6406 | 4,658 | 4,700 |
| Obscura `:efficient` | 0.6684 | 0.6625 | **0.6654** | 4,286 | 4,401 |
| Pinned Presidio configuration | 0.5443 | 0.6942 | 0.6102 | 7,578 | 3,987 |

Source: [heldout results and methodology](https://github.com/hfiguera/obscura/blob/v0.2.0/eval/efficient/README.md).

Relative to `:fast`, `:efficient` has **1,993 fewer missed exact spans** and
**3,044 more false positives**. That is a material improvement in recall,
with a material precision cost. Unnecessary replacement can remove useful
context from a support summary or make a log harder to interpret.

Relative to this Presidio configuration, `:efficient` has 3,292 fewer false
positives and 414 more missed exact spans. It is a different operating
tradeoff. Presidio has higher recall here.

We did not evaluate `:balanced` or `:accurate` on this new selection. Their
results on older datasets do not belong in this table. The entity policy also
differs from our earlier eight-entity benchmark: this one includes date/time
and omits URL.

## A Better F1 Can Still Leave More PII Exposed

An exact-span miss does not always mean the entire value was left visible.
If a detector finds only the surname in a full name, exact scoring counts a
false positive and a false negative. Some identity was masked; some remains.

We therefore inspected redaction coverage alongside exact matching. On this
same eight-entity request:

| Coverage of annotated PII | `:efficient` | Pinned Presidio |
| --- | ---: | ---: |
| Completely uncovered spans | 2,969 | 1,814 |
| Only partially covered spans | 1,238 | 1,637 |

These supplementary coverage measures were added after evaluation and did
not influence policy selection. They are included in the
[aggregate report](https://github.com/hfiguera/obscura/blob/v0.2.0/eval/efficient/results/heldout.json).

This changes how I read the headline result. Efficient has higher exact F1
on this set, yet leaves more annotated values completely uncovered than
Presidio. A higher F1 alone does not establish stronger privacy protection.

Full postal addresses are a particular weakness. Most annotated locations in
this test are complete addresses. Efficient covers at least part of 879 out
of 1,761 locations, but only **254 match exactly**. Detecting a city inside an
address is useful; it is not complete address redaction. These numbers apply
to the frozen eight-entity evaluation, not the default thirteen-entity profile.

For reversible pseudonymization, boundaries also define the vault mapping.
Replacing half a name or absorbing unrelated text changes what can be
restored later. A useful evaluation should measure missed data, unnecessary
replacement, and the quality of the replacement spans.

## Rust Inference, Owned by an Elixir Application

The runtime is a standalone Rust executable connected to Elixir through an
**Erlang Port**. It is not a Rustler NIF, and it does not require a Python
service during inference.

```text
Elixir application
  Obscura recognizers + span policy + redaction/vault
       |
       | local IPC through an Erlang Port
       v
  supervised native worker pool
       |
       v
  Rust inference + verified spaCy model assets
```

Source text crosses a local process boundary to the native worker. It does
not stay entirely inside the BEAM. The application still owns the workers'
lifecycle, and inference requires no network access.

The process boundary gives native failures a place to be contained. Each
worker handles one request at a time; the profile supports one to four
workers. When all are occupied, admission returns a busy error immediately.
The pool does not retain a queue of source texts.

A failed native request returns an error. There is no automatic fallback to
`:fast` that quietly changes the detection policy. Faulted or expired workers
are discarded and replaced, with bounded restart attempts. Applications must
decide how to handle unavailable capacity before sending content downstream.

Native input limits are 1 MiB of UTF-8 text and 10,000 tokens, with no implicit
chunking. They are native inference limits, not a deadline for the complete
analyzer: deterministic recognition also takes time. Apply document-size
limits and time budgets at the application boundary. The
[public contract](https://hexdocs.pm/obscura/0.2.0/efficient.html)
specifies timeouts, errors, recovery, and supported platforms.

## What Sustained CPU Traffic Looked Like

We tested the final profile with one through four workers on Apple Silicon
macOS, Linux ARM64, and physical Linux x86-64 hardware. Each configuration had
a warmup followed by 300 measured seconds. The workload mixed 80% short,
18% medium, and 2% long documents; long documents contained 250 sentences.

The physical Linux host was a System76 Meerkat with an Intel i5-1135G7
(four cores, eight threads) and 62 GiB RAM. It ran a native x86-64 Debian 12
container on Pop!_OS 22.04, without CPU emulation. These results measure that
CPU and container environment; they do not establish compatibility with the
older host glibc outside the container.

| Workers | Requests/second | p95 latency | p99 latency | Max sampled native RSS |
| --- | ---: | ---: | ---: | ---: |
| 1 | 16.93 | 35.5 ms | 2,566.4 ms | 66.9 MiB |
| 2 | 26.57 | 49.0 ms | 3,313.8 ms | 124.3 MiB |
| 3 | 33.26 | 69.2 ms | 4,128.3 ms | 185.8 MiB |
| 4 | 32.89 | 88.9 ms | 5,090.4 ms | 235.2 MiB |

Source: [physical Linux workload report](https://github.com/hfiguera/obscura/blob/v0.2.0/eval/efficient/results/workload-physical-linux-x86_64.json).

The fourth worker increased latency without increasing throughput. More
workers are not automatically better. The p99 includes long documents and
should not be presented as short-request latency.

RSS here sums native worker processes, excludes BEAM memory, and can count
shared mapped pages more than once. The largest sampled native growth was
47.29 MiB in the three-worker run. This passed the declared regression budget;
five-minute runs cannot establish hours-long memory stability.

All twelve platform/worker configurations passed the release checks, with
zero unexpected inference errors or restarts during normal traffic and
successful separate saturation and recovery checks. A replay also produced
identical typed byte spans on all 5,000 heldout documents across the three
platforms. The [complete evidence](https://github.com/hfiguera/obscura/blob/v0.2.0/eval/efficient/README.md)
includes raw samples and reproduction instructions. These are workload
measurements, not a production capacity promise or a timing comparison with
the other profiles.

## Install Assets Once, Reuse the Runtime

Obscura 0.2.0 is [available on Hex](https://hex.pm/packages/obscura/0.2.0).
Add it to your dependencies:

```elixir
{:obscura, "~> 0.2.0"}
```

Prebuilt targets cover Linux x86-64 and ARM64 with **glibc 2.36 or later**,
plus the validated Apple Silicon macOS development environment. Follow the
[installation guide](https://hexdocs.pm/obscura/0.2.0/efficient.html)
for platform libraries, provisioning tools, and deployment options. After
installing those prerequisites, provision the assets explicitly:

```bash
mix deps.get
mix obscura.efficient.install --allow-download
mix obscura.profile.check --profile efficient --prepare --offline --json
```

The installer verifies the native executable and official model wheel against
pinned hashes. A temporary, locked Python export environment converts the
model to verified native assets; upstream notices are retained. Python and uv
are provisioning tools; inference uses the Rust executable through an Erlang
Port, without Python or a network connection.

The assets occupy about **408 MiB on disk**, mostly memory-mapped vectors.
Include them in deployment planning: small measured RSS does not make the
model download small.

To reproduce the opening example in an IEx session after installation:

```elixir
{:ok, runtime} =
  Obscura.Profile.prepare(:efficient, workers: 2, offline: true)

text =
  "Find rachel.chen@example.test for Rachel Chen in London and summarize her support cases."

{:ok, messages, vault} =
  Obscura.LLM.redact_messages(
    [%{role: "user", content: text}],
    profile: runtime,
    entities: [:person, :location, :email],
    vault: :memory
  )

IO.puts(hd(messages).content)

{:ok, restored} =
  Obscura.LLM.rehydrate_response("Found <<PERSON_001>>.", vault: vault)

IO.puts(restored)
# Found Rachel Chen.
```

Pass the protected `messages` to the model. Keep the vault inside the trusted
application and manage its session lifecycle. The three selected entities
demonstrate this comparison; define the complete entity, message-role, and
outbound-path policy for your application, as in the
[agent integration article](the-agent-needs-identity-the-model-does-not.md).

For a server, prepare once under supervision. Add this child to the
application's supervision tree:

```elixir
{Obscura.Profile.Preparer,
 name: MyApp.Efficient,
 profile: :efficient,
 prepare_options: [workers: 2, offline: true]}
```

Wait for readiness before accepting work that requires the profile:

```elixir
{:ok, runtime} = Obscura.Profile.Preparer.await(MyApp.Efficient)
```

Reuse the returned runtime. The preparer owns the workers and stops them when
it stops. A directly prepared runtime belongs to its caller; a short-lived
request process is the wrong owner for a shared pool.

Assets and the span policy are pinned and versioned. The
[asset manifest](https://github.com/hfiguera/obscura/blob/v0.2.0/priv/obscura/efficient-assets.json)
and [provenance documentation](https://hexdocs.pm/obscura/0.2.0/model-asset-licensing.html)
record hashes and distribution terms. Model weights come from Explosion;
preserve their upstream notices when distributing prepared assets.

## Which Profile Would I Choose?

The name `:efficient` describes an operating choice. The profile adds English
NER while keeping a CPU deployment practical. It does not promise to be the
fastest profile or the most accurate one.

| Start with | When this is the main requirement |
| --- | --- |
| `:fast` | Minimum dependencies and latency, especially for structured identifiers and known formats |
| `:efficient` | Additional English person/location recognition with a native CPU runtime and a bounded worker pool |
| `:balanced` | Stronger general accuracy on Obscura's existing shared benchmarks, with the model runtime that entails |
| `:accurate` | The best measured general accuracy on those shared benchmarks, with a larger compute budget |

The transformer profiles can also run on CPUs. Efficient's distinction is its
particular model, runtime, and measured tradeoffs, not exclusive CPU support.

For a support assistant that routinely handles names in prose, I would test
`:efficient` against `:fast` on representative messages. For mostly emails,
cards, and identifiers, I would begin with `:fast`. For either, I would count
both what remains visible and what useful text is unnecessarily removed.

The [Obscura workbench](https://github.com/hfiguera/obscura_examples) lets you
try the profiles, and the [Jido example](https://github.com/hfiguera/obscura_jido_example)
shows the application boundary around an agent. Bring synthetic versions of
your own messages rather than real customer data to a public report.

The most useful next contribution is a small, reproducible failure case:
a missed name, an address with only its city masked, or ordinary prose
mistaken for PII. Include the requested entities, detected spans, and expected
replacement in an [issue](https://github.com/hfiguera/obscura/issues).
Those examples tell us which capability to improve—and whether the next
improvement needs a model at all.
