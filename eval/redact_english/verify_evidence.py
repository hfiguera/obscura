#!/usr/bin/env python3
"""Verify the delivered evidence bundle without inference or network access."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    commands = [
        [sys.executable, str(ROOT/'analyze_accuracy.py')],
        [sys.executable, str(ROOT/'analyze_workloads.py')],
        [sys.executable, str(ROOT/'analyze_diagnostics.py')],
        [sys.executable, str(ROOT/'audit_reports.py')],
        [sys.executable, '-m', 'unittest', 'discover', '-s', str(ROOT), '-p', 'test_score.py'],
        ['node', '--test', str(ROOT/'test_spans.mjs')],
    ]
    checks = []
    for command in commands:
        result = subprocess.run(command, cwd=REPO, capture_output=True, text=True)
        if result.returncode:
            sys.stderr.write(result.stdout+result.stderr)
            raise RuntimeError(f'Check failed: {command}')
        checks.append({'command': [str(Path(v).relative_to(REPO)) if v.startswith(str(REPO)+'/') else v for v in command], 'exit_code': 0})
    baseline = json.loads((ROOT/'results/baseline-source-parity.json').read_text())
    assert baseline['linux_source_matches_mac']
    for name, expected in baseline['source_files_sha256'].items(): assert sha(REPO/name) == expected
    declared = dict(re.findall(r'"([^"\n]+)" => "([0-9a-f]{64})"', (REPO/'lib/obscura/spacy/assets.ex').read_text()))
    for host in ['macos', 'linux']:
        report = json.loads((ROOT/f'results/{host}/baseline-integrity.json').read_text())
        assert len(report['efficient_files']) == len(report['tner_files']) == 5
        for name, row in report['efficient_files'].items(): assert row['sha256'] == declared[name]
        assert report['source_sha256'] == sha(ROOT/'verify_baseline_assets.py')
        post = json.loads((ROOT/f'results/{host}/postrun-audit.json').read_text())
        assert post['logs_checked'] == 56 and not post['remaining_candidate_workers']
        assert not any(row['fatal_signature_count'] for row in post['logs'].values())
        assert post['source_sha256'] == sha(ROOT/'postrun_audit.py')
    backend = json.loads((ROOT/'results/linux/backend-validation.json').read_text())
    assert backend['workers_checked'] == 14
    assert all(r['cpu_registered'] and r['xnnpack_cpu_delegate_created'] and not r['gpu_registered'] and r['gpu_unavailable'] and r['npu_unavailable'] for r in backend['reports'])
    assert backend['source_sha256'] == sha(ROOT/'audit_linux_backends.py')
    for name, digest in json.loads((ROOT/'diagnostic-manifest.json').read_text())['sha256'].items():
        if not name.startswith('.cache/'): assert sha(REPO/name) == digest
    # Markdown file targets, not external URLs or fragment anchors.
    links = 0
    for doc in ROOT.glob('*.md'):
        for target in re.findall(r'\]\(([^)]+)\)', doc.read_text()):
            if '://' in target or target.startswith('#'): continue
            path = (doc.parent/target.split('#')[0]).resolve()
            if path == ROOT/'results/final-validation.json': continue  # written below
            assert path.is_file(), f'Missing link: {doc.name}: {target}'
            links += 1
    files = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '--', str(ROOT)], cwd=REPO, text=True).splitlines()
    artifacts = {str(Path(name).relative_to(ROOT.relative_to(REPO))): sha(REPO/name) for name in sorted(set(files)) if not name.endswith('/final-validation.json')}
    assert not any(part in name.split('/') for name in artifacts for part in ['node_modules', 'raw', 'cache', 'deps', '_build', '.build', '__pycache__'])
    result = {'schema': 1, 'purpose': 'Evidence-bundle checks; requirement scope and limitations are in COMPLETION.md',
              'checks': checks, 'unit_tests': 8, 'markdown_file_links_checked': links,
              'obscura_source_files_checked': len(baseline['source_files_sha256']),
              'artifacts_sha256': artifacts}
    (ROOT/'results/final-validation.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({'checks_passed': len(checks), 'unit_tests': 8, 'artifact_files': len(artifacts), 'markdown_links': links}))


if __name__ == '__main__': main()
