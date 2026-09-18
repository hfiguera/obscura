import { Redact } from '@desert-ant-labs/redact/native';
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root=path.dirname(fileURLToPath(import.meta.url));
const directory=process.env.REDACT_MODEL_DIR;
if (!directory) throw new Error('REDACT_MODEL_DIR required');
const manifest=JSON.parse(await readFile(path.join(root,'model-manifest.json')));
for (const f of manifest.files.filter(f=>['labels.json','redact_tokenizer.bin'].includes(f.path) || (process.platform==='darwin'?f.path.startsWith('redact.mlmodelc/'):f.path==='redact.tflite'))) {
  if (createHash('sha256').update(await readFile(path.join(directory,f.path))).digest('hex')!==f.sha256) throw new Error('Asset hash mismatch');
}
const redact=await Redact.load({directory});
const segmenter=new Intl.Segmenter('en',{granularity:'sentence'});
const results=[];
try {
  for (const repeats of [0,5,20,150]) {
    const text='The worker finished the ordinary background task. '.repeat(repeats)+'Contact Rachel Chen in London at rachel.chen@example.test.';
    const full=await redact.redaction(text);
    const segmented=[];
    for (const {segment,index} of segmenter.segment(text)) {
      const part=await redact.redaction(segment);
      for (const item of part.items) {
        if (text.slice(index+item.start,index+item.end)!==item.original) throw new Error('Segment offset mismatch');
        segmented.push(item.label);
      }
    }
    results.push({repeats,utf8_bytes:Buffer.byteLength(text),full_labels:full.items.map(x=>x.label),segmented_labels:segmented});
  }
} finally {redact.dispose();}
await writeFile(process.argv[2],JSON.stringify({schema:1,purpose:'Separate sentence segmentation diagnostic; not default behavior or a validated production workaround',
  node:process.version,platform:process.platform,compute_units:process.env.DAL_COREML_COMPUTE_UNITS??'SDK default',results},null,2)+'\n');
