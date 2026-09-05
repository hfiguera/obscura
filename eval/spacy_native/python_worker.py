"""Timing control only: same JSON protocol, pinned original spaCy NER runtime."""
import json
import os
import resource
import sys
import time

started = time.perf_counter()
import spacy
spacy.require_cpu()
nlp = spacy.load("en_core_web_lg", enable=["ner"])
print(json.dumps({"ready": True, "backend": "python_spacy_cpu", "python_runtime": True,
                  "load_ms": (time.perf_counter() - started) * 1000, "pid": os.getpid(),
                  "peak_rss_bytes": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss}), flush=True)
for line in sys.stdin:
    try:
        text = json.loads(line)["text"]
        if len(text.encode()) > 1_048_576:
            raise ValueError("input limit")
        started = time.perf_counter()
        doc = nlp(text)
        inference_ms = (time.perf_counter() - started) * 1000
        offsets = [0]
        for char in text:
            offsets.append(offsets[-1] + len(char.encode()))
        result = {"predictions": [{"label": e.label_, "byte_start": offsets[e.start_char],
                                  "byte_end": offsets[e.end_char], "score": 0.85} for e in doc.ents],
                  "inference_ms": inference_ms, "token_count": len(doc),
                  "peak_rss_bytes": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss}
    except Exception:
        result = {"error": "reference inference failed"}
    print(json.dumps(result), flush=True)
