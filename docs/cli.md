# CLI

Obscura provides Mix tasks for operational workflows. They are wrappers over
the library APIs, not a standalone application.

## Detect

```sh
mix obscura.detect path/to/file.txt
mix obscura.detect path/to/file.txt --format json
mix obscura.detect --stdin --format json
```

JSON output is value-safe by default:

```json
{
  "status": "ok",
  "profile": "regex_only",
  "results": [
    {
      "entity": "email",
      "start": 10,
      "end": 28,
      "score": 0.85,
      "recognizer": "email",
      "source_entity": "EMAIL_ADDRESS"
    }
  ],
  "latency_ms": 1.0
}
```

Use `--include-text` only for local debugging when showing detected values is acceptable.

## Redact

```sh
mix obscura.redact note.txt --out note.redacted.txt
mix obscura.redact note.txt --stdout
mix obscura.redact --stdin --stdout
```

Output files are not overwritten unless `--force` is supplied.

## Config

```sh
mix obscura.gen.config
mix obscura.gen.config --write config/runtime.exs
mix obscura.gen.config --write config/runtime.exs --force
```

Generated config recommends stable local profiles. Model-backed runtime assets
must still be prepared explicitly by the host application.

## Prediction Export

```sh
mix obscura.export.predictions \
  --dataset synth_dataset_v2 \
  --profile regex_only \
  --limit 25 \
  --out eval/predictions/obscura_regex_only.jsonl
```

Each JSONL line uses Presidio-compatible character offsets and omits raw text and detected values.
