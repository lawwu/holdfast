import { createProvider, createAssistantMessageEventStream, getCurrentSystemPrompt, getCurrentTools } from '@earendil-works/pi-ai';

function textContent(content) {
  if (typeof content === 'string') return content;
  return content.map(block => {
    if (block.type !== 'text') throw new Error(`Swift MLX bridge only supports text, received ${block.type}`);
    return block.text;
  }).join('\n');
}

// Pi keeps system/tool updates in the transcript. Fold them before sending to MLX,
// whose chat template has one leading system prompt.
export function nativeRequest(model, context, options = {}, defaults = {}) {
  if (options.toolChoice && options.toolChoice !== 'auto' && options.toolChoice !== 'none') {
    throw new Error('Swift MLX supports toolChoice auto or none');
  }
  const generation = { ...defaults, maxTokens: options.maxTokens ?? defaults.maxTokens ?? model.maxTokens,
    ...(options.temperature === undefined ? {} : { temperature: options.temperature }) };
  if (!Number.isInteger(generation.maxTokens) || generation.maxTokens < 1 || generation.maxTokens > 32768) throw new Error('Invalid maxTokens');
  return {
    version: 1, model: model.id, sessionID: options.sessionId ?? 'default', generation,
    system: getCurrentSystemPrompt(context.messages),
    tools: options.toolChoice === 'none' ? [] : getCurrentTools(context.messages).map(t => ({ name: t.name,
      description: t.description ?? '', parameters: t.parameters })),
    messages: context.messages.filter(m => m.role !== 'system').map(m => {
      if (m.role === 'user') return { role: 'user', text: textContent(m.content) };
      if (m.role === 'toolResult') return { role: 'tool', id: m.toolCallId, name: m.toolName, text: textContent(m.content), isError: m.isError };
      if (m.role !== 'assistant') throw new Error(`Unsupported transcript role: ${m.role}`);
      return { role: 'assistant', text: m.content.filter(b => b.type === 'text').map(b => b.text).join(''),
        reasoning: m.content.filter(b => b.type === 'thinking').map(b => b.thinking).join(''),
        calls: m.content.filter(b => b.type === 'toolCall').map(b => ({ id: b.id, name: b.name, arguments: JSON.stringify(b.arguments) })) };
    }),
  };
}

export function createSwiftMLXProvider(config, generate) {
  if (!config.model || typeof generate !== 'function') throw new Error('A model ID and inference transport are required');
  const stream = (model, context, options = {}) => {
    const events = createAssistantMessageEventStream();
    const message = { role: 'assistant', content: [], api: model.api, provider: model.provider, model: model.id,
      usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } }, stopReason: 'stop', timestamp: Date.now() };
    void (async () => {
      try {
        events.push({ type: 'start', partial: message });
        let textIndex;
        const delta = text => {
          if (textIndex === undefined) {
            textIndex = message.content.length; message.content.push({ type: 'text', text: '' });
            events.push({ type: 'text_start', contentIndex: textIndex, partial: message });
          }
          message.content[textIndex].text += text;
          events.push({ type: 'text_delta', contentIndex: textIndex, delta: text, partial: message });
        };
        const reply = await generate(nativeRequest(model, context, options, config.generation), { signal: options.signal, onDelta: delta });
        if (reply.truncated && reply.calls?.length) throw new Error('MLX reached its output limit; no tool calls from this response were executed.');
        if (textIndex === undefined && reply.text) delta(reply.text);
        if (textIndex !== undefined) events.push({ type: 'text_end', contentIndex: textIndex, content: message.content[textIndex].text, partial: message });
        if (reply.reasoning) message.content.push({ type: 'thinking', thinking: reply.reasoning });
        const calls = (reply.calls ?? []).map(call => {
          const args = JSON.parse(call.arguments);
          if (!args || Array.isArray(args) || typeof args !== 'object') throw new Error('Tool arguments must be an object');
          if (!call.id || !call.name) throw new Error('Tool calls need an ID and name');
          return { type: 'toolCall', id: call.id, name: call.name, arguments: args };
        });
        for (const toolCall of calls) {
          const contentIndex = message.content.length;
          message.content.push(toolCall);
          events.push({ type: 'toolcall_start', contentIndex, partial: message });
          events.push({ type: 'toolcall_end', contentIndex, toolCall, partial: message });
        }
        message.usage.input = reply.usage?.promptTokens ?? 0;
        message.usage.output = reply.usage?.outputTokens ?? 0;
        message.usage.totalTokens = message.usage.input + message.usage.output;
        message.stopReason = reply.truncated ? 'length' : calls.length ? 'toolUse' : 'stop';
        events.push({ type: 'done', reason: message.stopReason, message });
      } catch (error) {
        message.stopReason = options.signal?.aborted ? 'aborted' : 'error';
        message.errorMessage = String(error.message ?? error);
        events.push({ type: 'error', reason: message.stopReason, error: message });
      } finally { events.end(); }
    })();
    return events;
  };
  const provider = config.providerID ?? 'swift-mlx';
  return createProvider({ id: provider, name: 'Swift MLX',
    auth: { apiKey: { name: 'In-process MLX', resolve: async () => ({ auth: {} }) } },
    models: [{ id: config.model, name: config.model, api: 'swift-mlx', provider,
      baseUrl: 'pipe://swift-mlx', reasoning: false, input: ['text'], contextWindow: config.contextWindow ?? 32768,
      maxTokens: config.maxTokens ?? 2000, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }],
    api: { stream, streamSimple: stream } });
}
