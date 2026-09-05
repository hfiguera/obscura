"""Cross-implementation tests using handcrafted inputs, independent of eval gold."""
import json
import subprocess
import unittest

import numpy as np
import spacy

from check_layers import BINARY, HERE


class NativeParity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.nlp = spacy.load("en_core_web_lg", enable=["ner"])
        cls.process = subprocess.Popen([str(BINARY), str(HERE / "assets")],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        cls.ready = json.loads(cls.process.stdout.readline())

    @classmethod
    def tearDownClass(cls):
        cls.process.stdin.close()
        cls.process.wait(timeout=10)
        cls.process.stdout.close()

    def request(self, payload):
        self.process.stdin.write(json.dumps(payload) + "\n")
        self.process.stdin.flush()
        return json.loads(self.process.stdout.readline())

    def test_python_free_backend(self):
        self.assertIs(self.ready["python_runtime"], False)
        self.assertEqual(self.ready["backend"], "rust_accelerate_cpu")

    def test_token_features_and_entities(self):
        cases = ["", " ", "  ", "\n\t", "Alice Smith visited New York.",
                 "José García lives in São Paulo.", "Jose\u0301 Garci\u0301a lives in Montre\u0301al.",
                 "Dr. O’Connor can't visit the U.S. today.", "  Alice\n\tBob  London ",
                 "Contact Alice at alice@example.com or +1 (212) 555-1234.",
                 "Alice paid $25.00 on Jan. 1, 2025.", "Mr. Smith's e-mail is a+b@example.org.",
                 "北京 東京 Москва Αθήνα İstanbul ΣΟΣ", "١٢٣ ²³ १२३", "👩🏽‍💻 Alice 👨‍👩‍👧‍👦", "A\u00a0B\u2003C",
                 "(can't) [won't] \"should've\" (U.S.)", "https://example.com/path?q=1#tag",
                 "x" * 100, "X __NORM__ NORM - _ + 1/2 10-20 foo—bar",
                 "He's gonna wanna visit Los Angeles and St. Louis."]
        for text in cases:
            with self.subTest(case=cases.index(text)):
                result = self.request({"text": text, "debug": True})
                doc = self.nlp(text)
                expected = [{"start": len(text[:t.idx].encode()), "end": len(text[:t.idx + len(t)].encode()),
                             "features": f.tolist()} for t, f in zip(doc, doc.to_array(["NORM", "PREFIX", "SUFFIX", "SHAPE"]))]
                self.assertEqual(result["tokens"], expected)
                entities = [{"label": e.label_, "byte_start": len(text[:e.start_char].encode()),
                             "byte_end": len(text[:e.end_char].encode()), "score": 0.85} for e in doc.ents]
                self.assertEqual(result["predictions"], entities)

    def test_neural_layer_numerical_parity(self):
        text = "Alice Smith visited New York. José García stayed in São Paulo."
        result = self.request({"text": text, "debug": True})
        doc = self.nlp.make_doc(text)
        model = self.nlp.get_pipe("ner").model.get_ref("tok2vec")
        embed = model.layers[0].get_ref("embed").predict([doc])[0]
        encode = model.layers[0].get_ref("encode").predict([embed])[0]
        for key, reference in [("embedding", embed), ("encoded", encode), ("token_vectors", model.predict([doc]))]:
            np.testing.assert_allclose(np.array(result[key]).reshape(reference.shape), reference, atol=1e-5, rtol=1e-5)

    def test_invalid_request_and_limits_do_not_corrupt_worker(self):
        self.assertIn("error", self.request({}))
        self.assertIn("error", self.request({"text": "x" * 1_048_577}))
        self.assertIn("error", self.request({"text": "a " * 10001}))
        result = self.request({"text": "Alice Smith lives in London."})
        self.assertNotIn("error", result)
        self.assertNotIn("text", result)
        self.assertNotIn("tokens", result)
        self.assertTrue(result["predictions"])


if __name__ == "__main__":
    unittest.main()
