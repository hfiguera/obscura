#!/usr/bin/env python3
import argparse
from array import array
from collections import Counter,deque
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import signal
import subprocess
import threading
import time
from harness import ROOT,Worker


def digest(value): return hashlib.sha256(json.dumps(value,sort_keys=True).encode()).hexdigest()


def summary(values):
    v=sorted(values)
    return {'count':len(v), **{name:v[max(0,math.ceil(len(v)*q)-1)] if v else None
                               for name,q in [('p50_ms',.5),('p95_ms',.95),('p99_ms',.99)]},
            'mean_ms':sum(v)/len(v) if v else None}


def memory(workers):
    output=subprocess.check_output(['ps','-axo','pid=,ppid=,rss=,comm='],text=True)
    entries={}
    for line in output.splitlines():
        fields=line.split(None,3)
        if len(fields)==4:
            try: entries[int(fields[0])]=(int(fields[1]),int(fields[2]))
            except ValueError: pass
    roots={w.process.pid for w in workers}
    owned=set(roots)
    while True:
        added={pid for pid,(parent,_) in entries.items() if parent in owned}-owned
        if not added: break
        owned|=added
    rss=sum(entries.get(pid,(0,0))[1] for pid in owned)
    pss=0; readable=0
    if platform.system()=='Linux':
        for pid in owned:
            try:
                line=next(x for x in Path(f'/proc/{pid}/smaps_rollup').read_text().splitlines() if x.startswith('Pss:'))
                pss+=int(line.split()[1]);readable+=1
            except (OSError,StopIteration): pass
    return {'rss_kib':rss,'pss_kib':pss if readable==len(owned) else None,
            'process_count':sum(pid in entries for pid in owned),'load_average':list(os.getloadavg())}


