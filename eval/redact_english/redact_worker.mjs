import { Redact } from '@desert-ant-labs/redact/native';
import { readFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { createInterface } from 'node:readline';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { normalize } from './spans.mjs';

const root = path.dirname(fileURLToPath(import.meta.url));
const directory = process.env.REDACT_MODEL_DIR;
if (!directory) throw new Error('REDACT_MODEL_DIR must point to verified model assets');
if (process.env.DAL_USAGE_DISABLED) throw new Error('Usage telemetry must remain enabled');
const began = performance.now();
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const manifestBytes = await readFile(path.join(root, 'model-manifest.json'));
const manifest = JSON.parse(manifestBytes);
const assetNames = ['labels.json', 'redact_tokenizer.bin'];
const selected = manifest.files.filter(f => assetNames.includes(f.path) ||
  (process.platform === 'darwin' ? f.path.startsWith('redact.mlmodelc/') : f.path === 'redact.tflite'));
for (const file of selected) {
  if (sha(await readFile(path.join(directory, file.path))) !== file.sha256) throw new Error(`Asset hash mismatch: ${file.path}`);
}
const nativeDir = path.join(root, 'node_modules/@desert-ant-labs/redact/native', `${process.platform}-${process.arch}`);
const binaries = {};
for (const name of (await readdir(nativeDir)).sort()) {
  if (/\.(so|dylib)$/.test(name)) binaries[name] = sha(await readFile(path.join(nativeDir, name)));
}
const version = JSON.parse(await readFile(path.join(root, 'node_modules/@desert-ant-labs/redact/package.json'))).version;
if (version !== manifest.sdk_version) throw new Error('SDK version mismatch');
const redact = await Redact.load({ directory });
console.log(JSON.stringify({ event: 'ready', profile: 'redact', sdk: version, node: process.version,
  platform: process.platform, arch: process.arch, pid: process.pid, binaries,
  preparation_ms: performance.now() - began, model_revision: manifest.revision,
  model_manifest_sha256: sha(manifestBytes),
  engine: process.platform === 'darwin'
    ? { backend: 'CoreML', requested: process.env.DAL_COREML_COMPUTE_UNITS ?? 'all',
        device: process.env.DAL_COREML_COMPUTE_UNITS === 'cpu' ? 'cpu' : 'unverified acceleration',
        numerical_validity: process.env.DAL_COREML_COMPUTE_UNITS === 'cpu' ? 'failed diagnostic gate' : 'finite in diagnostic probes' }
    : { backend: 'LiteRT/XNNPACK', device: 'cpu', evidence: 'Same native binary/runtime as CPU-only diagnostic run' } }));
try {
  for await (const line of createInterface({ input: process.stdin, crlfDelay: Infinity })) {
    const request = JSON.parse(line);
    const started = performance.now();
    try {
      const result = await redact.redaction(request.text);
      const { raw, predictions } = normalize(request.text, result.items);
      console.log(JSON.stringify({ id: request.id, predictions, raw_predictions: raw,
        inference_ms: performance.now() - started, changed: result.items.length > 0 }));
    } catch (error) {
      console.log(JSON.stringify({ id: request.id, error: error.name, inference_ms: performance.now() - started }));
    }
  }
} finally { redact.dispose(); }
