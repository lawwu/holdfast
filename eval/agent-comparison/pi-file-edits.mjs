import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { boundedFileTools } from './pi-edit-tools.mjs';

const input = JSON.parse(readFileSync(process.argv[2], 'utf8'));
if (readFileSync(join(input.vault, '.agent-eval-synthetic'), 'utf8') !== 'synthetic holdfast agent evaluation\n') throw new Error('Synthetic marker required');
const sdk = await import(pathToFileURL(join(input.piPackage, 'dist/index.js')).href);
const tools = await boundedFileTools(sdk, input.vault);
if (input.direct) {
  const tool = tools.find(tool => tool.name === input.name);
  try {
    const result = await tool.execute('direct-test', input.arguments);
    console.log(JSON.stringify({ result, isError: false }));
  } catch (error) { console.log(JSON.stringify({ isError: true, error: error.message })); }
} else {
  const { AuthStorage, ModelRegistry, SettingsManager, SessionManager, createAgentSession, createExtensionRuntime } = sdk;
  const authStorage = AuthStorage.inMemory();
  authStorage.setRuntimeApiKey('holdfast-file-eval', 'local-only');
  const modelRegistry = ModelRegistry.inMemory(authStorage);
  modelRegistry.registerProvider('holdfast-file-eval', {
    baseUrl: input.baseUrl, api: 'openai-completions', apiKey: 'local-only',
    models: [{ id: input.model, name: input.model, reasoning: false, input: ['text'],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 32768, maxTokens: 2000,
      compat: { supportsDeveloperRole: false, supportsStore: false, supportsStrictMode: false,
        maxTokensField: 'max_tokens', supportsUsageInStreaming: true } }]
  });
  const calls = [];
  const wrapped = tools.map(tool => ({ ...tool, execute: async (id, args, signal, update) => {
    if (calls.length >= 32) throw new Error('Tool call budget exhausted');
    const entry = { name: tool.name, arguments: args }; calls.push(entry);
    try { entry.result = await tool.execute(id, args, signal, update); return entry.result; }
    catch (error) { entry.error = error.message; throw error; }
  } }));
  const system = 'You edit files in a private knowledge base. Read the relevant file before editing it. Change only what the user asked and preserve all unrelated content, formatting and metadata. Use targeted edits for existing files; use write only when necessary. Files marked > GENERATED are generated reports: refuse direct edits and explain that their source or script must be changed. Summarize the actual outcome accurately and briefly.';
  const resourceLoader = {
    getExtensions: () => ({ extensions: [], errors: [], runtime: createExtensionRuntime() }),
    getSkills: () => ({ skills: [], diagnostics: [] }), getPrompts: () => ({ prompts: [], diagnostics: [] }),
    getThemes: () => ({ themes: [], diagnostics: [] }), getAgentsFiles: () => ({ agentsFiles: [] }),
    getSystemPrompt: () => system, getAppendSystemPrompt: () => [], extendResources: () => {}, reload: async () => {}
  };
  const { session } = await createAgentSession({ cwd: input.vault, agentDir: input.agentDir,
    authStorage, modelRegistry, model: modelRegistry.find('holdfast-file-eval', input.model), thinkingLevel: 'off',
    // SDK `tools` selects built-in names; customTools installs these exact
    // wrapped implementations, including the scratch boundary and call trace.
    tools: [], customTools: wrapped, resourceLoader, sessionManager: SessionManager.inMemory(),
    settingsManager: SettingsManager.inMemory({ compaction: { enabled: false }, retry: { enabled: false } }) });
  session.agent.toolExecution = 'sequential';
  if (session.getActiveToolNames().sort().join(',') !== 'edit,read,write') throw new Error('Unexpected active tools');
  const stream = session.agent.streamFn;
  let turns = 0;
  session.agent.streamFn = (model, context, options) => {
    if (turns > 8) throw new Error('Model round budget exhausted');
    const final = turns++ === 8 || calls.length >= 32;
    return stream(model, { ...context, systemPrompt: system, tools: final ? [] : context.tools },
      { ...options, maxTokens: 2000, temperature: 0.7 });
  };
  try {
    const started = performance.now();
    await session.prompt(input.question);
    const loopSeconds = (performance.now() - started) / 1000;
    const assistants = session.messages.filter(message => message.role === 'assistant');
    const last = assistants.at(-1);
    if (!last || ['error', 'aborted'].includes(last.stopReason)) throw new Error(last?.errorMessage ?? 'No answer');
    writeFileSync(input.transcript, JSON.stringify(session.messages, null, 2));
    console.log(JSON.stringify({ answer: last.content.filter(block => block.type === 'text').map(block => block.text).join(''),
      loopSeconds, calls, turns, outputTokens: assistants.reduce((sum, message) => sum + message.usage.output, 0), system }));
  } finally { session.dispose(); }
}
