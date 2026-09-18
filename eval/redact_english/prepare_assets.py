#!/usr/bin/env python3
"""Materialize the publisher's immutable model files; never weights in Git.

Verifies Hugging Face Git blob IDs / LFS hashes before writing files. The manifest
contains hashes only. This is provisioning for licensed evaluation, not a model
conversion, redistribution, training pipeline, or telemetry bypass.
"""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

REVISION = '3ed5033aeb544f454ebde77dc76fd7b7e76cc572'
REPOSITORY = 'desert-ant-labs/redact'
SOURCE = 'c015d5d95028caba783e802442e30ddd66c9247e'
NEEDED = {'labels.json', 'redact_tokenizer.bin', 'redact.tflite',
          'config.json', 'tokenizer.json', 'tokenizer_config.json', 'redact_meta.json',
          'THIRD_PARTY_NOTICES.md'}


def fetch(url):
    request = urllib.request.Request(url, headers={'Accept-Encoding': 'identity'})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def verify(data, entry):
    if len(data) != entry['size']:
        raise ValueError(f"size mismatch: {entry['rfilename']}")
    if 'lfs' in entry:
        actual = hashlib.sha256(data).hexdigest()
        expected = entry['lfs']['sha256']
    else:
        actual = hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest()
        expected = entry['blobId']
    if actual != expected:
        raise ValueError(f"publisher hash mismatch: {entry['rfilename']}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--existing', type=Path)
    args = parser.parse_args()
    info = json.loads(fetch(f'https://huggingface.co/api/models/{REPOSITORY}/revision/{REVISION}?blobs=true'))
    assert info['sha'] == REVISION
    files = []
    for entry in sorted(info['siblings'], key=lambda x: x['rfilename']):
        name = entry['rfilename']
        if name not in NEEDED and not name.startswith('redact.mlmodelc/'):
            continue
        path = args.directory / name
        existing = args.existing / name if args.existing else path
        if path.is_file():
            data = path.read_bytes()
        elif existing.is_file():
            data = existing.read_bytes()
        else:
            data = fetch(f'https://huggingface.co/{REPOSITORY}/resolve/{REVISION}/{name}')
        verify(data, entry)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        files.append({'path': name, 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                      'publisher_git_blob': entry['blobId']})
    manifest = {'schema': 1, 'repository': REPOSITORY, 'revision': REVISION,
                'sdk_version': '3.1.0', 'sdk_source': SOURCE,
                'license': 'https://license.desertant.com/1.0', 'files': files}
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Verified {len(files)} immutable model/configuration files.')


if __name__ == '__main__':
    main()
