#!/usr/bin/env python3
"""Extract backend evidence from each Linux Redact worker's native startup log."""
import argparse
import hashlib
import json
from pathlib import Path
import re


parser = argparse.ArgumentParser()
parser.add_argument('--log-directory',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
args = parser.parse_args()
reports = []
for workers in range(1,5):
    names = [f'workload-Linux-redact_cpu-{workers}-{i}.log' for i in range(workers)]
    names += [f'recovery-Linux-redact_cpu-{workers}.log']
    for name in names:
        payload = (args.log_directory/name).read_bytes()
        content = payload.decode(errors='replace')
        cpu = 'name=CpuAccelerator' in content and 'CPU accelerator registered.' in content
        xnnpack = 'Created TensorFlow Lite XNNPACK delegate for CPU.' in content
        gpu = bool(re.search(r'(?<![A-Za-z])GPU accelerator registered\.',content))
        gpu_unavailable = 'GPU accelerator could not be loaded and registered.' in content
        npu_unavailable = 'NPU accelerator could not be loaded and registered' in content
        assert cpu and xnnpack and not gpu and gpu_unavailable and npu_unavailable, f'CPU backend evidence missing or contradictory: {name}'
        reports.append({'log':name,'sha256':hashlib.sha256(payload).hexdigest(),
                        'cpu_registered':cpu,'xnnpack_cpu_delegate_created':xnnpack,'gpu_registered':gpu,
                        'gpu_unavailable':gpu_unavailable,'npu_unavailable':npu_unavailable})
args.output.write_text(json.dumps({'schema':1,'purpose':'Actual native startup logs for all Linux Redact workload and recovery workers; no log contents retained',
    'source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'workers_checked':len(reports),'reports':reports},indent=2)+'\n')
print(json.dumps({'workers_checked':len(reports),'cpu_backend_confirmed':True}))
