"""Handwritten, non-benchmark diagnostics for the fixed native model port."""
import json
import subprocess
from pathlib import Path

import numpy as np
import spacy

HERE = Path(__file__).resolve().parent
BINARY = HERE.parents[1] / "native/spacy_cpu/target/aarch64-apple-darwin/release/obscura-spacy-native-prototype"


def main():
    nlp = spacy.load("en_core_web_lg", enable=["ner"])
    model = nlp.get_pipe("ner").model.get_ref("tok2vec")
    original = model.layers[0]
    process = subprocess.Popen([str(BINARY), str(HERE / "assets")], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, text=True)
    print(process.stdout.readline().strip())
    try:
        for text in ["Alice Smith visited New York.", "", "José García lives in São Paulo.",
                     "Dr. O’Connor can't visit the U.S. today.", "  Alice\n\tBob  London ",
                     "Contact Alice at alice@example.com or +1 (212) 555-1234."]:
            process.stdin.write(json.dumps({"text": text, "debug": True}) + "\n")
            process.stdin.flush()
            native = json.loads(process.stdout.readline())
            if "error" in native:
                raise RuntimeError(native)
            doc = nlp(text)
            features = doc.to_array(["NORM", "PREFIX", "SUFFIX", "SHAPE"])
            expected_tokens = [{"start": len(text[:t.idx].encode()),
                                "end": len(text[:t.idx + len(t)].encode()),
                                "features": f.tolist()} for t, f in zip(doc, features)]
            print("CASE", repr(text), "tokens", expected_tokens == native["tokens"])
            if expected_tokens != native["tokens"]:
                print("expected", expected_tokens, "actual", native["tokens"])
                continue
            if not len(doc):
                assert native["predictions"] == []
                continue
            embedding = original.get_ref("embed").predict([doc])[0]
            encoded = original.get_ref("encode").predict([embedding])[0]
            token_vectors = model.predict([doc])
            if not isinstance(token_vectors, np.ndarray):
                token_vectors = token_vectors.data
            for name, reference in [("embedding", embedding), ("encoded", encoded),
                                    ("token_vectors", token_vectors)]:
                actual = np.array(native[name]).reshape(reference.shape)
                print(name, "max_abs_error", np.max(np.abs(reference - actual)) if actual.size else 0)
            expected = [{"label": e.label_, "byte_start": len(text[:e.start_char].encode()),
                         "byte_end": len(text[:e.end_char].encode()), "score": 0.85} for e in doc.ents]
            print("entities", expected == native["predictions"], expected, native["predictions"])
    finally:
        process.stdin.close()
        process.wait(timeout=10)


if __name__ == "__main__":
    main()
