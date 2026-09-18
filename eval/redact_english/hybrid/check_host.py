#!/usr/bin/env python3
import hashlib,json,os,platform,re,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parent
logs=sorted((ROOT/'raw').glob('*.log'));assert len(logs)==36,len(logs)
reports=[];cpu_count=0
for p in logs:
 content=p.read_text(errors='replace')
 fatal=len(re.findall(r'segmentation fault|sigsegv|segfault|fatal error|traceback|abort trap',content,re.I))
 assert fatal==0,p.name
 row={'log':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'fatal_signatures':fatal}
 is_redact=p.name.endswith('-redact_cpu.log') or (p.name.startswith('recovery-') and ('redact_cpu' in p.name or 'hybrid' in p.name))
 if platform.system()=='Linux' and is_redact:
  assert 'CPU accelerator registered.' in content and 'Created TensorFlow Lite XNNPACK delegate for CPU.' in content,p.name
  assert 'GPU accelerator could not be loaded and registered.' in content and 'NPU accelerator could not be loaded and registered' in content,p.name
  assert not re.search(r'(?<![A-Za-z])GPU accelerator registered\.',content)
  cpu_count+=1;row['cpu_backend_confirmed']=True
 reports.append(row)
if platform.system()=='Linux':assert cpu_count==18,cpu_count
processes={}
for line in subprocess.check_output(['ps','-axo','pid=,ppid=,command='],text=True).splitlines():
 parts=line.strip().split(None,2)
 if len(parts)==3:processes[int(parts[0])]=(int(parts[1]),parts[2])
ancestors=set();pid=os.getpid()
while pid in processes and pid not in ancestors:
 ancestors.add(pid);pid=processes[pid][0]
remaining=[pid for pid,(_,cmd) in processes.items() if pid not in ancestors and any(s in cmd for s in ['worker.exs','redact_worker.mjs','obscura-spacy-cpu'])]
assert not remaining,remaining
host='linux' if platform.system()=='Linux' else 'macos'
report={'schema':1,'created_unix':time.time(),'platform':platform.platform(),'cpu_model':subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip() if host=='macos' else next(l.split(':',1)[1].strip() for l in Path('/proc/cpuinfo').read_text().splitlines() if l.startswith('model name')),'logs':reports,'linux_cpu_workers_verified':cpu_count,'remaining_candidate_workers':remaining,'limits':'Known fatal-signature and process-name checks, not proof of graceful zero exit for every child.','source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
(ROOT/f'results/{host}/postrun.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'host':host,'logs':len(logs),'linux_cpu_workers_verified':cpu_count,'remaining':remaining}))
