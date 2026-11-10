#!/usr/bin/env python3
"""Real Swift bridge + regular Pi JSONL + Inbox; synthetic local inference only."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

binary = Path(sys.argv[1]).resolve()
root = Path(__file__).resolve().parents[1]
scratch = Path.home() / '.cache'
scratch.mkdir(exist_ok=True)

def reply(text='', calls=()):
    return dict(text=text, reasoning='', calls=list(calls), usage=dict(promptTokens=10, promptSeconds=.1, outputTokens=5, outputSeconds=.1), truncated=False)

def call(name, **args):
    return dict(id=str(uuid.uuid4()), name=name, arguments=json.dumps(args))

with tempfile.TemporaryDirectory(prefix='holdfast-pi-test-', dir=scratch) as temporary:
    vault = Path(temporary).resolve() / 'vault'
    (vault / 'finance').mkdir(parents=True)
    (vault / '.agent-eval-synthetic').write_text('synthetic holdfast agent evaluation\n')
    note = vault / 'finance/checklist.md'
    before = b'\xef\xbb\xbf# Checklist\r\n\r\n- [ ] Protect pretax 401(k) basis\r\n- [ ] Keep this open\r\n'
    note.write_bytes(before)
    env = {**os.environ, 'HOLDFAST_VAULT': str(vault), 'HOLDFAST_AGENT_EVAL': '1', 'HOLDFAST_PACKS': 'none',
           'HOLDFAST_EMBED': 'none', 'HOLDFAST_RERANK': '0', 'HOLDFAST_THINK': '0', 'HOLDFAST_AGENT_HARNESS': 'swift',
           'HOLDFAST_PI_DIR': str(root / 'Runtime/pi')}
    def cli(*args, check=True):
        result = subprocess.run([str(binary), *args], env=env, capture_output=True, text=True, timeout=45)
        if check: assert result.returncode == 0, result.stderr
        return result
    def bridge(request, check=True):
        result = subprocess.run([str(binary), '_agent-eval'], input=json.dumps(request)+'\n', env=env, capture_output=True, text=True, timeout=45)
        assert result.returncode == 0, (result.returncode, result.stderr)
        value = json.loads(result.stdout.splitlines()[-1])
        if check: assert 'error' not in value, (value, result.stderr)
        return value
    state = Path(bridge({'op': 'config'})['stateDir'])
    try:
        convo = str(uuid.uuid4())
        request = dict(op='run_pi', conversationID=convo, question='Mark the basis item done', replies=[
            reply(calls=[call('read_note', path='finance/checklist.md')]),
            reply(calls=[call('propose_edit', path='finance/checklist.md', old_text='- [ ] Protect pretax 401(k) basis', new_text='- [x] Protect pretax 401(k) basis')]),
            reply('Waiting for Inbox approval. [1]')])
        result = bridge(request)
        assert result['badCitations'] == [] and result['sources'] and result['sources'][0]['path'] == 'finance/checklist.md', result
        assert note.read_bytes() == before, 'Pi must not apply its own proposal'
        proposals = list((state/'inbox').glob('*.md')); assert len(proposals) == 1
        proposal = proposals[0]
        assert 'agent_operations:' in proposal.read_text()
        cli('approve', '@inbox/'+proposal.stem)
        applied = note.read_bytes()
        assert applied.startswith(b'\xef\xbb\xbf') and b'- [x] Protect' in applied and b'- [ ] Keep' in applied
        # A second independent approval inside the old snapshot throttle window.
        bridge(dict(op='call', name='propose_edit', arguments=dict(path='finance/checklist.md', old_text='- [ ] Keep this open', new_text='- [x] Keep this open')))
        second = list((state/'inbox').glob('*.md')); assert len(second) == 1
        cli('approve', '@inbox/'+second[0].stem)
        cli('undo', '1'); assert note.read_bytes() == applied, 'second approval must have its own snapshot'
        cli('undo', '2'); assert note.read_bytes() == before, 'Undo must restore BOM and CRLF bytes'
        for p in (state/'inbox').glob('*.md'): cli('reject', '@inbox/'+p.stem)
        print('PASS proposal → two approvals → byte-exact Undo (BOM/CRLF)')

        # A new process continues the same Pi conversation and source numbering.
        result = bridge(dict(op='run_pi', conversationID=convo, question='What did you read?', replies=[reply('The checklist. [1]')]))
        assert result['badCitations'] == [] and len(result['sources']) == 1, result
        print('PASS follow-up retains native citations across process restart')

        # Crash after native atomic proposal write but before its receipt is durable:
        # exercising the extra idempotency key inside the actual proposal.
        op = 'synthetic-replayed-operation'
        proposal_args = dict(path='finance/checklist.md', old_text='', new_text='- [ ] Append once')
        first = bridge(dict(op='call', name='propose_edit', operationID=op, arguments=proposal_args))
        second = bridge(dict(op='call', name='propose_edit', operationID=op, arguments=proposal_args))
        assert 'already proposed' in second['text'], second
        proposal = list((state/'inbox').glob('*.md'))[0]
        assert proposal.read_text().count('- [ ] Append once') == 1
        note.write_bytes(before + b'\nHuman change\n')
        rejected = cli('approve', '@inbox/'+proposal.stem, check=False)
        assert rejected.returncode != 0 and 'changed after' in rejected.stderr, rejected.stderr
        cli('reject', '@inbox/'+proposal.stem); note.write_bytes(before)
        print('PASS proposal replay is idempotent and stale approval is refused')

        (vault/'finance/generated.md').write_text('> GENERATED\n\n- [ ] untouched\n')
        (vault/'finance/data.csv').write_text('key,value\na,1\n')
        for path in ['finance/generated.md', 'finance/data.csv', '../outside.md']:
            value = bridge(dict(op='call', name='propose_edit', arguments=dict(path=path, old_text='', new_text='change')))
            assert value['isError'], value
        assert not list((state/'inbox').glob('*.md'))
        print('PASS generated / non-note / traversal guards')

        crashed = str(uuid.uuid4()).upper()
        crash_request = dict(op='run_pi', conversationID=crashed, question='Propose an append once', delayMS=1000, replies=[
            reply(calls=[call('propose_edit', path='finance/checklist.md', old_text='', new_text='- [ ] Survive crash once')]), reply('Waiting. [1]')])
        child = subprocess.Popen([str(binary), '_agent-eval'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        try:
            child.stdin.write(json.dumps(crash_request)+'\n'); child.stdin.flush()
            native = state/'pi'/crashed/'native.json'
            deadline = time.monotonic()+15
            while not native.exists() and time.monotonic() < deadline:
                assert child.poll() is None, child.stderr.read()
                time.sleep(.02)
            assert native.exists(), 'native tool did not complete'
            child.kill(); child.wait(timeout=5)
        finally:
            if child.poll() is None: child.kill(); child.wait(timeout=5)
            child.stdin.close(); child.stdout.close(); child.stderr.close()
        time.sleep(.5) # EOF closes Pi; opening history must not replay the stopped job.
        resumed = bridge(dict(op='run_pi', conversationID=crashed, question='What was completed before the interruption?', replies=[reply('Recovered conversation; approval is still pending.')]))
        assert resumed['answer'].startswith('Recovered'), resumed
        assert note.read_bytes() == before
        proposals = list((state/'inbox').glob('*.md')); assert len(proposals) == 1
        assert proposals[0].read_text().count('- [ ] Survive crash once') == 1
        cli('reject', '@inbox/'+proposals[0].stem)
        print('PASS killed Swift host: new request opens saved history without replaying an interrupted tool')

        # Stop cancels this turn: next input can use the conversation and the stopped input
        # never produces a delayed proposal after its native model is cancelled.
        stopped = str(uuid.uuid4())
        value = bridge(dict(op='run_pi', conversationID=stopped, question='Stop this run', delayMS=10000, cancelAfterMS=500,
                            replies=[reply(calls=[call('propose_edit', path='finance/checklist.md', old_text='', new_text='MUST NOT APPEAR')])]), check=False)
        assert 'error' in value, value
        value = bridge(dict(op='run_pi', conversationID=stopped, question='Continue after Stop', replies=[reply('Ready.')]))
        assert value['answer'] == 'Ready.' and not list((state/'inbox').glob('*.md')), value
        assert not (state/'pi'/stopped.upper()/'pending.json').exists()
        print('PASS Stop cancels inference; new Pi turn works with no delayed proposal')
        assert not list((state/'pi').rglob('*.sqlite')), 'Regular Pi must not create Durable databases'
    finally:
        shutil.rmtree(state)
