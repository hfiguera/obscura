#!/usr/bin/env python3

from __future__ import annotations

from collections import Counter
import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("incremental_error_analysis.py")
SPEC = importlib.util.spec_from_file_location("pplx_incremental_analysis", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
analysis = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = analysis
SPEC.loader.exec_module(analysis)


def overlaps(left: dict, right: dict) -> bool:
    return (
        left["byte_start"] < right["byte_end"]
        and right["byte_start"] < left["byte_end"]
    )


class IncrementalErrorAnalysisTest(unittest.TestCase):
    def test_classifies_exact_boundary_wrong_type_and_false_positive(self) -> None:
        expected = [
            {"entity": "phone", "byte_start": 2, "byte_end": 10},
            {"entity": "ip_address", "byte_start": 20, "byte_end": 28},
        ]

        self.assertEqual(
            "exact",
            analysis.classify(
                {"entity": "phone", "byte_start": 2, "byte_end": 10},
                expected,
                overlaps,
            ),
        )
        self.assertEqual(
            "boundary_mismatch",
            analysis.classify(
                {"entity": "phone", "byte_start": 3, "byte_end": 10},
                expected,
                overlaps,
            ),
        )
        self.assertEqual(
            "wrong_entity_type",
            analysis.classify(
                {"entity": "url", "byte_start": 20, "byte_end": 28},
                expected,
                overlaps,
            ),
        )
        self.assertEqual(
            "false_positive",
            analysis.classify(
                {"entity": "email", "byte_start": 30, "byte_end": 35},
                expected,
                overlaps,
            ),
        )

    def test_shape_gate_keeps_contact_formats_and_rejects_model_noise(self) -> None:
        self.assertTrue(analysis.valid_contact_shape("person@example.test", "email"))
        self.assertTrue(analysis.valid_contact_shape("+44 20 7946 0958", "phone"))
        self.assertTrue(analysis.valid_contact_shape("ftp://example.test/a", "url"))

        self.assertFalse(analysis.valid_contact_shape("at", "phone"))
        self.assertFalse(analysis.valid_contact_shape("person@example", "email"))
        self.assertFalse(analysis.valid_contact_shape("00:1a:2b:3c:4d:5e", "url"))

    def test_url_probe_trims_sentence_punctuation_and_unmatched_closer(self) -> None:
        text = "See https://example.test/path). Then ftp://files.example.test/a."

        predictions = analysis.url_probe_predictions(text)

        self.assertEqual(2, len(predictions))
        self.assertEqual(
            "https://example.test/path",
            analysis.byte_slice(text, predictions[0]),
        )
        self.assertEqual(
            "ftp://files.example.test/a",
            analysis.byte_slice(text, predictions[1]),
        )

    def test_merge_rejects_overlaps_and_applies_shape_gate_first(self) -> None:
        base = [{"entity": "email", "byte_start": 0, "byte_end": 5}]
        candidates = [
            {"entity": "phone", "byte_start": 1, "byte_end": 4},
            {"entity": "phone", "byte_start": 8, "byte_end": 10},
            {"entity": "url", "byte_start": 12, "byte_end": 20},
        ]

        accepted, predicted = analysis.merge_candidates(
            base,
            candidates,
            overlaps,
            lambda candidate: candidate["entity"] == "url",
        )

        self.assertEqual([candidates[2]], accepted)
        self.assertEqual(base + [candidates[2]], predicted)

    def test_aggregate_does_not_overstate_unrecovered_spans(self) -> None:
        datasets = {
            "one": {
                "exact_contact_additions": {"email": 0, "phone": 4, "url": 3},
                "existing_phone_parser": {
                    "exact_model_phone_additions_recovered": 2
                },
                "deterministic_url_probe": {
                    "exact_model_url_additions_recovered": 3
                },
                "broad_supported_diagnostic": {
                    "exact_by_entity": {"person": 1},
                    "classification": {
                        "person": {"exact": 1, "false_positive": 2}
                    },
                },
            }
        }

        result = analysis.aggregate(datasets)

        self.assertEqual(7, result["exact_contact_additions"])
        self.assertEqual(5, result["deterministic_probe_recovered_total"])
        self.assertEqual(
            2, result["exact_additions_not_recovered_by_current_probes"]
        )
        self.assertEqual(
            {"person": 1}, result["broad_diagnostic"]["exact_by_entity"]
        )
        self.assertEqual(
            {"person": 2}, result["broad_diagnostic"]["nonexact_by_entity"]
        )

    def test_nested_classification_includes_zero_counts(self) -> None:
        result = analysis.nested_classification(Counter({("phone", "exact"): 2}))

        self.assertEqual(2, result["phone"]["exact"])
        self.assertEqual(0, result["phone"]["false_positive"])
        self.assertEqual(0, result["email"]["exact"])

    def test_wrong_type_targets_are_reported_without_values(self) -> None:
        counts = Counter()
        candidate = {"entity": "url", "byte_start": 3, "byte_end": 12}
        expected = [
            {"entity": "ip_address", "byte_start": 4, "byte_end": 11}
        ]

        analysis.count_wrong_type_targets(counts, candidate, expected, overlaps)

        self.assertEqual({"url": {"ip_address": 1}}, analysis.nested_targets(counts))

    def test_report_guard_rejects_raw_fields(self) -> None:
        analysis.assert_raw_omitted({"aggregate": {"exact": 2}})

        with self.assertRaisesRegex(ValueError, "rows.0.text"):
            analysis.assert_raw_omitted({"rows": [{"text": "private"}]})


if __name__ == "__main__":
    unittest.main()
