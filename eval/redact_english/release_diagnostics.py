#!/usr/bin/env python3
"""Replay the tensor observer at npm 3.1.0's gitHead, after timed workloads."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
RELEASE = '9e11fdf9566df2e34b9516ac76403b1ff0f839d8'
ORIGINAL_DIAGNOSTIC = 'c015d5d95028caba783e802442e30ddd66c9247e'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sdk-source',type=Path,required=True)
    parser.add_argument('--model-directory',type=Path,required=True)
    parser.add_argument('--scratch',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--linux-native-directory',type=Path)
    args = parser.parse_args()
    if os.environ.get('DAL_USAGE_DISABLED'): raise RuntimeError('Telemetry must remain enabled')
    provenance = json.loads((ROOT/'sdk-provenance.json').read_text())
    for name, hashes in provenance['selected_source_parity'].items():
        assert hashlib.sha256((args.sdk_source/name).read_bytes()).hexdigest() == hashes['release_sha256']
    args.scratch.mkdir(parents=True,exist_ok=True)
    args.output.mkdir(parents=True,exist_ok=True)
    package = args.scratch/'package'
    package.mkdir(exist_ok=True)
    swift = (ROOT/'swift_probe/Sources/RedactDiagnostic/Probe.swift').read_text()
    assert swift.count(ORIGINAL_DIAGNOSTIC) == 1
    swift = swift.replace(ORIGINAL_DIAGNOSTIC,RELEASE)
    destination = package/'Sources/RedactDiagnostic/Probe.swift'
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text(swift)
    package.joinpath('Package.swift').write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "RedactDiagnostic",
    platforms: [.macOS(.v15)],
    dependencies: [.package(name: "SDK", path: SDK_PATH)],
    targets: [.executableTarget(name: "RedactDiagnostic", dependencies: [
        .product(name: "Redact", package: "SDK"),
        .product(name: "DesertAnt", package: "SDK")
    ])]
)
'''.replace('SDK_PATH',json.dumps(str(args.sdk_source.resolve()))))
    lock = json.loads((ROOT/'swift_probe/Package.resolved').read_text())
    shutil.copyfile(ROOT/'swift_probe/Package.resolved',package/'Package.resolved')
    command = ['swift','build','--package-path',str(package),'--scratch-path',str(args.scratch/'build'),'-c','release','-j','2']
    if platform.system() == 'Linux':
        if args.linux_native_directory is None: raise ValueError('Linux native library directory required')
        command += ['-Xlinker','-L'+str(args.linux_native_directory.resolve()),'-Xlinker','-rpath','-Xlinker',str(args.linux_native_directory.resolve())]
    with (args.scratch/'build.log').open('w') as log:
        subprocess.run(command,stdout=log,stderr=log,check=True)
    assert json.loads((package/'Package.resolved').read_text())['pins'] == lock['pins']
    reports = {}
    for mode in (['all','cpu'] if platform.system() == 'Darwin' else ['cpu']):
        name = f'tensors-{platform.system().lower()}-release-{mode}.json'
        output = args.output/name
        if output.exists(): raise FileExistsError(output)
        environment = {**os.environ,'DAL_COREML_COMPUTE_UNITS':mode,
                       'REDACT_DIAGNOSTIC_INPUTS':str((args.scratch/f'inputs-{mode}.jsonl').resolve())}
        result = subprocess.run([str((args.scratch/'build/release/RedactDiagnostic').resolve()),
            str(args.model_directory.resolve()),str(output.resolve())],env=environment,text=True,capture_output=True)
        (args.scratch/f'run-{mode}.log').write_text(result.stdout+result.stderr)
        if result.returncode != 0:
            raise RuntimeError(f'Release diagnostic exited {result.returncode}; see scratch run-{mode}.log')
        report = json.loads(output.read_text())
        assert report['sdkSource'] == RELEASE
        reports[mode] = {'report':name,'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
            'windows':sum(len(row['windows']) for row in report['rows']),
            'nonfinite_values':sum(w['nonfiniteValues'] for row in report['rows'] for w in row['windows'])}
    summary = {'schema':1,'sdk_release_source':RELEASE,'original_diagnostic_source':ORIGINAL_DIAGNOSTIC,
        'swift_observer_sha256':hashlib.sha256(destination.read_bytes()).hexdigest(),
        'source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'swift_dependency_pins':lock['pins'],'results':reports,
        'purpose':'Release-source replay; original source snapshot results preserved separately. Telemetry remains enabled.'}
    (args.output/f'release-replay-{platform.system().lower()}.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary))


if __name__ == '__main__':
    main()
