#!/usr/bin/env python3
"""Fresh assistant-authored English synthetic evaluation text; no evaluated-model predictions.

Development and test use distinct templates and name pools. This is a diagnostic
application-style corpus, not sampled production traffic or a population estimate.
Do not change a frozen corpus after seeing test predictions.
"""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).parent
PRIMARY = ['person', 'location', 'email', 'phone', 'us_ssn', 'credit_card', 'ip_address', 'url', 'iban']
NAMES = {
 'development': ['Ethan Brooks', 'June Park', 'Isabel Costa', 'Noah Patel', 'Lena Fischer', 'Owen Reed', 'Maya Bell', 'Arun Shah'],
 'test': ['Amelia Hart', 'May Jordan', 'Zoë O’Neill', 'Marcus Wells', 'José Alvarez', 'Robin West', 'Grace Li', 'Sam Carter', 'Nora van Dijk', 'Lee Morgan', 'Aisha Khan', 'Dylan Price', 'Chloë Martin', 'Alex Stone', 'Priya Rao', 'Louis Bernard', 'Jean-Luc Moreau', 'Rose Winter']}
DEV = [
 'Please ask {{person}} to review the refund request.',
 'The caller is {{person}}. A reply can go to {{email}}.',
 'Our technician will meet {{person}} in {{location}}.',
 'Customer: {{person}}\nPhone: {{phone}}\nPreferred contact: email.',
 'Forward the receipt to {{email}} and call {{phone}} if it bounces.',
 'Delivery destination: {{address}}. Recipient: {{person}}.',
 'The client connected from {{ip_address}} while visiting {{url}}.',
 'The bank transfer instructions specify IBAN {{iban}}.',
 'Card number {{credit_card}} was entered in the payment form.',
 'The identity form contains SSN {{us_ssn}} for {{person}}.',
 'Do you have an update for {{person}} or {{person2}}?',
 'The message says “{{person}} moved to {{location}}.”',
 '😀 Owner: {{person}}; contact: {{email}}.',
 'We cannot reach {{person}} on {{phone}}. Leave the ticket open.',
 'No personal details are present in the retry log.',
 'The job completed in three steps and the queue is empty.',
 'May the next build finish before the scheduled maintenance?',
 'The release notes discuss memory, threads, and error handling.',
 'The client asked for a slower retry interval. The team reviewed the request and agreed that the queue should stay open. ' * 12 + 'The contact is {{person}} in {{location}}, at {{email}}.',
 '{{person}} requested a callback on {{phone}}. ' + 'The remaining notes describe the storage queue and the proposed retry sequence. ' * 18,
]
TEST = [
 'I spoke with {{person}} about the duplicate charge. Please attach the transcript to the case.',
 'Has {{person}} approved the replacement? The warehouse is waiting for a reply.',
 '{{person}} asked whether their account could be restored without losing saved preferences.',
 'The previous owner was {{person}}; the new owner is {{person2}}. Keep both names in the handover record.',
 'According to {{person}}, the parcel never reached {{location}}.',
 'We found an earlier conversation with {{person}} in the archive.',
 'For the attention of {{person}}: please confirm that {{email}} is still your preferred address.',
 'A callback to {{phone}} was requested by {{person}} after the chat ended.',
 'Reply-To: {{email}}\nMessage: I have not received a confirmation.\nSignature: {{person}}',
 '{"contact":"{{person}}","email":"{{email}}","phone":"{{phone}}"}',
 '😀 The person assigned to this case is {{person}}. Their office is in {{location}}.',
 '“{{person}}” appears in the scanned signature. The form also lists {{phone}}.',
 'Dr. {{person}} will collect the package from {{location}}.',
 'The request came from {{location}}, but the delivery address is {{address}}.',
 'Send the replacement to {{person}}, {{address}}. Please use the side entrance.',
 'My new address is {{address}}. The account holder is {{person}}.',
 'Shipment recipient\n{{person}}\n{{address}}\nContact {{phone}} if access is blocked.',
 'The billing address on the form reads {{address}}; it has not been verified.',
 'We can schedule an appointment in {{location}} or contact {{person}} remotely.',
 'The audit entry records client_ip={{ip_address}} and user_email={{email}}.',
 'Browser history included {{url}}. The support agent copied it into the case notes.',
 'The application posted the reply to {{url}} from {{ip_address}}.',
 'Payment details copied into chat: card {{credit_card}}, name {{person}}.',
 'The transfer was rejected. Please check the IBAN {{iban}} against the original instruction.',
 'The customer accidentally pasted {{us_ssn}} into the SSN field of the support form.',
 'Please remove the card {{credit_card}} and SSN {{us_ssn}} from the exported notes.',
 'The first message mentions {{email}}. A later message repeats {{email}} with the same spelling.',
 'I cannot remember the case number, but {{person}} was the person who helped me.',
 'May I retry the failed upload after the queue drains?',
 'The orange button opens a preview. The green button submits the form.',
 'Spring and winter themes share the same layout and validation rules.',
 'A worker crashed during the request. Restarting it restored normal service.',
 'Please read the manual before changing the storage policy or timeout.',
 'There are four pending tasks and two idle workers. No action is required.',
 'The next step is to compare the old result with the new result.',
 'Contact names and addresses were omitted from this export by the operator.',
]
LONG_A = ('The support team reviewed the upload sequence after the customer reported an incomplete preview. '
 'The original file was accepted and the processing queue returned a successful acknowledgement. '
 'A stale cache entry caused the dashboard to display the previous result. '
 'The operator checked the retry policy, compared the event order, and confirmed that no messages were lost. '
 'The proposed fix refreshes the preview after the background task completes. '
 'The team will verify the change with a small upload and then repeat the check with a larger attachment. ')
