#!/usr/bin/env python3
"""Observe Core ML's native array before SDK conversion, preserving usage tracking.

Copies the pinned SDK into an ignored diagnostic build tree. Adds aggregate
logging only; no inference inputs, outputs, thresholds or telemetry are changed.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT=Path(__file__).resolve().parent
CACHE=ROOT.parents[1]/'.cache/redact-evaluation'
source=CACHE/'desert-ant-core-c015d5d95028caba783e802442e30ddd66c9247e'
target=CACHE/'coreml-observed-sdk'
shutil.copytree(source,target,dirs_exist_ok=True,ignore=shutil.ignore_patterns('.build','.git'))
file=target/'Sources/Inference/CoreMLSession.swift'
original=file.read_text()
anchor='            return readTensor(array)'
assert original.count(anchor)==1
insertion='''            var nonfinite = 0
            var absoluteMax: Float = 0
            let shape = array.shape.map(\\.intValue)
            let count = shape.reduce(1, *)
            for flat in 0..<count {
                var remaining = flat
                var coordinates = [NSNumber](repeating: 0, count: shape.count)
                for dimension in shape.indices.reversed() {
                    coordinates[dimension] = NSNumber(value: remaining % shape[dimension])
                    remaining /= shape[dimension]
                }
                let value = array[coordinates].floatValue
                if value.isFinite { absoluteMax = max(absoluteMax, abs(value)) }
                else { nonfinite += 1 }
            }
            let observation: [String: Any] = [
                "event": "coreml_array_observation", "count": count,
                "nonfinite": nonfinite, "finite_absolute_max": absoluteMax,
                "shape": shape, "strides": array.strides.map(\\.intValue),
                "data_type": array.dataType.rawValue,
                "configured_cpu_only": model.configuration.computeUnits == .cpuOnly
            ]
            let json = try Foundation.JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys])
            FileHandle.standardError.write(json + Data([10]))
'''
file.write_text(original.replace(anchor,insertion+anchor))
patch_identity={'original_source_sha256':hashlib.sha256(original.encode()).hexdigest(),
                'observed_source_sha256':hashlib.sha256(file.read_bytes()).hexdigest(),
                'change':'Aggregate native MLMultiArray diagnostics before SDK readTensor conversion; no computation or telemetry change'}
env={**os.environ,'REDACT_SDK_SOURCE':str(target)}
scratch=CACHE/'coreml-array-build'
with (CACHE/'coreml-array-build.log').open('w') as log:
    subprocess.run(['swift','build','--package-path',str(ROOT/'swift_probe'),'--scratch-path',str(scratch),'-c','release','-j','4'],env=env,stdout=log,stderr=log,check=True)
reports={}
for mode in ['cpu','all']:
    env['DAL_COREML_COMPUTE_UNITS']=mode
    env.pop('REDACT_DIAGNOSTIC_INPUTS',None)
    report=CACHE/f'coreml-array-converted-{mode}.json'
    run=subprocess.run([str(scratch/'release/RedactDiagnostic'),str(CACHE/'model'),str(report)],env=env,capture_output=True,text=True,check=True)
    observations=[]
    for line in run.stderr.splitlines():
        if line.startswith('{'):
            item=json.loads(line)
            if item.get('event')=='coreml_array_observation': observations.append(item)
    assert len(observations)==8
    reports[mode]={'native_arrays':observations,'converted':json.loads(report.read_text())}
output=ROOT/'results/coreml-array-observation.json'
output.write_text(json.dumps({'schema':1,'patch':patch_identity,'results':reports},indent=2)+'\n')
print(json.dumps({'output':str(output),'cpu_nonfinite_counts':[x['nonfinite'] for x in reports['cpu']['native_arrays']]}))
