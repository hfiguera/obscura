#!/usr/bin/env python3
"""Evaluate real spaCy predictions inside Obscura's deterministic analyzer.

Run with the existing .presidio-authoritative-venv. Python only generates model
predictions; score.exs runs the actual Obscura analyzer and shared evaluator.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import importlib.util
import json
import platform
import resource
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SELECTIONS = {
    "generated_large": "generated_large_template_heldout.json",
    "synth_dataset_v2": "synth_dataset_v2_all.json",
    "nemotron_pii_test_subset": "nemotron_pii_test_subset_all.json",
}
# Fixed before evaluation. FAC follows the pinned Presidio configuration.
LABEL_MAP = {"PERSON": "person", "GPE": "location", "LOC": "location", "FAC": "location"}
DEFAULT_SCORE = 0.85  # Presidio's assigned score, not a calibrated probability.
MODES = ("spacy_full", "spacy_ner_only", "presidio")


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def assert_private(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key in {"text", "value", "full_text", "masked", "expected"}:
                raise ValueError(f"raw input or gold field forbidden in artifact: {key}")
            assert_private(child)
    elif isinstance(value, list):
        for child in value:
            assert_private(child)


def write_json(path, value):
    assert_private(value)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def load_adapter():
    path = ROOT / "eval/presidio_adapter/real_presidio_benchmark.py"
    spec = importlib.util.spec_from_file_location("spacy_hybrid_presidio_reference", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def verify_environment():
    lock_path = ROOT / "eval/presidio_adapter/authoritative-environment.json"
    lock = json.loads(lock_path.read_text())
    versions = {name: importlib.metadata.version(name) for name in lock["packages"]}
    for name, actual in versions.items():
        if actual != lock["packages"][name]["version"]:
            raise RuntimeError(f"pinned package mismatch: {name}")
    if platform.python_version() != lock["python"]["version"]:
        raise RuntimeError("use the pinned .presidio-authoritative-venv Python")
    return {"python": platform.python_version(), "packages": versions,
            "environment_lock_sha256": sha256_file(lock_path)}


def spans_from_doc(doc):
    # Python offsets count Unicode codepoints; Obscura consumes UTF-8 bytes.
    offsets = [0]
    for character in doc.text:
        offsets.append(offsets[-1] + len(character.encode("utf-8")))
    return [
        {"label": ent.label_, "entity": LABEL_MAP[ent.label_],
         "byte_start": offsets[ent.start_char], "byte_end": offsets[ent.end_char],
         "char_start": ent.start_char, "char_end": ent.end_char, "score": DEFAULT_SCORE}
        for ent in doc.ents if ent.label_ in LABEL_MAP
    ]


def predict(mode, sample, nlp, analyzer, source_mapping):
    started = time.perf_counter()
    if mode == "presidio":
        found = analyzer.analyze(text=sample["text"], language="en",
                                 entities=sorted(source_mapping), return_decision_process=False)
        inference_ms = (time.perf_counter() - started) * 1000
        spans = [
            {"entity": source_mapping[item.entity_type],
             "byte_start": len(sample["text"][:item.start].encode("utf-8")),
             "byte_end": len(sample["text"][:item.end].encode("utf-8")),
             "char_start": item.start, "char_end": item.end, "score": item.score}
            for item in sorted(found, key=lambda item: (item.start, item.end))
            if item.entity_type in source_mapping
        ]
    else:
        doc = nlp(sample["text"])
        inference_ms = (time.perf_counter() - started) * 1000
        spans = spans_from_doc(doc)
    return {"sample_id": sample["id"], "predictions": spans,
            "inference_ms": inference_ms,
            "processing_ms": (time.perf_counter() - started) * 1000}


def export_predictions(args, out):
    import spacy
    from presidio_analyzer import AnalyzerEngine

    environment = verify_environment()
    spacy.require_cpu()
    started = time.perf_counter()
    analyzer = AnalyzerEngine()
    load_ms = (time.perf_counter() - started) * 1000
    nlp = analyzer.nlp_engine.nlp["en"]
    if nlp.meta["name"] != "core_web_lg" or nlp.meta["version"] != "3.8.0":
        raise RuntimeError("unexpected spaCy model")
    config = analyzer.nlp_engine.ner_model_configuration
    for label, entity in LABEL_MAP.items():
        if config.model_to_presidio_entity_mapping[label].lower() != entity:
            raise RuntimeError("spaCy mapping differs from pinned Presidio")
    if config.default_score != DEFAULT_SCORE:
        raise RuntimeError("Presidio assigned score changed")

    environment.update({
        "platform": platform.platform(), "machine": platform.machine(),
        "hardware_model": subprocess.check_output(["sysctl", "-n", "hw.model"], text=True).strip()
        if sys.platform == "darwin" else platform.processor(),
        "backend": "cpu", "array_type": type(nlp.vocab.vectors.data).__module__,
        "presidio_and_model_load_ms": load_ms,
        "spacy_pipeline": nlp.pipe_names, "model_path": str(nlp.path),
        "model_asset_sha256": {str(p.relative_to(nlp.path)): sha256_file(p)
                               for p in sorted(nlp.path.rglob("*")) if p.is_file()},
        "ner_parameters": sum(node.get_param(name).size
                              for node in nlp.get_pipe("ner").model.walk()
                              for name in node.param_names),
        "vector_bytes": nlp.vocab.vectors.data.nbytes,
        "presidio_ner_configuration": config.model_dump(),
    })
    adapter = load_adapter()
    datasets = []
    for dataset in args.datasets:
        selection_path = ROOT / "eval/authoritative/selections" / SELECTIONS[dataset]
        loaded = adapter.load_dataset(dataset)
        selection = adapter.load_selection(str(selection_path), loaded)
        samples = adapter.selected_samples_from_selection(loaded.samples, selection)
        if len(samples) != selection["dataset"]["sample_count"]:
            raise RuntimeError("selection sample count mismatch")
        entry = {"name": dataset, "selection_path": str(selection_path.relative_to(ROOT)),
                 "selection_sha256": sha256_file(selection_path), "runs": []}
        for repetition in range(1, args.repetitions + 1):
            # Reverse order in the second repetition to reduce systematic order bias.
            modes = MODES if repetition % 2 else tuple(reversed(MODES))
            for mode in modes:
                enabled = ["ner"] if mode == "spacy_ner_only" else environment["spacy_pipeline"]
                with nlp.select_pipes(enable=enabled):
                    mapping = selection["entity_policy"]["source_entity_mapping"]
                    for sample in samples[:args.warmup]:
                        predict(mode, sample, nlp, analyzer, mapping)
                    rows = [predict(mode, sample, nlp, analyzer, mapping) for sample in samples]
                artifact = {"schema_version": 1, "dataset": dataset, "mode": mode,
                            "repetition": repetition, "selection_sha256": entry["selection_sha256"],
                            "rows": rows, "raw_text_omitted": True}
                path = out / f"{dataset}__{mode}__r{repetition}.json"
                write_json(path, artifact)
                entry["runs"].append({"mode": mode, "repetition": repetition,
                                      "path": str(path), "sha256": sha256_file(path)})
                print(json.dumps({"phase": "inference", "dataset": dataset, "mode": mode,
                                  "repetition": repetition, "samples": len(rows)}), flush=True)
        datasets.append(entry)
    peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    environment["python_peak_rss_bytes"] = peak if sys.platform == "darwin" else peak * 1024
    return {"schema_version": 1, "phase": "spacy_hybrid_experiment", "status": "unpromoted",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            "branch": subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip(),
            "code_sha256": {str(p.relative_to(ROOT)): sha256_file(p)
                            for p in [HERE / "benchmark.py", HERE / "score.exs",
                                      ROOT / "eval/presidio_adapter/real_presidio_benchmark.py"]},
            "environment": environment, "label_map": LABEL_MAP, "assigned_score": DEFAULT_SCORE,
            "warmup_samples_per_mode": args.warmup, "repetitions": args.repetitions,
            "primary_candidate": "hybrid_spacy_full", "datasets": datasets,
            "latency_contract": "Single-input serial CPU. Hybrid is Python processing plus actual Obscura analysis; excludes IPC, serialization, startup and disk reads. Presidio timing is analyzer inference only.",
            "raw_text_omitted": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--datasets", nargs="+", choices=list(SELECTIONS), default=list(SELECTIONS))
    parser.add_argument("--repetitions", type=int, default=2)
    parser.add_argument("--warmup", type=int, default=5)
    parser.add_argument("--out-dir", type=Path,
                        default=ROOT / "eval/reports/spacy_hybrid" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
    args = parser.parse_args()
    if args.repetitions < 2 or args.warmup < 1:
        parser.error("at least two repetitions and one warmup are required")
    out = args.out_dir.resolve()
    if (out / "experiment.json").exists():
        parser.error("output already contains an experiment; choose a new directory")
    experiment = export_predictions(args, out)
    manifest = out / "experiment.json"
    write_json(manifest, experiment)
    subprocess.run(["mix", "run", "--no-start", "-r", str(HERE / "score.exs"), "-e",
                    "Obscura.SpacyHybrid.Score.main(System.argv())", "--", str(manifest)],
                   cwd=ROOT, check=True)
    result_path = out / "results.json"
    result = json.loads(result_path.read_text())
    assert_private(result)
    print(json.dumps({"results": str(result_path)}), flush=True)


if __name__ == "__main__":
    main()
