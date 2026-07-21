# Anonymizer Operators

Obscura validates every configured operator before it modifies text. A bad
configuration returns `{:error, %Obscura.Anonymizer.Error{}}`; it never returns
a successful or partially anonymized result.

Errors expose only stable codes, operator and field atoms, safe reason atoms,
and allowlisted metadata. They never contain source text, replacements, salts,
callback return values, or exception messages.

## Replace

```elixir
%{type: :replace, value: "[EMAIL]"}
```

`value` is optional and defaults to `[REDACTED]`. When present, it must be a
binary. The only accepted keys are `type` and `value`.

## Redact

```elixir
%{type: :redact}
```

Redact replaces the detected span with an empty binary. It accepts no options
other than `type`.

## Mask

```elixir
%{type: :mask, char: "*", keep_last: 4}
```

- `char` defaults to `*` and must contain exactly one valid Unicode grapheme.
- `keep_last` defaults to `0` and must be a non-negative integer.
- Masking operates on graphemes, while result offsets remain byte offsets.
- When `keep_last` exceeds the source grapheme count, the source is unchanged.

Empty or multi-grapheme mask strings, negative counts, invalid types, and
unknown options are rejected.

## Hash

Hash replacements use this self-describing format:

```text
$obscura$v1$hash$ALGORITHM$MODE$BASE64URL_SALT$HEX_DIGEST
```

Supported algorithms are `:sha256` and `:sha512`.

### Secure Mode

```elixir
%{type: :hash, mode: :secure, algorithm: :sha256}
```

Secure mode is the default. It generates a fresh 16-byte salt with
`:crypto.strong_rand_bytes/1` for every replacement. The same source value
therefore produces different replacements. Supplying a salt in secure mode is
an error.

### Deterministic Mode

```elixir
%{
  type: :hash,
  mode: :deterministic,
  algorithm: :sha256,
  salt: "application-salt"
}
```

The salt must be a binary containing at least 16 bytes. Identical value, salt,
and algorithm inputs produce identical replacements. This reveals equality and
does not make low-entropy identifiers unguessable.

`Obscura.Operator.Hash.verify/2` verifies a source value against either encoded
mode without raising for malformed input.

### Hash Migration

The pre-release hash contract previously defaulted to deterministic SHA-256,
allowed an empty or short salt, and returned `sha256:HEX`. That format is no
longer generated or accepted by `verify/2`.

To migrate intentional deterministic use, add `mode: :deterministic`, provide
at least 16 salt bytes, and store the new versioned replacement. Otherwise omit
the salt and use the secure default. Existing stored legacy hashes require an
application-specific migration because Obscura cannot recover their source
values.

## Pseudonymize

```elixir
%{type: :pseudonymize}
```

Pass the vault in the operator config or anonymizer options:

```elixir
{:ok, vault} = Obscura.Vault.Memory.start_link()
text = "Email user@example.test"

Obscura.redact(text,
  entities: [:email],
  operators: %{email: %{type: :pseudonymize}},
  vault: vault
)
```

Pseudonymization is reversible vault-backed tokenization, not encryption. The
vault and token formatting options are checked during operator preflight.

## Custom Operators

Custom operators implement `Obscura.Operator.Custom`:

```elixir
defmodule MyOperator do
  @behaviour Obscura.Operator.Custom

  @impl Obscura.Operator.Custom
  def apply(value, %{entity: entity}, options) do
    {:ok, "<#{options.prefix}:#{entity}:#{byte_size(value)}>", %{format: :custom}}
  end
end
```

Configure the module and a map of explicit options:

```elixir
%{type: :custom, module: MyOperator, options: %{prefix: "private"}}
```

Valid callback results are `{:ok, replacement}` and
`{:ok, replacement, metadata}`. The replacement must be a binary and metadata
must be a map. Missing modules, missing behaviour declarations, invalid
returns, callback errors, exceptions, throws, and exits become sanitized
operator errors. The callback receives only the entity context in addition to
the explicit source value and options.

Custom operator modules are trusted application code. They receive the raw
matched value and can log, transmit, retain, or raise with it before Obscura
sanitizes the callback boundary. Review callback implementations and avoid
embedding source values in their own telemetry or process metadata.

## Error Contract

`Obscura.Anonymizer.Error` has these public fields:

- `code`: stable machine-readable category;
- `operator`: operator atom when known;
- `field`: invalid field atom when known;
- `reason`: safe reason atom;
- `metadata`: allowlisted non-sensitive details.

Applications should branch on `code`, `operator`, and `field` rather than the
human-readable exception message. Unknown options and malformed operator
collections are errors, including configurations for entities which do not
appear in the current input.

Operator types, keys, defaults, preflight behavior, and stable error codes are
part of the `0.1.x` contract. Human-readable messages and additive metadata are
not. See `docs/public-api-stability.md`.

Default `Inspect` implementations for anonymizer result and item structs hide
redacted output, replacements, token-like values, and metadata. Their explicit
public fields still contain the values required by the operation and must be
handled as sensitive data.
