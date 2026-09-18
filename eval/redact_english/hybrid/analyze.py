#!/usr/bin/env python3
import hashlib,json,sys
from pathlib import Path
from adapter import combine
from run import hashes
from score import score
from source_evidence import sources_match
ROOT=Path(__file__).resolve().parent

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def canonical(rows):return sorted((p['entity'],p['byte_start'],p['byte_end']) for p in rows)
def clean(value):
 if isinstance(value,dict):
  for k,v in value.items():
   assert k not in {'text','original','input_text','redactedText','redacted_text','input_ids'},k
   clean(v)
 elif isinstance(value,list):
  for v in value:clean(v)

def main():
 source=hashes();inventory={};accuracy={};workloads=[];parity=[]
 datasets={s:json.loads((ROOT/f'{s}.json').read_text()) for s in ['development','test']}
 manifest=json.loads((ROOT/'manifest.json').read_text())
 for s,rows in datasets.items():
  assert sha(ROOT/f'{s}.json')==manifest['files'][s]['sha256']
  for row in rows:
   b=row['text'].encode()
   for g in row['gold']:
    a,z=g['byte_start'],g['byte_end'];assert 0<=a<z<=len(b);b[:a].decode();b[:z].decode()
 for host in ['macos','linux']:
  for split,rows in datasets.items():
   reports={}
   for profile in ['fast','efficient','redact_cpu','hybrid']:
    path=ROOT/f'results/{host}/{split}-{profile}.json';d=json.loads(path.read_text());inventory[str(path.relative_to(ROOT))]=sha(path)
    assert sources_match(d['sources'],source)
    assert score(rows,d['rows'])==d['metrics'] and not d['metrics']['error_rows']
    clean(d);reports[profile]=d
   for b,r,h in zip(reports['efficient']['rows'],reports['redact_cpu']['rows'],reports['hybrid']['rows']):
    assert b['id']==r['id']==h['id']
    expected=combine(b,r)
    for key in ['predictions','raw_predictions']:assert canonical(expected[key])==canonical(h[key]),(host,split,h['id'])
   accuracy[f'{host}/{split}']={p:d['metrics'] for p,d in reports.items()}
   parity.append({'host':host,'split':split,'live_hybrid_matches_saved_component_merge':True,'rows':len(rows)})
  for count in [1,4]:
   for profile in ['efficient','redact_cpu','hybrid']:
    path=ROOT/f'results/{host}/workload-{profile}-{count}.json';d=json.loads(path.read_text());inventory[str(path.relative_to(ROOT))]=sha(path)
    clean(d);assert sources_match(d['sources'],source)
    assert d['workers']==count and d['elapsed_seconds']>=60 and d['seconds_requested']==60
    assert len(d['counts_by_input'])==6 and len(set(d['counts_by_input'].values()))==1
    assert sum(d['counts_by_input'].values())==d['requests']==d['latency']['count']
    assert not d['errors'] and not d['burst']['errors'] and d['burst']['requests']==8*count
    assert all(d['recovery'][k] for k in ['failure_observed','output_restored','survivors_unchanged'])
    assert d['cpu_quality_valid']==not_invalid(host,profile)
    assert len(d['memory'])>=10 and all(s['rss_kib']>0 for s in d['memory'])
    assert len(d['cold'])==count
    for cold in d['cold']:
     assert len(cold['metadata'])==(2 if profile=='hybrid' else 1)
     assert all(m['engine']['device']=='cpu' for m in cold['metadata'])
    workloads.append({'host':host,**{k:d[k] for k in ['profile','workers','requests_per_second','latency','peak_rss_mib','rss_growth_mib','peak_pss_mib','cpu_quality_valid','recovery','burst']},
                      'startup_mean_ms':sum(c['startup_ms'] for c in d['cold'])/count})
 for host in ['macos','linux']:
  path=ROOT/f'results/{host}/postrun.json';d=json.loads(path.read_text());clean(d)
  assert d['source_sha256']==sha(ROOT/'check_host.py') and not d['remaining_candidate_workers']
  assert len(d['logs'])==36 and all(r['fatal_signatures']==0 for r in d['logs'])
  if host=='linux':assert d['linux_cpu_workers_verified']==18
  inventory[str(path.relative_to(ROOT))]=sha(path)
 result={'schema':1,'accuracy_reports':16,'workload_reports':12,'sources':source,'accuracy':accuracy,'live_merge_parity':parity,
         'workloads':workloads,'report_sha256':inventory,'analyzer_sha256':sha(Path(__file__))}
 (ROOT/'results/analysis.json').write_text(json.dumps(result,indent=2)+'\n')
 lines=['# Efficient plus Redact address experiment','','The live hybrid improves address coverage on this fresh Linux test. It is a useful research result, but does not justify a public integration yet. Mac CPU remains defective, and the full Redact runtime and licensing requirements still apply.','','## Fresh English test','','48 new synthetic texts, 59 gold PII spans, 14 negative texts. Of 26 location spans, 23 are full addresses; this deliberately emphasizes the proposed benefit. The test uses 12 address values and eight person names across different templates. Eight long texts reuse neutral context. This is not 48 independent samples of production traffic, and it does not estimate general English accuracy. The previous post-hoc 0.9019 F1 used a different, already inspected corpus and is not comparable to these absolute scores.','','| Linux pipeline | Precision | Recall | Exact F1 | Fully covered | Partly exposed | Fully exposed | Negative texts changed |','| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
 for p,m in accuracy['linux/test'].items():
  e=m['exact'];c=m['coverage'];lines.append(f"| {p} | {e['precision']:.4f} | {e['recall']:.4f} | {e['f1']:.4f} | {c.get('fully_covered',0)}/59 | {c.get('partially_exposed',0)} | {c.get('fully_exposed',0)} | {m['negative_text']['changed_rows']}/14 |")
 lines+=['','The hybrid retains efficient person F1 (0.8780) and exact email/phone/IP results, while location F1 rises from 0.0909 to 0.5902. Location false positives fall from 37 to 17 because many previous fragments become correct complete addresses. These are span-scoring false positives, not necessarily unrelated words incorrectly masked. Coverage counts letters/digits using original detections; it does not count inferred gaps as masked.','','On Mac CPU, efficient F1 is 0.5038 and hybrid F1 is 0.4521. Hybrid fully covered counts rise from 36 to 39, but false positives rise from 39 to 54. Those changes do not make the known invalid neural output useful or safe. No default-accelerated Mac results are called CPU evidence.','','## Matched operational follow-up','','Each configuration ran 60 seconds with complete cycles over the same six short development inputs. Workers are reused; assets are cached. There are one and four logical workers. Each hybrid worker owns an efficient Elixir worker/native child and a Redact Node/native worker. The Python compositor invokes them sequentially. Measured latency includes both calls and merging; memory sums their child process trees, excluding the driver/compositor. PSS apportions shared pages on Linux. Background activity and one short run per configuration limit causal comparisons; these are not additional five-minute endurance tests.','','| Host | Pipeline | Workers | Requests/s | p95 ms | Peak RSS MiB | RSS change MiB | Peak PSS MiB | Startup mean ms |','| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
 for w in workloads:
  p=w['profile']+(' (invalid Redact CPU)' if not w['cpu_quality_valid'] else '')
  pss=f"{w['peak_pss_mib']:.1f}" if w['peak_pss_mib'] is not None else '—'
  lines.append(f"| {w['host']} | {p} | {w['workers']} | {w['requests_per_second']:.2f} | {w['latency']['p95_ms']:.2f} | {w['peak_rss_mib']:.1f} | {w['rss_growth_mib']:+.1f} | {pss} | {w['startup_mean_ms']:.1f} |")
 lines+=['','All twelve runs completed without reported request errors, all bursts completed, and deliberate underlying-worker failure was observable. Replacing that worker restored the original predictions; surviving pipelines remained consistent. This is evaluator-managed recovery, not a new Elixir supervisor. Mac recovery restores the defective behavior too. Sampled memory growth does not establish leak freedom.','','## Failure cases and decision','','The hybrid fixes complete-address boundaries in test-00 (US street), test-01 (UK street), test-02 (apartment), test-06 (suite), test-08 (multiline) and other cases. It still partly exposes addresses in test-03/test-15 (Canadian street variants), test-05/test-17 (PO boxes), and several long contexts. Test-11 covers identifying characters but still misses the exact annotated full boundary. The single completely exposed hybrid span is a person, which address enrichment cannot repair. These examples were inspected after scoring; the rule was not tuned in response.','','Always invoking Redact makes efficient pay the second inference and resident-runtime cost. Address-label selection occurs after full detection in the official SDK; it does not yield a small address-only model. An explicitly identified address field could support an optional call, but automatic routing based on clues could miss addresses. Neither routing nor sentence splitting is included or validated here.','','Recommendation: keep address enrichment as an experimental direction, with this implementation as evidence. Do not promote this Redact dependency now: Mac CPU correctness and the distribution/offline terms remain unresolved. See [the original license review](../LICENSING.md) and [integration assessment](../INTEGRATION.md). No profile/default changes, training, vendor contact, push or publication were made.','','See [POLICY.md](POLICY.md), [README.md](README.md), [manifest.json](manifest.json), and [results/analysis.json](results/analysis.json) for the frozen rule, reproduction and full measurements.']
 (ROOT/'REPORT.md').write_text('\n'.join(lines)+'\n')
 print(json.dumps({'accuracy_reports_verified':16,'workload_reports_verified':12,'live_merges_verified':sum(p['rows'] for p in parity)}))
def not_invalid(host,profile):return not(host=='macos' and profile in ['redact_cpu','hybrid'])
if __name__=='__main__':main()
