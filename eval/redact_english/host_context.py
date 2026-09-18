#!/usr/bin/env python3
"""Small host snapshot; no command arguments, usernames, hostnames or input text."""
import argparse
import json
import os
from pathlib import Path
import platform
import subprocess
import time


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()


parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
result = {'schema':1,'created_unix':time.time(),'platform':platform.platform(),
          'machine':platform.machine(),'logical_cpus':os.cpu_count(),
          'load_average':list(os.getloadavg()),
          'purpose':'Host context snapshot during measurements; not a full-run utilization trace'}
processes = []
for line in run('ps','-axo','%cpu=,comm=').splitlines():
    value, command = line.strip().split(None,1)
    processes.append({'ps_cpu_percent':float(value),'executable':Path(command).name})
result['largest_ps_cpu'] = sorted(processes,key=lambda x:x['ps_cpu_percent'],reverse=True)[:12]
result['ps_cpu_note'] = 'ps CPU semantics differ by OS and can reflect historical utilization; this snapshot cannot quantify concurrent CPU time over an entire benchmark.'
if platform.system() == 'Darwin':
    result['cpu_model'] = run('sysctl','-n','machdep.cpu.brand_string')
    result['memory_bytes'] = int(run('sysctl','-n','hw.memsize'))
    result['os_version'] = run('sw_vers','-productVersion')
    result['os_build'] = run('sw_vers','-buildVersion')
    result['cpu_utilization_samples'] = [line.strip() for line in run('top','-l','2','-s','1','-n','0').splitlines() if line.startswith('CPU usage:')]
else:
    result['cpu_model'] = next(line.split(':',1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name'))
    result['memory_bytes'] = int(next(line.split()[1] for line in Path('/proc/meminfo').read_text().splitlines() if line.startswith('MemTotal:')))*1024
    virtualization = subprocess.run(['systemd-detect-virt'],text=True,capture_output=True)
    result['virtualization'] = virtualization.stdout.strip()
    result['vmstat_two_samples'] = run('vmstat','1','2').splitlines()
    result['vmstat_note'] = 'First row is since boot; second row is the one-second interval.'
args.output.parent.mkdir(parents=True,exist_ok=True)
args.output.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'output':str(args.output),'cpu':result['cpu_model'],'memory_bytes':result['memory_bytes']}))
