import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { createProcessTransport } from '../process.mjs';

const host = fileURLToPath(new URL('./fixtures/host.mjs', import.meta.url));
const request = system => ({ version: 1, model: 'fixture', sessionID: 'one', system,
  messages: [{ role: 'user', text: 'A 🙂\u2028B\nC' }], tools: [], generation: {} });

test('subprocess framing preserves Unicode, cancellation acknowledges before reuse, and exit fails pending work', { timeout: 15000 }, async () => {
  let stderr = '';
  const transport = createProcessTransport({ executable: process.execPath, args: [host], model: 'fixture', modelDirectory: '.', onStderr: text => { stderr += text; } });
  try {
    let text = '';
    const first = await transport.generate(request('ok'), { onDelta: delta => { text += delta; } });
    assert.equal(first.text, text); assert.equal(text, 'A 🙂\u2028B\nC'); assert.match(stderr, /ready/);
    const controller = new AbortController();
    const delayed = transport.generate(request('delay'), { signal: controller.signal, onDelta: () => assert.fail('cancelled output') });
    await assert.rejects(transport.generate(request('ok'), { onDelta: () => {} }), /busy/);
    controller.abort(); await assert.rejects(delayed, { name: 'AbortError' });
    assert.equal((await transport.generate(request('ok'), { onDelta: () => {} })).text, text);
    await assert.rejects(transport.generate(request('exit'), { onDelta: () => {} }), /exited/);
    assert.equal((await transport.generate(request('ok'), { onDelta: () => {} })).text, text);
  } finally { await transport.close(); }
  await assert.rejects(transport.generate(request('ok'), { onDelta: () => {} }), /closed/);
});

test('a timed-out host is reaped before the next request starts', { timeout: 10000 }, async () => {
  const transport = createProcessTransport({ executable: process.execPath, args: [host], model: 'fixture', modelDirectory: '.', timeoutMs: 500 });
  try {
    await assert.rejects(transport.generate(request('delay')), /timed out/);
    assert.equal((await transport.generate(request('ok'))).text, 'A 🙂\u2028B\nC');
  } finally { await transport.close(); }
});
