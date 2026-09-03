#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("hybrid_benchmark.py")
SPEC = importlib.util.spec_from_file_location("pplx_pii_hybrid", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
hybrid = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = hybrid
SPEC.loader.exec_module(hybrid)


class HybridBenchmarkTest(unittest.TestCase):
    def test_obscura_wins_overlapping_predictions(self) -> None:
        samples = [
            {
                "id": "one",
                "spans": [{"entity": "email", "byte_start": 0, "byte_end": 8}],
            }
        ]
        obscura = {
            "one": {
                "latency_ms": 1.0,
                "predictions": [
                    {"entity": "email", "byte_start": 0, "byte_end": 8}
                ],
            }
        }
        pplx = {
            "one": {
                "latency_ms": 2.0,
                "predictions": [
                    {"entity": "email", "byte_start": 1, "byte_end": 8}
                ],
            }
        }

        results, additions = hybrid.build_results(
            samples, obscura, pplx, frozenset({"email"}), ["email"]
        )

        self.assertEqual(obscura["one"]["predictions"], results[0]["predicted"])
        self.assertEqual(0, additions["accepted"])
        self.assertEqual(1, additions["rejected_overlap"])

    def test_allowed_nonoverlapping_prediction_is_added(self) -> None:
        samples = [{"id": 1, "spans": []}]
        obscura = {"1": {"latency_ms": 1.0, "predictions": []}}
        person = {"entity": "person", "byte_start": 4, "byte_end": 9}
        pplx = {"1": {"latency_ms": 2.0, "predictions": [person]}}

        results, additions = hybrid.build_results(
            samples, obscura, pplx, frozenset({"person"}), ["person"]
        )

        self.assertEqual([person], results[0]["predicted"])
        self.assertEqual(1, additions["accepted_by_entity"]["person"])
        self.assertEqual(3.0, results[0]["latency_ms"])

    def test_base_policy_does_not_include_model_latency(self) -> None:
        samples = [{"id": 1, "spans": []}]
        obscura = {"1": {"latency_ms": 1.0, "predictions": []}}
        pplx = {"1": {"latency_ms": 2.0, "predictions": []}}

        results, _additions = hybrid.build_results(
            samples, obscura, pplx, frozenset(), ["person"]
        )

        self.assertEqual(1.0, results[0]["latency_ms"])

    def test_location_is_not_in_primary_policy(self) -> None:
        self.assertNotIn("location", hybrid.POLICIES["pplx_conservative"])
        self.assertIn("location", hybrid.POLICIES["pplx_broad_diagnostic"])

    def test_report_guard_rejects_raw_fields(self) -> None:
        hybrid.assert_raw_omitted({"predictions": [{"entity": "email"}]})

        with self.assertRaisesRegex(ValueError, "rows.0.text"):
            hybrid.assert_raw_omitted({"rows": [{"text": "private"}]})


if __name__ == "__main__":
    unittest.main()
