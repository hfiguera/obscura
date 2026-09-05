#!/usr/bin/env python3
"""Compatibility entry point for the original feasibility experiment export."""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
if __name__ == "__main__":
    subprocess.run([sys.executable, str(HERE.parents[1] / "native/spacy_cpu/export.py"),
                    "--output", str(HERE / "assets")], check=True)
