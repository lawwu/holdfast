import assert from 'node:assert/strict';
import test from 'node:test';
import { createModels } from '@earendil-works/pi-ai';
import { nativeRequest, createSwiftMLXProvider } from '../provider.mjs';
import { runHarness, schema } from './harnesses.mjs';

const values = { limit: 2, enabled: false, values: [0, 1, 2.5], metadata: { value: null } };
const reply = (text, calls = []) => ({ text, calls, usage: { promptTokens: 10, outputTokens: 5 } });
const call = { id: 'typed-call', name: 'inspect_data', arguments: JSON.stringify(values) };

for (const kind of ['pi', 'durable']) {
  test(`real ${kind} harness uses the provider with arbitrary tool schemas and typed arguments`, { timeout: 20000 }, async () => {
    let generations = 0, tools = 0;
    const answer = await runHarness(kind, {
      generate: async (request, { onDelta }) => {
        assert.equal(request.version, 1);
        assert.deepEqual(request.tools.find(t => t.name === 'inspect_data').parameters, schema);
        if (generations++ === 0) return reply('', [call]);
        assert.equal(request.messages.at(-1).role, 'tool');
        assert.equal(request.messages.at(-1).id, 'typed-call');
        assert.equal(request.messages.at(-1).text, 'inspection complete');
        onDelta('Finished.'); return reply('Finished.');
      },
      execute: async args => { tools++; assert.deepEqual(args, values); return 'inspection complete'; },
    });
    assert.equal(answer, 'Finished.'); assert.equal(tools, 1); assert.equal(generations, 2);
  });
}

test('system/tool updates and generation controls cross the versioned boundary intact', () => {
  const result = nativeRequest({ id: 'model', maxTokens: 2000 }, { messages: [
    { role: 'system', content: 'base', toolsAdded: [{ name: 'old', parameters: {} }] },
    { role: 'user', content: 'question\u2028intact' },
    { role: 'assistant', content: [{ type: 'toolCall', ...call, arguments: values }] },
    { role: 'toolResult', toolCallId: call.id, toolName: call.name, content: [{ type: 'text', text: 'result' }], isError: false },
    { role: 'system', content: 'updated', toolsRemoved: [{ name: 'old' }], toolsAdded: [{ name: 'inspect_data', parameters: schema }] },
  ] }, { sessionId: 'session', maxTokens: 120, temperature: 0 });
  assert.match(result.system, /base/); assert.match(result.system, /updated/);
  assert.deepEqual(result.tools.map(t => t.name), ['inspect_data']); assert.equal(result.messages.length, 3);
  assert.deepEqual(JSON.parse(result.messages[1].calls[0].arguments), values);
  assert.equal(result.sessionID, 'session'); assert.equal(result.generation.temperature, 0); assert.equal(result.generation.maxTokens, 120);
  assert.throws(() => nativeRequest({ maxTokens: 20 }, { messages: [{ role: 'user', content: [{ type: 'image', data: 'x' }] }] }), /only supports text/);
});

test('streaming, usage, truncated/malformed calls and cancellation', async () => {
  const models = createModels(); let mode = 'stream';
  models.setProvider(createSwiftMLXProvider({ model: 'fixture' }, async (_request, { signal, onDelta }) => {
    if (mode === 'stream') { onDelta('hel'); onDelta('lo'); return reply('hello'); }
    if (mode === 'length') return { ...reply('', [call]), truncated: true };
    if (mode === 'invalid') return reply('', [{ ...call, arguments: '[]' }]);
    return new Promise((_resolve, reject) => signal.addEventListener('abort', () => reject(new Error('cancelled'))));
  }));
  const model = models.getModel('swift-mlx', 'fixture');
  const context = { messages: [{ role: 'user', content: 'hi', timestamp: Date.now() }] };
  const events = [];
  for await (const ev of models.streamSimple(model, context)) events.push(ev);
  assert.equal(events.filter(e => e.type === 'text_delta').map(e => e.delta).join(''), 'hello');
  assert.equal(events.at(-1).message.usage.totalTokens, 15);
  mode = 'length'; const truncated = await models.completeSimple(model, context);
  assert.equal(truncated.stopReason, 'error'); assert.equal(truncated.content.filter(c => c.type === 'toolCall').length, 0);
  mode = 'invalid'; assert.match((await models.completeSimple(model, context)).errorMessage, /must be an object/);
  mode = 'abort'; const controller = new AbortController();
  const pending = models.completeSimple(model, context, { signal: controller.signal });
  setTimeout(() => controller.abort(), 10); assert.equal((await pending).stopReason, 'aborted');
});
