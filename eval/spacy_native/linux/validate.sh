#!/bin/sh
set -eu

# Required rather than skipped: this lane must exercise the real checkpoint.
: "${OBSCURA_SPACY_MODEL_DIR:?Mount the pinned spaCy export read-only and set its directory}"
: "${OBSCURA_SPACY_RESULTS_DIR:?Mount a writable directory for validation results}"

uname -m
elixir --version
rustc --version
ldd priv/spacy_cpu/obscura-spacy-cpu
dpkg-query -W libopenblas0-pthread libpcre2-8-0 libc6
mix obscura.profile.check --profile spacy_cpu --prepare --offline --json
mix test test/obscura/spacy test/obscura/profile_test.exs test/obscura/profile \
  test/obscura/capabilities_test.exs test/obscura/public_api_contract_test.exs \
  test/obscura/analyzer test/mix/tasks/obscura.profile.check_test.exs \
  test/mix/tasks/obscura.profile.prepare_test.exs
mix run --no-start eval/spacy_native/profile_benchmark.exs
