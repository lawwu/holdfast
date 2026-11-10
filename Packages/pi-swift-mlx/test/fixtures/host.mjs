// Protocol peer for transport failure/cancellation tests; never used by the package.
const jobs = new Map();
const send = value => process.stdout.write(JSON.stringify(value) + '\n');
process.stderr.write('fixture host ready\n');
function receive(line) {
  const value = JSON.parse(line);
  if (value.type === 'cancel') { clearTimeout(jobs.get(value.id)); jobs.delete(value.id); send({ type: 'response', id: value.id, error: 'cancelled' }); return; }
  if (value.request.system === 'exit') process.exit(9);
  const finish = () => {
    jobs.delete(value.id);
    const text = value.request.messages[0].text;
    const wire = Buffer.from(JSON.stringify({ type: 'delta', id: value.id, text }) + '\n');
    for (const byte of wire) process.stdout.write(Buffer.from([byte]));
    send({ type: 'response', id: value.id, result: { text, calls: [] } });
  };
  jobs.set(value.id, setTimeout(finish, value.request.system === 'delay' ? 10000 : 0));
}
let buffer = Buffer.alloc(0);
process.stdin.on('data', data => {
  buffer = Buffer.concat([buffer, data]); let end;
  while ((end = buffer.indexOf(10)) !== -1) { receive(buffer.subarray(0, end).toString('utf8')); buffer = buffer.subarray(end + 1); }
});
process.stdin.on('end', () => process.exit(0));
