#!/usr/bin/env python3
"""Compare captured SDK tensors with the publisher's canonical tokenizer.

Only aggregate comparison counts are written. Captured token IDs remain local.
Uses the diagnostic sentences in swift_probe, not development or final test data.
"""
import argparse
import hashlib
import json
from pathlib import Path
from tokenizers import Tokenizer, __version__

parser = argparse.ArgumentParser()
parser.add_argument('--tokenizer', type=Path, required=True)
parser.add_argument('--inputs', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
tokenizer = Tokenizer.from_file(str(args.tokenizer))
captured = [json.loads(line) for line in args.inputs.read_text().splitlines()]
contact = 'Contact Rachel Chen in London at rachel.chen@example.test.'
filler = 'The worker finished the ordinary background task. '
cursor = 0
rows = []
for repeats in [0, 1, 3, 5, 10, 50]:
    text = filler * repeats + contact
    masked = text.replace('rachel.chen@example.test', ' ' * len('rachel.chen@example.test'))
    tokens = tokenizer.encode(masked, add_special_tokens=False).ids
    start = 0
    while True:
        chunk = tokens[start:start + 254]
        ids = [tokenizer.token_to_id('<s>')] + chunk + [tokenizer.token_to_id('</s>')]
        expected = {'input_ids': ids + [tokenizer.token_to_id('<pad>')] * (256 - len(ids)),
                    'attention_mask': [1] * len(ids) + [0] * (256 - len(ids)),
                    'position_ids': list(range(256)), 'token_type_ids': [0] * 256}
        actual = captured[cursor]
        differences = {name: sum(a != b for a, b in zip(values, actual[name]))
                       + abs(len(values) - len(actual[name])) for name, values in expected.items()}
        rows.append({'case': f'prefix_{repeats}', 'window': cursor, 'real_tokens': len(ids),
                     'different_elements': differences, 'equal': expected == actual})
        cursor += 1
        if start + 254 >= len(tokens):
            break
        start += 190
assert cursor == len(captured), 'Unmatched captured windows'
report = {'schema': 1, 'tokenizers_version': __version__,
          'tokenizer_sha256': hashlib.sha256(args.tokenizer.read_bytes()).hexdigest(),
          'all_equal': all(row['equal'] for row in rows), 'windows': rows}
args.output.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'all_equal': report['all_equal'], 'windows': len(rows)}))
