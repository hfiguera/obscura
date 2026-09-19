"""Author the blog's SVG scenes with Python's standard library.
Run from any directory after changing geometry; generated HTML and catalog are committed.
The Elixir site build reads the committed output and does not require Python.
"""
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CATALOG = {}

def attrs(**kw):
    return ''.join(f' {k.replace("_", "-")}="{html.escape(str(v), quote=True)}"' for k,v in kw.items() if v is not None)
def el(tag, body='', **kw): return f'<{tag}{attrs(**kw)}>{body}</{tag}>'
def text(x,y,value,kind='body',**kw): return el('text',html.escape(value),x=x,y=y,**{'class':f'art-{kind}'},**kw)
def rect(x,y,w,h,kind='panel',**kw): return el('rect',x=x,y=y,width=w,height=h,rx=kw.pop('rx',5),**{'class':f'art-{kind}'},**kw)
def path(d,kind='wire',**kw): return el('path',d=d,**{'class':f'art-{kind}'},**kw)
def group(body,x=0,y=0,**kw): return el('g',body,transform=f'translate({x} {y})',**kw)
def show(start,end): return {'data_show':f'{start} {end}'}
def hide(start,end): return {'data_hide':f'{start} {end}','opacity':'0'}
def shift(start,end,x,y): return {'data_shift':f'{start} {end} {x} {y}'}
def line(x1,y1,x2,y2,start=None,end=None):
    return path(f'M{x1} {y1}L{x2} {y2}', 'signal' if start else 'wire', **({'pathLength':1,'data_draw':f'{start} {end}'} if start else {}))
def label(x,y,s): return text(x,y,s,'label')
def code(x,y,s,kind='code',**kw): return text(x,y,s,kind,**kw)
def chip(x,y,s,w=166,**kw):
    return group(rect(0,0,w,32,'chip',rx=3)+code(12,21,s,'token'),x,y,**kw)
def travel(x1,y1,x2,y2,s,start,end,w=166):
    # Resting markup is invisible; only the moving protected representation appears.
    return group(chip(0,0,s,w),0,0,data_flight=f'{start} {end} {x1} {y1} {x2} {y2}',opacity=0)
def wipe(x,y,raw,safe,start,w=230):
    return group(code(0,20,raw,'raw',**hide(start+480,start+500)) + code(0,20,safe,'token',**show(start+480,start+500)) + rect(0,0,0,28,'mask',rx=2,data_mask=f'{start} {start+550} {start+1150} {w}'),x,y)
def panel(x,y,w,h,title,content='',kind='panel',**kw):
    return group(rect(0,0,w,h,kind)+label(18,28,title)+path(f'M0 43H{w}','rule')+content,x,y,**kw)
def check(x,y,start=9000): return group(path('M0 7L5 12L15 0','signal'),x,y,**show(start,start+350))
def make(slug,title,intro,description,captions,draw,note='Illustrative sequence · synthetic examples'):
    CATALOG[slug] = dict(title=title,intro=intro,description=description,captions=captions,note=note)
    results=[]
    for mobile in [False,True]:
        name='narrow' if mobile else 'wide'
        content,height=draw(mobile)
        svg=el('svg',el('title',html.escape(title),id=f'scene-title-{name}')+el('desc',html.escape(description),id=f'scene-desc-{name}')+content,
               **{'class':f'request-scene-art request-scene-{name}','viewBox':f'0 0 {380 if mobile else 960} {height}','fill':'none','role':'img','aria-labelledby':f'scene-title-{name} scene-desc-{name}'})
        results.append(svg)
    (ROOT/f'{slug}.html').write_text('\n'.join(results)+'\n')

