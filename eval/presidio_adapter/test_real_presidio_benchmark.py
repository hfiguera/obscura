from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("real_presidio_benchmark.py")
SPEC = importlib.util.spec_from_file_location("real_presidio_benchmark", SCRIPT)
assert SPEC and SPEC.loader
BENCHMARK = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = BENCHMARK
SPEC.loader.exec_module(BENCHMARK)


class RealPresidioBenchmarkTest(unittest.TestCase):
    def test_sha256_json_is_key_order_independent(self) -> None:
        left = {"b": 2, "a": {"z": 1, "x": [3, 2, 1]}}
        right = {"a": {"x": [3, 2, 1], "z": 1}, "b": 2}
        self.assertEqual(BENCHMARK.sha256_json(left), BENCHMARK.sha256_json(right))

    def test_selection_preserves_requested_order(self) -> None:
        samples = [{"id": 1}, {"id": 2}, {"id": 3}]
        selection = {"dataset": {"ordered_sample_ids": [3, 1, 2]}}
        selected = BENCHMARK.selected_samples_from_selection(samples, selection)
        self.assertEqual([3, 1, 2], [sample["id"] for sample in selected])

    def test_selection_rejects_missing_id(self) -> None:
        selection = {"dataset": {"ordered_sample_ids": [2]}}
        with self.assertRaises(SystemExit):
            BENCHMARK.selected_samples_from_selection([{"id": 1}], selection)

    def test_prediction_export_omits_values(self) -> None:
        rows = [
            {
                "sample": {"id": 1},
                "predicted": [
                    {
                        "entity": "email",
                        "byte_start": 0,
                        "byte_end": 3,
                        "value": "secret@example.com",
                    }
                ],
                "latency_ms": 1.0,
            }
        ]

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "predictions.jsonl"
            BENCHMARK.write_predictions(path, rows)
            row = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual("[omitted]", row["predictions"][0]["value"])
            self.assertNotIn("secret@example.com", path.read_text(encoding="utf-8"))

    def test_authoritative_lock_and_environment_are_tracked(self) -> None:
        root = SCRIPT.parents[2]
        lock = root / "eval/presidio_adapter/requirements-authoritative.lock"
        environment = root / "eval/presidio_adapter/authoritative-environment.json"
        self.assertTrue(lock.is_file())
        self.assertGreater(lock.stat().st_size, 10_000)
        metadata = json.loads(environment.read_text(encoding="utf-8"))
        self.assertEqual("3.11.15", metadata["python"]["version"])
        self.assertEqual("2.2.363", metadata["packages"]["presidio_analyzer"]["version"])

    def test_command_line_omits_machine_specific_absolute_paths(self) -> None:
        original_argv = sys.argv
        original_executable = sys.executable
        try:
            sys.executable = "/private/example/.venv/bin/python"
            sys.argv = [
                "/private/example/real_presidio_benchmark.py",
                "--selection",
                "/private/example/selection.json",
            ]

            command = BENCHMARK.command_line()

            self.assertEqual(
                "python eval/presidio_adapter/real_presidio_benchmark.py "
                "--selection selection.json",
                command,
            )
            self.assertNotIn("/private/example", command)
        finally:
            sys.argv = original_argv
            sys.executable = original_executable


if __name__ == "__main__":
    unittest.main()
