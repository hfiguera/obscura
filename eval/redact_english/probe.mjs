import { Redact } from '@desert-ant-labs/redact/native';
import { writeFile, readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import os from 'node:os';

// Authored synthetic diagnostics, not test gold for model selection or training.
const contact = 'Contact Rachel Chen in London at rachel.chen@example.test.';
const filler = 'The worker finished the ordinary background task. ';
const paragraph = 'The customer reported that the upload completed but the dashboard still showed the previous result. We checked the processing queue and confirmed that the file had been accepted. The next step is to review the application logs and retry the request after the cache expires. No changes to the account settings are needed. ';
const cases = [];
for (const position of ['start', 'end']) {
  for (const repeats of [0, 1, 3, 5, 8, 10, 20, 50, 150]) {
    cases.push({ id: `repeated_${position}_${repeats}`, position, repeats,
      text: position === 'start' ? contact + ' ' + filler.repeat(repeats) : filler.repeat(repeats) + contact });
  }
}
cases.push({ id: 'paragraph_before', text: paragraph + contact });
cases.push({ id: 'paragraph_after', text: contact + ' ' + paragraph });
cases.push({ id: 'long_mixed', text: paragraph + contact + ' ' + paragraph.repeat(5) });
const sdkPackage = JSON.parse(await readFile(new URL('./node_modules/@desert-ant-labs/redact/package.json', import.meta.url)));
const start = performance.now();
const redact = await Redact.load({ cacheRoot: process.env.REDACT_CACHE_ROOT ?? new URL('./cache', import.meta.url).pathname });
const readyMs = performance.now() - start;
const results = [];
try {
  for (const minimumConfidence of [0.6, 0]) {
    for (const { text, ...meta } of cases) {
      const began = performance.now();
      const result = await redact.redaction(text, { minimumConfidence });
      const items = result.items.map(({ label, start, end }) => ({ label, startUtf16: start, endUtf16: end }));
      const row = { ...meta, minimumConfidence,
        inputSha256: createHash('sha256').update(text).digest('hex'), inputUtf8Bytes: Buffer.byteLength(text),
        latencyMs: performance.now() - began, items,
        detectedNameComponents: items.filter(x => ['GIVEN_NAME', 'SURNAME'].includes(x.label)).length,
        detectedCities: items.filter(x => x.label === 'CITY').length,
        utf16SpansMatch: result.items.every(x => text.slice(x.start, x.end) === x.original),
        restorationExact: result.restore(result.redactedText) === text };
      results.push(row);
    }
  }
} finally { redact.dispose(); }
const report = { schema: 1, purpose: 'Synthetic functional diagnosis; not a performance or accuracy ranking',
  sdk: sdkPackage.version, node: process.version, platform: process.platform, arch: process.arch,
  osRelease: os.release(), cpu: os.cpus()[0]?.model,
  requestedCoreMLComputeUnits: process.env.DAL_COREML_COMPUTE_UNITS ?? 'SDK default',
  actualDeviceInstrumentation: 'not yet collected', readyMs, results };
const output = process.argv[2];
if (!output) throw new Error('Usage: node probe.mjs OUTPUT.json');
await writeFile(output, JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ output, calls: results.length,
  defaultThresholdMissingNames: results.filter(r => r.minimumConfidence === 0.6 && r.detectedNameComponents !== 2).length,
  spansValid: results.every(r => r.utf16SpansMatch), restorationExact: results.every(r => r.restorationExact) }));
