#!/usr/bin/env python3
"""Prepare the pinned Nemotron subset used by authoritative selections."""

from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path

from huggingface_hub import snapshot_download


ROOT = Path(__file__).resolve().parents[2]
REPO_ID = "nvidia/Nemotron-PII"
REVISION = "b70ffaf5ff39e079776134c5bf4381f00a9fd1ed"
SOURCE_RELATIVE = Path(
    ".cache/obscura-research/datasets/nvidia-Nemotron-PII/"
    "data/test-00000-of-00001.parquet"
)
OUTPUT_RELATIVE = Path(
    ".cache/obscura-research/datasets/nvidia-Nemotron-PII/"
    "nemotron_pii_test_subset.json"
)
EXPECTED_SHA256 = "a36582d34f64ba871a604eabd53a8d92f0628b76ddb027105ac0f9d9a3042577"


def main() -> int:
    local_dir = ROOT / SOURCE_RELATIVE.parents[1]
    snapshot_download(
        repo_id=REPO_ID,
        repo_type="dataset",
        revision=REVISION,
        local_dir=local_dir,
        allow_patterns=["data/test-00000-of-00001.parquet"],
    )

    subprocess.run(
        [
            sys.executable,
            "eval/datasets/nemotron_pii_to_obscura_json.py",
            "--input",
            str(SOURCE_RELATIVE),
            "--output",
            str(OUTPUT_RELATIVE),
            "--split",
            "test",
            "--limit",
            "500",
        ],
        cwd=ROOT,
        check=True,
    )

    output = ROOT / OUTPUT_RELATIVE
    actual = hashlib.sha256(output.read_bytes()).hexdigest()
    if actual != EXPECTED_SHA256:
        raise SystemExit(
            f"dataset hash mismatch: expected {EXPECTED_SHA256}, got {actual}"
        )

    print(f"verified {OUTPUT_RELATIVE} sha256={actual}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