LONG_B = ('The incident review began with a comparison of the browser trace and the application log. '
 'A reconnect occurred while the response was still being assembled. '
 'The first attempt was cancelled, but the second attempt completed normally. '
 'The operator documented the sequence and asked the team to retain the diagnostic record. '
 'No data repair was needed and the existing retry policy was left in place. '
 'The follow-up check will exercise a delayed response and a temporary loss of connectivity. ')
TEST += [
 LONG_A + 'The customer is {{person}}, based in {{location}}; their email is {{email}}.',
 'The customer is {{person}} in {{location}}, using {{email}}. ' + LONG_A,
 LONG_A + 'Call {{person}} on {{phone}}. ' + LONG_B,
 LONG_A * 3 + 'Deliver to {{person}} at {{address}}.',
 'The account belongs to {{person}}. ' + LONG_B * 4 + 'Reply to {{email}}.',
 LONG_A * 2 + 'The requester is {{person}} in {{location}}. ' + LONG_B * 2,
 LONG_A * 4 + LONG_B * 3,
 LONG_B + 'The copied payment details were {{credit_card}} and {{iban}}. ' + LONG_A,
]
SUPPLEMENTAL = [
 'The appointment date is {{date_time}}. Please retain it in the calendar export.',
 'Employer: {{organization}}. The department approved the request.',
 'The account domain is {{domain}}. It has no URL scheme.',
 'Government document number: {{government_id}}. The support team should not retain it.',
]


def values(split, index):
    names = NAMES[split]
    name = names[index % len(names)]
    person2 = names[(index + 5) % len(names)]
    cities = ['Boston', 'Seattle', 'Denver', 'Portland', 'Austin', 'Chicago', 'London', 'Bristol']
    addresses = ['123 Maple Street, Springfield, IL 62704', '48 Willow Road, Apt 7, Boston, MA 02110',
                 '720 Cedar Avenue, Seattle, WA 98104', '9 Meadow Lane, Bristol BS1 4ST']
    return {'person': name, 'person2': person2,
            'email': f'contact{index}@example.test', 'phone': f'(202) 555-{100 + index % 100:04d}',
            'location': cities[index % len(cities)], 'address': addresses[index % len(addresses)],
            'ip_address': f'192.0.2.{index % 200 + 1}' if index % 2 == 0 else f'2001:db8::{index + 1:x}',
            'url': f'https://support.example.test/cases/{index + 100}',
            'credit_card': ['4111 1111 1111 1111', '5555 5555 5555 4444'][index % 2],
            'iban': ['GB82 WEST 1234 5698 7654 32', 'DE89 3704 0044 0532 0130 00'][index % 2],
            'us_ssn': ['123-45-6789', '078-05-1120'][index % 2],
            'date_time': '2031-04-17', 'organization': 'Cedarfield Research',
            'domain': 'customer.example.test', 'government_id': 'AB1234567'}


def render(template, supplied):
    text, gold, cursor = '', [], 0
    for match in re.finditer(r'\{\{(\w+)\}\}', template):
        text += template[cursor:match.start()]
        key = match[1]
        value = supplied[key]
        entity = {'person2': 'person', 'address': 'location'}.get(key, key)
        start = len(text.encode())
        text += value
        gold.append({'entity': entity, 'byte_start': start, 'byte_end': len(text.encode())})
        cursor = match.end()
    text += template[cursor:]
    return text, gold


def main():
    target = ROOT / 'data'
    target.mkdir(exist_ok=True)
    manifest = {'schema': 1, 'provenance': 'Assistant-authored synthetic English during this evaluation; no external dataset or evaluated-model predictions used',
                'limitations': 'Template families and a finite name pool; not sampled production data, human-audited language coverage, or an estimate of population accuracy',
                'primary_entities': PRIMARY, 'files': {}}
    for split, templates, variants in [('development', DEV, 2), ('test', TEST + SUPPLEMENTAL, 3)]:
        rows = []
        for family, template in enumerate(templates):
            for variant in range(variants):
                text, gold = render(template, values(split, family * variants + variant))
                rows.append({'id': f'{split}-{family:02d}-{variant}', 'family': f'{split}-{family:02d}',
                    'supplemental': split == 'test' and family >= len(TEST),
                    'kind': 'negative' if not gold else 'long' if len(text.encode()) > 500 else 'positive',
                    'text': text, 'gold': gold})
        payload = (json.dumps(rows, ensure_ascii=False, indent=2) + '\n').encode()
        path = target / f'{split}.json'
        if path.exists() and path.read_bytes() != payload:
            raise RuntimeError(f'Refusing to overwrite frozen {path}; use an explicitly versioned corpus')
        path.write_bytes(payload)
        manifest['files'][split] = {'sha256': hashlib.sha256(payload).hexdigest(), 'rows': len(rows),
            'families': len(templates), 'gold_spans': sum(len(r['gold']) for r in rows),
            'negative_rows': sum(not r['gold'] for r in rows), 'long_rows': sum(r['kind'] == 'long' for r in rows)}
    (ROOT / 'corpus-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest['files'], indent=2))


if __name__ == '__main__': main()
