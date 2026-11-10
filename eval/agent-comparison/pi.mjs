// Pi's installed SDK with Holdfast's real tools. No built-in shell/edit/write tools,
// credentials, project discovery, extensions or automatic provider fallback.
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

const input = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const sdk = await import(pathToFileURL(join(input.piPackage, 'dist/index.js')).href);
const { AuthStorage, ModelRegistry, SettingsManager, SessionManager, createAgentSession, createExtensionRuntime } = sdk;
const bridge = spawn(input.binary, ['_agent-eval'], { env: process.env, stdio: ['pipe', 'pipe', 'inherit'] });
const pending = [];
createInterface({ input: bridge.stdout }).on('line', line => {
  const item = pending.shift();
  if (!item) throw new Error('Unexpected bridge response');
  try { const value = JSON.parse(line); value.error ? item.reject(new Error(value.error)) : item.resolve(value); }
  catch (error) { item.reject(error); }
});
bridge.on('exit', code => { for (const item of pending.splice(0)) item.reject(new Error(`Bridge exited: ${code}`)); });
function request(value) {
  return new Promise((resolve, reject) => {
    pending.push({ resolve, reject });
    bridge.stdin.write(JSON.stringify(value) + '\n');
  });
}

let session;
try {
  const config = await request({ op: 'config' });
  const calls = [];
  const customTools = config.tools.map(spec => ({
    name: spec.name, label: spec.name, description: spec.description,
    parameters: { type: 'object', properties: Object.fromEntries(Object.entries(spec.fields).map(([name, description]) =>
      [name, { type: 'string', description }])), required: spec.required, additionalProperties: false },
    execute: async (_id, args, signal) => {
      if (signal?.aborted) throw new Error('Cancelled');
      if (calls.length >= config.maxToolCalls) throw new Error('Tool budget exhausted');
      const result = await request({ op: 'call', name: spec.name, arguments: args });
      calls.push({ name: spec.name, arguments: args, result });
      // All fixtures are synthetic, but fail closed if a future fixture touches a private domain.
      if (result.localOnly) throw new Error('Local-only tool result: evaluation refuses to forward it');
      if (result.isError) throw new Error(result.text);
      return { content: [{ type: 'text', text: result.text }], details: {} };
    }
  }));
  const authStorage = AuthStorage.inMemory();
  authStorage.setRuntimeApiKey('holdfast-eval', 'local-only');
  const modelRegistry = ModelRegistry.inMemory(authStorage);
  modelRegistry.registerProvider('holdfast-eval', {
    baseUrl: input.baseUrl, api: 'openai-completions', apiKey: 'local-only',
    models: [{ id: input.model, name: input.model, reasoning: false, input: ['text'],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 32768, maxTokens: 2000,
      compat: { supportsDeveloperRole: false, supportsStore: false, supportsStrictMode: false,
        maxTokensField: 'max_tokens', supportsUsageInStreaming: true } }]
  });
  const resourceLoader = {
    getExtensions: () => ({ extensions: [], errors: [], runtime: createExtensionRuntime() }),
    getSkills: () => ({ skills: [], diagnostics: [] }), getPrompts: () => ({ prompts: [], diagnostics: [] }),
    getThemes: () => ({ themes: [], diagnostics: [] }), getAgentsFiles: () => ({ agentsFiles: [] }),
    getSystemPrompt: () => config.system, getAppendSystemPrompt: () => [], extendResources: () => {}, reload: async () => {}
  };
  ({ session } = await createAgentSession({ cwd: input.vault, agentDir: input.agentDir,
    authStorage, modelRegistry, model: modelRegistry.find('holdfast-eval', input.model), thinkingLevel: 'off',
    tools: [], customTools, resourceLoader, sessionManager: SessionManager.inMemory(),
    settingsManager: SettingsManager.inMemory({ compaction: { enabled: false }, retry: { enabled: false } }) }));
  session.agent.toolExecution = 'sequential';
  // The SDK adds cwd/date to custom prompts. Use exactly the app's system prompt
  // at the provider boundary so this experiment compares harnesses, not prompts.
  const stream = session.agent.streamFn;
  let turns = 0;
  session.agent.streamFn = (model, context, options) => {
    if (turns > config.maxToolRounds) throw new Error('Model round budget exhausted');
    const final = turns++ === config.maxToolRounds || calls.length >= config.maxToolCalls;
    return stream(model, { ...context, systemPrompt: config.system,
      tools: final ? [] : context.tools,
      messages: final ? [...context.messages, { role: 'user', content: 'Answer now from what the tools returned, with [n] citations.', timestamp: Date.now() }] : context.messages
    }, { ...options, maxTokens: 2000, temperature: config.temperature });
  };
  const started = performance.now();
  await session.prompt(input.question);
  const loopSeconds = (performance.now() - started) / 1000;
  const messages = session.messages;
  const assistants = messages.filter(message => message.role === 'assistant');
  const last = assistants.at(-1);
  if (!last || ['error', 'aborted'].includes(last.stopReason)) throw new Error(last?.errorMessage ?? 'Pi ended without an answer');
  const answer = last.content.filter(block => block.type === 'text').map(block => block.text).join('');
  writeFileSync(input.transcript, JSON.stringify(messages, null, 2));
  console.log(JSON.stringify({ answer, loopSeconds, loadSeconds: 0, turns, calls,
    promptTokens: assistants.reduce((n, m) => n + (m.usage?.input ?? 0) + (m.usage?.cacheRead ?? 0), 0),
    outputTokens: assistants.reduce((n, m) => n + (m.usage?.output ?? 0), 0) }));
} finally {
  session?.dispose();
  bridge.stdin.end();
}
