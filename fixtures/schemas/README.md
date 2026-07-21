# Fixture Schemas

The executable fixture schemas are implemented in `Obscura.Fixtures.Schema`.

Analyzer fixtures are stored under:

```text
fixtures/analyzer/
```

Operator fixtures are stored under:

```text
fixtures/operator/
```

The executable schemas validate:

- required top-level fields
- fixture kind
- source attribution
- requested entities
- expected spans
- operator spans
- byte offsets
- character offsets when present
- expected span values
- operator expected item shape
- unique fixture IDs through `Obscura.Fixtures.Loader`

The schemas use Elixir terms so the fixture runner can load them directly. A
JSON schema can be added later if an external fixture generator needs it.
