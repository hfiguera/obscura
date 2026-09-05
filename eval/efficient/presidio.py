#!/usr/bin/env python3
"""Pinned full Presidio reference, used only for release evaluation."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("reference", ROOT / "eval/spacy_hybrid/benchmark.py")
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


def main():
    from presidio_analyzer import AnalyzerEngine
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    environment = reference.verify_environment()
    engine = AnalyzerEngine()
    mapping = {"PERSON": "person", "LOCATION": "location", "EMAIL_ADDRESS": "email",
               "PHONE_NUMBER": "phone", "US_SSN": "us_ssn", "CREDIT_CARD": "credit_card",
               "IP_ADDRESS": "ip_address", "DATE_TIME": "date_time"}
    rows = json.loads(args.input.read_text())
    output = []
    for row in rows:
        text = row["text"]
        found = engine.analyze(text=text, language="en", entities=list(mapping), return_decision_process=False)
        output.append({"id": row["id"], "predictions": [{"entity": mapping[s.entity_type],
            "byte_start": len(text[:s.start].encode()), "byte_end": len(text[:s.end].encode())} for s in found]})
    args.output.write_text(json.dumps({"profile": "presidio", "environment": environment,
        "input_sha256": hashlib.sha256(args.input.read_bytes()).hexdigest(), "predictions": output}, indent=2) + "\n")
    print(f"Predicted {len(rows)} documents with pinned Presidio.")


if __name__ == "__main__":
    main()
