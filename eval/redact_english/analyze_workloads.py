#!/usr/bin/env python3
"""Audit saved workload reports. A partial matrix cannot pass the completion gate."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parent
PROFILES = ['fast','efficient','balanced','redact_cpu']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def render_markdown(result):
    lines = ['# CPU workload results', '',
        'These are measured external-worker workloads on development hosts with ambient load. '
        'They are not isolated hardware capacity measurements or production reliability certification.', '',
        'Each worker is an independent consumer process: an Elixir VM for an Obscura profile, '
        'or Node plus the official native SDK for Redact. The Obscura consumer includes optional '
        'dependencies for all three baselines. This is not a measurement of four native workers '
        'inside one shared Elixir VM, nor of a minimal fast/efficient release.', '',
        'Each configuration ran for at least 300 seconds after a full warmup cycle, completing '
        'whole seven-request cycles. The burst queues eight requests per worker in the harness. '
        'Recovery deliberately kills one owned process group, replaces it and compares a canary '
        'with its original result. All collected request-error counters are zero, all bursts '
        'complete, and all recovery comparisons pass. Those transport results do not repair '
        'Redact\'s invalid Mac CPU neural output.', '',
        'Redact Mac CPU rows are marked **invalid NER**. Their RPC rates are diagnostic '
        'observations and must not be presented as successful NER performance. Mac default '
        'Core ML acceleration is excluded from the timed CPU matrix.', '']
    for host in ['macos','linux']:
        context = json.loads((ROOT/'results'/host/'host-context.json').read_text())
        rows = [r for r in result['comparisons'] if r['host'] == host]
        lines += [f'## {host}', '',
            f"{context['cpu_model']}; {context['logical_cpus']} logical CPUs; "
            f"{context['memory_bytes']/2**30:.1f} GiB RAM. {context['platform']}.", '',
            '| Profile / workers | RPCs/s | p95 round trip ms | p99 ms | Peak RSS MiB | RSS change MiB | Peak PSS MiB |',
            '| --- | ---: | ---: | ---: | ---: | ---: | ---: |']
        for r in rows:
            label = f"{r['profile']} / {r['workers']}" + (' (invalid NER)' if not r['ner_performance_eligible'] else '')
            link = f"[{label}](results/{host}/workload-{r['profile']}-{r['workers']}.json)"
            pss = f"{r['peak_pss_mib']:.1f}" if r['peak_pss_mib'] is not None else '—'
            lines.append(f"| {link} | {r['requests_per_second']:.2f} | {r['p95_roundtrip_ms']:.2f} | {r['p99_roundtrip_ms']:.2f} | {r['peak_rss_mib']:.1f} | {r['rss_growth_mib']:+.1f} | {pss} |")
        lines += ['', '| Profile / workers | Process startup median ms | First RPC median ms | Burst completion p95 ms | Restart + canary ms |',
            '| --- | ---: | ---: | ---: | ---: |']
        for r in rows:
            label = f"{r['profile']} / {r['workers']}" + (' (invalid NER)' if not r['ner_performance_eligible'] else '')
            lines.append(f"| {label} | {r['cold_process_startup_median_ms']:.1f} | {r['first_roundtrip_median_ms']:.1f} | {r['burst_p95_completion_ms']:.1f} | {r['restart_and_canary_ms']:.1f} |")
        lines += ['']
    rows = json.loads((ROOT/'data/development.json').read_text())
    selected = {f'development-{i:02d}-0' for i in [0,1,5,8,14,18,19]}
    lines += ['## Input mixture and limits', '',
        '| Input ID | UTF-8 bytes | Kind | Gold entity types |', '| --- | ---: | --- | --- |']
    for r in rows:
        if r['id'] in selected:
            lines.append(f"| {r['id']} | {len(r['text'].encode())} | {r['kind']} | {', '.join(sorted({g['entity'] for g in r['gold']})) or 'none'} |")
    intervals = [r['memory_interval_max_seconds'] for r in result['comparisons']]
    lines += ['',
        'This is a repeated fixed input mixture. It does not establish behavior for arbitrarily '
        'large documents or an unlimited stream of unique text. Latency includes the request/response '
        'boundary and mapping; the driver is outside worker-tree memory measurements. Worker count '
        'does not cap internal BEAM, XLA or BLAS threads.', '',
        'Startup means a fresh process with cached assets, including runtime initialization and '
        'asset checks. It is not a reboot, first download or purged filesystem-cache measurement. '
        'The first RPC follows readiness; warm latency follows a full seven-input warmup.', '',
        f"Memory sampling waits ten seconds after collection, so actual intervals include query "
        f"overhead (largest observed gap: {max(intervals):.2f} seconds). RSS is summed over worker "
        'process trees and can count shared pages multiple times. Linux PSS apportions shared pages. '
        'Sampled peaks can miss intervening peaks. Start/end growth over five minutes is not '
        'evidence of long-term leak freedom or input-retention safety.', '',
        'The hosts have unrelated background activity, including virtualization. Host snapshots '
        'and per-run load averages are retained. The fixed run order, different language-runtime '
        'builds between hosts, and one sustained sample per configuration limit generalization. '
        'Compare within a host; do not interpret cross-host ratios as a hardware benchmark.', '',
        'See [WORKLOAD.md](WORKLOAD.md) for the frozen protocol, '
        '[results/workload-analysis.json](results/workload-analysis.json) for the audit and '
        '[ACCURACY.md](ACCURACY.md) for detection quality.']
    (ROOT/'WORKLOAD_RESULTS.md').write_text('\n'.join(lines)+'\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--allow-partial',action='store_true')
    args = parser.parse_args()
    reports = []; missing = []; sources = {}
    corpus_hash = json.loads((ROOT/'corpus-manifest.json').read_text())['files']['development']['sha256']
    for host in ['macos','linux']:
        for profile in PROFILES:
            for workers in range(1,5):
                path = ROOT/'results'/host/f'workload-{profile}-{workers}.json'
                if not path.exists():
                    missing.append(str(path.relative_to(ROOT))); continue
                d = json.loads(path.read_text())
                assert d['profile'] == profile and d['workers'] == workers
                assert d['elapsed_seconds'] >= 300 and d['protocol_duration_met'] is True
                assert d['workload_input_sha256'] == corpus_hash
                assert d['protocol_sha256'] == sha(ROOT/'WORKLOAD.md')
                assert d['driver_sha256'] == sha(ROOT/'workload.py')
                for name, expected in d['execution_sources'].items():
                    assert sha(ROOT/name) == expected, f'Source drift: {path}: {name}'
                counts = d['counts_by_input']
                assert set(counts) == set(d['workload_ids']) and len(counts) == 7
                assert len(set(counts.values())) == 1
                assert sum(counts.values()) == d['requests'] == d['latency']['count']
                assert d['requests'] > 0 and d['errors'] == {}
                assert abs(d['requests']/d['elapsed_seconds'] - d['requests_per_second']) < 1e-9
                assert len(d['cold_process']) == workers
                assert d['burst']['requests'] == 8*workers and d['burst']['errors'] == 0
                assert d['burst']['completion_latency']['count'] == 8*workers
                for key in ['failure_observed','canary_matches_baseline','survivors_match_baseline']:
                    assert d['recovery'][key] is True
                valid_ner = not (host == 'macos' and profile == 'redact_cpu')
                assert d['ner_performance_eligible'] is valid_ner
                expected_name = profile != 'fast' and valid_ner
                assert d['recovery']['canary_name_detected'] is expected_name
                for cold in d['cold_process']:
                    assert cold['canary_name_detected'] is expected_name
                    engine = cold['metadata']['engine']
                    assert engine['device'] == 'cpu'
                    if profile == 'balanced': assert engine['platform'] == 'host'
                    if profile == 'redact_cpu':
                        assert cold['metadata']['model_manifest_sha256'] == sha(ROOT/'model-manifest.json')
                        assert engine['backend'] == ('CoreML' if host=='macos' else 'LiteRT/XNNPACK')
                samples = d['memory_samples']
                # The frozen driver waits ten seconds *after* each memory query.
                # Query cost makes a fixed 30-sample expectation incorrect.
                # Audit full-span coverage and reject an entire missed nominal
                # period instead; retain measured cadence in the summary.
                assert len(samples) >= 2 and 0 <= samples[0]['elapsed_seconds'] < 1
                intervals = [b['elapsed_seconds']-a['elapsed_seconds'] for a,b in zip(samples,samples[1:])]
                assert all(0 < interval <= 20 for interval in intervals), f'Memory trace gap: {path}'
                assert all(s['rss_kib'] > 0 and s['process_count'] >= workers for s in samples)
                assert d['rss_start_kib'] == samples[0]['rss_kib']
                assert d['rss_end_kib'] == samples[-1]['rss_kib']
                assert d['rss_peak_kib'] == max(s['rss_kib'] for s in samples)
                assert d['rss_growth_kib'] == d['rss_end_kib'] - d['rss_start_kib']
                assert samples[-1]['elapsed_seconds'] == d['elapsed_seconds']
                pss = [s['pss_kib'] for s in samples if s['pss_kib'] is not None]
                reports.append({'host':host,'profile':profile,'workers':workers,
                    'ner_performance_eligible':valid_ner,'requests':d['requests'],
                    'requests_per_second':d['requests_per_second'],'p95_roundtrip_ms':d['latency']['p95_ms'],
                    'p99_roundtrip_ms':d['latency']['p99_ms'],
                    'cold_process_startup_median_ms':statistics.median(c['startup_ms'] for c in d['cold_process']),
                    'first_roundtrip_median_ms':statistics.median(c['first_roundtrip_ms'] for c in d['cold_process']),
                    'peak_rss_mib':d['rss_peak_kib']/1024,'rss_growth_mib':d['rss_growth_kib']/1024,
                    'peak_pss_mib':max(pss)/1024 if pss else None,'pss_sample_count':len(pss),
                    'memory_sample_count':len(samples),
                    'memory_interval_median_seconds':statistics.median(intervals),
                    'memory_interval_max_seconds':max(intervals),
                    'burst_p95_completion_ms':d['burst']['completion_latency']['p95_ms'],
                    'restart_and_canary_ms':d['recovery']['restart_and_canary_ms'],
                    'load_average_1_min':min(s['load_average'][0] for s in samples),
                    'load_average_1_max':max(s['load_average'][0] for s in samples)})
                sources[str(path.relative_to(ROOT))] = sha(path)
    if missing and not args.allow_partial:
        raise RuntimeError(f'Incomplete workload matrix: {len(missing)} reports missing')
    result = {'schema':1,'matrix_complete':not missing,'audited_reports':len(reports),
        'missing_reports':missing,'source_reports_sha256':sources,
        'analysis_source_sha256':sha(Path(__file__)),
        'limits':['One measured five-minute run per configuration, on development hosts with ambient workloads.',
                  'Same external RPC driver and input mixture; not maximum in-process throughput.',
                  'RSS sums shared pages; memory snapshots can miss peaks between samples.',
                  'Sampling waits ten seconds after collection; actual intervals include collection overhead. Audit requires full-span coverage with gaps no greater than twenty seconds.',
                  'Mac CPU Redact fails the neural quality gate and is excluded from successful NER performance.',
                  'Fresh processes use cached assets and filesystem pages; startup includes verification and runtime setup.'],
        'comparisons':reports}
    (ROOT/'results/workload-analysis.json').write_text(json.dumps(result,indent=2)+'\n')
    if not missing: render_markdown(result)
    print(json.dumps({'audited_reports':len(reports),'missing_reports':len(missing),'matrix_complete':not missing}))


if __name__ == '__main__':
    main()
