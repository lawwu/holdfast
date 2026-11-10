import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const runner = fileURLToPath(new URL('../runner.mjs', import.meta.url));
const spec = { name: 'propose_edit', description: 'Propose an edit for approval', fields: { path: 'Note', new_text: 'Append' }, required: ['path', 'new_text'] };
const reply = (text, calls = []) => ({ text, calls, usage: { promptTokens: 10, outputTokens: 5 } });
const call = { id: 'call-1', name: 'propose_edit', arguments: JSON.stringify({ path: 'note.md', new_text: 'line' }) };

async function drive(config, respond) {
  const child = spawn(process.execPath, [runner], { stdio: ['pipe', 'pipe', 'pipe'] });
  let errors = '', outcome;
  child.stderr.on('data', data => { errors += data; });
  const lines = createInterface({ input: child.stdout });
  const closed = new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (code, signal) => resolve({ code, signal }));
  });
  child.stdin.on('error', () => {});
  child.stdin.write(JSON.stringify({ type: 'start', protocol: 1, model: 'test-mlx', system: 'Test assistant', tools: [spec], ...config }) + '\n');
  for await (const line of lines) {
    const value = JSON.parse(line);
    if (value.type === 'request') {
      const result = await respond(value, child);
      if (result !== undefined) child.stdin.write(JSON.stringify({ type: 'response', id: value.id, result }) + '\n');
    }
    if (value.type === 'done' || value.type === 'error') outcome = value;
  }
  const status = await closed;
  return { ...status, outcome, errors };
}

test('real durable SQLite: interrupted proposal replays the same ID, follow-up and duplicate submission retain history', { timeout: 25000 }, async () => {
  const dir = await mkdtemp(join(tmpdir(), 'holdfast-pi-'));
  try {
    const config = { database: join(dir, 'conversation.sqlite'), question: 'Append a line', requestID: 'request-1' };
    const receipts = new Map();
    let effects = 0, initialOperation;
    const interrupted = await drive(config, async (r, child) => {
      if (r.method === 'model') return reply('', [call]);
      initialOperation = r.params.operationID;
      assert.equal(typeof initialOperation, 'string');
      effects++; receipts.set(initialOperation, { text: 'Proposal waiting in Inbox', isError: false });
      child.kill('SIGKILL'); // Native side effect happened, Pi hasn't committed its result.
    });
    assert.equal(interrupted.signal, 'SIGKILL');
    const resumed = await drive(config, async r => {
      if (r.method === 'tool') {
        assert.equal(r.params.operationID, initialOperation);
        return receipts.get(initialOperation);
      }
      assert.equal(r.params.messages.at(-1).role, 'tool');
      assert.match(r.params.messages.at(-1).text, /waiting/);
      return reply('Waiting for your approval.');
    });
    assert.equal(resumed.outcome?.type, 'done', JSON.stringify(resumed));
    assert.equal(effects, 1);
    const duplicate = await drive(config, () => { throw new Error('Duplicate request must not run inference or tools'); });
    assert.equal(duplicate.outcome?.text, 'Waiting for your approval.');
    const followup = await drive({ ...config, question: 'What is waiting?', requestID: 'request-2' }, r => {
      assert.equal(r.method, 'model');
      assert(r.params.messages.some(m => m.role === 'tool' && m.text.includes('Inbox')));
      assert.equal(r.params.messages.at(-1).text, 'What is waiting?');
      return reply('The edit is still waiting.');
    });
    assert.equal(followup.outcome?.text, 'The edit is still waiting.');
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('hard-killed model generation resumes without repeating a completed tool', { timeout: 25000 }, async () => {
  const dir = await mkdtemp(join(tmpdir(), 'holdfast-pi-model-crash-'));
  try {
    const config = { database: join(dir, 'conversation.sqlite'), question: 'Append a line', requestID: 'model-crash' };
    let modelCalls = 0, effects = 0;
    const interrupted = await drive(config, (r, child) => {
      if (r.method === 'tool') { effects++; return { text: 'Proposal waiting in Inbox', isError: false }; }
      if (++modelCalls === 1) return reply('', [call]);
      child.kill('SIGKILL'); // Pi committed the tool result, but not the next model answer.
    });
    assert.equal(interrupted.signal, 'SIGKILL');
    const resumed = await drive(config, r => {
      assert.equal(r.method, 'model', 'A completed tool must not run again');
      assert(r.params.messages.some(m => m.role === 'tool' && m.text.includes('Inbox')));
      return reply('Recovered; approval is still pending.');
    });
    assert.equal(resumed.outcome?.type, 'done', JSON.stringify(resumed));
    assert.equal(resumed.outcome.text, 'Recovered; approval is still pending.');
    assert.equal(effects, 1);
    const duplicate = await drive(config, () => assert.fail('A recovered input must remain idempotent'));
    assert.equal(duplicate.outcome?.text, resumed.outcome.text);
  } finally { await rm(dir, { recursive: true, force: true }); }
});
