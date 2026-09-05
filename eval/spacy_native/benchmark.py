#!/usr/bin/env python3
"""Compare the native port to pinned spaCy, then benchmark live Obscura IPC."""
import argparse
import json
import os
import platform
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE.parent / "spacy_hybrid"))
import benchmark as reference

BINARY = HERE.parents[1] / "native/spacy_cpu/target/aarch64-apple-darwin/release/obscura-spacy-native-prototype"


def canonical(spans):
    return [(s["label"], s["byte_start"], s["byte_end"]) for s in spans]


def doc_spans(doc):
    return [{"label": e.label_, "byte_start": len(doc.text[:e.start_char].encode()),
             "byte_end": len(doc.text[:e.end_char].encode()), "score": 0.85} for e in doc.ents]


def request(process, text, **extra):
    process.stdin.write(json.dumps({"text": text, **extra}) + "\n")
    process.stdin.flush()
    row = json.loads(process.stdout.readline())
    if "error" in row:
        raise RuntimeError(row["error"])
    return row


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", type=Path)
    parser.add_argument("--datasets", nargs="+", choices=list(reference.SELECTIONS),
                        default=list(reference.SELECTIONS))
    parser.add_argument("--repetitions", type=int, default=2)
    parser.add_argument("--skip-elixir", action="store_true")
    args = parser.parse_args()
    out = args.out_dir or ROOT / "eval/reports/spacy_native" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out.mkdir(parents=True, exist_ok=False)
    environment = reference.verify_environment()
    config = json.loads((HERE / "assets/model.json").read_text())
    for file, digest in config["files"].items():
        assert reference.sha256_file(HERE / "assets" / file) == digest
    import spacy
    spacy.require_cpu()
    start = time.perf_counter()
    nlp = spacy.load("en_core_web_lg", enable=["ner"])
    python_load_ms = (time.perf_counter() - start) * 1000
    assert config["source_model_sha256"] == {
        str(p.relative_to(nlp.path)): reference.sha256_file(p)
        for p in sorted(nlp.path.rglob("*")) if p.is_file()}
    start = time.perf_counter()
    process = subprocess.Popen([str(BINARY), str(HERE / "assets")], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, text=True)
    ready = json.loads(process.stdout.readline())
    startup_ms = (time.perf_counter() - start) * 1000
    print(json.dumps({"phase": "ready", "native": ready, "startup_ms": startup_ms}), flush=True)
    environment.update({"platform": platform.platform(), "machine": platform.machine(),
                        "hardware_model": subprocess.check_output(["sysctl", "-n", "hw.model"], text=True).strip(),
                        "cpu": subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip(),
                        "VECLIB_MAXIMUM_THREADS": os.environ.get("VECLIB_MAXIMUM_THREADS"),
                        "python_model_load_ms": python_load_ms, "native_ready": ready,
                        "native_startup_ms": startup_ms, "python_pipeline": nlp.pipe_names})
    experiment = {"schema_version": 1, "environment": environment, "repetitions": args.repetitions,
                  "warmup_samples_per_mode": 5, "datasets": [], "model_sha256": reference.sha256_file(HERE / "assets/model.json"),
                  "binary_sha256": reference.sha256_file(BINARY), "asset_bytes": sum(p.stat().st_size for p in (HERE / "assets").iterdir()),
                  "branch": subprocess.check_output(["git", "branch", "--show-current"], text=True).strip(),
                  "code_sha256": {str(p.relative_to(ROOT)): reference.sha256_file(p)
                                  for p in sorted(HERE.rglob("*")) if p.is_file() and
                                  not any(part in {"assets", "target", "__pycache__", "results"} for part in p.relative_to(HERE).parts)}}
    adapter = reference.load_adapter()
    try:
        for dataset in args.datasets:
            selection_path = ROOT / "eval/authoritative/selections" / reference.SELECTIONS[dataset]
            loaded = adapter.load_dataset(dataset)
            selection = adapter.load_selection(str(selection_path), loaded)
            samples = adapter.selected_samples_from_selection(loaded.samples, selection)
            entry = {"name": dataset, "selection_path": str(selection_path.relative_to(ROOT)),
                     "selection_sha256": reference.sha256_file(selection_path), "runs": []}
            for repetition in range(1, args.repetitions + 1):
                modes = ["python", "native"] if repetition % 2 else ["native", "python"]
                predictions = {}
                for mode in modes:
                    for sample in samples[:5]:
                        nlp(sample["text"]) if mode == "python" else request(process, sample["text"])
                    rows = []
                    for sample in samples:
                        start = time.perf_counter()
                        if mode == "python":
                            doc = nlp(sample["text"])
                            elapsed = (time.perf_counter() - start) * 1000
                            result = {"predictions": doc_spans(doc), "inference_ms": elapsed}
                        else:
                            result = request(process, sample["text"])
                            result["roundtrip_ms"] = (time.perf_counter() - start) * 1000
                        result["sample_id"] = sample["id"]
                        rows.append(result)
                    predictions[mode] = rows
                    path = out / f"{dataset}__{mode}__r{repetition}.json"
                    reference.write_json(path, rows)
                    entry["runs"].append({"mode": mode, "repetition": repetition, "path": str(path),
                                          "sha256": reference.sha256_file(path)})
                mismatches = []
                common_mismatches = 0
                token_mismatches = 0
                for sample, py, native in zip(samples, predictions["python"], predictions["native"]):
                    if canonical(py["predictions"]) != canonical(native["predictions"]):
                        mismatches.append(sample["id"])
                        common_mismatches += canonical([p for p in py["predictions"] if p["label"] in reference.LABEL_MAP]) != canonical([p for p in native["predictions"] if p["label"] in reference.LABEL_MAP])
                        doc = nlp.make_doc(sample["text"])
                        actual = request(process, sample["text"], tokens_only=True)["tokens"]
                        expected = [{"start": len(doc.text[:t.idx].encode()), "end": len(doc.text[:t.idx + len(t)].encode()),
                                     "features": f.tolist()} for t, f in zip(doc, doc.to_array(["NORM", "PREFIX", "SUFFIX", "SHAPE"]))]
                        token_mismatches += actual != expected
                parity = {"documents": len(samples), "all_label_mismatches": len(mismatches),
                          "mapped_label_mismatches": common_mismatches, "token_feature_mismatches_among_entity_mismatches": token_mismatches,
                          "mismatch_sample_ids": mismatches, "repetition": repetition}
                entry.setdefault("parity", []).append(parity)
                print(json.dumps({"phase": "parity", "dataset": dataset, **parity}), flush=True)
            experiment["datasets"].append(entry)
            reference.write_json(out / "experiment.json", experiment)
    finally:
        process.stdin.close()
        process.wait(timeout=10)
    if not args.skip_elixir:
        subprocess.run(["mix", "run", "--no-start", "-r", str(HERE / "native.exs"),
                        "-r", str(HERE / "score.exs"), "-e",
                        "Obscura.SpacyNative.Score.main(System.argv())", "--", str(out / "experiment.json")], cwd=ROOT, check=True)
    print(json.dumps({"experiment": str(out / "experiment.json")}), flush=True)


if __name__ == "__main__":
    main()
