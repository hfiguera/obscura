#!/usr/bin/env python3
"""Export pinned spaCy NER assets. Does not read any evaluation dataset."""
import argparse
import importlib.metadata
import platform
import hashlib
import json
import struct
import shutil
import sys
from pathlib import Path

import numpy as np
import spacy
from spacy.attrs import ORTH, NORM
from spacy.lang.norm_exceptions import BASE_NORMS
from spacy.symbols import IDS

HERE = Path(__file__).resolve().parent
def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_environment():
    lock_path = HERE / "export-environment.json"
    lock = json.loads(lock_path.read_text())
    versions = {name: importlib.metadata.version(name) for name in lock["packages"]}
    for name, actual in versions.items():
        if actual != lock["packages"][name]["version"]:
            raise RuntimeError(f"pinned package mismatch: {name}")
    if platform.python_version() != lock["python"]["version"]:
        raise RuntimeError("use the pinned export Python environment")
    return {"python": platform.python_version(), "packages": versions,
            "environment_lock_sha256": sha256_file(lock_path)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    environment = verify_environment()
    out = args.output
    out.mkdir(parents=True, exist_ok=True)
    spacy.require_cpu()
    nlp = spacy.load("en_core_web_lg", enable=["ner"])
    ner = nlp.get_pipe("ner")
    nodes = list(ner.model.walk())
    bindings = {"lower": 2, "upper": 3, "token": 6, "static": 14,
                "embed": 30, "embed_norm": 31,
                **{f"hash{i}": v for i, v in enumerate([53, 55, 57, 59])},
                **{f"cnn{i}": 60 + i * 2 for i in range(4)},
                **{f"cnn{i}_norm": 61 + i * 2 for i in range(4)}}
    tensors = {}
    with (out / "weights.bin").open("wb") as handle:
        for prefix, index in bindings.items():
            node = nodes[index]
            for name in node.param_names:
                data = np.asarray(node.get_param(name), dtype="<f4", order="C")
                tensors[f"{prefix}.{name}"] = {"offset": handle.tell() // 4, "shape": list(data.shape)}
                handle.write(data.tobytes())
    np.asarray(nlp.vocab.vectors.data, dtype="<f4").tofile(out / "vectors.bin")
    with (out / "vector_keys.bin").open("wb") as handle:
        for key, row in sorted(nlp.vocab.vectors.key2row.items()):
            handle.write(struct.pack("<QI", key, row))
    # Match the reference Python Unicode database for shape and whitespace.
    (out / "unicode.bin").write_bytes(bytes(
        int(chr(c).isalpha()) | (int(chr(c).isupper()) << 1)
        | (int(chr(c).isdigit()) << 2) | (int(chr(c).isspace()) << 3)
        for c in range(0x110000)
    ))
    tokenizer = nlp.tokenizer
    regex = {}
    for key in ["prefix_search", "suffix_search", "infix_finditer", "url_match", "token_match"]:
        function = getattr(tokenizer, key)
        regex[key] = function.__self__.pattern if function is not None else None
    rules = {word: [{"orth": token[ORTH], "norm": token.get(NORM)} for token in rule]
             for word, rule in tokenizer.rules.items()}
    # Patterns used by spaCy's second special-case pass, built without exceptions.
    bare = spacy.tokenizer.Tokenizer(nlp.vocab, rules={},
        prefix_search=tokenizer.prefix_search, suffix_search=tokenizer.suffix_search,
        infix_finditer=tokenizer.infix_finditer, token_match=tokenizer.token_match,
        url_match=tokenizer.url_match)
    special_patterns = [{"word": word, "tokens": [token.text for token in bare(word)]}
                        for word in rules if len(bare(word)) > 1]
    config = {"schema_version": 1, "environment": environment, "tensors": tensors,
              "model": "en_core_web_lg", "version": "3.8.0", "pipeline": ["ner"],
              "actions": [ner.moves.get_class_name(i) for i in range(ner.moves.n_moves)],
              "unseen_classes": sorted(ner.model.attrs["unseen_classes"]),
              "hash_seeds": [nodes[i].attrs["seed"] for i in [53, 55, 57, 59]],
              "regex": regex, "rules": rules, "special_patterns": special_patterns,
              "symbols": IDS, "base_norms": BASE_NORMS,
              "norms": {str(k): v for k, v in nlp.vocab.lookups.get_table("lexeme_norm").items()},
              "source_model_sha256": {str(p.relative_to(nlp.path)): sha256_file(p)
                                      for p in sorted(nlp.path.rglob("*")) if p.is_file()},
              "files": {name: sha256_file(out / name) for name in
                        ["weights.bin", "vectors.bin", "vector_keys.bin", "unicode.bin"]}}
    (out / "model.json").write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n")
    for notice in ["LICENSE", "LICENSES_SOURCES"]:
        shutil.copyfile(nlp.path / notice, out / notice)
    print(json.dumps({"assets": str(out), "model_sha256": sha256_file(out / "model.json"),
                      "ner_parameters": (out / "weights.bin").stat().st_size // 4}))


if __name__ == "__main__":
    main()
