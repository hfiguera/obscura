"""New synthetic text, independent of observed candidate predictions."""
import json,hashlib,re
from pathlib import Path
ROOT=Path(__file__).resolve().parent

def row(rid,template,values,kind):
    text='';gold=[];end=0
    for m in re.finditer(r'\{(\w+)\}',template):
        text+=template[end:m.start()];key=m.group(1);value=values[key]
        start=len(text.encode());text+=value
        gold.append({'entity':'location' if key=='address' else key,'byte_start':start,'byte_end':len(text.encode())})
        end=m.end()
    text+=template[end:]
    return {'id':rid,'family':rid,'kind':kind,'supplemental':False,'text':text,'gold':gold}

DEVELOPMENT=[
 'Courier note: {person} can receive the box at {address}.',
 'Delivery label\n{person}\n{address}\nTelephone {phone}',
 'Payment location changed to {address}; notify {email}.',
 'We have only the town, {location}, and no delivery destination.',
 'Name: {person}. Email: {email}.',
 'The warehouse has 90 empty shelves and 6 loading bays.',
 'The state machine processes a zip archive without extracting it.',
 'An address will be requested when checkout opens.',
 'Destination={address}; retry=true.',
 'Please confirm {address} before printing the manifest.',
 '😀 Account holder {person} lives at {address}.',
 'Report downloaded by {person} at {email}.'
]
TEST=[
 'Return authorization: direct the envelope to {person} at {address}.',
 'We corrected the invoice. Its postal destination now reads {address}.',
 'Carrier handoff\nDeliver to: {person}\n{address}\nSignature required.',
 'The subscriber typed "{address}" into the checkout comments.',
 'A technician should report to {address} and ask for {person}.',
 'Could you update the saved destination to {address}? The old label was discarded.',
 '{person} confirmed this location: {address}. Call {phone} on arrival.',
 'Delivery exception — {address} — access code omitted.',
 '😀 Forwarding instruction from {person}: {address}. Thanks!',
 'The warranty form lists recipient={person}; destination={address}; email={email}.',
 'Billing details were supplied in chat: {address}. Keep the original spelling.',
 'Please arrange collection at {address}. A reply may be sent to {email}.',
 'We received a scanned label:\n{person}\n{address}\nEnd of label.',
 'The drop-off address was transcribed as {address}; please verify it.',
 'Registered correspondence should be delivered to {address}, for {person}.',
 'The driver could not locate {address}. The recipient is {person}.',
 'The customer supplied {address} but left the company field blank.',
 'Please mail the access card to:\n{person}\n{address}\nUse tracked postage.',
 'Our meeting takes place in {location}; {person} will join remotely.',
 'The customer named {person} wants an email at {email}.',
 'Incident record: ip={ip_address}; contact={email}.',
 'A callback for {person} is pending on {phone}.',
 'Dispatch staff in {location} could not reach {person}.',
 'Dear {person}, your appointment has been moved. Please check {email}.',
 'City field: {location}. Street field: not supplied.',
 'The signature reads {person}; no postal information was provided.',
 'Form input\nFull name: {person}\nTelephone: {phone}\n',
 'User address in the network log: {ip_address}.',
 'The building has 42 floors and three lifts, all working.',
 'Read chapter 17 before opening the street map.',
 'The address sanitizer rejected an empty buffer.',
 'Build number 730 passed; ZIP extraction took 12 seconds.',
 'The state transition table contains a city column with no values.',
 'Number the avenues for discussion, starting with option 4.',
 'The account has no name, address, telephone or email on file.',
 'The article discusses how postal codes vary by country.',
 'We have 200 sample labels and 16 empty boxes in stock.',
 'The documentation says to replace STREET_NAME with user input.',
 'The second address line must remain empty until checkout.',
 'The service runs on port 8080 and accepts at most 512 records.'
]
NEUTRAL=('The replacement procedure begins with a review of the returned item. '
 'Staff compare its condition with the original shipment record and inspect the packaging. '
 'The inspection notes are attached to the return authorization before a new label is printed. '
 'A supervisor checks the inventory and chooses a suitable dispatch date. ')
TEST += [
 NEUTRAL*8+'The final destination is {address}, for {person}.',
 '{person} requested delivery to {address}. '+NEUTRAL*8,
 NEUTRAL*4+'Carrier destination: {address}. Contact {email}. '+NEUTRAL*4,
 NEUTRAL*8+'The address field is still empty; no recipient has been assigned.',
 'Case summary: '+NEUTRAL*5+'\nDispatch label\n{person}\n{address}\n'+NEUTRAL*3,
 'Notes: '+NEUTRAL*6+'The caller is {person} and their number is {phone}.',
 '😀 '+NEUTRAL*6+'The client entered {address} in the form.',
 NEUTRAL*6+'We checked the manual; the system uses port 3000 and build 14.'
]
DEV_ADDR=['615 Juniper Lane, Salem, OR 97301','29 Orchard Road, York YO1 7HF','84 Hill Street, Bristol BS1 5TR']
ADDR=[
 '482 Willow Drive, Boise, ID 83702','19 Harbour Road, Edinburgh EH6 6LA',
 'Apartment 7, 260 Maple Street, Burlington, VT 05401','73 King Street West, Toronto, ON M5H 1A1',
 '8 Wattle Road, Adelaide SA 5000','PO Box 418, Helena, MT 59601',
 'Suite 210, 935 Beacon Avenue, Tacoma, WA 98402','14 Rue des Érables, Ottawa, ON K1N 5T5',
 '650 North Pine Road\nMadison, WI 53703','Unit 12, 48 Victoria Street, Manchester M1 6DP',
 '1225 Lakeview Boulevard, Austin, TX 78701','Flat 3B, 61 Mill Road, Cambridge CB1 2AW']
NAMES=['Tessa Morgan','Victor Ramos','Élodie Marchand','Darius Cole','Mina Okafor','Patrick Walsh','Naomi Tanaka','Felix Meyer']
manifest={'schema':1,'provenance':'Fresh assistant-authored synthetic English; no candidate predictions used. Not production or human-annotated data.','files':{}}
for split,templates in [('development',DEVELOPMENT),('test',TEST)]:
 rows=[]
 for i,t in enumerate(templates):
  values={'address':(DEV_ADDR if split=='development' else ADDR)[i%len(DEV_ADDR if split=='development' else ADDR)],
          'person':(['Selena Woods','Hugo Martins','Imani Drake'] if split=='development' else NAMES)[i%(3 if split=='development' else len(NAMES))],
          'location':['Denver','Glasgow','Vancouver','Perth'][i%4], 'email':f'contact{i}@example.test',
          'phone':f'(303) 555-{100+i:04d}','ip_address':'2001:db8:8::45' if i%2 else '192.0.2.74'}
  rows.append(row(f'{split}-{i:02d}',t,values,'long' if i>=40 and split=='test' else 'positive' if '{' in t else 'negative'))
 p=ROOT/f'{split}.json';assert not p.exists(),p
 payload=(json.dumps(rows,ensure_ascii=False,indent=2)+'\n').encode();p.write_bytes(payload)
 manifest['files'][split]={'sha256':hashlib.sha256(payload).hexdigest(),'rows':len(rows),'gold':sum(len(x['gold']) for x in rows),'negative_rows':sum(not x['gold'] for x in rows)}
manifest['policy_sha256']=hashlib.sha256((ROOT/'POLICY.md').read_bytes()).hexdigest()
(ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest))
