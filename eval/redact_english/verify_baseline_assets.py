#!/usr/bin/env python3
"""Verify existing baseline assets without loading a model or changing a cache."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import platform
import time
import urllib.request

REVISION = '0bce50f7884d5bb040469c907c897d4b061ccbb4'
REPOSITORY = 'tner/roberta-large-ontonotes5'


def hash_file(path, algorithm='sha256', git_blob=False):
    before = path.stat()
    result = hashlib.new(algorithm)
    if git_blob: result.update(f'blob {before.st_size}\0'.encode())
    with path.open('rb') as stream:
        while chunk := stream.read(4*1024*1024): result.update(chunk)
    after = path.stat()
    assert (before.st_size,before.st_mtime_ns) == (after.st_size,after.st_mtime_ns)
    return result.hexdigest()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--efficient-dir',type=Path,required=True)
    p.add_argument('--tner-cache',type=Path,required=True)
    p.add_argument('--publisher-metadata',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args = p.parse_args()
    receipt = json.loads((args.efficient_dir/'installation.json').read_text())
    efficient = {}
    for name, expected in receipt['model_hashes'].items():
        path = args.efficient_dir/'model'/name
        actual = hash_file(path)
        assert actual == expected, f'Efficient hash mismatch: {name}'
        efficient[name] = {'sha256':actual,'bytes':path.stat().st_size,'mtime_unix':path.stat().st_mtime}
    native = args.efficient_dir/'obscura-spacy-cpu'
    assert hash_file(native) == receipt['native_sha256']
    if not args.publisher_metadata.exists():
        url = f'https://huggingface.co/api/models/{REPOSITORY}/revision/{REVISION}?blobs=true'
        with urllib.request.urlopen(url,timeout=120) as response: data = response.read()
        info = json.loads(data)
        assert info['sha'] == REVISION
        args.publisher_metadata.parent.mkdir(parents=True,exist_ok=True)
        args.publisher_metadata.write_bytes(data)
    info = json.loads(args.publisher_metadata.read_text())
    assert info['sha'] == REVISION
    entries = {f['rfilename']:f for f in info['siblings']}
    tner = {}
    for metadata in args.tner_cache.glob('*.json'):
        record = json.loads(metadata.read_text())
        if f'/resolve/{REVISION}/' not in record['url']: continue
        name = record['url'].split('/')[-1]
        encoded = base64.b32encode(record['etag'].encode()).decode().rstrip('=').lower()
        path = metadata.with_suffix('.'+encoded)
        entry = entries[name]
        assert path.stat().st_size == entry['size']
        digest = hash_file(path)
        if 'lfs' in entry:
            assert digest == entry['lfs']['sha256'], f'TNER LFS mismatch: {name}'
            verification = {'algorithm':'sha256','expected':entry['lfs']['sha256']}
        else:
            actual_blob = hash_file(path,'sha1',git_blob=True)
            assert actual_blob == entry['blobId'], f'TNER Git blob mismatch: {name}'
            verification = {'algorithm':'git-blob-sha1','expected':entry['blobId']}
        tner[name] = {'sha256':digest,'bytes':path.stat().st_size,
                      'mtime_unix':path.stat().st_mtime,'publisher_verification':verification}
    assert set(tner) == {'pytorch_model.bin','config.json','tokenizer.json','tokenizer_config.json','special_tokens_map.json'}
    result = {'schema':1,'created_unix':time.time(),'platform':platform.platform(),
        'purpose':'Post-inference byte verification against efficient receipt and immutable publisher TNER metadata',
        'efficient_asset_version':receipt['asset_version'],'efficient_files':efficient,
        'efficient_native_sha256':receipt['native_sha256'],'tner_revision':REVISION,'tner_files':tner,
        'tner_publisher_metadata_sha256':hash_file(args.publisher_metadata),
        'source_sha256':hash_file(Path(__file__))}
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'output':str(args.output),'verified_efficient_files':len(efficient),'verified_tner_files':len(tner)}))


if __name__ == '__main__':
    main()
