#!/usr/bin/env python3
"""Generate Python tiktoken parity fixtures for Obscura.Tiktoken.

The generated JSON is consumed by pure Elixir tests. Python is required only
when explicitly regenerating fixtures.
"""

from __future__ import annotations

import base64
import hashlib
import importlib.metadata
import json
import platform
import random
from pathlib import Path
from typing import Any

import tiktoken


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "test" / "fixtures" / "tiktoken" / "parity" / "generated.json"
ASSET_DIR = ROOT / "priv" / "tiktoken"
SEED = 8675309

ENCODINGS = [
    "gpt2",
    "r50k_base",
    "p50k_base",
    "p50k_edit",
    "cl100k_base",
    "o200k_base",
    "o200k_harmony",
]

ASSET_FILES = [
    "r50k_base.tiktoken",
    "p50k_base.tiktoken",
    "cl100k_base.tiktoken",
    "o200k_base.tiktoken",
]

UPSTREAM_PORTED = [
    "test_encoding.test_simple",
    "test_encoding.test_simple_repeated",
    "test_encoding.test_large_repeated",
    "test_encoding.test_simple_regex",
    "test_encoding.test_basic_encode",
    "test_encoding.test_encode_empty",
    "test_encoding.test_catastrophically_repetitive",
    "test_encoding.test_basic_roundtrip",
    "test_encoding.test_special_token",
    "test_encoding.test_hyp_special_ordinary",
    "test_offsets.test_basic_offsets",
    "test_offsets.test_hyp_offsets",
    "test_simple_public.test_encoding_for_model",
    "test_misc.test_encoding_for_model",
]

UPSTREAM_OUT_OF_SCOPE = [
    {
        "test": "test_encoding.test_encode_bytes",
        "reason": "Python private _encode_bytes API is not a public Obscura API; privacy-filter uses valid UTF-8 text plus decode_single_token_bytes.",
    },
    {
        "test": "test_encoding.test_hyp_encode_bytes",
        "reason": "Arbitrary invalid-byte encoding is intentionally unsupported in the first Obscura.Tiktoken API.",
    },
    {
        "test": "test_encoding.test_encode_surrogate_pairs",
        "reason": "Elixir binaries used as strings are valid UTF-8; lone Python surrogate replacement is not a normal Elixir text input path.",
    },
    {
        "test": "test_encoding.test_single_token_roundtrip",
        "reason": "Full-vocabulary single-token roundtrip is too expensive for normal tests; Obscura tests deterministic samples across mergeable and special-token ranges.",
    },
    {
        "test": "test_encoding.test_batch_encode",
        "reason": "Batch encode/decode helpers are not exposed by Obscura.Tiktoken; callers map over encode/decode explicitly.",
    },
    {
        "test": "test_encoding.test_hyp_batch_roundtrip",
        "reason": "Batch helpers are not exposed by Obscura.Tiktoken.",
    },
    {
        "test": "test_simple_public.test_optional_blobfile_dependency",
        "reason": "Python import dependency behavior is irrelevant to the Elixir implementation; Obscura separately proves no runtime network fetches.",
    },
    {
        "test": "test_misc.test_optional_blobfile_dependency",
        "reason": "Python import dependency behavior is irrelevant to the Elixir implementation.",
    },
    {
        "test": "test_pickle",
        "reason": "Python pickle compatibility is not applicable to Elixir structs.",
    },
]


def b64(value: bytes) -> str:
    return base64.b64encode(value).decode("ascii")


def asset_hashes() -> dict[str, str]:
    return {
        filename: hashlib.sha256((ASSET_DIR / filename).read_bytes()).hexdigest()
        for filename in ASSET_FILES
    }


def allowed_special(case: dict[str, Any]):
    selector = case.get("allowed_special")
    if selector == "all":
        return "all"
    if isinstance(selector, list):
        return set(selector)
    return set()


def disallowed_special(case: dict[str, Any]):
    selector = case.get("disallowed_special")
    if selector == "empty":
        return ()
    if selector == "all":
        return "all"
    if isinstance(selector, list):
        return set(selector)
    return "all"