# 1. The backing allocation breaks apart only after the result owns its bytes.
def memory(m):
    ax,ay,aw,ah=(24,40,332,180) if m else (28,54,390,236)
    rx,ry=(24,334) if m else (580,78)
    ox,oy=(24,470) if m else (580,274)
    s=label(ax,ay-15,'INPUT ALLOCATION')+rect(ax,ay,aw,ah,'outline')
    cols,rows=(12,4) if m else (14,5)
    cells=''
    for i in range(cols*rows):
        x=12+(i%cols)*((aw-24)/cols); y=14+(i//cols)*26
        cells+=rect(x,y,19,16,'memory',rx=1,**hide(6800+i*18,7500+i*18),data_drift=f'6800 8800 {(i%5-2)*15} {-15-i%3*8}')
    s+=group(cells,ax,ay)
    s+=group(code(14,ah-23,'≈ 1 MB request','raw'),ax,ay,**hide(7000,7700))
    s+=text(ax+18,ay+ah/2,'Allocation can be reclaimed','body',**show(8700,9500))
    s+=text(ax+18,ay+ah/2+25,'when no other references remain.','muted',**show(8900,9600))
    s+=panel(rx,ry,300,96,'BORROWED RESULT',code(18,76,'alice@example.com','raw'),**hide(5800,6700))
    s+=text(rx,ry+42,'Borrowed reference released.','muted',**show(6900,7500))
    route=f'M{rx+150} {ry}V{ay+ah+28}H{ax+aw/2}V{ay+ah}' if m else f'M{rx} {ry+64}H{ax+aw}'
    s+=path(route,'borrow',**hide(5800,6500))
    s+=text(24 if m else 447,280 if m else 123,'reference','muted',**hide(5800,6500))
    s+=panel(ox,oy,300,96,'OWNED RESULT',code(18,76,'alice@example.com','token'),kind='safe',**show(4000,4800))
    s+=travel(rx+18,ry+53,ox+18,oy+53,'17 owned bytes',4300,5700,180)
    s+=check(ox,oy+123,9000)+text(ox+26,oy+135,'Independent bytes. Still PII.','body',**show(9000,9500))
    return s,640 if m else 460
make('making-pii-detection-faster-without-keeping-input-alive','Let the input go.\nKeep only the result.','Watch a borrowed slice become an owned result before the backing allocation is released.',
'A small sub-binary retains a large request. Copying the selected result gives it independent ownership, allowing the input allocation to be reclaimed when no references remain. The owned email is still PII.',
[[0,'A 17-byte match can retain the allocation behind a roughly one-megabyte request.'],[3800,'Copy only the selected data that will escape, after filtering.'],[5800,'The result now owns its bytes. The borrowed reference detaches.'],[8500,'The input can be reclaimed when no other references remain. This does not erase the PII in the result.']],memory)

# 2. A vault anchors a round trip through the model and a trusted lookup.
def agent(m):
    vx,vy=(24,32) if m else (26,50)
    mx,my=(24,248) if m else (610,50)
    tx,ty=(24,446) if m else (610,264)
    ux,uy=(24,650) if m else (26,310)
    w=332 if m else 300
    s=panel(vx,vy,w,162,'APPLICATION · SESSION VAULT',code(18,75,'jane@example.com','raw')+code(18,113,'<<EMAIL_001>>','token',**show(1100,1750))+text(18,143,'The identity mapping stays here.','muted'))
    s+=panel(mx,my,w,130,'MODEL',code(18,80,'<<EMAIL_001>>','token',**show(3000,3500))+text(18,109,'Stable reference, no raw identity.','muted'))
    s+=panel(tx,ty,w,146,'TRUSTED TOOL',code(18,76,'jane@example.com','raw',**show(4900,5400))+text(18,105,'Restore for a narrow local lookup.','muted')+code(18,132,'<<EMAIL_001>>','token',**show(6500,7200)))
    s+=panel(ux,uy,w,106,'TRUSTED APPLICATION VIEW',code(18,78,'jane@example.com','raw',**show(9300,9900)))
    if m:
        s+=line(190,194,190,248)+line(190,378,190,446)+line(190,592,190,650)
        s+=rect(16,238,348,150,'boundary',rx=7)+label(24,415,'MODEL BOUNDARY')
    else:
        s+=line(326,131,610,131)+line(760,180,760,264)+path('M610 377H430V363H326')
        s+=rect(596,36,328,158,'boundary',rx=7)+label(610,225,'MODEL BOUNDARY')
    s+=travel(vx+18,vy+89,mx+18,my+57,'<<EMAIL_001>>',1600,3250)
    s+=travel(mx+18,my+57,tx+18,ty+110,'<<EMAIL_001>>',3500,4800)
    s+=travel(tx+18,ty+110,mx+18,my+57,'<<EMAIL_001>>',6800,8250)
    s+=travel(mx+18,my+57,ux+18,uy+56,'<<EMAIL_001>>',8350,9400)
    return s,794 if m else 470
make('the-agent-needs-identity-the-model-does-not','Identity stays here.\nTokens make the trip.','A stable pseudonym travels through the model and tools. Its mapping stays in the application.',
'A local vault maps a synthetic email to EMAIL_001. Only the token reaches the model. A trusted tool restores identity for a local lookup and protects the result again. The complete answer is restored in the trusted application view.',
[[0,'Create a session-scoped mapping inside the trusted application.'],[1600,'Only the pseudonym crosses into the model request.'],[4400,'A trusted tool restores one identifier for a narrow local lookup.'],[6500,'Protect the tool result before returning it to the model.'],[9000,'Keep streaming tokenized. Restore only after the complete answer reaches the trusted view.']],agent)

# 3. Detection splits into two distinct outbound policies.
def protect(m):
    x,y=24,42
    rx,ry=(24,285) if m else (360,42)
    px,py=(24,455) if m else (360,232)
    lx,ly=(24,665) if m else (690,42)
    vx,vy=(24,803) if m else (690,232)
    w=332 if m else 278
    s=panel(x,y,w,178,'LOCAL INPUT',code(18,82,'info@acme.example','raw')+code(18,128,'202-555-0188','raw'))
    s+=group(rect(11,59,w-22,31,'recognition',rx=2)+label(w-73,53,'EMAIL'),x,y,**show(650,1400))
    s+=group(rect(11,105,w-22,31,'recognition',rx=2)+label(w-73,153,'PHONE'),x,y,**show(1400,2050))
    s+=panel(rx,ry,w,132,'REDACT FOR LOGS',wipe(18,60,'info@acme.example','[EMAIL]',2800,w-36))
    s+=panel(px,py,w,150,'PSEUDONYMIZE FOR THE MODEL',wipe(18,60,'info@acme.example','<<EMAIL_001>>',4200,w-36)+code(18,126,'<<PHONE_001>>','token',**show(5300,5900)))
    s+=panel(lx,ly,w-12,96,'LOG RECORD',code(18,77,'[EMAIL] · [PHONE]','token',**show(7400,8000)))
    s+=panel(vx,vy,w-12,118,'MODEL MESSAGE',code(18,76,'<<EMAIL_001>>','token',**show(8850,9400))+code(18,102,'<<PHONE_001>>','token',**show(9300,9750)))
    if not m:
        s+=path('M302 131H330V306H360M330 113H360M638 110H690M638 306H690')
        s+=label(26,314,'APPLICATION OWNS THE ORIGINAL')+text(26,341,'Choose policy at each exit.','muted')
    s+=travel(rx+18,ry+58,lx+18,ly+55,'[EMAIL]',6200,7600,138)
    s+=travel(px+18,py+58,vx+18,vy+54,'<<EMAIL_001>>',7600,9000)
    return s,955 if m else 430
make('protecting-pii-in-elixir','Find it locally.\nProtect each exit.','One input branches into a redacted log record and a pseudonymized model message.',
'Local detection identifies an email and phone number. Redaction replaces values with entity labels for logs. Pseudonymization preserves stable references for model messages. Detection is not a guarantee that all sensitive data is found.',
[[0,'Recognize structured identifiers locally, before they reach a downstream system.'],[2600,'For a log record, replace the sensitive values with entity labels.'],[4200,'For a model message, keep relationships through stable pseudonyms.'],[6200,'Send the representation selected for each boundary.'],[9500,'Every exit needs a policy. Detection can still miss sensitive values.']],protect)

# 4. Realtime raw metadata is preserved on the input side; the emitted copy is bounded.
def realtime(m):
    x,y=24,44; ox,oy=(24,386) if m else (582,44); w=332 if m else 332
    raw=[('topic','room:customer-42'),('event','new_message'),('parameters','{ customer data }'),('connect_info','{ client metadata }')]
    content=''
    for i,(k,v) in enumerate(raw): content+=text(18,72+i*58,k,'muted')+code(18,96+i*58,v,'raw')
    s=panel(x,y,w,300,'PHOENIX TELEMETRY',content)
    output=[('topic','room:*',2800),('event','new_message',4700),('parameters','[OMITTED]',6500)]
    content=''
    for i,(k,v,t) in enumerate(output):
        content+=group(text(18,72+i*64,k,'muted')+code(18,99+i*64,v,'token'),**show(t+1000,t+1550))
        s+=travel(x+18,y+79+i*58,ox+18,oy+79+i*64,v,t,t+1200,170)
    s+=panel(ox,oy,w,282,'OPERATIONAL RECORD',content)
    if m:
        s+=line(190,344,190,386)+path('M24 365H356','boundary')
    else:
        s+=path('M356 166H582')+path('M468 36V376','boundary')
        s+=label(388,395,'OMIT · NORMALIZE · ALLOWLIST')
    s+=check(ox,oy+311,8900)+text(ox+26,oy+323,'No connect_info in this record.','body',**show(8900,9400))
    return s,754 if m else 440
make('privacy-safe-phoenix-realtime-logging','Keep the event.\nLeave the payload.','Raw telemetry stays on one side. A small, controlled vocabulary reaches the log.',
'A raw channel topic becomes room:*, an allowlisted new_message event is retained, parameters become OMITTED, and connect_info is excluded from the record. The raw telemetry itself is not rewritten.',
[[0,'Socket and channel telemetry already contains raw, client-controlled values.'],[2600,'Use the configured topic pattern instead of a raw topic identifier.'],[4400,'Emit event names from the startup allowlist. Unknown names get a fixed label.'],[6300,'Omit payloads by default and exclude connect_info.'],[9000,'The handler protects only the record it emits. Other telemetry consumers need their own policy.']],realtime)

# 5. Two recognizers scan the same three spans, with different coverage.
def efficient(m):
    w=332 if m else 430; x1,y1=24,44; x2,y2=(24,402) if m else (506,44)
    rows=[('email','rachel.chen@example.test','<<EMAIL_001>>'),('person','Rachel Chen','<<PERSON_001>>'),('location','London','<<LOCATION_001>>')]
    s=''
    for efficient_lane,x,y in [(False,x1,y1),(True,x2,y2)]:
        content=''
        for i,(label_,raw,safe) in enumerate(rows):
            yy=80+i*75
            content+=text(18,yy-10,label_,'muted')
            content+=wipe(18,yy,raw,safe,2000 if i==0 else 4050+(i-1)*1700,w-36) if efficient_lane or i==0 else code(18,yy+20,raw,'raw')
        s+=panel(x,y,w,296,':efficient · CPU NER' if efficient_lane else ':fast · deterministic',content)
        s+=text(x,y+326,'More context, more coverage.' if efficient_lane else 'These name and location spans remain.', 'muted',**show(7700,8300))
    yy=775 if m else 416
    s+=group(line(24,yy-22,356 if m else 936,yy-22)+text(24,yy,'Heldout tradeoff vs. :fast','body')+text(24,yy+29,'1,993 fewer missed exact spans','positive')+text(24 if m else 506,yy+55 if m else yy+29,'3,044 more false positives','warning'),**show(8700,9500))
    return s,867 if m else 489
make('beyond-regex-why-we-shipped-a-cpu-profile-for-pii-detection','Same request.\nMore context.','Two profiles inspect the same email, person, and place from the article’s synthetic request.',
'Both profiles mask the email. In this example the fast profile misses Rachel Chen and London, while efficient masks them as person and location. The heldout evaluation also has more false positives with efficient.',
[[0,'The input and requested entity types are the same for both profiles.'],[2000,'Both profiles recognize and pseudonymize the structured email.'],[4000,'Local CPU NER recognizes the name Rachel Chen.'],[5700,'It also recognizes London. The fast output keeps both spans in this example.'],[8500,'The heldout tradeoff matters: 1,993 fewer missed exact spans and 3,044 more false positives.']],efficient,'Illustrative sequence · article’s Obscura 0.2.0 outputs and heldout counts')

# 6. Exact additions are counted dots, not decorative benchmark bars.
def hybrid(m):
    s=label(24,27,'163 ADDED SPANS · ONE SQUARE PER SPAN')
    groups=[(69,'Exact phones','positive'),(18,'Exact URLs','positive'),(76,'Other outcomes','warning')]
    for j,(count,title,kind) in enumerate(groups):
        gx,gy=(24,70+j*172) if m else (24+j*316,84)
        cols=12; cells=''
        for i in range(count):
            dx=(i%cols)*20; dy=(i//cols)*18
            # Deterministic scattered start, resolved into countable rows by classification.
            cells+=rect(dx,dy,12,10,kind,rx=1,**shift(1200+j*1350+i*8,2900+j*1350+i*8,((i*29+j*71)%170)-85,((i*17)%70)-35))
        s+=group(cells,gx,gy)
        s+=text(gx,gy+147,f'{count} · {title}','body',**show(2400+j*1350,3100+j*1350))
    yy=621 if m else 289
    s+=group(path(f'M24 {yy-24}H{356 if m else 936}','rule')+text(24,yy,'Follow the useful signal','body')+text(24,yy+30,'18 URL gains recovered by a rule.','positive')+text(24,yy+55,'The probe found six more.','muted'),**show(7000,7900))
    s+=group(rect(24,yy+82,332 if m else 610,60,'outline')+text(42,yy+108,'Runtime decision: do not ship the hybrid.','body')+text(42,yy+130,'Use the model to improve smaller recognizers.','muted'),**show(9000,9700))
    return s,807 if m else 477
make('an-ai-hybrid-improved-pii-detection-we-still-did-not-ship-it','A better score.\nA closer look.','Watch 163 added spans sort into the outcomes that changed the shipping decision.',
'The contact hybrid added 163 spans: 69 exact phones, 18 exact URLs, and 76 other outcomes comprising 3 boundary mismatches, 26 wrong types, and 47 false positives. A deterministic probe recovered all 18 URL gains and six more.',
[[0,'The contact-only hybrid improved the aggregate exact-span F1. What did it actually add?'],[1200,'Sort the added spans by outcome instead of judging only the total score.'],[5500,'87 exact additions are phones and URLs. The other 76 are boundary mismatches, wrong types, or false positives.'],[7000,'The deterministic URL probe recovers all 18 URL gains and finds six more.'],[9000,'Use that evidence to improve smaller recognizers. Do not add the hybrid runtime dependency.']],hybrid,'Illustrative sorting · counts from the article’s incremental error analysis')

# 7. Different routes through two real architecture choices, without a winner badge.
def architecture(m):
    if m:
        s=label(24,27,'SEPARATELY OPERATED SERVICE')
        s+=panel(24,44,332,100,'ELIXIR APPLICATION',code(18,77,'Request data','raw'))
        s+=panel(24,230,332,112,'PRESIDIO SERVICE',text(18,76,'Detection + policy','body')+text(18,98,'Independent operation','muted'))
        s+=line(108,144,108,230)+line(266,230,266,144)
        s+=travel(44,111,44,275,'request',1600,3050,115)+travel(202,275,202,111,'protected',3650,5100,128)
        s+=label(24,408,'INSIDE THE BEAM')+rect(24,426,332,272,'outline')+label(42,454,'ELIXIR APPLICATION')
        s+=code(42,503,'Native values','raw')+panel(42,543,296,127,'OBSCURA · LOCAL BOUNDARY',text(18,76,'Detection + policy','body')+text(18,101,'Application-owned integration','muted'))
        s+=travel(42,483,60,596,'request',5900,7300,115)+travel(60,596,42,483,'protected',7700,9050,128)
        s+=text(24,743,'Both can be valid. Choose who owns','body')+text(24,767,'the deployment and failure boundary.','body')
        return s,805
    s=label(24,32,'SEPARATELY OPERATED SERVICE')
    s+=panel(24,52,290,128,'ELIXIR APPLICATION',code(18,84,'Request data','raw'))
    s+=panel(652,52,282,128,'PRESIDIO SERVICE',text(18,80,'Detection + policy','body')+text(18,105,'Independent operation','muted'))
    s+=path('M314 106H652M652 145H314')+path('M487 45V194','boundary')
    s+=travel(314,82,652,82,'request',1600,3050,115)+travel(652,127,314,127,'protected',3650,5100,128)
    s+=label(24,253,'INSIDE THE BEAM')+rect(24,276,910,150,'outline')+label(42,303,'ELIXIR APPLICATION')
    s+=code(42,364,'Native values','raw')+panel(534,295,375,112,'OBSCURA · LOCAL BOUNDARY',text(18,77,'Detection + application policy','body'))
    s+=path('M270 339H534M534 382H270')
    s+=travel(270,318,534,318,'request',5900,7300,115)+travel(534,364,270,364,'protected',7700,9050,128)
    return s,465
make('should-pii-detection-live-inside-the-beam','Two routes.\nTwo kinds of ownership.','Follow the request through a separate privacy service, then through a local BEAM boundary.',
'A separate Presidio service receives a request and returns a protected representation across a network boundary. An Obscura local boundary transforms values inside the Elixir application. Either can be valid; the architectures have different operating and failure boundaries.',
[[0,'A service architecture separates the application from the privacy runtime.'],[1500,'The request crosses a network boundary to the independently operated service.'],[3500,'The protected representation returns to the application.'],[5800,'With a local Obscura boundary, the transformation stays next to the Elixir values.'],[9200,'Both architectures can be correct. Choose deployment ownership, data movement, and failure handling deliberately.']],architecture)

# 8. A proof chain lights a chip only when execution evidence is reached.
def gpu(m):
    cx,cy=(100,504) if m else (666,126)
    labels=[('CPU baseline','Phoenix + :fast'),('CUDA device','EXLA discovery'),('Compiled operation','EXLA.Backend tensor'),('Device consumer','beam.smp on CUDA'),('Model serving',':balanced + :accurate')]
    s=''
    for i,(title,detail) in enumerate(labels):
        y=48+i*84; start=450+i*1900
        s+=el('circle',cx=40,cy=y,r=11,**{'class':'art-outline'})+el('circle',cx=40,cy=y,r=5,**{'class':'art-positive'},**show(start,start+500))
        if i<4: s+=line(40,y+11,40,y+73)+line(40,y+11,40,y+73,start+400,start+1600)
        s+=text(65,y+5,title,'body')+code(65,y+29,detail,'muted')
    chipbody=rect(0,0,164,164,'outline',rx=7)+rect(22,22,120,120,'panel',rx=3)
    for i in range(7):
        z=25+i*19
        chipbody+=path(f'M{z} -12V0M{z} 164V176M-12 {z}H0M164 {z}H176','wire')
    chipbody+=rect(38,38,88,88,'chip',rx=2,**show(4300,4900))+text(50,76,'CUDA','body')+text(47,100,'Tesla T4','muted')
    chipbody+=group(path('M58 132L65 139L83 120','signal'),**show(8200,8800))
    s+=group(chipbody,cx,cy)
    if not m:
        s+=path('M395 216H620V208H666','signal',pathLength=1,data_draw='4250 5300')+path('M395 300H620V248H666','signal',pathLength=1,data_draw='6150 7300')
        s+=text(642,351,'Execution evidence','positive',**show(6500,7100))
    else: s+=text(90,716,'Execution evidence','positive',**show(6500,7100))
    return s,755 if m else 469
make('running-obscura-on-nvidia-exla','Installed is not\nthe same as executing.','A GPU claim earns its way through five separate validation gates.',
'First establish the CPU app baseline. Discover CUDA, run a compiled Nx operation returning an EXLA.Backend tensor, observe beam.smp as a GPU consumer, then exercise both model profiles. This is the reported Tesla T4 compatibility path, not a performance recommendation.',
[[0,'Start with a working Phoenix application and the fast profile on CPU.'],[2300,'EXLA discovers a CUDA device. Discovery alone is not execution proof.'],[4200,'Run a compiled operation and inspect the EXLA.Backend tensor.'],[6100,'Observe beam.smp as a CUDA consumer on the Tesla T4.'],[8000,'Prepare and reuse both model-serving paths. This validates the tested configuration, not all GPU deployments.']],gpu,'Illustrative proof sequence · the article’s Tesla T4 validation path')

# 9. Follow provenance through separate artifacts, ending in an explicit review.
def license_scene(m):
    nodes=[('Model card','Metadata + links'),('Base weights','Original terms'),('Tokenizer','Asset provenance'),('Training data','Dataset agreement'),('Checkpoint','Exact revision'),('Deployment','Intended use + conditions')]
    coords=[(24,40+i*116) for i in range(6)] if m else [(24,50),(350,50),(676,50),(24,258),(350,258),(676,258)]
    w=332 if m else 260
    s=''
    for i,((name,detail),(x,y)) in enumerate(zip(nodes,coords)):
        s+=panel(x,y,w,90,name, text(18,73,detail,'muted'))
        # A ruled provenance marker advances without implying legal clearance.
        s+=rect(x+12,y+11,3,21,'warning',rx=0,**show(300+i*1500,900+i*1500))
        if i<5:
            nx,ny=coords[i+1]
            if m: d=f'M{x+w/2} {y+90}V{ny}'
            elif i==2: d=f'M{x+w/2} {y+90}V221H154V258'
            else: d=f'M{x+w} {y+45}H{nx}'
            s+=path(d,'wire')+path(d,'signal',pathLength=1,data_draw=f'{900+i*1500} {1800+i*1500}')
    yy=782 if m else 411
    s+=text(24,yy,'Permission at one layer does not resolve the others.','warning',**show(9200,9850)) if not m else text(24,yy,'Permission at one layer does not','warning',**show(9200,9850))+text(24,yy+24,'resolve the others.','warning',**show(9200,9850))
    return s,845 if m else 455
make('model-card-is-not-a-license','Follow the provenance.\nKeep the questions open.','A model is assembled from separate artifacts, each with its own review questions.',
'Follow the model card to base weights, tokenizer assets, training data, the exact checkpoint, and intended deployment. Terms and provenance must be reviewed at each layer. This schematic review sequence does not determine licensing permission.',
[[0,'The model card is a starting point: metadata and links, not the whole permission story.'],[1600,'Identify the original weights and their applicable terms.'],[3100,'Trace the tokenizer assets as well as the model.'],[4600,'Follow the training data and the dataset agreement.'],[6100,'Pin the exact checkpoint revision that will be loaded.'],[7600,'Review the intended deployment and keep unresolved conditions explicit.']],license_scene,'Illustrative engineering review · not a licensing determination')

(ROOT/'catalog.json').write_text(json.dumps(CATALOG,indent=2,ensure_ascii=False)+'\n')
print(f'Generated {len(CATALOG)} original scene compositions in {ROOT}')
