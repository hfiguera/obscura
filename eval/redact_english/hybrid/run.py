#!/usr/bin/env python3
import argparse,hashlib,json,os,platform,signal,time,threading
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from array import array
from collections import Counter
from adapter import Pipeline,Worker
from score import score
from workload import memory,summary,digest
ROOT=Path(__file__).resolve().parent

def hashes():
    files=[ROOT/'POLICY.md',ROOT/'adapter.py',ROOT/'run.py',ROOT/'development.json',ROOT/'test.json',ROOT/'manifest.json']
    files += [ROOT.parent/n for n in ['harness.py','worker.exs','redact_worker.mjs','spans.mjs','score.py','workload.py','model-manifest.json','consumer/mix.lock']]
    return {str(p.relative_to(ROOT.parent)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}

def put(path,data):
    assert not path.exists(),path
    path.write_text(json.dumps(data,indent=2)+'\n')

def accuracy(profile,split,output,sources):
    rows=json.loads((ROOT/f'{split}.json').read_text()); pipe=Pipeline(profile,ROOT/'raw'/f'{platform.system()}-{split}-{profile}')
    try:
        results=[pipe.request(row) for row in rows]
        data={'profile':profile,'split':split,'platform':platform.platform(),'sources':sources,'metadata':pipe.metadata,
              'startup_ms':pipe.startup_ms,'rows':results,'metrics':score(rows,results)}
        data['by_kind']={k:score([r for r in rows if r['kind']==k],[r for r in results if r['id'] in {x['id'] for x in rows if x['kind']==k}]) for k in {r['kind'] for r in rows}}
        assert sources==hashes()
        put(output/f'{split}-{profile}.json',data)
        print(json.dumps({'event':'accuracy','profile':profile,'split':split,'exact':data['metrics']['exact'],'coverage':data['metrics']['coverage']}),flush=True)
    finally:pipe.close()

def operational(profile,count,seconds,output,sources):
    data=json.loads((ROOT/'development.json').read_text())
    rows=[data[i] for i in [0,1,3,4,5,10]]
    canary=rows[0];pipes=[];cold=[]
    def snapshot():return memory([child for p in pipes for child in p.children])
    print(json.dumps({'event':'starting','profile':profile,'workers':count}),flush=True)
    try:
        for i in range(count):
            p=Pipeline(profile,ROOT/'raw'/f'workload-{platform.system()}-{profile}-{count}-{i}');pipes.append(p)
            first=p.request(canary)
            cold.append({'startup_ms':p.startup_ms,'first_ms':first['roundtrip_ms'],'fingerprint':digest(first['predictions']),'metadata':p.metadata})
            for row in rows: assert 'error' not in p.request(row)
        started=time.perf_counter();deadline=started+seconds;stop=threading.Event();samples=[]
        def sampler():
            while not stop.is_set():
                samples.append({'elapsed':time.perf_counter()-started,**snapshot()});stop.wait(5)
        t=threading.Thread(target=sampler);t.start()
        def traffic(p):
            times=array('d');counts=Counter();errors=Counter()
            while time.perf_counter()<deadline:
                for row in rows:
                    result=p.request(row);times.append(result['roundtrip_ms']);counts[row['id']]+=1
                    if 'error' in result: errors[result['error']]+=1
            return times,counts,errors
        try:
            with ThreadPoolExecutor(max_workers=count) as pool:records=list(pool.map(traffic,pipes))
        finally:stop.set();t.join()
        elapsed=time.perf_counter()-started;samples.append({'elapsed':elapsed,**snapshot()})
        times=array('d');counts=Counter();errors=Counter()
        for a,b,c in records:times.extend(a);counts.update(b);errors.update(c)
        submitted=time.perf_counter()
        def burst(p):
            values=[]
            for i in range(8):
                result=p.request(rows[i%len(rows)])
                values.append({'completion_ms':(time.perf_counter()-submitted)*1000,'error':'error' in result})
            return values
        with ThreadPoolExecutor(max_workers=count) as pool:queued=sum(list(pool.map(burst,pipes)),[])
        victim=pipes[0].children[-1]
        os.killpg(victim.process.pid,signal.SIGKILL);victim.process.wait(timeout=10)
        observed=False
        try:pipes[0].request(canary)
        except (RuntimeError,BrokenPipeError,OSError,TimeoutError):observed=True
        victim.close();start=time.perf_counter()
        replacement=Worker(victim.profile,ROOT/'raw'/f'recovery-{platform.system()}-{profile}-{count}.log')
        pipes[0].children[-1]=replacement;response=pipes[0].request(canary)
        recovery={'failure_observed':observed,'restart_and_request_ms':(time.perf_counter()-start)*1000,
                  'output_restored':digest(response['predictions'])==cold[0]['fingerprint'],
                  'survivors_unchanged':all(digest(p.request(canary)['predictions'])==cold[i]['fingerprint'] for i,p in enumerate(pipes[1:],1))}
        report={'profile':profile,'workers':count,'seconds_requested':seconds,'elapsed_seconds':elapsed,'platform':platform.platform(),
                'sources':sources,'cpu_quality_valid':not(platform.system()=='Darwin' and profile in ['redact_cpu','hybrid']),
                'requests':len(times),'requests_per_second':len(times)/elapsed,'counts_by_input':dict(counts),'errors':dict(errors),
                'latency':summary(times),'cold':cold,'memory':samples,'peak_rss_mib':max(s['rss_kib'] for s in samples)/1024,
                'rss_growth_mib':(samples[-1]['rss_kib']-samples[0]['rss_kib'])/1024,
                'peak_pss_mib':max(s['pss_kib'] for s in samples)/1024 if all(s['pss_kib'] is not None for s in samples) else None,
                'burst':{'requests':len(queued),'errors':sum(r['error'] for r in queued),'completion':summary([r['completion_ms'] for r in queued])},
                'recovery':recovery}
        assert sources==hashes()
        assert elapsed>=seconds and len(set(counts.values()))==1 and not errors
        assert all(recovery[k] for k in ['failure_observed','output_restored','survivors_unchanged'])
        put(output/f'workload-{profile}-{count}.json',report)
        print(json.dumps({'event':'complete','profile':profile,'workers':count,'rps':report['requests_per_second'],'rss_mib':report['peak_rss_mib']}),flush=True)
    finally:
        for p in pipes:p.close()

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);parser.add_argument('--seconds',type=int,default=60)
    parser.add_argument('--phase',choices=['accuracy','workload','all'],default='all');args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True);sources=hashes()
    manifest=json.loads((ROOT/'manifest.json').read_text())
    assert sources['hybrid/POLICY.md']==manifest['policy_sha256']
    for split in ['development','test']:assert sources[f'hybrid/{split}.json']==manifest['files'][split]['sha256']
    if args.phase in ['accuracy','all']:
        for split in ['development','test']:
            for profile in ['fast','efficient','redact_cpu','hybrid']:accuracy(profile,split,args.output,sources)
    if args.phase in ['workload','all']:
        for count in [1,4]:
            for profile in ['efficient','redact_cpu','hybrid']:operational(profile,count,args.seconds,args.output,sources)
