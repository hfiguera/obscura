#!/usr/bin/env python3
"""Measure installed file sizes without loading models or rewriting assets."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import time

REVISION = '0bce50f7884d5bb040469c907c897d4b061ccbb4'


def files_under(path):
    path = path.resolve()
    if path.is_file(): return [path]
    if not path.is_dir(): raise FileNotFoundError(path)
    found = []; visited = set()
    for directory, folders, files in os.walk(path, followlinks=True):
        real = Path(directory).resolve()
        if real in visited:
            folders[:] = []; continue
        visited.add(real)
        for name in files:
            file = Path(directory)/name
            if file.is_file(): found.append(file)
    return found


def total(files):
    seen = set(); apparent = allocated = count = 0
    for path in files:
        info = path.stat()
        identity = (info.st_dev, info.st_ino)
        if identity in seen: continue
        seen.add(identity); count += 1
        apparent += info.st_size; allocated += info.st_blocks*512
    return {'files':count,'apparent_bytes':apparent,'allocated_bytes':allocated}


def main():
    p = argparse.ArgumentParser()
    for name in ['redact-node-root','redact-model-dir','efficient-dir','tner-cache',
                 'node-prefix','beam-prefix','elixir-prefix','consumer-lib','output']:
        p.add_argument('--'+name,type=Path,required=True)
    args = p.parse_args()
    sdk = args.redact_node_root/'node_modules/@desert-ant-labs/redact'
    manifest = json.loads((args.redact_node_root/'model-manifest.json').read_text())
    mac = platform.system() == 'Darwin'
    model_entries = [f for f in manifest['files'] if f['path'] in ['labels.json','redact_tokenizer.bin'] or
                     (f['path'].startswith('redact.mlmodelc/') if mac else f['path']=='redact.tflite')]
    model_paths = [args.redact_model_dir/f['path'] for f in model_entries]
    for f in model_entries: assert (args.redact_model_dir/f['path']).stat().st_size == f['size']
    receipt = json.loads((args.efficient_dir/'installation.json').read_text())
    efficient_paths = [args.efficient_dir/'model'/f for f in receipt['model_hashes']]
    tner_paths = []; tner_files = []
    for metadata in args.tner_cache.glob('*.json'):
        m = json.loads(metadata.read_text())
        if f'/resolve/{REVISION}/' not in m['url']: continue
        encoded = base64.b32encode(m['etag'].encode()).decode().rstrip('=').lower()
        candidate = metadata.with_suffix('.'+encoded)
        assert candidate.is_file(), candidate
        tner_paths.append(candidate)
        tner_files.append({'file':m['url'].split('/')[-1],'url':m['url'],
                           'publisher_etag':m['etag'],'bytes':candidate.stat().st_size})
    assert any(f['file']=='pytorch_model.bin' for f in tner_files)
    groups = {
        'redact_platform_inference_assets':model_paths,
        'redact_all_downloaded_assets':files_under(args.redact_model_dir),
        'redact_installed_npm_dependency_tree':files_under(args.redact_node_root/'node_modules'),
        'redact_current_platform_native_directory':files_under(sdk/'native'/('darwin-arm64' if mac else 'linux-x64')),
        'node_installed_prefix':files_under(args.node_prefix),
        'efficient_five_model_files':efficient_paths,
        'efficient_complete_install_directory':files_under(args.efficient_dir),
        'balanced_selected_revision_assets':tner_paths,
        'obscura_consumer_compiled_libraries':files_under(args.consumer_lib),
        'erlang_installed_prefix':files_under(args.beam_prefix),
        'elixir_installed_prefix':files_under(args.elixir_prefix)}
    node_dependencies = []
    if mac and args.node_prefix.resolve().is_relative_to('/opt/homebrew/Cellar/node'):
        environment = {**os.environ,'HOMEBREW_NO_AUTO_UPDATE':'1'}
        formulas = subprocess.check_output(['brew','deps','--installed','--formula','node'],env=environment,text=True).splitlines()
        dependency_files = []
        for formula in formulas:
            assert re.fullmatch(r'[A-Za-z0-9@+_.-]+',formula)
            prefix = Path('/opt/homebrew/opt')/formula
            files = files_under(prefix)
            node_dependencies.append({'formula':formula,'installed_version':prefix.resolve().name,**total(files)})
            dependency_files.extend(files)
        groups['node_homebrew_dependency_prefixes'] = dependency_files
    native = args.efficient_dir/'obscura-spacy-cpu'
    assert hashlib.sha256(native.read_bytes()).hexdigest() == receipt['native_sha256']
    report = {'schema':1,'created_unix':time.time(),'platform':platform.platform(),
        'purpose':'Observed installed files, not compressed downloads, minimal releases or runtime memory',
        'measurement':'Logical size and allocated file blocks; hardlinks counted once within each group. Groups overlap and must not all be added.',
        'limits':['System shared libraries and OS frameworks are excluded; language runtime prefixes include developer tooling.',
                  'The Obscura consumer contains all baseline optional dependencies; this is not a minimal fast/efficient installation.',
                  'Current-platform native libraries are already included in the npm tree.',
                  'A future Swift-only adapter or pruned npm bundle has not been built or measured.',
                  'Model sizes are stat-checked against previously verified assets; this script does not rehash large weights.'],
        'groups':{name:total(files) for name,files in groups.items()},
        'redact_node_pipeline_observed_total':total(groups['redact_all_downloaded_assets']+groups['redact_installed_npm_dependency_tree']+groups['node_installed_prefix']+groups.get('node_homebrew_dependency_prefixes',[])),
        'redact_node_platform_subset_total':total(groups['redact_platform_inference_assets']+groups['redact_installed_npm_dependency_tree']+groups['node_installed_prefix']+groups.get('node_homebrew_dependency_prefixes',[])),
        'homebrew_node_dependencies':node_dependencies,
        'efficient_installation_receipt':receipt,'balanced_assets':tner_files,
        'model_manifest_sha256':hashlib.sha256((args.redact_node_root/'model-manifest.json').read_bytes()).hexdigest(),
        'source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'output':str(args.output),'groups':report['groups']}))


if __name__ == '__main__':
    main()
