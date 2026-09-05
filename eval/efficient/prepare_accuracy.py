#!/usr/bin/env python3
"""Freeze gold offsets and selection hashes before running any model.

uv run --no-project --with pyarrow==21.0.0 python eval/efficient/prepare_accuracy.py
Downloads are explicit here; this is evaluation tooling, never runtime setup.
"""
import ast
import collections
import hashlib
import json
import re
import urllib.request
from pathlib import Path

import pyarrow.parquet as pq

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".cache/efficient/gretel"
REVISION = "e06eb1499ca8d54470f085021cd8e54f9efac7fd"
HASHES = {
    "validation": "3de64be0dddd0dc8a6a1a1368533cc1efe8a9ec290f87feaa064e4e78a5d22b8",
    "test": "c89a6bffa838edb0f2fc6686bf35da4930944519ac97308b0b6e32298594b5b1",
}
LABELS = {
    "name": "person", "first_name": "person", "last_name": "person",
    "city": "location", "state": "location", "country": "location",
    "address": "location", "street_address": "location", "postcode": "location",
    "email": "email", "phone_number": "phone", "ssn": "us_ssn",
    "credit_card_number": "credit_card", "ipv4": "ip_address", "ipv6": "ip_address",
    "date": "date_time", "date_of_birth": "date_time", "date_time": "date_time", "time": "date_time",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n")


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    seen = set()
    manifest = {"schema_version": 1, "dataset": "gretelai/gretel-pii-masking-en-v1",
                "revision": REVISION, "license": "Apache-2.0", "synthetic": True,
                "label_mapping": LABELS, "splits": {},
                "annotation_policy": "All literal occurrences with Unicode word boundaries; merge adjacent whitespace-separated person annotations; retain separate location components; do not infer unlabeled entities."}
    for source, split in [("validation", "development"), ("test", "heldout")]:
        parquet = CACHE / f"{source}.parquet"
        if not parquet.exists():
            urllib.request.urlretrieve(f"https://huggingface.co/datasets/{manifest['dataset']}/resolve/{REVISION}/data/{source}-00000-of-00001.parquet", parquet)
        assert sha(parquet.read_bytes()) == HASHES[source]
        rows, unsupported, missing = [], collections.Counter(), collections.Counter()
        duplicates = invalid = 0
        for row in pq.read_table(parquet).to_pylist():
            text = row["text"]
            fingerprint = sha(" ".join(text.split()).casefold().encode())
            if fingerprint in seen:
                duplicates += 1
                continue
            seen.add(fingerprint)
            try:
                annotations = ast.literal_eval(row["entities"])
                assert isinstance(annotations, list)
            except (ValueError, SyntaxError, AssertionError):
                invalid += 1
                continue
            spans = set()
            for annotation in annotations:
                value = annotation["entity"]
                types = annotation["types"]
                for label in types:
                    if label not in LABELS:
                        unsupported[label] += 1
                        continue
                    matches = list(re.finditer(r"(?<!\w)" + re.escape(value) + r"(?!\w)", text))
                    if not matches:
                        missing[label] += 1
                    for match in matches:
                        spans.add((LABELS[label], match.start(), match.end()))
            merged = []
            for entity, start, end in sorted(spans, key=lambda s: (s[1], s[2], s[0])):
                if merged and entity == "person" == merged[-1][0] and text[merged[-1][2]:start].isspace():
                    merged[-1] = (entity, merged[-1][1], end)
                else:
                    merged.append((entity, start, end))
            expected = [{"entity": entity, "byte_start": len(text[:start].encode()), "byte_end": len(text[:end].encode())} for entity, start, end in merged]
            rows.append({"id": row["uid"], "text": text, "expected": expected,
                         "domain": row["domain"], "document_type": row["document_type"], "text_sha256": sha(text.encode())})
        target = CACHE / f"{split}.json"
        write(target, rows)
        manifest["splits"][split] = {"source_split": source, "parquet_sha256": HASHES[source],
            "documents": len(rows), "normalized_duplicates_excluded": duplicates,
            "invalid_annotation_documents_excluded": invalid, "missing_annotation_values": dict(missing),
            "unsupported_annotations": dict(unsupported), "prepared_sha256": sha(target.read_bytes()),
            "selection": [{"id": r["id"], "text_sha256": r["text_sha256"]} for r in rows],
            "gold_counts": dict(collections.Counter(s["entity"] for r in rows for s in r["expected"]))}
    write(ROOT / "eval/efficient/accuracy-selection.json", manifest)
    print(json.dumps({k: {a: b for a, b in v.items() if a != "selection"} for k, v in manifest["splits"].items()}, indent=2))


if __name__ == "__main__":
    main()