def encodings_for(case: dict[str, Any]) -> list[str]:
    return list(case.get("encodings", ENCODINGS))


def fixture_for_case(encoding_name: str, case: dict[str, Any]) -> dict[str, Any]:
    encoding = tiktoken.get_encoding(encoding_name)
    text = str(case["text"])
    fixture = {
        "encoding": encoding_name,
        "category": case["category"],
        "case": case["name"],
        "text": text,
        "allowed_special": case.get("allowed_special"),
        "disallowed_special": case.get("disallowed_special"),
        "offset_focus": bool(case.get("offset_focus", False)),
        "privacy_filter_focus": bool(case.get("privacy_filter_focus", False)),
        "source": case.get("source", "generated"),
    }

    try:
        tokens = encoding.encode(
            text,
            allowed_special=allowed_special(case),
            disallowed_special=disallowed_special(case),
        )
    except ValueError as exc:
        expected_special = case.get("expected_special")
        if not expected_special:
            raise

        fixture["expected_error"] = {
            "operation": "encode",
            "kind": "disallowed_special_token",
            "special": expected_special,
            "python_message": str(exc),
        }
        return fixture

    decoded_bytes = encoding.decode_bytes(tokens)
    token_bytes = [encoding.decode_single_token_bytes(token) for token in tokens]
    decoded_text, offsets = encoding.decode_with_offsets(tokens)

    fixture.update(
        {
            "tokens": tokens,
            "ordinary_tokens": encoding.encode_ordinary(text),
            "decoded_bytes_b64": b64(decoded_bytes),
            "decoded_text": decoded_text,
            "token_bytes_b64": [b64(value) for value in token_bytes],
            "offsets": offsets,
        }
    )
    return fixture


def curated_cases() -> list[dict[str, Any]]:
    cases: list[dict[str, Any]] = [
        {
            "category": "upstream_public",
            "name": "ascii",
            "text": "hello world",
            "source": "test_encoding.test_simple",
        },
        {
            "category": "upstream_public",
            "name": "empty",
            "text": "",
            "source": "test_encoding.test_encode_empty",
        },
        {
            "category": "upstream_public",
            "name": "newline_sensitive",
            "text": "today\n \n",
            "source": "test_encoding.test_simple_regex",
        },
        {
            "category": "upstream_public",
            "name": "newline_sensitive_double_space",
            "text": "today\n  \n",
            "source": "test_encoding.test_simple_regex",
        },
        {
            "category": "upstream_public",
            "name": "cl100k_non_ascii_control",
            "text": " \x850",
            "encodings": ["cl100k_base"],
            "source": "test_encoding.test_basic_encode",
        },
        {
            "category": "roundtrip",
            "name": "chinese",
            "text": "我非常渴望与人工智能一起工作",
            "offset_focus": True,
            "source": "test_offsets.test_basic_offsets",
        },
        {
            "category": "roundtrip",
            "name": "tamil",
            "text": "நடிகர் சூர்யா",
            "offset_focus": True,
            "source": "test_offsets.test_basic_offsets",
        },
        {
            "category": "roundtrip",
            "name": "continuation_byte_boundary",
            "text": " Ġ除",
            "offset_focus": True,
            "source": "test_offsets.test_basic_offsets",
        },
        {
            "category": "privacy_filter",
            "name": "synthetic_pii",
            "text": "Rachel works at OpenAI in Paris. Email rachel@example.com.",
            "privacy_filter_focus": True,
        },
        {
            "category": "privacy_filter",
            "name": "o200k_privacy_filter_input",
            "text": "Ada Lovelace can be reached at ada@example.com or 415-555-0199.",
            "encodings": ["o200k_base"],
            "privacy_filter_focus": True,
            "offset_focus": True,
        },
        {
            "category": "privacy_filter",
            "name": "o200k_multilingual_pii",
            "text": "Paciente María vive en Bogotá. هاتفه +971 50 123 4567.",
            "encodings": ["o200k_base"],
            "privacy_filter_focus": True,
            "offset_focus": True,
        },
        {
            "category": "special_tokens",
            "name": "special_allowed_all",
            "text": "hello <|endoftext|> green cow",
            "allowed_special": "all",
            "offset_focus": True,
            "source": "test_encoding.test_special_token",
        },
        {
            "category": "special_tokens",
            "name": "cl100k_fim_allowed_subset",
            "text": "<|endoftext|> hello <|fim_prefix|> there <|fim_middle|>",
            "encodings": ["cl100k_base"],
            "allowed_special": ["<|fim_prefix|>"],
            "disallowed_special": "empty",
            "source": "test_encoding.test_special_token",
        },
        {
            "category": "special_tokens",
            "name": "cl100k_special_as_ordinary",
            "text": "<|endoftext|> hello <|fim_prefix|> there <|fim_middle|>",
            "encodings": ["cl100k_base"],
            "disallowed_special": "empty",
            "source": "test_encoding.test_special_token",
        },
        {
            "category": "special_tokens",
            "name": "cl100k_special_disallowed_default",
            "text": "<|endoftext|> hello <|fim_prefix|>",
            "encodings": ["cl100k_base"],
            "expected_special": "<|endoftext|>",
            "source": "test_encoding.test_special_token",
        },
        {
            "category": "long_text",
            "name": "o200k_large_repeated_x",
            "text": "x" * 2_000,
            "encodings": ["o200k_base"],
            "source": "test_encoding.test_large_repeated",
        },
    ]

    for count in range(1, 18):
        cases.append(
            {
                "category": "upstream_public",
                "name": f"gpt2_repeated_digits_{count}",
                "text": "0" * count,
                "encodings": ["gpt2"],
                "source": "test_encoding.test_simple_repeated",
            }
        )

    for value in ["^", "0", "a", "'s", " ", "\n"]:
        cases.append(
            {
                "category": "upstream_public",
                "name": f"catastrophic_repetitive_{value.encode().hex()}",
                "text": " " + (value * 500) + "\n",
                "source": "test_encoding.test_catastrophically_repetitive",
            }
        )

    return cases


