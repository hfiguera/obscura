import unittest

from report import compare_predictions, strict_metrics


class ReportTest(unittest.TestCase):
    def test_strict_metrics_count_boundary_and_type_errors_in_both_denominators(self):
        metrics = {"true_positives": 4, "false_positives": 1, "false_negatives": 2,
                   "offset_mismatches": 2, "wrong_entity_type": 1}
        strict = strict_metrics(metrics)
        self.assertEqual(4 / 8, strict["precision"])
        self.assertEqual(4 / 9, strict["recall"])
        self.assertEqual(8 / 17, strict["f1"])

    def test_structured_parity_preserves_prediction_multiplicity(self):
        span = {"entity": "email", "byte_start": 0, "byte_end": 10}
        left = [{"sample_id": 1, "predictions": [span]}]
        right = [{"sample_id": 1, "predictions": [span, span]}]
        self.assertEqual(1, compare_predictions(left, right, {"email"}))

    def test_comparison_rejects_misaligned_documents(self):
        with self.assertRaises(ValueError):
            compare_predictions([{"sample_id": 1}], [{"sample_id": 2}])


if __name__ == "__main__":
    unittest.main()
