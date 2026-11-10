import type { Generate } from './index.js';
export interface ProcessOptions {
  executable: string; model: string; modelDirectory: string; args?: string[]; timeoutMs?: number; onStderr?: (text: string) => void;
}
export function createProcessTransport(options: ProcessOptions): { generate: Generate; close(): Promise<void> };
