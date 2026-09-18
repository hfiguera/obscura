#!/usr/bin/env python3
import argparse
import hashlib
import json
import platform
from pathlib import Path
import time
from harness import ROOT,Worker
from score import score

parser=argparse.ArgumentParser()
parser.add_argument('--split',choices=['development','test'],required=True)
parser.add_argument('--profiles',nargs='+',required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
data_path=ROOT/'data'/f'{args.split}.json'
payload=data_path.read_bytes()
sha=hashlib.sha256(payload).hexdigest()
manifest=json.loads((ROOT/'corpus-manifest.json').read_text())
assert sha==manifest['files'][args.split]['sha256'],'Corpus hash mismatch'
rows=json.loads(payload)
args.output.mkdir(parents=True,exist_ok=True)
for profile in args.profiles:
    output=args.output/f'{args.split}-{profile}.json'
    if output.exists(): raise RuntimeError(f'Refusing to overwrite {output}')
    worker=Worker(profile,ROOT/'raw'/f'{platform.system()}-{args.split}-{profile}.log')
    results=[]
    try:
        for row in rows:
            results.append(worker.request(row))
    finally: worker.close()
    report={'schema':1,'purpose':'Fresh synthetic English evaluation; not population accuracy',
            'profile':profile,'platform':platform.platform(),'split':args.split,'input_sha256':sha,
            'mapping_sha256':hashlib.sha256((ROOT/'MAPPING.md').read_bytes()).hexdigest(),
            'worker_source_sha256':hashlib.sha256((ROOT/('redact_worker.mjs' if profile.startswith('redact') else 'worker.exs')).read_bytes()).hexdigest(),
            'created_unix':time.time(),'startup_ms':worker.startup_ms,'metadata':worker.metadata,
            'metrics':score(rows,results),'rows':results}
    report['by_kind']={kind:score([r for r in rows if r['kind']==kind],
                                   [p for p in results if p['id'] in {r['id'] for r in rows if r['kind']==kind}])
                       for kind in sorted({r['kind'] for r in rows})}
    output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'output':str(output),'exact':report['metrics']['exact'],'error_rows':report['metrics']['error_rows']}),flush=True)
