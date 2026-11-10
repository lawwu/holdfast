import { BACKGROUND_CONTEXT as ctx } from '@earendil-works/chord/context';
import { createModels } from '@earendil-works/pi-ai/models';
import { AssistantEntry, createRegistry, defineExtension, defineTool, Harness, section } from '@earendil-works/pi-durable';
import { openNodeSqliteStorage } from '@earendil-works/pi-durable/storage/sqlite/node';
import { createSwiftMLXProvider } from 'pi-swift-mlx';

process.umask(0o077);
const send = value => process.stdout.write(JSON.stringify(value) + '\n');
const pending = new Map();
let serial = 0, harness, root, started = false, closing = false, abortRequested = false;
function rpc(method, params, { signal, onDelta } = {}) {
  if (signal?.aborted) return Promise.reject(new Error('Cancelled'));
  return new Promise((resolve, reject) => {
    const id = String(++serial);
    const abort = () => { send({ type: 'cancel', id }); finish(new Error('Cancelled')); };
    const finish = (error, value) => {
      pending.delete(id); signal?.removeEventListener('abort', abort);
      error ? reject(error) : resolve(value);
    };
    pending.set(id, { finish, onDelta });
    signal?.addEventListener('abort', abort, { once: true });
    send({ type: 'request', id, method, params });
  });
}

async function run(config) {
  if (config.protocol !== 1) throw new Error('Unsupported Holdfast bridge protocol');
  const models = createModels();
  models.setProvider(createSwiftMLXProvider({ ...config, providerID: 'holdfast-mlx' },
    (request, options) => rpc('model', request, options))); // Swift owns the selected inference transport and data policy; no credentials in Node.
  const registry = createRegistry();
  registry.install(defineExtension({ name: 'holdfast',
    sections: [section('holdfast', () => config.system, { tag: false })],
    tools: config.tools.map(spec => defineTool({ name: spec.name, description: spec.description,
      parameters: { type: 'object', properties: Object.fromEntries(Object.entries(spec.fields).map(([name, description]) => [name, { type: 'string', description }])),
        required: spec.required, additionalProperties: false },
      replay: 'safe', // Native receipts + proposal operation IDs make replay safe.
      execute: async (args, api, context) => {
        const result = await rpc('tool', { name: spec.name, args, operationID: String(api.taskId) }, { signal: context.abortSignal });
        return { output: [{ type: 'text', text: result.text }], isError: result.isError };
      },
    })) }));
  harness = await Harness.open(await openNodeSqliteStorage(config.database), { models, registry,
    // Pi charges a process crash during generation against this budget too.
    // Zero retries would prevent recovery even after completed tools were saved.
    settings: { toolExecution: 'sequential', retry: { maxRetries: 2 }, stream: { timeoutMs: 300_000 },
      compaction: { enabled: true, reserveTokens: 4096, keepRecentTokens: 8000, backgroundTokens: 0 } },
  }, ctx);
  if (closing) { await harness.close(ctx); return; }
  root = await harness.root(ctx, { agent: { model: { provider: 'holdfast-mlx', modelId: config.model }, maxTurns: 8 } });
  // A prior Swift-only conversation is a handoff, never replayed as new requests.
  if (config.handoff) await root.configure({ instructions: config.handoff }, ctx);
  await root.configure({ model: { provider: 'holdfast-mlx', modelId: config.model } }, ctx);
  if (abortRequested) throw new Error('Pi run cancelled before submission');
  const submission = await root.submit({ type: 'input', content: config.question, requestId: config.requestID }, ctx);
  send({ type: 'accepted', submissionID: submission.id });
  const settled = await submission.wait(ctx);
  if (settled.status !== 'done' || settled.type !== 'input') {
    throw new Error(`Pi run ${settled.status}: ${JSON.stringify(settled.reason ?? settled)}`);
  }
  const entry = await root.commit(tx => tx.entry(AssistantEntry, settled.answer), ctx);
  const message = entry?.model?.[0];
  if (!message) throw new Error('Pi finished without an assistant answer');
  send({ type: 'done', text: message.content.filter(b => b.type === 'text').map(b => b.text).join(''), usage: message.usage });
}

async function close() {
  if (closing) return;
  closing = true;
  await harness?.close(ctx);
  for (const value of pending.values()) value.finish(new Error('Bridge closed'));
  process.stdin.destroy();
}
function receive(line) {
  try {
    const value = JSON.parse(line);
    if (value.type === 'start' && !started) {
      started = true;
      void run(value).catch(error => send({ type: 'error', message: String(error.message ?? error) })).finally(close);
    } else if (value.type === 'response') {
      pending.get(value.id)?.finish(value.error ? new Error(value.error) : undefined, value.result);
    } else if (value.type === 'delta') pending.get(value.id)?.onDelta?.(value.text);
    else if (value.type === 'abort') {
      abortRequested = true;
      if (root) void root.abort(ctx, { background: true }).then(close);
      else if (!started) void close();
    }
  } catch (error) { send({ type: 'error', message: String(error.message ?? error) }); void close(); }
}
// Split only on LF. Node readline also treats Unicode separators inside valid
// JSON strings as line endings, which can corrupt note/model content.
let inputBuffer = Buffer.alloc(0);
process.stdin.on('data', data => {
  inputBuffer = Buffer.concat([inputBuffer, data]); let end;
  while ((end = inputBuffer.indexOf(10)) !== -1) {
    if (end > 32 * 1024 * 1024) { void close(); return; }
    receive(inputBuffer.subarray(0, end).toString('utf8')); inputBuffer = inputBuffer.subarray(end + 1);
  }
  if (inputBuffer.length > 32 * 1024 * 1024) void close();
});
// EOF/termination preserves pending durable work; explicit Stop above cancels it.
process.stdin.on('end', () => { if (!closing) void close(); });
// The native host can disappear between an RPC write and stdin EOF. Let close
// persist pending work instead of an unhandled EPIPE killing the helper.
process.stdout.on('error', () => void close());
process.on('SIGTERM', () => void close());