def run(profile,count,seconds,output):
    source_files=['workload.py','harness.py','worker.exs','redact_worker.mjs','spans.mjs','MAPPING.md','WORKLOAD.md','model-manifest.json','consumer/mix.lock']
    sources={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in source_files}
    payload=(ROOT/'data/development.json').read_bytes()
    expected=json.loads((ROOT/'corpus-manifest.json').read_text())['files']['development']['sha256']
    assert hashlib.sha256(payload).hexdigest()==expected
    rows={r['id']:r for r in json.loads(payload)}
    workload=[rows[f'development-{i:02d}-0'] for i in [0,1,5,8,14,18,19]]
    canary={'id':'canary','text':'Contact Rachel Chen in London at rachel.chen@example.test.'}
    workers=[]; cold=[]; baselines=[]
    print(json.dumps({'event':'starting','profile':profile,'workers':count}),flush=True)
    try:
        for i in range(count):
            worker=Worker(profile,ROOT/'raw'/f'workload-{platform.system()}-{profile}-{count}-{i}.log')
            workers.append(worker)
            response=worker.request(canary)
            baselines.append(digest(response.get('predictions',[])))
            cold.append({'startup_ms':worker.startup_ms,'first_inference_ms':response.get('inference_ms'),
                         'first_roundtrip_ms':response['roundtrip_ms'],'metadata':worker.metadata,
                         'canary_name_detected':any(p['entity']=='person' for p in response.get('predictions',[]))})
            for row in workload: worker.request(row)
        samples=[]; stop=threading.Event(); started=time.perf_counter();deadline=started+seconds
        def sample_memory():
            while True:
                samples.append({'elapsed_seconds':time.perf_counter()-started,**memory(workers)})
                if stop.wait(10): break
        sampler=threading.Thread(target=sample_memory,daemon=True);sampler.start()
        def traffic(worker):
            latencies=array('d'); by_id=Counter(); errors=Counter()
            while time.perf_counter()<deadline:
                for row in workload:
                    response=worker.request(row)
                    latencies.append(response['roundtrip_ms']);by_id[row['id']]+=1
                    if 'error' in response: errors[response['error']]+=1
            return latencies,by_id,errors
        try:
            with ThreadPoolExecutor(max_workers=count) as pool:
                futures=[pool.submit(traffic,w) for w in workers]
                records=[f.result() for f in futures]
        finally:
            elapsed=time.perf_counter()-started; stop.set();sampler.join(timeout=15)
        samples.append({'elapsed_seconds':elapsed,**memory(workers)})
        latencies=array('d'); by_id=Counter();errors=Counter()
        for values,counts,failures in records: latencies.extend(values);by_id.update(counts);errors.update(failures)
        available=deque(workers);guard=threading.Lock();queued=[];submitted=time.perf_counter()
        def burst(index):
            with guard: worker=available.popleft()
            try:
                result=worker.request(workload[index%len(workload)])
                return {'completion_ms':(time.perf_counter()-submitted)*1000,'error':'error' in result}
            finally:
                with guard: available.append(worker)
        with ThreadPoolExecutor(max_workers=count) as pool:
            queued=list(pool.map(burst,range(8*count)))
        victim=workers[0]
        os.killpg(victim.process.pid,signal.SIGKILL);victim.process.wait(timeout=10)
        observed=False
        try: victim.request(canary)
        except (RuntimeError,BrokenPipeError,OSError,TimeoutError): observed=True
        victim.close()
        recovery_start=time.perf_counter()
        replacement=Worker(profile,ROOT/'raw'/f'recovery-{platform.system()}-{profile}-{count}.log')
        workers[0]=replacement
        result=replacement.request(canary)
        recovery={'failure_observed':observed,'restart_and_canary_ms':(time.perf_counter()-recovery_start)*1000,
                  'canary_matches_baseline':digest(result.get('predictions',[]))==baselines[0],
                  'canary_name_detected':any(p['entity']=='person' for p in result.get('predictions',[])),
                  'survivors_match_baseline':all(digest(w.request(canary).get('predictions',[]))==baselines[i]
                                               for i,w in enumerate(workers[1:],1))}
        report={'schema':1,'profile':profile,'workers':count,'platform':platform.platform(),
                'machine':platform.machine(),'logical_cpus':os.cpu_count(),'created_unix':time.time(),
                'workload_input_sha256':expected,'workload_ids':[r['id'] for r in workload],
                'protocol_sha256':hashlib.sha256((ROOT/'WORKLOAD.md').read_bytes()).hexdigest(),
                'driver_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                'execution_sources':sources,
                'protocol_duration_met':seconds>=300 and elapsed>=300,
                'ner_performance_eligible':seconds>=300 and elapsed>=300 and not(profile=='redact_cpu' and platform.system()=='Darwin'),
                'cold_process':cold,'elapsed_seconds':elapsed,'requests':len(latencies),
                'requests_per_second':len(latencies)/elapsed,'errors':dict(errors),
                'latency':summary(latencies),'counts_by_input':dict(by_id),
                'memory_samples':samples,'rss_start_kib':samples[0]['rss_kib'],
                'rss_end_kib':samples[-1]['rss_kib'],'rss_peak_kib':max(s['rss_kib'] for s in samples),
                'rss_growth_kib':samples[-1]['rss_kib']-samples[0]['rss_kib'],
                'burst':{'requests':len(queued),'errors':sum(x['error'] for x in queued),
                         'completion_latency':summary([x['completion_ms'] for x in queued])},
                'recovery':recovery}
        assert sources=={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in source_files}, 'Execution source changed during measurement'
        output.write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps({'event':'complete','output':str(output),'rps':report['requests_per_second'],
                          'errors':report['errors'],'recovery':recovery}),flush=True)
    finally:
        for worker in workers: worker.close()


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--profiles',nargs='+',required=True)
    p.add_argument('--workers',nargs='+',type=int,default=[1,2,3,4]);p.add_argument('--seconds',type=int,default=300)
    p.add_argument('--output',type=Path,required=True);args=p.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    for profile in args.profiles:
        for count in args.workers:
            if count not in range(1,5): raise ValueError('Worker count must be 1–4')
            target=args.output/f'workload-{profile}-{count}.json'
            if target.exists(): raise RuntimeError(f'Refusing to overwrite {target}')
            run(profile,count,args.seconds,target)
