// Opt-in real-model check: PI_MLX_HOST, PI_MLX_MODEL, PI_MLX_MODEL_DIR.
import assert from 'node:assert/strict';
import { createProcessTransport } from '../process.mjs';
import { runHarness } from './harnesses.mjs';

const transport = createProcessTransport({ executable: process.env.PI_MLX_HOST, model: process.env.PI_MLX_MODEL,
  modelDirectory: process.env.PI_MLX_MODEL_DIR, onStderr: text => process.stderr.write(text) });
const expected = { limit: 2, enabled: false, values: [0, 1, 2.5], metadata: { value: null } };
try {
  for (const kind of ['pi', 'durable']) {
    let tools = 0; const start = performance.now();
    const answer = await runHarness(kind, { model: process.env.PI_MLX_MODEL, generate: transport.generate,
      question: 'Call inspect_data exactly once with limit=2, enabled=false, values=[0,1,2.5], and metadata={"value":null}. After its result, reply with Finished.',
      execute: async args => { tools++; assert.deepEqual(args, expected); return 'inspection complete'; },
    });
    assert.equal(tools, 1); assert.match(answer, /finished/i);
    console.log(JSON.stringify({ harness: kind, model: process.env.PI_MLX_MODEL, answer, tools, seconds: (performance.now() - start) / 1000 }));
  }
} finally { await transport.close(); }
