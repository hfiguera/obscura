#!/usr/bin/env python3
"""Recheck saved default/CPU diagnoses and exact release-source replay parity."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def main():
    sources = {}
    def read(name):
        path = ROOT/'results'/name
        sources[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        return json.loads(path.read_text())
    missing = {}
    for name, expected in [('probe-macos-default.json', 13), ('probe-macos-cpu.json', 21), ('probe-linux-default.json', 12)]:
        report = read(name)
        assert report['sdk'] == '3.1.0' and len(report['results']) == 42
        defaults = [r for r in report['results'] if r['minimumConfidence'] == 0.6]
        assert len(defaults) == 21
        assert all(r['utf16SpansMatch'] and r['restorationExact'] for r in report['results'])
        missing[name] = sum(r['detectedNameComponents'] != 2 for r in defaults)
        assert missing[name] == expected
    replay = []
    for original, release, expected_nonfinite in [
        ('tensors-linux-default.json', 'release/tensors-linux-release-cpu.json', 0),
        ('tensors-macos-default.json', 'release/tensors-darwin-release-all.json', 0),
        ('tensors-macos-cpu.json', 'release/tensors-darwin-release-cpu.json', 8*22784),
    ]:
        a, b = read(original), read(release)
        assert a['sdkSource'] == 'c015d5d95028caba783e802442e30ddd66c9247e'
        assert b['sdkSource'] == '9e11fdf9566df2e34b9516ac76403b1ff0f839d8'
        assert a['rows'] == b['rows'] and len(b['rows']) == 6
        windows = [w for r in b['rows'] for w in r['windows']]
        assert len(windows) == 8
        assert sum(w['nonfiniteValues'] for w in windows) == expected_nonfinite
        if expected_nonfinite == 0:
            for row in b['rows'][3:]:
                assert row['labels'] == ['EMAIL']
                assert all(w['argmaxHistogram'] == {'0': w['realTokens']} for w in row['windows'])
        replay.append({'original_report': original, 'release_report': release, 'rows_identical': True, 'windows': 8})
    for host in ['darwin', 'linux']:
        summary = read(f'release/release-replay-{host}.json')
        assert summary['source_sha256'] == hashlib.sha256((ROOT/'release_diagnostics.py').read_bytes()).hexdigest()
        for result in summary['results'].values():
            assert sources['release/'+result['report']] == result['sha256']
    tokenizer = read('tokenizer-parity.json')
    assert tokenizer['all_equal'] and len(tokenizer['windows']) == 8
    assert all(w['equal'] and not any(w['different_elements'].values()) for w in tokenizer['windows'])
    arrays = read('coreml-array-observation.json')['results']['cpu']['native_arrays']
    assert len(arrays) == 8
    assert all(a['configured_cpu_only'] and a['count'] == a['nonfinite'] == 22784 for a in arrays)
    segmentation = {}
    for name, working in [('linux/segmentation-linux-cpu.json', True), ('segmentation-macos-default.json', True), ('segmentation-macos-cpu.json', False)]:
        rows = read(name)['results']
        assert [r['repeats'] for r in rows] == [0, 5, 20, 150]
        target = {'GIVEN_NAME', 'SURNAME', 'CITY'}
        whole = [target <= set(r['full_labels']) for r in rows]
        split = [target <= set(r['segmented_labels']) for r in rows]
        assert whole == ([True, False, False, False] if working else [False]*4)
        assert split == [working]*4
        segmentation[name] = {'whole_detects_name_city': whole, 'segmented_detects_name_city': split}
    result = {'schema': 1, 'default_calls_missing_complete_name': missing,
              'release_source_parity': replay, 'canonical_tokenizer_windows_equal': 8,
              'native_cpu_arrays_all_nonfinite': 8, 'segmentation': segmentation,
              'source_reports_sha256': sources,
              'analysis_source_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (ROOT/'results/diagnostic-analysis.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({'release_configurations_identical': 3, 'canonical_tokenizer_windows_equal': 8,
                      'native_cpu_arrays_all_nonfinite': 8, 'probe_calls_checked': 126}))


if __name__ == '__main__': main()
