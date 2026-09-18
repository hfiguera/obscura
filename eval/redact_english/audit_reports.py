#!/usr/bin/env python3
"""Reject raw content in the diagnostic reports; this is not a metric audit."""
import json
from pathlib import Path

RAW_FIELDS = {'text', 'original', 'input_text', 'redactedText', 'redacted_text'}


def inspect(value, path=()):
    if isinstance(value, dict):
        for key, child in value.items():
            assert key not in RAW_FIELDS, f'Raw-content field at {path + (key,)}'
            if key == 'input_ids':
                assert path[-1:] == ('different_elements',) and type(child) is int, \
                    f'Raw token IDs at {path + (key,)}'
            inspect(child, path + (key,))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            inspect(child, path + (index,))


for report in sorted((Path(__file__).parent / 'results').rglob('*.json')):
    inspect(json.loads(report.read_text(), parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x))))
    print(f'Passed raw-content field check: {report.name}')
