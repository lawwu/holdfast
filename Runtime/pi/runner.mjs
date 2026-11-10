import { createHash } from 'node:crypto';
import { mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { InMemoryCredentialStore } from '@earendil-works/pi-ai';
import { createAgentSession, DefaultResourceLoader, ModelRuntime, SessionManager, SettingsManager } from '@earendil-works/pi-coding-agent';
import { createSwiftMLXProvider } from 'pi-swift-mlx';

process.umask(0o077);
const send = value => process.stdout.write(JSON.stringify(value) + '\n');
const pending = new Map();
const shutdown = new AbortController();
let serial = 0, session, started = false, closing = false;

function rpc(method, params, { signal, onDelta } = {}) {
  const combined = signal ? AbortSignal.any([signal, shutdown.signal]) : shutdown.signal;
  if (combined.aborted) return Promise.reject(new Error('Cancelled'));
  return new Promise((resolve, reject) => {
    const id = String(++serial);
    const finish = (error, value) => {
      pending.delete(id); combined.removeEventListener('abort', abort); clearTimeout(timer);
      error ? reject(error) : resolve(value);
    };
    const abort = () => { send({ type: 'cancel', id }); finish(new Error('Cancelled')); };
    const timer = setTimeout(() => {
      send({ type: 'cancel', id }); finish(new Error('The Swift model/tool request timed out.'));
    }, 300_000);
    pending.set(id, { finish, onDelta });
    combined.addEventListener('abort', abort, { once: true });
    send({ type: 'request', id, method, params });
  });
}

// Regular Pi saves a transcript, not executable jobs. Close any unmatched historical
// calls with an explicit unknown outcome; never execute them just by opening a session.
function markInterruptedCalls(manager) {
  const unresolved = new Map();
  for (const message of manager.buildSessionContext().messages) {
    if (message.role === 'assistant') {
      for (const block of message.content) if (block.type === 'toolCall') unresolved.set(block.id, block.name);
    } else if (message.role === 'toolResult') unresolved.delete(message.toolCallId);
  }
  for (const [toolCallId, toolName] of unresolved) {
    manager.appendMessage({ role: 'toolResult', toolCallId, toolName, isError: true, timestamp: Date.now(),
      content: [{ type: 'text', text: 'This earlier call was interrupted. Its outcome is unknown; an Inbox proposal may already exist. Do not repeat it automatically. Respond to the new user request.' }] });
  }
}

async function run(config) {
  if (config.protocol !== 1 || !config.sessionDirectory || !config.requestID) throw new Error('Unsupported Holdfast Pi bridge configuration');
  const dir = config.sessionDirectory;
  await mkdir(dir, { recursive: true, mode: 0o700 });
  const manager = SessionManager.continueRecent(dir, dir);
  const previous = manager.getEntries().filter(e => e.type === 'custom' && e.customType === 'holdfast.request' && e.data?.id === config.requestID);
  if (previous.length) {
    if (previous[0].data.question !== config.question) throw new Error('Request ID was already used for another question.');
    const completed = previous.findLast(e => e.data.status === 'complete');
    if (completed) { send({ type: 'done', text: completed.data.text }); return; }
    throw new Error('That request was interrupted or stopped. Continue the conversation with a new request ID; Pi will not replay the unfinished job.');
  }
  markInterruptedCalls(manager);
  if (config.handoff && !manager.buildSessionContext().messages.length) {
    manager.appendCustomMessageEntry('holdfast.handoff', config.handoff, false);
  }
  const runtime = await ModelRuntime.create({ credentials: new InMemoryCredentialStore(), modelsPath: null,
    modelsStorePath: join(dir, 'models-cache.json'), refreshOnCreate: false, allowModelNetwork: false });
  let modelRequests = 0;
  runtime.registerNativeProvider(createSwiftMLXProvider({ ...config, providerID: 'holdfast-swift' }, (request, options) => {
    if (++modelRequests > 12) throw new Error('Pi reached Holdfast’s model-turn limit. Ask a follow-up to continue.');
    return rpc('model', request, options);
  }));
  const settingsManager = SettingsManager.inMemory({ compaction: { enabled: true, reserveTokens: 4096, keepRecentTokens: 8000 },
    retry: { enabled: false }, cacheWarming: 'off' });
  const resourceLoader = new DefaultResourceLoader({ cwd: dir, agentDir: dir, settingsManager,
    noExtensions: true, disabledBuiltinExtensions: ['mcp'], noSkills: true, noPromptTemplates: true, noThemes: true,
    noContextFiles: true, systemPrompt: config.system });
  await resourceLoader.reload();
  if (closing) return;
  ({ session } = await createAgentSession({ cwd: dir, agentDir: dir, modelRuntime: runtime,
    model: runtime.getModel('holdfast-swift', config.model), thinkingLevel: 'off', resourceLoader, settingsManager,
    sessionManager: manager, tools: config.tools.map(spec => spec.name), customTools: config.tools.map(spec => ({
      name: spec.name, label: spec.name, description: spec.description, executionMode: 'sequential',
      parameters: { type: 'object', properties: Object.fromEntries(Object.entries(spec.fields).map(([name, description]) => [name, { type: 'string', description }])),
        required: spec.required, additionalProperties: false },
      execute: async (id, args, signal) => {
        const operationID = createHash('sha256').update(config.requestID + ':' + id).digest('hex');
        const result = await rpc('tool', { name: spec.name, args, operationID }, { signal });
        // Throwing makes the regular SDK persist an error tool result, rather than
        // a successful result whose details merely contain an error flag.
        if (result.isError) throw new Error(result.text);
        return { content: [{ type: 'text', text: result.text }], details: {} };
      },
    })) }));
  session.agent.toolExecution = 'sequential';
  manager.appendCustomEntry('holdfast.request', { id: config.requestID, question: config.question, status: 'started' });
  send({ type: 'accepted', sessionFile: manager.getSessionFile() });
  try {
    if (closing) throw new Error('Cancelled');
    // This awaits an ordinary Pi turn. Opening a saved session never runs a previous job.
    await session.prompt(config.question, { expandPromptTemplates: false });
    const last = session.messages.findLast(message => message.role === 'assistant');
    if (!last || ['error', 'aborted'].includes(last.stopReason)) throw new Error(last?.errorMessage || 'Pi stopped without completing an answer.');
    if (last.content.some(block => block.type === 'toolCall')) throw new Error('Pi stopped before finishing its tool work.');
    const text = session.getLastAssistantText() ?? '';
    manager.appendCustomEntry('holdfast.request', { id: config.requestID, question: config.question, status: 'complete', text });
    send({ type: 'done', text });
  } catch (error) {
    manager.appendCustomEntry('holdfast.request', { id: config.requestID, question: config.question, status: closing ? 'cancelled' : 'failed' });
    throw error;
  }
}

async function close() {
  if (closing) return;
  closing = true; shutdown.abort();
  await session?.abort(); session?.dispose();
  for (const value of pending.values()) value.finish(new Error('Bridge closed'));
  process.stdin.destroy();
}
function receive(line) {
  try {
    const value = JSON.parse(line);
    if (value.type === 'start' && !started) {
      started = true;
      void run(value).catch(error => { if (!closing) send({ type: 'error', message: String(error.message ?? error) }); }).finally(close);
    } else if (value.type === 'response') {
      pending.get(value.id)?.finish(value.error ? new Error(value.error) : undefined, value.result);
    } else if (value.type === 'delta') pending.get(value.id)?.onDelta?.(value.text);
    else if (value.type === 'abort') void close();
  } catch (error) { send({ type: 'error', message: String(error.message ?? error) }); void close(); }
}
// LF framing preserves Unicode line separators inside JSON strings.
let inputBuffer = Buffer.alloc(0);
process.stdin.on('data', data => {
  inputBuffer = Buffer.concat([inputBuffer, data]); let end;
  while ((end = inputBuffer.indexOf(10)) !== -1) {
    if (end > 32 * 1024 * 1024) { void close(); return; }
    receive(inputBuffer.subarray(0, end).toString('utf8')); inputBuffer = inputBuffer.subarray(end + 1);
  }
  if (inputBuffer.length > 32 * 1024 * 1024) void close();
});
process.stdin.on('end', () => void close());
process.stdout.on('error', () => void close());
process.on('SIGTERM', () => void close());
