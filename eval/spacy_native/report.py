#!/usr/bin/env python3
"""Create a shareable native feasibility report from verified experiment artifacts."""
import argparse
import json
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE.parent / "spacy_hybrid"))
from benchmark import sha256_file, write_json, assert_private


def mean(rows, key):
    return statistics.mean(r[key] for r in rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", type=Path, required=True)
    args = parser.parse_args()
    result = json.loads(args.results.read_text())
    assert_private(result)
    historical_path = HERE.parent / "spacy_hybrid/results/comparison.json"
    historical = json.loads(historical_path.read_text())
    summary = {"schema_version": 1, "status": "exploratory_unpromoted", "raw_text_omitted": True,
               "source_results": str(args.results.resolve()), "source_results_sha256": sha256_file(args.results),
               "historical_comparison_sha256": sha256_file(historical_path),
               "environment": result["environment"], "live_workers": result["live_workers"],
               "model_sha256": result["model_sha256"], "binary_sha256": result["binary_sha256"],
               "asset_bytes": result["asset_bytes"], "measurement": result["measurement"],
               "branch": result["branch"], "datasets": []}
    for dataset in result["datasets"]:
        previous = next(r for r in historical["comparisons"] if r["dataset"] == dataset["name"])
        assert dataset["selection_sha256"] == previous["selection_sha256"]
        modes = {}
        for mode in ["fast", "python", "native"]:
            runs = [r for r in dataset["live_runs"] if r["mode"] == mode]
            assert len(runs) == result["repetitions"] == 2
            assert len({r["output_fingerprint_sha256"] for r in runs}) == 1
            for r in runs:
                assert sha256_file(r["predictions_path"]) == r["predictions_sha256"]
            modes[mode] = {"shared_f1": runs[0]["metrics"]["f1"], "strict_exact": runs[0]["strict_exact"],
                           "per_entity": runs[0]["metrics"]["per_entity"],
                           "output_fingerprint_sha256": runs[0]["output_fingerprint_sha256"],
                           "latency": {key: statistics.mean(r["latency"][key] for r in runs)
                                       for key in ["mean_ms", "p50_ms", "p95_ms"]},
                           "repetition_latencies": [r["latency"] for r in runs],
                           "peak_worker_rss_bytes": max(r["peak_worker_rss_bytes"] for r in runs)}
        assert modes["native"]["output_fingerprint_sha256"] == modes["python"]["output_fingerprint_sha256"]
        authoritative = {}
        for mode in ["balanced", "accurate", "presidio"]:
            source = previous["authoritative"][mode]
            assert sha256_file(ROOT / source["report"]) == source["sha256"]
            authoritative[mode] = {"shared_f1": source["metrics"]["f1"], "strict_exact": source["strict_exact"],
                                   "report": source["report"], "sha256": source["sha256"]}
        for run in dataset["parity"]:
            assert run["all_label_mismatches"] == 0
        for run in dataset["concurrency"]:
            assert run["output_fingerprint_sha256"] == modes["native"]["output_fingerprint_sha256"]
        summary["datasets"].append({"name": dataset["name"], "samples": dataset["parity"][0]["documents"],
                                    "parity": dataset["parity"], "modes": modes,
                                    "selection_sha256": dataset["selection_sha256"], "authoritative": authoritative,
                                    "concurrency": dataset["concurrency"],
                                    "live_speedup_over_python": modes["python"]["latency"]["mean_ms"] / modes["native"]["latency"]["mean_ms"]})
    out = HERE / "results"
    write_json(out / "comparison.json", summary)
    lines = ["# Native spaCy CPU prototype results", "",
             "The native port reproduces pinned spaCy NER-only predictions on all 2,648 selected documents in both repetitions. "
             "It is a useful CPU candidate; `:balanced` remains the stronger general accuracy choice.", "",
             f"Measured on {result['environment']['cpu']} ({result['environment']['machine']}); Apple Accelerate CPU, "
             "one math thread per native worker. Branch: `benchmark-spacy-hybrid`. No production profile or authoritative manifest changed.", "",
             "## Accuracy", "", "| Dataset | Documents | Native shared F1 | Native strict F1 | Balanced strict F1 | Accurate strict F1 |",
             "|---|---:|---:|---:|---:|---:|"]
    for d in summary["datasets"]:
        n = d["modes"]["native"]
        lines.append(f"| {d['name']} | {d['samples']} | {n['shared_f1']:.4f} | {n['strict_exact']['f1']:.4f} | "
                     f"{d['authoritative']['balanced']['strict_exact']['f1']:.4f} | {d['authoritative']['accurate']['strict_exact']['f1']:.4f} |")
    lines += ["", "Parity covers all 18 entity labels and UTF-8 boundaries, before mapping PERSON→person and GPE/LOC/FAC→location. "
              "The live Elixir analyzer also produces identical final predictions for native and Python workers. All six structured categories "
              "match the deterministic control; repeated runs and native concurrency produce identical output fingerprints.", "",
              "The historical shared F1 excludes boundary and wrong-type errors from FP/FN denominators. Strict F1 counts them as both "
              "a false positive and a false negative. This port preserves NER-only accuracy; it does not improve the trained model. "
              "The prior full-pipeline Nemotron strict F1 was 0.5404; this NER-only candidate is 0.5403. "
              "Balanced's 0.5659 remains higher. There was no threshold tuning, retraining, vector pruning, or use of gold to generate predictions.", "",
              "## Live end-to-end CPU latency", "", "| Dataset | Deterministic mean | Python hybrid mean | Native hybrid mean | Native p95 | Speedup vs Python |",
              "|---|---:|---:|---:|---:|---:|"]
    for d in summary["datasets"]:
        m = d["modes"]
        lines.append(f"| {d['name']} | {m['fast']['latency']['mean_ms']:.3f} ms | {m['python']['latency']['mean_ms']:.3f} ms | "
                     f"{m['native']['latency']['mean_ms']:.3f} ms | {m['native']['latency']['p95_ms']:.3f} ms | {d['live_speedup_over_python']:.2f}× |")
    lines += ["", "Timings wrap actual `Obscura.analyze`: deterministic recognizers, live GenServer/Port request, JSON serialization, CPU inference, "
              "offset normalization, and normal conflict resolution. Both candidates use the same Elixir adapter and protocol. Two repetitions, five warmup "
              "documents per mode; mode order reverses in repetition two. Table entries average the two runs (p95 is the mean of run p95s). "
              "Startup and dataset loading are excluded. Historical GPU profile timings are not used as CPU speed comparisons.", "", "## Startup and memory", "",
              "| Worker | Startup to ready | Model load inside worker | Peak RSS across serial evaluation |",
              "|---|---:|---:|---:|"]
    for mode in ["native", "python"]:
        ready = result["live_workers"][mode]
        rss = max(d["modes"][mode]["peak_worker_rss_bytes"] for d in summary["datasets"])
        lines.append(f"| {mode} | {ready['startup_ms']:.1f} ms | {ready['load_ms']:.1f} ms | {rss / 2**20:.1f} MiB |")
    lines += ["", f"Exported assets total {result['asset_bytes'] / 2**20:.1f} MiB; static vectors alone are 392.4 MiB. "
              "Native maps vectors read-only and faults in used pages; the measured RSS is workload-dependent, not an upper memory bound. "
              "RSS is the worker process high-water mark, excludes the BEAM, and includes each runtime's loaded vocabulary/model. "
              "Python uses the pinned model with only NER enabled. Startup uses fresh processes on a warm filesystem cache, not cold disk or fresh installation.", "",
              "## Bounded native concurrency", "", "Nemotron's same 500 documents, fixed 1/2/4-worker pools, one in-flight document per worker. "
              "Each row averages two repetitions; input sharding changes with pool size. No batching or queue-overload test.", "",
              "| Native workers | Documents/second | Mean request latency | Sum of worker peak RSS |",
              "|---:|---:|---:|---:|"]
    nemotron = next(d for d in summary["datasets"] if d["name"] == "nemotron_pii_test_subset")
    for count in [1, 2, 4]:
        rows = [r for r in nemotron["concurrency"] if r["workers"] == count]
        lines.append(f"| {count} | {mean(rows, 'documents_per_second'):.0f} | "
                     f"{statistics.mean(r['latency']['mean_ms'] for r in rows):.3f} ms | "
                     f"{max(r['sum_peak_worker_rss_bytes'] for r in rows) / 2**20:.1f} MiB |")
    lines += ["", "Summed RSS double-counts shared mapped pages and is not unique physical memory. These are short throughput runs, "
              "not a production soak, autoscaling policy, or tail-latency guarantee.", "", "## Decision and limits", "",
              "Proceed with a separately named experimental CPU integration if this speed/accuracy tradeoff fits the product. Keep `:balanced` as the "
              "general recommendation. The port avoids a Python runtime at inference and delivers substantial CPU savings while preserving this model's accuracy.", "",
              "This is an Apple Silicon macOS feasibility implementation under `eval/spacy_native`, not a packaged production profile. "
              "Linux/Windows portability, supervised pool admission/recovery, signed/versioned model packaging, and a deployment-representative external "
              "test set remain work before shipping. Exact parity on these documents and handcrafted edge cases is evidence, not a proof for all possible "
              "Unicode/tokenizer inputs or future spaCy versions. The vector footprint remains substantial.", "", "## Reproduction and provenance", "",
              "See [README.md](../README.md) for build, export, tests, and benchmark commands. "
              "[comparison.json](comparison.json) contains shareable metrics and artifact hashes; no raw input text or gold spans are committed.", "",
              f"Source result: `{args.results.resolve()}`", "", f"SHA-256: `{sha256_file(args.results)}`", "",
              f"Native binary SHA-256: `{result['binary_sha256']}`", "", f"Model manifest SHA-256: `{result['model_sha256']}`", ""]
    (out / "RESULTS.md").write_text("\n".join(lines))
    print(out / "RESULTS.md")


if __name__ == "__main__":
    main()
