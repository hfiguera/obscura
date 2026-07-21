#!/usr/bin/env python3
"""Unit tests for privacy-filter report comparison helpers."""

from __future__ import annotations

import importlib.util
import json
import pathlib
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).with_name("compare_privacy_filter_reports.py")
SPEC = importlib.util.spec_from_file_location("compare_privacy_filter_reports", SCRIPT)
assert SPEC is not None
compare = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(compare)


class ComparePrivacyFilterReportsTest(unittest.TestCase):
    def test_stage_latency_is_preserved_and_rendered(self) -> None:
        entries = {
            "python_reference": self.entry("python_reference", stage_latency={}),
            "native_privacy_filter": self.entry(
                "native_privacy_filter",
                stage_latency={
                    "tokenization_ms": {"mean_ms": 1.0, "p95_ms": 2.0},
                    "model_ms": {"mean_ms": 10.0, "p95_ms": 12.0},
                    "decode_ms": {"mean_ms": 0.5, "p95_ms": 0.7},
                    "total_ms": {"mean_ms": 11.5, "p95_ms": 14.7},
                },
            ),
            "hybrid_privacy_filter": self.entry("hybrid_privacy_filter", stage_latency={}),
            "current_best_obscura": self.entry("current_best_obscura", stage_latency={}),
        }

        report = compare.build_report("stage_latency_test", entries)
        native = report["entries"]["native_privacy_filter"]
        rendered = compare.markdown(report)

        self.assertEqual(native["stage_latency"]["model_ms"]["mean_ms"], 10.0)
        self.assertIn("## Stage Latency", rendered)
        self.assertIn("10.0000ms", rendered)

    def test_model_runtime_settings_are_rendered(self) -> None:
        entries = {
            "python_reference": self.entry("python_reference", stage_latency={}),
            "native_privacy_filter": self.entry(
                "native_privacy_filter",
                stage_latency={},
                model={
                    "model_id": "openai/privacy-filter",
                    "checkpoint": ".cache/privacy-filter/openai",
                    "n_ctx": "auto",
                    "pad_windows": False,
                    "decoder": "viterbi",
                },
                runtime_backend={"adapter": "native_privacy_filter"},
            ),
            "hybrid_privacy_filter": self.entry("hybrid_privacy_filter", stage_latency={}),
            "current_best_obscura": self.entry("current_best_obscura", stage_latency={}),
        }

        rendered = compare.markdown(compare.build_report("settings_test", entries))

        self.assertIn("## Model And Runtime", rendered)
        self.assertIn("openai/privacy-filter", rendered)
        self.assertIn(".cache/privacy-filter/openai", rendered)
        self.assertIn("| native_privacy_filter | openai/privacy-filter | .cache/privacy-filter/openai | auto | false | viterbi | native_privacy_filter |", rendered)

    def test_skipped_entry_reason_is_preserved_and_rendered(self) -> None:
        entries = {
            "python_reference": self.entry("python_reference", stage_latency={}),
            "native_privacy_filter": self.entry(
                "native_privacy_filter",
                stage_latency={},
                status="skipped",
                skip_reason={
                    "category": "run_failed",
                    "message": "Native privacy-filter compatibility run failed: checkpoint_dir_not_found",
                },
            ),
            "hybrid_privacy_filter": self.entry("hybrid_privacy_filter", stage_latency={}),
            "current_best_obscura": self.entry("current_best_obscura", stage_latency={}),
        }

        report = compare.build_report("skipped_test", entries)
        rendered = compare.markdown(report)

        self.assertEqual(
            report["entries"]["native_privacy_filter"]["skip_reason"]["category"],
            "run_failed",
        )
        self.assertIn("## Skipped Entries", rendered)
        self.assertIn("checkpoint_dir_not_found", rendered)

    def test_load_entry_derives_skip_reason_from_legacy_limitations(self) -> None:
        payload = {
            "run_id": "legacy_skipped",
            "status": "skipped",
            "profile": "hf_token_classification",
            "dataset": {"sample_ids": [1]},
            "metrics": {},
            "latency": {},
            "stage_latency": {},
            "limitations": [
                "Skipped optional Python/HF token-classification run: missing optional dependency transformers/torch: No module named 'transformers'"
            ],
        }

        with tempfile.TemporaryDirectory() as tmpdir:
            path = pathlib.Path(tmpdir) / "report.json"
            path.write_text(json.dumps(payload), encoding="utf-8")

            entry = compare.load_entry("python_reference", str(path))

        self.assertEqual(entry["status"], "skipped")
        self.assertEqual(entry["skip_reason"]["category"], "optional_dependency_missing")
        self.assertIn("missing optional dependency", entry["skip_reason"]["message"])

    def test_markdown_summarizes_long_sample_id_lists(self) -> None:
        entries = {
            "python_reference": self.entry(
                "python_reference", stage_latency={}, sample_ids=list(range(20))
            ),
            "native_privacy_filter": self.entry("native_privacy_filter", stage_latency={}),
            "hybrid_privacy_filter": self.entry("hybrid_privacy_filter", stage_latency={}),
            "current_best_obscura": self.entry("current_best_obscura", stage_latency={}),
        }

        report = compare.build_report("sample_summary_test", entries)
        rendered = compare.markdown(report)

        self.assertEqual(report["sample_sets"]["python_reference"], list(range(20)))
        self.assertEqual(report["sample_summaries"]["python_reference"]["count"], 20)
        self.assertIn("20 total; 10 omitted", rendered)
        self.assertNotIn("0, 1, 2, 3, 4, 5, 6", rendered)

    def entry(
        self,
        label: str,
        stage_latency: dict,
        model: dict | None = None,
        runtime_backend: dict | None = None,
        status: str = "completed",
        skip_reason: dict | None = None,
        sample_ids: list[int] | None = None,
    ) -> dict:
        return {
            "label": label,
            "path": f"{label}.json",
            "run_id": label,
            "phase": "presidio_compatibility",
            "status": status,
            "adapter": "adapter",
            "profile": label,
            "model": model or {},
            "runtime_backend": runtime_backend or {},
            "skip_reason": skip_reason,
            "dataset": {"sample_ids": sample_ids if sample_ids is not None else [1, 2]},
            "metrics": {
                "precision": 1.0,
                "recall": 1.0,
                "f1": 1.0,
                "f2": 1.0,
                "true_positives": 1,
                "false_positives": 0,
                "false_negatives": 0,
                "offset_mismatches": 0,
                "wrong_entity_type": 0,
                "unsupported_expected_spans": 0,
                "total_supported_expected_spans": 1,
                "total_predicted_spans": 1,
            },
            "latency": {
                "mean_ms": 1.0,
                "p50_ms": 1.0,
                "p95_ms": 1.0,
                "max_ms": 1.0,
            },
            "stage_latency": stage_latency,
        }


if __name__ == "__main__":
    unittest.main()
