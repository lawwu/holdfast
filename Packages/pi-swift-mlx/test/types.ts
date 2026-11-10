import { createSwiftMLXProvider, type Generate, type NativeRequest } from 'pi-swift-mlx';
import { createProcessTransport } from 'pi-swift-mlx/process';
import type { Provider } from '@earendil-works/pi-ai';

const request: NativeRequest = { version: 1, model: 'test', sessionID: 'session', system: '', messages: [],
  tools: [{ name: 'typed', description: '', parameters: { type: 'object', properties: { value: { type: ['number', 'null'] } } } }],
  generation: { temperature: 0, maxTokens: 64 } };
const generate: Generate = async (input, options) => {
  options.onDelta(input.model);
  return { text: 'ok', calls: [], usage: { promptTokens: 2, outputTokens: 1 } };
};
const provider: Provider = createSwiftMLXProvider({ model: 'test' }, generate);
const transport = createProcessTransport({ executable: '/path/to/host', model: 'test', modelDirectory: '/path/to/model' });
void request; void provider; void transport;
