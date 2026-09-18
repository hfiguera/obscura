#!/usr/bin/env python3
"""Recompute frozen results and summarize comparisons without inference or raw text."""
from collections import Counter
import hashlib
import json
from pathlib import Path
import random
from score import score
from source_evidence import source_matches

ROOT = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def spans(row, key='predictions'):
    return sorted((p['entity'], p['byte_start'], p['byte_end']) for p in row.get(key, []))


def main():
    manifest = json.loads((ROOT/'corpus-manifest.json').read_text())
    datasets = {}
    reports = {}
    sources = {}
    for split in ['development', 'test']:
        path = ROOT/'data'/f'{split}.json'
        assert sha(path) == manifest['files'][split]['sha256']
        datasets[split] = json.loads(path.read_text())
        for row in datasets[split]:
            data = row['text'].encode()
            for gold in row['gold']:
                a, b = gold['byte_start'], gold['byte_end']
                assert 0 <= a < b <= len(data)
                data[:a].decode(); data[:b].decode()
                assert any(c.isalnum() for c in data[a:b].decode())
        for host, profiles in [('linux', ['fast','efficient','balanced','redact_cpu']),
                               ('macos', ['fast','efficient','balanced','redact_cpu','redact_default'])]:
            for profile in profiles:
                path = ROOT/'results'/host/f'{split}-{profile}.json'
                result = json.loads(path.read_text())
                assert result['input_sha256'] == manifest['files'][split]['sha256']
                assert result['mapping_sha256'] == sha(ROOT/'MAPPING.md')
                worker = 'redact_worker.mjs' if profile.startswith('redact') else 'worker.exs'
                assert source_matches(ROOT/worker, result['worker_source_sha256'])
                assert score(datasets[split], result['rows']) == result['metrics']
                assert result['metrics']['error_rows'] == 0
                for row in result['rows']:
                    data = next(r['text'].encode() for r in datasets[split] if r['id'] == row['id'])
                    for key in ['predictions','raw_predictions']:
                        for _, a, b in spans(row, key):
                            assert 0 <= a < b <= len(data)
                            data[:a].decode(); data[:b].decode()
                reports[(host, split, profile)] = result
                sources[str(path.relative_to(ROOT))] = sha(path)

    parity = []
    for split in datasets:
        for profile in ['fast','efficient','balanced']:
            a = {r['id']:r for r in reports['linux',split,profile]['rows']}
            b = {r['id']:r for r in reports['macos',split,profile]['rows']}
            mismatches = [rid for rid in a if any(spans(a[rid], k) != spans(b[rid], k)
                                                   for k in ['predictions','raw_predictions'])]
            parity.append({'split':split,'profile':profile,'rows':len(a),'different_row_ids':mismatches})

    # Resample template families, never treat three variants as independent samples.
    # This measures sensitivity to this synthetic family mix, not population uncertainty.
    rows = [r for r in datasets['test'] if not r['supplemental']]
    families = sorted({r['family'] for r in rows})
    profiles = ['fast','efficient','balanced','redact_cpu']
    counts = {}
    for profile in profiles:
        results = reports['linux','test',profile]['rows']
        counts[profile] = []
        for family in families:
            subset = [r for r in rows if r['family'] == family]
            ids = {r['id'] for r in subset}
            metric = score(subset, [r for r in results if r['id'] in ids])['exact']
            counts[profile].append(tuple(metric[k] for k in ['tp','fp','fn']))
    rng = random.Random(20260913)
    deltas = {p:[] for p in profiles if p != 'redact_cpu'}
    for _ in range(2000):
        weights = Counter(rng.randrange(len(families)) for _ in families)
        f1 = {}
        for profile in profiles:
            tp, fp, fn = (sum(weights[i]*counts[profile][i][j] for i in weights) for j in range(3))
            f1[profile] = 2*tp/(2*tp+fp+fn) if 2*tp+fp+fn else 0
        for profile in deltas:
            deltas[profile].append(f1['redact_cpu']-f1[profile])
    sensitivity = {}
    for profile, values in deltas.items():
        values.sort()
        sensitivity[profile] = {
            'observed_redact_minus_baseline_f1':reports['linux','test','redact_cpu']['metrics']['exact']['f1']-reports['linux','test',profile]['metrics']['exact']['f1'],
            'family_resampling_percentile_2_5':values[49],
            'family_resampling_percentile_97_5':values[1949]}

    corpus = {}
    for split, data in datasets.items():
        corpus[split] = {'rows':len(data),'families':len({r['family'] for r in data}),
            'unique_texts':len({r['text'] for r in data}),
            'primary_rows':sum(not r['supplemental'] for r in data),
            'primary_gold':sum(len(r['gold']) for r in data if not r['supplemental']),
            'negative_families':len({r['family'] for r in data if not r['gold']}),
            'utf8_bytes_min':min(len(r['text'].encode()) for r in data),
            'utf8_bytes_max':max(len(r['text'].encode()) for r in data)}
    output = {'schema':1,'purpose':'Recomputed accuracy audit and synthetic family-mix sensitivity; not population confidence intervals',
        'source_reports_sha256':sources,'analysis_source_sha256':sha(Path(__file__)),
        'corpus':corpus,'baseline_cross_platform_span_parity':parity,
        'family_resampling':{'seed':20260913,'draws':2000,'primary_families':len(families),'redact_cpu_linux_minus':sensitivity},
        'test_metrics':{f'{host}/{profile}':r['metrics'] for (host,split,profile),r in reports.items() if split=='test'}}
    target = ROOT/'results/accuracy-analysis.json'
    target.write_text(json.dumps(output,indent=2)+'\n')
    print(json.dumps({'audited_reports':len(reports),'baseline_parity':parity,'corpus':corpus,'sensitivity':sensitivity},indent=2))


if __name__ == '__main__':
    main()
