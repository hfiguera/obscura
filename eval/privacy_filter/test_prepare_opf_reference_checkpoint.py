#!/usr/bin/env python3
"""Unit tests for OPF reference checkpoint preparation."""

from __future__ import annotations

import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).with_name("prepare_opf_reference_checkpoint.py")
SPEC = importlib.util.spec_from_file_location("prepare_opf_reference_checkpoint", SCRIPT)
assert SPEC is not None
prepare = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(prepare)


class PrepareOpfReferenceCheckpointTest(unittest.TestCase):
    def test_normalizes_openmed_hf_config_for_local_opf_runtime(self) -> None:
        payload = {
            "model_type": "openai_privacy_filter",
            "pad_token_id": 199_999,
            "num_local_experts": 128,
            "num_experts_per_tok": 8,
            "sliding_window": 128,
            "dtype": "float16",
            "id2label": {
                "0": "O",
                "2": "I-first_name",
                "1": "B-first_name",
            },
            "rope_parameters": {
                "rope_theta": 500_000,
                "factor": 32.0,
                "beta_slow": 1.0,
                "beta_fast": 4.0,
                "original_max_position_embeddings": 4096,
            },
        }

        normalized = prepare.normalize_config(payload)

        self.assertEqual(normalized["model_type"], "privacy_filter")
        self.assertEqual(normalized["encoding"], "o200k_base")
        self.assertEqual(normalized["num_experts"], 128)
        self.assertEqual(normalized["experts_per_token"], 8)
        self.assertEqual(normalized["num_labels"], 3)
        self.assertEqual(normalized["param_dtype"], "float16")
        self.assertTrue(normalized["bidirectional_context"])
        self.assertEqual(normalized["bidirectional_left_context"], 128)
        self.assertEqual(normalized["bidirectional_right_context"], 128)
        self.assertEqual(normalized["sliding_window"], 257)
        self.assertEqual(normalized["rope_theta"], 500_000)
        self.assertEqual(normalized["rope_scaling_factor"], 32.0)
        self.assertEqual(normalized["rope_ntk_alpha"], 1.0)
        self.assertEqual(normalized["rope_ntk_beta"], 4.0)
        self.assertEqual(normalized["initial_context_length"], 4096)
        self.assertEqual(normalized["ner_class_names"], ["O", "B-first_name", "I-first_name"])

    def test_explicit_encoding_overrides_inference(self) -> None:
        normalized = prepare.normalize_config(
            {"model_type": "openai_privacy_filter", "pad_token_id": 199_999},
            encoding="cl100k_base",
        )

        self.assertEqual(normalized["encoding"], "cl100k_base")


if __name__ == "__main__":
    unittest.main()
