#!/usr/bin/env bash
# Install evaluation-only runtimes under a caller-supplied directory. No sudo,
# service changes, global package installation, or existing project changes.
set -euo pipefail
task_root=${1:?usage: setup_linux_beam.sh TASK_ROOT}
mkdir -p "$task_root/tools/debs" "$task_root/tools/sysroot" "$task_root/tools/elixir-1.18.4"
cd "$task_root/tools/debs"
otp_version='1:25.3.2.8+dfsg-1ubuntu4.6'
packages=()
for suffix in base asn1 crypto dev inets parsetools public-key runtime-tools ssl syntax-tools tools mnesia xmerl; do
  packages+=("erlang-$suffix=$otp_version")
done
apt-get download "${packages[@]}" 'libopenblas0-pthread=0.3.26+ds-1ubuntu0.1' 'libgfortran5=14.2.0-4ubuntu2~24.04.1'
sha256sum ./*.deb > SHA256SUMS
for package in ./*.deb; do dpkg-deb -x "$package" ../sysroot; done
python3 - "$task_root" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]).resolve() / 'tools/sysroot/usr/lib/erlang'
for script in [root / 'bin/erl', *root.glob('erts-*/bin/erl')]:
    script.write_text(script.read_text().replace('ROOTDIR=/usr/lib/erlang', f'ROOTDIR={root}'))
PY
cd "$task_root/tools"
curl --compressed -fsSL https://github.com/elixir-lang/elixir/releases/download/v1.18.4/elixir-otp-25.zip -o elixir-otp-25.zip
curl --compressed -fsSL https://github.com/elixir-lang/elixir/releases/download/v1.18.4/elixir-otp-25.zip.sha256sum -o elixir-otp-25.zip.sha256sum
python3 - <<'PY'
from pathlib import Path
import hashlib
expected = Path('elixir-otp-25.zip.sha256sum').read_text().split()[0]
assert hashlib.sha256(Path('elixir-otp-25.zip').read_bytes()).hexdigest() == expected
print('Elixir archive SHA256 verified.')
PY
unzip -qo elixir-otp-25.zip -d elixir-1.18.4
printf '%s\n' 'Runtime files installed locally; configure Erlang root before use.'