def random_text(rng: random.Random, min_len: int, max_len: int) -> str:
    alphabets = [
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
        "0123456789",
        " \t\n\r    ",
        ".,;:!?-_/@#$%^&*()[]{}",
        "áéíóúüñçøåß",
        "北京上海東京서울",
        "தமிழ்சூர்யா",
        "مرحبابالعالم",
        "🙂🚀✨",
    ]

    length = rng.randint(min_len, max_len)
    chars = []

    for _ in range(length):
        alphabet = rng.choice(alphabets)
        chars.append(rng.choice(alphabet))

    return "".join(chars)


def random_cases() -> list[dict[str, Any]]:
    rng = random.Random(SEED)
    cases = []

    for index in range(36):
        cases.append(
            {
                "category": "deterministic_random",
                "name": f"unicode_mixed_{index:03d}",
                "text": random_text(rng, 0, 160),
                "offset_focus": index % 3 == 0,
                "source": "deterministic_random_fixture",
            }
        )

    for index in range(12):
        text = "User " + random_text(rng, 5, 40) + " <|endoftext|> " + random_text(rng, 5, 40)
        cases.append(
            {
                "category": "deterministic_random_special",
                "name": f"special_ordinary_{index:03d}",
                "text": text,
                "disallowed_special": "empty",
                "source": "deterministic_random_fixture",
            }
        )

    return cases


def generate() -> dict[str, Any]:
    cases = curated_cases() + random_cases()
    fixtures = []

    for case in cases:
        for encoding_name in encodings_for(case):
            fixtures.append(fixture_for_case(encoding_name, case))

    return {
        "metadata": {
            "generator": "eval/tiktoken/generate_tiktoken_fixtures.py",
            "python_version": platform.python_version(),
            "tiktoken_version": importlib.metadata.version("tiktoken"),
            "seed": SEED,
            "encodings": ENCODINGS,
            "asset_hashes": asset_hashes(),
            "upstream_tests": {
                "ported": UPSTREAM_PORTED,
                "out_of_scope": UPSTREAM_OUT_OF_SCOPE,
            },
            "case_count": len(fixtures),
        },
        "cases": fixtures,
    }


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(generate(), indent=2, sort_keys=True) + "\n")
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
