import sys,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from harness import Worker

def combine(base, redact):
    if 'error' in base or 'error' in redact:
        return {'id':base['id'],'error':'hybrid_child_error'}
    addresses=[p for p in redact['predictions'] if p['entity']=='location' and any(
        q.get('source_entity') in ['STREET_NAME','BUILDING_NUMBER'] and
        p['byte_start']<=q['byte_start']<q['byte_end']<=p['byte_end'] for q in redact['raw_predictions'])]
    predictions=[p for p in base['predictions'] if not(p['entity'] in ['location','street_address'] and any(
        a['byte_start']<=p['byte_start']<p['byte_end']<=a['byte_end'] for a in addresses))]+addresses
    unique={(p['entity'],p['byte_start'],p['byte_end']):p for p in predictions}
    raw=base['raw_predictions']+[q for q in redact['raw_predictions'] if q['entity']=='location' and any(
        a['byte_start']<=q['byte_start']<q['byte_end']<=a['byte_end'] for a in addresses)]
    return {'id':base['id'],'predictions':list(unique.values()),'raw_predictions':raw,
            'address_candidates':len(addresses)}

class Pipeline:
    def __init__(self,profile,log):
        self.profile=profile;self.children=[];started=time.perf_counter()
        try:
            for name in (['efficient','redact_cpu'] if profile=='hybrid' else [profile]):
                self.children.append(Worker(name,str(log)+'-'+name+'.log'))
        except Exception:
            self.close();raise
        self.startup_ms=(time.perf_counter()-started)*1000
        self.metadata=[w.metadata for w in self.children]
    def request(self,row):
        started=time.perf_counter()
        results=[w.request(row) for w in self.children]
        response=combine(*results) if self.profile=='hybrid' else results[0]
        response['roundtrip_ms']=(time.perf_counter()-started)*1000
        return response
    def close(self):
        for child in self.children: child.close()
