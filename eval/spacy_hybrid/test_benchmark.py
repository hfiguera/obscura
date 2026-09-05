import importlib.util
import unittest
from pathlib import Path
from types import SimpleNamespace


spec = importlib.util.spec_from_file_location("spacy_hybrid", Path(__file__).with_name("benchmark.py"))
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)


class BenchmarkTest(unittest.TestCase):
    def test_unicode_offsets_are_bytes_and_end_is_exclusive(self):
        text = "🙂 e\u0301 — José visits Zürich."
        entities = []
        for label, value in [("PERSON", "José"), ("GPE", "Zürich")]:
            start = text.index(value)
            entities.append(SimpleNamespace(label_=label, start_char=start, end_char=start + len(value)))
        spans = benchmark.spans_from_doc(SimpleNamespace(text=text, ents=entities))
        self.assertEqual(["person", "location"], [span["entity"] for span in spans])
        for value, span in zip(["José", "Zürich"], spans):
            self.assertEqual(value, text.encode()[span["byte_start"]:span["byte_end"]].decode())
            self.assertNotEqual(span["char_start"], span["byte_start"])

    def test_facility_maps_to_location_and_other_labels_are_excluded(self):
        doc = SimpleNamespace(text="Clinic Acme", ents=[
            SimpleNamespace(label_="FAC", start_char=0, end_char=6),
            SimpleNamespace(label_="ORG", start_char=7, end_char=11),
        ])
        spans = benchmark.spans_from_doc(doc)
        self.assertEqual(1, len(spans))
        self.assertEqual("location", spans[0]["entity"])
        self.assertEqual(0.85, spans[0]["score"])

    def test_artifact_cannot_contain_gold_or_raw_text(self):
        benchmark.assert_private({"rows": [{"predictions": [{"entity": "person"}]}]})
        for key in ["text", "value", "full_text", "masked", "expected"]:
            with self.assertRaises(ValueError):
                benchmark.assert_private({"rows": [{key: "must not persist"}]})


if __name__ == "__main__":
    unittest.main()
