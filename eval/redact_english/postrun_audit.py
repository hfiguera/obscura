#!/usr/bin/env python3
"""Record limited crash-log and remaining-worker checks without saving log text."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--log-directory', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    logs = sorted(args.log_directory.glob('workload-*.log')) + sorted(args.log_directory.glob('recovery-*.log'))
    assert len(logs) == 56, f'Expected 40 initial and 16 replacement worker logs, got {len(logs)}'
    signature = re.compile(r'segmentation fault|sigsegv|segfault|fatal error|traceback|abort trap', re.I)
    findings = {}
    for path in logs:
        data = path.read_bytes()
        findings[path.name] = {'sha256': hashlib.sha256(data).hexdigest(),
                              'fatal_signature_count': len(signature.findall(data.decode(errors='replace')))}
    # Exclude this check and its ancestors, which can contain the search terms in
    # shell command text. No process is stopped by this read-only audit.
    lines = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,command='], text=True).splitlines()
    processes = {}
    for line in lines:
        fields = line.strip().split(None, 2)
        if len(fields) == 3: processes[int(fields[0])] = (int(fields[1]), fields[2])
    ancestors = set()
    pid = os.getpid()
    while pid in processes and pid not in ancestors:
        ancestors.add(pid)
        pid = processes[pid][0]
    remaining = []
    for pid, (_, command) in processes.items():
        if pid in ancestors: continue
        if any(name in command for name in ['redact_worker.mjs', 'worker.exs', 'RedactDiagnostic', 'workload.py', 'obscura-spacy-cpu']):
            remaining.append({'pid': pid, 'command_sha256': hashlib.sha256(command.encode()).hexdigest()})
    report = {'schema': 1, 'created_unix': time.time(), 'platform': platform.platform(),
              'logs_checked': len(logs), 'logs': findings, 'remaining_candidate_workers': remaining,
              'source_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'limits': 'Checks known fatal log signatures and current process names. Graceful shutdown return codes were not retained; this is not proof that every exit was zero.'}
    args.output.write_text(json.dumps(report, indent=2)+'\n')
    assert not remaining, 'Potential evaluation workers remain; inspect ownership before cleanup'
    assert not any(row['fatal_signature_count'] for row in findings.values()), 'Inspect fatal log signatures'
    print(json.dumps({'logs_checked': len(logs), 'fatal_signatures': 0, 'remaining_candidate_workers': 0}))


if __name__ == '__main__': main()
