#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENV="${ROOT}/.presidio-authoritative-venv"
PYTHON="${PYTHON:-python3.11}"
EXPECTED_PYTHON="3.11.15"

actual_python="$("${PYTHON}" -c 'import platform; print(platform.python_version())')"
if [[ "${actual_python}" != "${EXPECTED_PYTHON}" ]]; then
  printf 'Expected CPython %s, got %s\n' "${EXPECTED_PYTHON}" "${actual_python}" >&2
  exit 1
fi

"${PYTHON}" -m venv "${VENV}"
"${VENV}/bin/python" -m pip install --disable-pip-version-check "pip==26.1.1"
"${VENV}/bin/python" -m pip install \
  --disable-pip-version-check \
  --require-hashes \
  -r "${ROOT}/eval/presidio_adapter/requirements-authoritative.lock"

"${VENV}/bin/python" - <<'PY'
import importlib.metadata
import platform

expected = {
    "presidio-analyzer": "2.2.363",
    "presidio-evaluator": "0.2.5",
    "spacy": "3.8.13",
    "en_core_web_lg": "3.8.0",
}

assert platform.python_version() == "3.11.15"
for package, version in expected.items():
    actual = importlib.metadata.version(package)
    assert actual == version, (package, version, actual)
PY

printf 'Authoritative Presidio environment ready at %s\n' "${VENV}"
