"""Exact canonical spans and original-span privacy coverage. No prediction text."""
from collections import Counter
from harness import PRIMARY


def metrics(tp, fp, fn):
    p=tp/(tp+fp) if tp+fp else 0.0
    r=tp/(tp+fn) if tp+fn else 0.0
    return {'tp':tp,'fp':fp,'fn':fn,'precision':p,'recall':r,'f1':2*p*r/(p+r) if p+r else 0.0}


def score(rows, results):
    by_id={r['id']:r for r in results}
    if len(by_id)!=len(rows) or set(by_id)!={r['id'] for r in rows}: raise ValueError('Incomplete or duplicate predictions')
    counts={e:Counter() for e in PRIMARY}
    coverage=Counter(); negatives=Counter(); errors=0; unmapped=Counter(); supplemental=[]
    for row in rows:
        result=by_id[row['id']]
        errors += 'error' in result
        raw=result.get('raw_predictions',[])
        predicted={(p['entity'],p['byte_start'],p['byte_end']) for p in result.get('predictions',[]) if p['entity'] in PRIMARY}
        expected={(g['entity'],g['byte_start'],g['byte_end']) for g in row['gold'] if g['entity'] in PRIMARY}
        for p in raw:
            if p['entity'] not in PRIMARY and p['entity']!='street_address': unmapped[p['entity']]+=1
        if not row.get('supplemental'):
            for e in PRIMARY:
                counts[e]['tp']+=sum(x[0]==e for x in predicted & expected)
                counts[e]['fp']+=sum(x[0]==e for x in predicted-expected)
                counts[e]['fn']+=sum(x[0]==e for x in expected-predicted)
        if not row['gold']:
            negatives['rows']+=1
            negatives['changed_rows']+=bool(raw)
            negatives['detections']+=len(raw)
        characters=[]; offset=0
        for char in row['text']:
            end=offset+len(char.encode())
            covered=any(p['byte_start']<=offset and end<=p['byte_end'] for p in raw)
            characters.append((offset,end,char,covered));offset=end
        for gold in row['gold']:
            chars=[x for x in characters if gold['byte_start']<=x[0] and x[1]<=gold['byte_end']]
            alnum=[x[3] for x in chars if x[2].isalnum()]
            strict=[x[3] for x in chars if not x[2].isspace()]
            category='fully_covered' if all(alnum) else 'partially_exposed' if any(alnum) else 'fully_exposed'
            if row.get('supplemental'):
                supplemental.append({'id':row['id'],'entity':gold['entity'],'coverage':category})
            else:
                coverage[category]+=1
                coverage['alnum_characters']+=len(alnum);coverage['covered_alnum_characters']+=sum(alnum)
                coverage['strict_nonspace_characters']+=len(strict);coverage['covered_strict_nonspace_characters']+=sum(strict)
    per_entity={e:metrics(c['tp'],c['fp'],c['fn']) for e,c in counts.items()}
    total=metrics(*(sum(c[k] for c in counts.values()) for k in ['tp','fp','fn']))
    return {'exact':total,'per_entity':per_entity,'coverage':dict(coverage),'negative_text':dict(negatives),
            'error_rows':errors,'additional_raw_labels':dict(unmapped),'supplemental':supplemental}
