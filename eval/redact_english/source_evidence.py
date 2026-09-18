"""Verify measured source bytes across an explicitly recorded formatting-only edit."""
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

@lru_cache(maxsize=None)
def formatting_equivalent(snapshot, current):
    # Compare the language formatter's output, not a whitespace-stripped string:
    # whitespace inside literals and comments must not be silently discarded.
    code = '[old, new] = System.argv(); if Code.format_string!(File.read!(old)) != Code.format_string!(File.read!(new)), do: raise("Source changed beyond formatting")'
    subprocess.run(['elixir', '-e', code, '--', str(snapshot), str(current)], check=True, capture_output=True)
    return True

def source_matches(path, expected):
    path = path.resolve()
    if sha(path) == expected:
        return True
    entries = json.loads((ROOT/'source-formatting.json').read_text())['files']
    entry = entries.get(str(path.relative_to(ROOT)))
    if entry is None or entry['recorded_sha256'] != expected or sha(path) != entry['current_sha256']:
        return False
    snapshot = ROOT/entry['snapshot']
    return sha(snapshot) == expected and formatting_equivalent(snapshot, path)

def sources_match(recorded, current):
    return set(recorded) == set(current) and all(
        current[name] == digest or source_matches(ROOT/name, digest)
        for name, digest in recorded.items())
