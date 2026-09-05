#!/usr/bin/env python3
"""Verify local evidence for the unpublished efficient candidate. Never publishes."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(name):
    return json.loads((ROOT / name).read_text())


def sha(name):
    return hashlib.sha256((ROOT / name).read_bytes()).hexdigest()


def main():
    assets = read("priv/obscura/efficient-assets.json")
    policy = read("eval/efficient/boundary-policy.json")
    assert policy["source_sha256"] == sha("lib/obscura/spacy/boundaries.ex")
    assert policy["development_results_sha256"] == sha("eval/efficient/results/development.json")
    accuracy = read("eval/efficient/results/heldout.json")
    assert accuracy["selection_sha256"] == sha("eval/efficient/accuracy-selection.json")
    profiles = accuracy["profiles"]
    fast = profiles["fast"]["strict_exact"]
    native = profiles["native"]["strict_exact"]
    efficient = profiles["efficient"]["strict_exact"]
    assert efficient["all"]["f1"] >= native["all"]["f1"] - 0.005
    for entity in ["person", "location"]:
        assert efficient[entity]["recall"] > fast[entity]["recall"]
    parity = read("eval/efficient/results/prediction-parity.json")
    assert set(parity["platforms"]) == {"macos-arm64", "linux-arm64", "physical-linux-x86_64"}
    assert len({p["predictions_sha256"] for p in parity["platforms"].values()}) == 1
    for result in parity["platforms"].values():
        assert result["documents"] == 5_000
        assert result["identical_to_reference"] and result["mismatched_documents"] == 0
    targets = {
        "macos-arm64": "aarch64-apple-darwin",
        "linux-arm64": "aarch64-unknown-linux-gnu",
        "physical-linux-x86_64": "x86_64-unknown-linux-gnu",
    }
    for name, target in targets.items():
        report = read(f"eval/efficient/results/workload-{name}.json")
        assert report["passed"] and report["source_and_binary_unchanged_during_measurement"]
        assert report["sustained_seconds_per_configuration"] >= 300
        assert [c["workers"] for c in report["configurations"]] == [1, 2, 3, 4]
        assert all(c["passed"] and c["errors"] == {} for c in report["configurations"])
        assert report["runner_sha256"] == sha("eval/efficient/workload.exs")
        assert report["binary_sha256"] == assets["native"][target]["sha256"]
        for source, expected in report["runtime_source_sha256"].items():
            assert sha(source) == expected, f"Runtime changed after workload measurement: {source}"
    builds = read("eval/efficient/results/builds.json")
    for target, details in builds["native"].items():
        expected = assets["native"][target]["sha256"]
        assert details["sha256"] == expected == details["independent_rebuild_sha256"]
    assert builds["model_export"]["fresh_macos_model_sha256"] == builds["model_export"]["fresh_linux_model_sha256"]
    assert builds["model_export"]["export_environment_sha256"] == sha("native/spacy_cpu/export-environment.json")
    assert builds["model_export"]["hashed_requirements_sha256"] == sha("native/spacy_cpu/export-requirements.txt")
    assert builds["linux_build"]["recipe_sha256"] == sha("native/spacy_cpu/release/Dockerfile")
    assert builds["physical_linux"]["virtualization"] == "none"
    assert builds["package_consumer"]["passed"]
    assert builds["package_consumer"]["elixir"] == "1.17.3"
    print("Local efficient candidate gates passed. Unpublished; hosted Linux release CI remains required before publication.")


if __name__ == "__main__":
    main()
