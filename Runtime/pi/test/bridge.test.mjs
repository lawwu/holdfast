import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, rm, writeFile, readdir, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const runner = fileURLToPath(new URL('../runner.mjs', import.meta.url));
const spec = { name: 'propose_edit', description: 'Propose an edit for approval', fields: { path: 'Note', new_text: 'Append' }, required: ['path', 'new_text'] };
const reply = (text, calls = []) => ({ text, calls, usage: { promptTokens: 10, outputTokens: 5 } });
const call = { id: 'call-1', name: 'propose_edit', arguments: JSON.stringify({ path: 'note.md', new_text: 'line 🌿\u2028tail' }) };
async function drive(config, respond) {
  const child = spawn(process.execPath, [runner], { stdio: ['pipe', 'pipe', 'pipe'] });
  let errors = '', outcome, buffer = Buffer.alloc(0);
  child.stderr.on('data', data => { errors += data; });
  const closed = new Promise((resolve, reject) => {
    child.once('error', reject); child.once('close', (code, signal) => resolve({ code, signal }));
  });
  child.stdin.on('error', () => {});
  child.stdin.write(JSON.stringify({ type: 'start', protocol: 1, model: 'test-mlx', system: 'Test assistant', tools: [spec], ...config }) + '\n');
  try {
    for await (const chunk of child.stdout) {
      buffer = Buffer.concat([buffer, chunk]); let end;
      while ((end = buffer.indexOf(10)) !== -1) {
        const value = JSON.parse(buffer.subarray(0, end).toString('utf8')); buffer = buffer.subarray(end + 1);
        if (value.type === 'request') {
          const result = await respond(value, child);
          if (result !== undefined && !child.stdin.destroyed) child.stdin.write(JSON.stringify({ type: 'response', id: value.id, result }) + '\n');
        }
        if (value.type === 'done' || value.type === 'error') outcome = value;
      }
    }
    return { ...await closed, outcome, errors };
  } finally { if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL'); }
}
async function records(dir) {
  const files = (await readdir(dir)).filter(f => f.endsWith('.jsonl'));
  assert.equal(files.length, 1);
  return (await readFile(join(dir, files[0]), 'utf8')).trim().split('\n').map(JSON.parse);
}

test('regular Pi JSONL: tools, Unicode, follow-ups and completed-request deduplication', { timeout: 25000 }, async () => {
  const dir = await mkdtemp(join(tmpdir(), 'holdfast-regular-pi-'));
  try {
    await writeFile(join(dir, 'AGENTS.md'), 'DO NOT DISCOVER THIS CONTEXT');
    const config = { sessionDirectory: dir, question: 'Append a line', requestID: 'first' };
    let models = 0, tools = 0;
    const first = await drive(config, r => {
      if (r.method === 'tool') { tools++; assert.equal(r.params.args.new_text, 'line 🌿\u2028tail'); return { text: 'Waiting in Inbox 🌿\u2028tail', isError: false }; }
      assert.deepEqual(r.params.tools.map(t => t.name), ['propose_edit']);
      assert(!r.params.system.includes('DO NOT DISCOVER'));
      if (++models === 1) return reply('', [call]);
      assert.equal(r.params.messages.at(-1).text, 'Waiting in Inbox 🌿\u2028tail');
      return reply('Waiting for approval.');
    });
    assert.equal(first.outcome?.text, 'Waiting for approval.', JSON.stringify(first));
    assert.equal(tools, 1);
    const duplicate = await drive(config, () => assert.fail('A completed request must not execute again'));
    assert.equal(duplicate.outcome?.text, first.outcome.text);
    const mismatch = await drive({ ...config, question: 'Different question' }, () => assert.fail());
    assert.match(mismatch.outcome?.message, /another question/);
    const next = await drive({ ...config, question: 'What is waiting?', requestID: 'second' }, r => {
      assert.equal(r.method, 'model'); assert(r.params.messages.some(m => m.role === 'tool' && m.text.includes('Inbox')));
      assert.equal(r.params.messages.at(-1).text, 'What is waiting?');
      return reply('The same proposal.');
    });
    assert.equal(next.outcome?.text, 'The same proposal.', JSON.stringify(next));
    assert((await records(dir)).some(e => e.customType === 'holdfast.request' && e.data.status === 'complete'));
    assert(!(await readdir(dir)).some(f => f.endsWith('.sqlite')));
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('interrupted tool is not replayed; a new request continues the saved conversation', { timeout: 25000 }, async () => {
  const dir = await mkdtemp(join(tmpdir(), 'holdfast-pi-interrupted-'));
  try {
    const config = { sessionDirectory: dir, question: 'Append a line', requestID: 'interrupted' };
    let effects = 0;
    const crashed = await drive(config, (r, child) => {
      if (r.method === 'model') return reply('', [call]);
      effects++; child.kill('SIGKILL');
    });
    assert.equal(crashed.signal, 'SIGKILL');
    const repeat = await drive(config, () => assert.fail('Interrupted work must not replay'));
    assert.match(repeat.outcome?.message, /interrupted or stopped/);
    const next = await drive({ ...config, requestID: 'new', question: 'What happened?' }, r => {
      assert.equal(r.method, 'model');
      assert(r.params.messages.some(m => m.role === 'tool' && m.text.includes('outcome is unknown')));
      assert.equal(r.params.messages.at(-1).text, 'What happened?');
      return reply('Check the existing Inbox proposal.');
    });
    assert.equal(next.outcome?.text, 'Check the existing Inbox proposal.', JSON.stringify(next));
    assert.equal(effects, 1);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('Stop cancels inference; next request can continue without executing stopped tools', { timeout: 25000 }, async () => {
  const dir = await mkdtemp(join(tmpdir(), 'holdfast-pi-stop-'));
  try {
    const config = { sessionDirectory: dir, question: 'Stop', requestID: 'stop' };
    const stopped = await drive(config, (r, child) => {
      assert.equal(r.method, 'model'); child.stdin.write(JSON.stringify({ type: 'abort' }) + '\n');
    });
    assert.equal(stopped.code, 0, JSON.stringify(stopped));
    const next = await drive({ ...config, requestID: 'next', question: 'Continue' }, r => {
      assert.equal(r.method, 'model'); return reply('Ready.');
    });
    assert.equal(next.outcome?.text, 'Ready.', JSON.stringify(next));
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('built-in file and shell tools are unavailable', { timeout: 25000 }, async () => {
  const dir = await mkdtemp(join(tmpdir(), 'holdfast-pi-tools-'));
  try {
    let models = 0;
    const value = await drive({ sessionDirectory: dir, question: 'Test tools', requestID: 'tools' }, r => {
      assert.equal(r.method, 'model', 'No built-in tool may reach the native service');
      assert.deepEqual(r.params.tools.map(t => t.name), ['propose_edit']);
      if (++models === 1) return reply('', [{ id: 'write', name: 'write', arguments: JSON.stringify({ path: join(dir, 'must-not-exist'), content: 'unsafe' }) }]);
      return reply('Use proposals only.');
    });
    assert.equal(value.outcome?.text, 'Use proposals only.', JSON.stringify(value));
    assert(!(await readdir(dir)).includes('must-not-exist'));
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('native tool refusals stay errors in the saved Pi conversation', { timeout: 25000 }, async () => {
  const dir = await mkdtemp(join(tmpdir(), 'holdfast-pi-error-'));
  try {
    let models = 0;
    const value = await drive({ sessionDirectory: dir, question: 'Try a proposal', requestID: 'refusal' }, r => {
      if (r.method === 'tool') return { text: 'Error: generated notes cannot be edited', isError: true };
      if (++models === 1) return reply('', [call]);
      assert.equal(r.params.messages.at(-1).isError, true);
      assert.match(r.params.messages.at(-1).text, /generated notes/);
      return reply('That note is generated; no proposal was made.');
    });
    assert.equal(value.outcome?.type, 'done', JSON.stringify(value));
    const entries = await records(dir);
    assert(entries.some(e => e.message?.role === 'toolResult' && e.message.isError === true));
  } finally { await rm(dir, { recursive: true, force: true }); }
});
