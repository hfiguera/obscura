#!/usr/bin/env bash
set -euo pipefail
task_root=${1:?usage: linux_run.sh TASK_ROOT COMMAND ...}
shift
export PATH="$task_root/tools/elixir-1.18.4/bin:$task_root/tools/sysroot/usr/lib/erlang/bin:$task_root/tools/node-v26.8.2-linux-x64/bin:$PATH"
export MIX_HOME="$task_root/tools/mix" HEX_HOME="$task_root/tools/hex"
export LD_LIBRARY_PATH="$task_root/tools/sysroot/usr/lib/x86_64-linux-gnu/openblas-pthread:$task_root/tools/sysroot/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
export OBSCURA_EFFICIENT_ASSET_DIR="$task_root/assets/efficient"
export REDACT_NODE_ROOT="$task_root/eval"
export REDACT_MODEL_DIR="$task_root/eval/cache/desert-ant-models/desert-ant-labs/redact/v0.4.0"
cd "$task_root/source/eval/redact_english/consumer"
exec "$@"
