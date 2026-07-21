#!/usr/bin/env python3
"""Read Obscura JSONL prediction exports for presidio_evaluator workflows."""

import json
import sys
from pathlib import Path


def load_predictions(path):
    rows = []
    with Path(path).open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def main(argv):
    if len(argv) != 2:
        print("usage: obscura_predictions.py PATH", file=sys.stderr)
        return 2

    rows = load_predictions(argv[1])
    prediction_count = sum(len(row.get("predictions", [])) for row in rows)
    print(json.dumps({"samples": len(rows), "predictions": prediction_count}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
