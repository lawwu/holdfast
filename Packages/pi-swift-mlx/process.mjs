import { spawn } from 'node:child_process';

/** Inference-only subprocess transport. No shell, vault, tools, or harness dependency. */
export function createProcessTransport({ executable, model, modelDirectory, args = [], timeoutMs = 300_000, onStderr } = {}) {
  if (!executable || !model || !modelDirectory) throw new Error('executable, model and modelDirectory are required');
  let child, ended, exitError, closed = false, serial = 0, buffer = Buffer.alloc(0);
  const pending = new Map();
  function fail(error) { for (const job of [...pending.values()]) job.finish(error); }
  function stop(current, error) {
    if (child !== current) return;
    exitError ??= error;
    current.kill('SIGKILL'); // Pending work settles after close, so a retry starts a fresh host.
  }
  function start() {
    if (closed) throw new Error('Swift MLX transport is closed');
    if (child) return child;
    const current = spawn(executable, [...args, '--model', model, '--model-dir', modelDirectory], { stdio: ['pipe', 'pipe', 'pipe'] });
    child = current; exitError = undefined; buffer = Buffer.alloc(0);
    ended = new Promise(resolve => current.once('close', resolve));
    current.on('error', error => stop(current, error));
    current.stdin.on('error', error => stop(current, error));
    current.stderr.on('data', data => onStderr?.(data.toString('utf8')));
    current.once('close', (code, signal) => {
      if (child !== current) return;
      child = undefined;
      fail(exitError ?? new Error(`Swift MLX host exited (${signal ?? code})`));
    });
    current.stdout.on('data', data => {
      try {
        buffer = Buffer.concat([buffer, data]);
        let newline;
        while ((newline = buffer.indexOf(10)) !== -1) {
          if (newline > 32 * 1024 * 1024) throw new Error('Swift MLX frame exceeds 32 MiB');
          const value = JSON.parse(buffer.subarray(0, newline).toString('utf8'));
          buffer = buffer.subarray(newline + 1);
          const job = pending.get(value.id);
          if (value.type === 'delta') { if (!job?.aborted) job?.onDelta?.(value.text); }
          else if (value.type === 'response') job?.finish(value.error ? new Error(value.error) : undefined, value.result);
          else throw new Error('Invalid Swift MLX host response');
        }
        if (buffer.length > 32 * 1024 * 1024) throw new Error('Swift MLX frame exceeds 32 MiB');
      } catch (error) { stop(current, error); }
    });
    return current;
  }
  function generate(request, { signal, onDelta } = {}) {
    if (signal?.aborted) return Promise.reject(new DOMException('Cancelled', 'AbortError'));
    if (pending.size) return Promise.reject(new Error('Swift MLX transport is busy'));
    return new Promise((resolve, reject) => {
      let process;
      try { process = start(); } catch (error) { reject(error); return; }
      const id = String(++serial);
      let abortTimer;
      const timer = setTimeout(() => stop(process, new Error('Swift MLX request timed out')), timeoutMs);
      const abort = () => {
        job.aborted = true;
        process.stdin.write(JSON.stringify({ type: 'cancel', id }) + '\n');
        // Wait for native cancellation acknowledgement before accepting another request.
        abortTimer = setTimeout(() => process.kill('SIGKILL'), 3000);
      };
      const job = { onDelta, aborted: false, finish(error, result) {
        pending.delete(id); clearTimeout(timer); clearTimeout(abortTimer); signal?.removeEventListener('abort', abort);
        if (job.aborted) reject(new DOMException('Cancelled', 'AbortError'));
        else if (error) reject(error); else resolve(result);
      } };
      pending.set(id, job); signal?.addEventListener('abort', abort, { once: true });
      process.stdin.write(JSON.stringify({ type: 'generate', id, request }) + '\n');
      if (signal?.aborted) abort();
    });
  }
  async function close() {
    closed = true;
    const current = child;
    if (!current) return;
    current.stdin.end();
    const timer = setTimeout(() => current.kill('SIGKILL'), 3000);
    await ended; clearTimeout(timer);
  }
  return { generate, close };
}
