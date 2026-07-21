# Language Detection

Obscura provides safe language normalization and a language detector behavior.

The default remains:

```text
language: :en
detect_language: false
```

Supported normalized tags are:

```text
[:en, :es, :fr, :de, :pt, :it, :unknown]
```

String language tags are mapped through this allow-list. Obscura never calls `String.to_atom/1` on user input.

Real language detection is optional and caller-provided:

```elixir
defmodule MyApp.LanguageDetector do
  @behaviour Obscura.Language.Detector

  def detect(_text, _opts), do: {:ok, :en}
end

Obscura.analyze(text,
  detect_language: true,
  language_detector: MyApp.LanguageDetector
)
```

If `detect_language: true` is used without a detector, Obscura returns a safe error.
