# Structured Redaction

`Obscura.Structured` recursively redacts maps, lists, keyword lists, strings,
and opted-in structs. String inputs return `%Obscura.Anonymizer.Result{}`;
structured inputs return `%Obscura.Structured.Result{}`.

## Maps and Lists

```elixir
input = %{
  user: %{email: "jane@example.com", password: "secret"},
  phones: ["202-555-0188"]
}

{:ok, result} =
  Obscura.redact(input,
    entities: [:email, :phone],
    field_policies: %{password: :drop}
  )

result.data
#=> %{user: %{email: "[EMAIL]"}, phones: ["[PHONE]"]}
```

Each redaction item records the structured path, entity, operator, source byte offsets within the leaf string, replacement, and safe metadata.

Structured traversal validates UTF-8 string leaves, option shapes, field
policies, and recursion depth. Improper lists and inputs exceeding `max_depth`
return controlled errors rather than partially redacted output. Tuples remain
opaque values; callers must convert tuple-held data explicitly when it needs
redaction. Very wide collections can still consume proportional CPU and
memory, so untrusted input size needs an application-level limit.

## Field Policies

Field policies are keyed by map key or struct field:

- `:drop` removes map keys and resets struct fields to their default value.
- `:keep` leaves the field unchanged.
- `{:replace, value}` replaces the whole field value.
- `{:operator, config}` applies an anonymizer operator to the whole field.
- `{:entity, entity}` analyzes the field as a specific entity.
- `:traverse` recurses into nested values.

Common sensitive keys such as `:password`, `:token`, and `:api_key` are replaced by default unless an explicit policy overrides them.

## Structs

Opaque structs such as `Date`, `Time`, `DateTime`, `URI`, `Regex`, `MapSet`, and `Range` are preserved.

Application structs can opt in with `@derive`:

```elixir
defmodule User do
  @derive {Obscura.Redactable,
           fields: [
             email: {:entity, :email},
             password_hash: :drop,
             profile: :traverse
           ]}
  defstruct [:email, :password_hash, :profile]
end
```

`traverse_structs: true` can traverse non-derived structs, and `preserve_structs: false` converts traversed structs to maps.

## Dry Run

`Obscura.Structured.analyze/2` runs traversal with `dry_run: true` and returns only structured items. This is useful for audits where the original data must remain unchanged.

Default `Inspect` implementations hide result data, item paths, replacements,
and metadata. Explicit `result.data` and item fields remain sensitive. Dry-run
mode does not shorten the lifetime of the original input or analyzer result
values.
