# Efficient plus Redact address experiment

Frozen before this follow-up's fresh predictions. Keep the original evaluation
and its data, worker implementations, protocols and reports unchanged.

Run efficient on the original English text, then run the complete official
Redact CPU pipeline on that same text. Select only normalized Redact location
spans containing a raw STREET_NAME or BUILDING_NUMBER component. Replace any
existing location/street_address prediction wholly contained in such a span;
retain other efficient predictions. Deduplicate identical canonical spans.
Exposure uses the union of original component detections, never inferred gaps.
Do not gate calls by address keywords or change thresholds after test results.

A Redact error fails the hybrid request explicitly; no silent fallback is counted
as successful enrichment. Successful but invalid Mac CPU output remains a known
quality failure. The parent Python compositor is an evaluation adapter, not a
public Elixir profile. It calls two reusable child processes sequentially.

Fresh development and test text is assistant-authored synthetic English, created
without candidate predictions. It contains new templates and address/name values;
it is not population or human-annotated production evidence. No training use.
The previous test's post-hoc 0.9019 F1 is exploratory, not a validation target.

Compare fast, efficient, Redact CPU and the hybrid on identical fresh text on both
hosts. For operations, compare efficient, Redact CPU and hybrid with 1 and 4
logical workers, 60 seconds per configuration and whole six-input cycles. Each
hybrid logical worker owns two processes plus efficient's native child. Record
startup, first/warm latency, throughput, whole child-tree RSS/PSS and growth.
The compositor/driver memory is excluded for all variants. Capture host load.
Use a queued burst and deliberately kill/restart one underlying Redact process
(or the sole worker for a baseline), checking visible failure and restored output.
These short follow-up runs are not new five-minute endurance certification.
All assets are cached; no claim of filesystem-cold startup or new minimal bundle.
