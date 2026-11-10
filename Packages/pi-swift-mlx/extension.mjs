import { createSwiftMLXProvider } from './provider.mjs';
import { createProcessTransport } from './process.mjs';

/** Current Pi CLI extension. Host startup/model loading is lazy, after selection. */
export default function swiftMLXExtension(pi) {
  const { PI_MLX_HOST: executable, PI_MLX_MODEL: model, PI_MLX_MODEL_DIR: modelDirectory } = process.env;
  if (!executable || !model || !modelDirectory) throw new Error('Set PI_MLX_HOST, PI_MLX_MODEL and PI_MLX_MODEL_DIR to use Swift MLX');
  const transport = createProcessTransport({ executable, model, modelDirectory,
    onStderr: text => process.stderr.write(text) });
  pi.registerProvider(createSwiftMLXProvider({ model,
    contextWindow: Number(process.env.PI_MLX_CONTEXT_WINDOW ?? 32768), maxTokens: Number(process.env.PI_MLX_MAX_TOKENS ?? 2000),
  }, transport.generate));
  pi.on('session_shutdown', () => transport.close());
}
