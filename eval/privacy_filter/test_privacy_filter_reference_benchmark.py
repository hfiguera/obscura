#!/usr/bin/env python3
"""Unit tests for the Python privacy-filter reference wrapper."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import types
import unittest
from unittest import mock


SCRIPT = pathlib.Path(__file__).with_name("privacy_filter_reference_benchmark.py")
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("privacy_filter_reference_benchmark", SCRIPT)
assert SPEC is not None
benchmark = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(benchmark)


class PrivacyFilterReferenceBenchmarkTest(unittest.TestCase):
    def test_label_map_includes_elixir_native_privacy_filter_labels(self) -> None:
        required_labels = {
            "account",
            "date",
            "email",
            "hosp",
            "hospital",
            "id",
            "other_date",
            "other_email",
            "other_location",
            "other_person",
            "other_phone",
            "other_url",
            "patient",
            "patorg",
            "personal_date",
            "personal_device_id",
            "personal_edu_id",
            "personal_email",
            "personal_emp_id",
            "personal_fin_id",
            "personal_gov_id",
            "personal_handle",
            "personal_health_id",
            "personal_id",
            "personal_location",
            "personal_membership_id",
            "personal_name",
            "personal_org",
            "personal_phone",
            "personal_property_id",
            "personal_registry_id",
            "personal_url",
            "personal_vehicle_id",
            "phone",
            "secret_url",
            "staff",
            "url",
        }

        self.assertEqual(set(), required_labels - set(benchmark.LABEL_MAP))

    def test_main_writes_skipped_report_when_runtime_inference_fails(self) -> None:
        args = types.SimpleNamespace(
            dataset="generated_large",
            predictions_dir="eval/predictions",
            model_id="OpenMed/privacy-filter-nemotron",
            run_suffix="runtime_failure",
            template_split="template_heldout",
            template_train_ratio=0.7,
            full=False,
            sample_ids=None,
        )
        loaded = types.SimpleNamespace(samples=[{"id": 1}], invalid_samples=[])
        split = {"name": "template_heldout"}
        samples = [{"id": 1, "text": "Ada", "spans": []}]
        error = ValueError("runtime failed")

        with (
            mock.patch.object(benchmark, "parse_args", return_value=args),
            mock.patch.object(benchmark, "load_dataset", return_value=loaded),
            mock.patch.object(
                benchmark, "split_samples_by_template", return_value=(samples, split)
            ),
            mock.patch.object(benchmark, "select_samples", return_value=samples),
            mock.patch.object(benchmark, "build_redactor", return_value=object()),
            mock.patch.object(benchmark, "run_privacy_filter", side_effect=error),
            mock.patch.object(benchmark, "write_skipped_report", return_value=0) as skipped,
        ):
            self.assertEqual(benchmark.main(), 0)

        skipped.assert_called_once()
        self.assertIs(skipped.call_args.args[-1], error)

    def test_skip_reason_categories_common_reference_blockers(self) -> None:
        cases = [
            (
                RuntimeError("missing optional Python privacy-filter dependencies: No module named 'torch'"),
                "optional_dependency_missing",
            ),
            (
                RuntimeError("checkpoint directory has no .safetensors files: checkpoint"),
                "checkpoint_missing",
            ),
            (
                ValueError("Checkpoint config field encoding must be a non-empty string"),
                "checkpoint_config_invalid",
            ),
        ]

        for error, category in cases:
            with self.subTest(category=category):
                self.assertEqual(benchmark.skip_reason(error)["category"], category)
                self.assertIn(str(error), benchmark.skip_reason(error)["message"])


if __name__ == "__main__":
    unittest.main()
