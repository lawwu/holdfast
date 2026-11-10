import type { Provider, Model, TranscriptContext, StreamOptions } from '@earendil-works/pi-ai';
export type JSONValue = null | boolean | number | string | JSONValue[] | { [key: string]: JSONValue };
export interface Generation { maxTokens?: number; temperature?: number; topP?: number; topK?: number; presencePenalty?: number }
export interface ToolCall { id: string; name: string; arguments: string }
export interface NativeMessage { role: 'user' | 'assistant' | 'tool'; text: string; reasoning?: string; calls?: ToolCall[]; id?: string; name?: string; isError?: boolean }
export interface NativeRequest {
  version: 1; model: string; sessionID: string; system: string; messages: NativeMessage[];
  tools: { name: string; description: string; parameters: JSONValue }[]; generation: Generation;
}
export interface NativeReply {
  text: string; reasoning?: string; calls?: ToolCall[]; truncated?: boolean;
  usage?: { promptTokens: number; outputTokens: number; promptSeconds?: number; outputSeconds?: number };
}
export interface TransportOptions { signal?: AbortSignal; onDelta: (text: string) => void }
export type Generate = (request: NativeRequest, options: TransportOptions) => Promise<NativeReply>;
export interface ProviderOptions { model: string; providerID?: string; contextWindow?: number; maxTokens?: number; generation?: Generation }
export function createSwiftMLXProvider(config: ProviderOptions, generate: Generate): Provider;
export function nativeRequest(model: Model<any>, context: TranscriptContext, options?: StreamOptions & { toolChoice?: string }, defaults?: Generation): NativeRequest;
