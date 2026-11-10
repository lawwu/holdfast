import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createModels, InMemoryCredentialStore } from '@earendil-works/pi-ai';
import { createAgentSession, DefaultResourceLoader, ModelRuntime, SessionManager, SettingsManager } from '@earendil-works/pi-coding-agent';
import { BACKGROUND_CONTEXT as ctx } from '@earendil-works/chord/context';
import { AssistantEntry, createRegistry, defineExtension, defineTool, Harness, MemoryStorage, section } from '@earendil-works/pi-durable';
import { createSwiftMLXProvider } from '../provider.mjs';

export const schema = { type: 'object', properties: {
  limit: { type: 'integer' }, enabled: { type: 'boolean' }, values: { type: 'array', items: { type: 'number' } },
  metadata: { type: 'object', properties: { value: { type: 'null' } }, required: ['value'], additionalProperties: false },
}, required: ['limit', 'enabled', 'values', 'metadata'], additionalProperties: false };

export async function runHarness(kind, { model = 'fixture', generate, question = 'Inspect the data, then answer.', execute }) {
  const provider = createSwiftMLXProvider({ model }, generate);
  if (kind === 'durable') {
    const models = createModels(); models.setProvider(provider);
    const registry = createRegistry();
    registry.install(defineExtension({ name: 'fixture', sections: [section('test', () => 'Use inspect_data when asked.', { tag: false })],
      tools: [defineTool({ name: 'inspect_data', description: 'Inspect typed data', parameters: schema, replay: 'safe',
        execute: async args => ({ output: [{ type: 'text', text: await execute(args) }] }) })] }));
    const harness = await Harness.open(new MemoryStorage(), { models, registry, settings: { compaction: { enabled: false }, retry: { maxRetries: 0 } } }, ctx);
    try {
      const root = await harness.root(ctx, { agent: { model: { provider: 'swift-mlx', modelId: model }, maxTurns: 3 } });
      const settled = await (await root.submit({ type: 'input', content: question }, ctx)).wait(ctx);
      if (settled.status !== 'done') throw new Error(JSON.stringify(settled));
      const entry = await root.commit(tx => tx.entry(AssistantEntry, settled.answer), ctx);
      return entry.model[0].content.filter(c => c.type === 'text').map(c => c.text).join('');
    } finally { await harness.close(ctx); }
  }
  const dir = await mkdtemp(join(tmpdir(), 'pi-swift-mlx-sdk-'));
  let session;
  try {
    const runtime = await ModelRuntime.create({ credentials: new InMemoryCredentialStore(), modelsPath: null,
      modelsStorePath: join(dir, 'models-cache.json'), refreshOnCreate: false, allowModelNetwork: false });
    runtime.registerNativeProvider(provider);
    const settingsManager = SettingsManager.inMemory({ compaction: { enabled: false }, retry: { enabled: false } });
    const resourceLoader = new DefaultResourceLoader({ cwd: dir, agentDir: dir, settingsManager,
      noExtensions: true, disabledBuiltinExtensions: ['mcp'], noSkills: true, noPromptTemplates: true, noThemes: true,
      noContextFiles: true, systemPrompt: 'Use inspect_data when asked.' });
    await resourceLoader.reload();
    ({ session } = await createAgentSession({ cwd: dir, agentDir: dir, modelRuntime: runtime,
      model: runtime.getModel('swift-mlx', model), thinkingLevel: 'off', resourceLoader, settingsManager,
      sessionManager: SessionManager.inMemory(), tools: ['inspect_data'], customTools: [{
        name: 'inspect_data', label: 'Inspect data', description: 'Inspect typed data', parameters: schema,
        execute: async (_id, args) => ({ content: [{ type: 'text', text: await execute(args) }], details: {} }),
      }] }));
    await session.prompt(question);
    const answer = session.getLastAssistantText();
    if (answer === undefined) throw new Error(`Pi did not answer: ${JSON.stringify(session.messages.at(-1))}`);
    return answer;
  } finally { session?.dispose(); await rm(dir, { recursive: true, force: true }); }
}
