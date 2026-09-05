#!/usr/bin/env python3
"""Score frozen predictions; writes aggregates only, never application text."""
import argparse
import collections
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def spans(rows):
    return {(s["entity"], s["byte_start"], s["byte_end"]) for s in rows}


def ratios(c):
    tp, fp, fn = c["true_positives"], c["false_positives"], c["false_negatives"]
    return {**c, "precision": tp / (tp + fp) if tp + fp else 0,
            "recall": tp / (tp + fn) if tp + fn else 0,
            "f1": 2 * tp / (2 * tp + fp + fn) if 2 * tp + fp + fn else 0}


def covered_bytes(gold, predicted):
    """Union of redaction intervals inside one gold span, regardless of type."""
    _, first, last = gold
    end, total = first, 0
    for _, a, b in sorted(predicted, key=lambda s: (s[1], s[2])):
        a, b = max(first, a, end), min(last, b)
        if b > a:
            total += b - a
            end = b
    return total


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--split", choices=["development", "heldout"], required=True)
    parser.add_argument("--profiles", nargs="+", default=["fast", "native", "efficient", "presidio"])
    args = parser.parse_args()
    cache = ROOT / ".cache/efficient/gretel"
    selection = ROOT / "eval/efficient/accuracy-selection.json"
    manifest = json.loads(selection.read_text())
    input_path = cache / f"{args.split}.json"
    assert sha(input_path) == manifest["splits"][args.split]["prepared_sha256"]
    samples = json.loads(input_path.read_text())
    result = {"schema_version": 1, "split": args.split, "documents": len(samples),
              "selection_sha256": sha(selection), "gold_sha256": sha(input_path), "profiles": {}}
    for profile in args.profiles:
        path = cache / f"{args.split}-{profile}.json"
        prediction = json.loads(path.read_text())
        assert prediction["input_sha256"] == sha(input_path)
        assert [r["id"] for r in prediction["predictions"]] == [r["id"] for r in samples]
        counts = collections.defaultdict(collections.Counter)
        for sample, row in zip(samples, prediction["predictions"]):
            gold, found = spans(sample["expected"]), spans(row["predictions"])
            for entity in ["all"] + sorted(set(manifest["label_mapping"].values())):
                g = {s for s in gold if entity == "all" or s[0] == entity}
                p = {s for s in found if entity == "all" or s[0] == entity}
                c = counts[entity]
                c.update(true_positives=len(g & p), false_positives=len(p - g), false_negatives=len(g - p),
                         documents_with_missed_pii=bool(g - p), documents_with_false_positives=bool(p - g),
                         gold_spans_with_any_typed_overlap=sum(any(a == x and b < z and y < d for x, y, z in p) for a, b, d in g))
                for span in g:
                    covered = covered_bytes(span, found)
                    length = span[2] - span[1]
                    c.update(completely_uncovered_gold_spans=covered == 0,
                             partially_covered_gold_spans=0 < covered < length,
                             fully_covered_gold_spans=covered == length,
                             uncovered_gold_span_bytes=length - covered)
        result["profiles"][profile] = {"prediction_sha256": sha(path),
            "strict_exact": {k: ratios(v) for k, v in counts.items()},
            "reference_environment": prediction.get("environment")}
    output = ROOT / f"eval/efficient/results/{args.split}.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    for name, profile in result["profiles"].items():
        print(name, json.dumps(profile["strict_exact"]["all"]))


if __name__ == "__main__":
    main()
