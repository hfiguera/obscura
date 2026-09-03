#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("reference_benchmark.py")
SPEC = importlib.util.spec_from_file_location("pplx_pii_benchmark", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
benchmark = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = benchmark
SPEC.loader.exec_module(benchmark)


class ReferenceBenchmarkTest(unittest.TestCase):
    def test_model_labels_have_an_explicit_compatibility_mapping(self) -> None:
        self.assertEqual(
            {
                "private_person",
                "private_email",
                "private_phone",
                "private_address",
                "private_url",
                "private_date",
                "account_number",
                "secret",
                "other_pii",
            },
            set(benchmark.ENTITY_MAP),
        )
        self.assertEqual("account_number", benchmark.ENTITY_MAP["account_number"])

    def test_character_scoring_is_label_agnostic_and_reports_pii_free_fp_rate(self) -> None:
        results = [
            {
                "expected": [{"entity": "email", "char_start": 2, "char_end": 6}],
                "predicted": [
                    {"entity": "other_pii", "char_start": 3, "char_end": 7}
                ],
            },
            {
                "expected": [],
                "predicted": [{"entity": "person", "char_start": 0, "char_end": 2}],
            },
        ]

        metrics = benchmark.score_characters(results)

        self.assertEqual(3, metrics["true_positive_characters"])
        self.assertEqual(3, metrics["false_positive_characters"])
        self.assertEqual(1, metrics["false_negative_characters"])
        self.assertEqual(1.0, metrics["pii_free_false_positive_rate"])

    def test_typed_protocol_filters_predictions_outside_shared_entities(self) -> None:
        results = [
            {
                "expected": [],
                "predicted": [
                    {"entity": "email"},
                    {"entity": "date_time"},
                    {"entity": "other_pii"},
                ],
            }
        ]

        filtered = benchmark.typed_protocol_results(results, ["email", "phone"])

        self.assertEqual([{"entity": "email"}], filtered[0]["predicted"])

    def test_character_positions_deduplicate_overlapping_spans(self) -> None:
        positions = benchmark.character_positions(
            [
                {"char_start": 0, "char_end": 3},
                {"char_start": 2, "char_end": 5},
            ]
        )

        self.assertEqual({0, 1, 2, 3, 4}, positions)

    def test_untyped_exact_scoring_ignores_labels_but_not_boundaries(self) -> None:
        results = [
            {
                "expected": [
                    {"entity": "email", "char_start": 0, "char_end": 5},
                    {"entity": "phone", "char_start": 7, "char_end": 12},
                ],
                "predicted": [
                    {"entity": "other_pii", "char_start": 0, "char_end": 5},
                    {"entity": "phone", "char_start": 8, "char_end": 12},
                ],
            }
        ]

        metrics = benchmark.score_untyped_exact(results)

        self.assertEqual(1, metrics["true_positives"])
        self.assertEqual(1, metrics["false_positives"])
        self.assertEqual(1, metrics["false_negatives"])
        self.assertEqual(0.5, metrics["f1"])

    def test_f1_handles_empty_and_zero_scores(self) -> None:
        self.assertIsNone(benchmark.f1(None, 1.0))
        self.assertEqual(0.0, benchmark.f1(0.0, 0.0))
        self.assertAlmostEqual(2 / 3, benchmark.f1(0.5, 1.0))

    def test_raw_report_guard_rejects_text_and_value_fields(self) -> None:
        benchmark.assert_raw_omitted({"metrics": {"f1": 1.0}})

        with self.assertRaisesRegex(ValueError, "samples.0.text"):
            benchmark.assert_raw_omitted({"samples": [{"text": "private"}]})

        with self.assertRaisesRegex(ValueError, "prediction.value"):
            benchmark.assert_raw_omitted({"prediction": {"value": "private"}})

    def test_prediction_artifact_omits_source_text(self) -> None:
        results = [
            {
                "sample": {"id": "sample-1"},
                "latency_ms": 2.5,
                "predicted": [
                    {
                        "entity": "email",
                        "source_entity": "private_email",
                        "char_start": 3,
                        "char_end": 12,
                        "byte_start": 3,
                        "byte_end": 12,
                        "score": 0.9,
                    }
                ],
            }
        ]

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "predictions.json"
            benchmark.write_prediction_artifact(path, "fixture", SCRIPT, results)
            artifact = json.loads(path.read_text(encoding="utf-8"))

        self.assertTrue(artifact["raw_text_omitted"])
        self.assertNotIn("text", artifact["rows"][0])
        self.assertNotIn("value", artifact["rows"][0]["predictions"][0])
        self.assertEqual("sample-1", artifact["rows"][0]["sample_id"])


if __name__ == "__main__":
    unittest.main()
