from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("compare_reports.py")
SPEC = importlib.util.spec_from_file_location("compare_reports", SCRIPT)
assert SPEC and SPEC.loader
COMPARE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = COMPARE
SPEC.loader.exec_module(COMPARE)


class CompareReportsTest(unittest.TestCase):
    def test_cpu_rows_on_same_machine_are_latency_comparable(self) -> None:
        baseline = self.entry("arm64", "cpu")
        candidate = self.entry("aarch64-apple-darwin25.5.0", "cpu")

        qualified = COMPARE.qualify_latency(candidate, baseline)

        self.assertTrue(qualified["latency_comparable_to_baseline"])

    def test_nested_gpu_metadata_is_not_comparable_to_cpu(self) -> None:
        baseline = self.entry("arm64", "cpu")
        candidate = self.entry("arm64", None)
        candidate["runtime_backend"] = {
            "serving_backend_metadata": {"actual_device": "gpu"}
        }

        qualified = COMPARE.qualify_latency(candidate, baseline)

        self.assertFalse(qualified["latency_comparable_to_baseline"])

    def test_sample_summary_uses_count_and_hash(self) -> None:
        entry = self.entry("arm64", "cpu")
        entry["label"] = "presidio"
        entry["dataset"] = {"ordered_sample_ids": [3, 1, 2]}
        entry["comparison_protocol"] = {"sample_ids_sha256": "abc123"}

        self.assertEqual(
            "- presidio: 3 ordered IDs; SHA-256 `abc123`",
            COMPARE.sample_row(entry),
        )

    def test_metric_row_keeps_iou_f1_beside_exact_metrics(self) -> None:
        entry = {
            "label": "presidio",
            "profile": "presidio_spacy_en_core_web_lg",
            "scope": "all",
            "template_split": {"name": "all"},
            "metrics": {
                "precision": 0.9,
                "recall": 0.8,
                "f1": 0.85,
                "f2": 0.81,
                "span_iou": {"f1": 0.8123},
                "true_positives": 1,
                "false_positives": 2,
                "false_negatives": 3,
                "offset_mismatches": 4,
                "wrong_entity_type": 5,
                "unsupported_expected_spans": 6,
            },
        }

        self.assertIn("| 0.8123 | 1 | 2 | 3 |", COMPARE.metric_row(entry))

    @staticmethod
    def entry(architecture: str, device: str | None) -> dict:
        return {
            "environment": {
                "hardware_label": "test-machine",
                "cpu": "Apple M4 Max",
                "architecture": architecture,
            },
            "runtime_backend": {"actual_device": device},
        }


if __name__ == "__main__":
    unittest.main()
