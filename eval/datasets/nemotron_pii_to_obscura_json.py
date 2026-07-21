#!/usr/bin/env python3
"""Convert a deterministic Nemotron-PII Parquet subset to Obscura eval JSON."""

from __future__ import annotations

import argparse
import ast
import json
from pathlib import Path
from typing import Any

import pyarrow.parquet as pq


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="Nemotron-PII parquet file")
    parser.add_argument("--output", required=True, help="Output JSON path")
    parser.add_argument("--split", default="test", help="Source split name")
    parser.add_argument("--limit", type=int, default=500, help="Maximum rows to export")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    samples = []

    parquet = pq.ParquetFile(args.input)
    for batch in parquet.iter_batches(
        batch_size=1024,
        columns=[
            "uid",
            "domain",
            "document_type",
            "document_description",
            "document_format",
            "locale",
            "text",
            "spans",
        ],
    ):
        for row in batch.to_pylist():
            if len(samples) >= args.limit:
                break
            samples.append(convert_row(row, len(samples), args.split))

        if len(samples) >= args.limit:
            break

    output = {
        "dataset": {
            "name": "nemotron_pii_test_subset",
            "source": "nvidia/Nemotron-PII",
            "split": args.split,
            "source_file": args.input,
            "limit": args.limit,
        },
        "samples": samples,
    }

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output_path), "samples": len(samples)}, sort_keys=True))
    return 0


def convert_row(row: dict[str, Any], index: int, split: str) -> dict[str, Any]:
    text = row["text"]
    spans = ast.literal_eval(row["spans"] or "[]")

    return {
        "id": row.get("uid") or index,
        "text": text,
        "template_id": f"{split}:{row.get('domain')}:{row.get('document_type')}:{row.get('document_format')}:{row.get('locale')}",
        "metadata": {
            "source_index": index,
            "uid": row.get("uid"),
            "domain": row.get("domain"),
            "document_type": row.get("document_type"),
            "document_description": row.get("document_description"),
            "document_format": row.get("document_format"),
            "locale": row.get("locale"),
        },
        "spans": [convert_span(text, span) for span in spans],
    }


def convert_span(text: str, span: dict[str, Any]) -> dict[str, Any]:
    start = span["start"]
    end = span["end"]

    return {
        "start": start,
        "end": end,
        "label": span["label"],
        "text": text[start:end],
    }


if __name__ == "__main__":
    raise SystemExit(main())
