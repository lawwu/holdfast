#!/usr/bin/env python3
"""Production CLI + all server choices + both harnesses, using synthetic notes and HTTP peers."""
import http.server, json, os, pathlib, shutil, subprocess, sys, tempfile, threading, uuid

binary = pathlib.Path(sys.argv[1]).resolve()
cache = pathlib.Path.home()/'.cache'
before = b'\xef\xbb\xbf# Checklist\r\n\r\n- [ ] Keep basis\r\n- [ ] Leave this open\r\n'

def scenario(kind, pi, private=False, live=False, legacy=False):
    with tempfile.TemporaryDirectory(prefix='holdfast-providers-', dir=cache) as temp:
        vault = pathlib.Path(temp)/'vault'
        folder = 'ministry' if private else 'finance'
        (vault/folder).mkdir(parents=True)
        note = vault/folder/'checklist.md'
        note.write_bytes(b'# Session\nPRIVATE_SENTINEL_never_send\n' if private else before)
        h = 1469598103934665603
        for byte in str(vault).encode(): h = ((h ^ byte)*1099511628211) & ((1<<64)-1)
        state = pathlib.Path.home()/'Library/Application Support/Holdfast/vaults'/('vault-'+format(h,'x')[:8])
        assert not state.exists()
        received, failures = [], []
        conversation = str(uuid.uuid4())
        legacy_files = {}
        if legacy:
            old = state/'pi-durable'/conversation.upper()
            old.mkdir(parents=True)
            legacy_files = {old/'native.json': json.dumps({'sources': [], 'receipts': {}, 'localOnly': True}).encode(),
                            old/'conversation.sqlite': b'SYNTHETIC_DURABLE_ARCHIVE', old/'pending.json': b'{"unfinished":"preserve"}'}
            for path, data in legacy_files.items(): path.write_bytes(data)

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def do_POST(self):
                try:
                    assert self.headers.get('Authorization') == 'Bearer integration-key'
                    data = self.rfile.read(int(self.headers['Content-Length']))
                    assert b'PRIVATE_SENTINEL' not in data, 'private content leaked'
                    body = json.loads(data); stage = len(received); received.append(body)
                    native = kind == 'ollama'
                    assert self.path == ('/api/chat' if native else '/v1/chat/completions')
                    assert {t['function']['name'] for t in body['tools']} == {'search','read_note','list_folder','list_tables','query_table','propose_edit'}
                    if stage == 0:
                        name, args = 'read_note', {'path': f'{folder}/checklist.md'}
                    elif stage == 1:
                        assert not private, 'private conversation contacted the server again'
                        assert '- [ ] Keep basis' in body['messages'][-1]['content']
                        name, args = 'propose_edit', {'path': 'finance/checklist.md', 'old_text': '- [ ] Keep basis', 'new_text': '- [x] Keep basis', 'why': 'User requested this edit'}
                    else:
                        assert not private
                        name = None
                    message = {'role': 'assistant', 'content': ''}
                    if name:
                        message['tool_calls'] = [{'id': f'call-{stage}', 'type': 'function', 'function': {'name': name, 'arguments': args if native else json.dumps(args)}}]
                    else:
                        message['content'] = 'The change is waiting in the Inbox. [1]'
                    if native:
                        payload = json.dumps({'message': message, 'done': True, 'done_reason': 'stop', 'eval_count': 10}).encode()+b'\n'
                        content_type = 'application/x-ndjson'
                    else:
                        payload = ('data: '+json.dumps({'choices': [{'index': 0, 'delta': message, 'finish_reason': 'tool_calls' if name else 'stop'}]})+'\n\ndata: [DONE]\n\n').encode()
                        content_type = 'text/event-stream'
                    self.send_response(200); self.send_header('Content-Type', content_type); self.send_header('Content-Length', str(len(payload))); self.end_headers(); self.wfile.write(payload)
                except Exception as error:
                    failures.append(repr(error)); self.send_error(500)

        server = http.server.ThreadingHTTPServer(('127.0.0.1',0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        env = {**os.environ, 'HOLDFAST_VAULT': str(vault), 'HOLDFAST_BACKEND': kind,
               'HOLDFAST_PROVIDER_URL': f'http://127.0.0.1:{server.server_port}', 'HOLDFAST_PROVIDER_MODEL': 'synthetic-model',
               'HOLDFAST_PROVIDER_API_KEY': 'integration-key', 'HOLDFAST_MLX_REPO': 'test/no-model-downloaded',
               'HOLDFAST_EMBED': 'none', 'HOLDFAST_RERANK': '0', 'HOLDFAST_PACKS': 'none', 'HOLDFAST_AGENT_HARNESS': 'swift'}
        env.pop('HOLDFAST_MLX_DIR', None)
        def run(*args, success=True):
            result = subprocess.run([str(binary), *args], env=env, text=True, capture_output=True, timeout=600 if live else 90)
            if success: assert result.returncode == 0, result.stdout+result.stderr+repr(failures)
            else: assert result.returncode != 0, 'expected refusal'
            return result
        if live == "mlx":
            env.update(HOLDFAST_BACKEND="mlx", HOLDFAST_MLX_REPO="mlx-community/Qwen3.8-27B-4bit")
        elif live:
            env.update(HOLDFAST_PROVIDER_URL='http://localhost:11434', HOLDFAST_PROVIDER_MODEL='qwen38-27b-q8-32k:latest', HOLDFAST_PROVIDER_API_KEY='')
        if pi: env.pop('HOLDFAST_AGENT_HARNESS', None)
        ask = ['ask','--no-embed', *(['--conversation',conversation] if pi else []), '--research']
        try:
            if legacy:
                run(*ask, 'Continue this earlier conversation', success=False)
                assert not received, 'Legacy local-only context reached a server'
                for path, data in legacy_files.items(): assert path.read_bytes() == data, 'Old Durable state changed'
                assert (state/'pi'/conversation.upper()/'native.json').exists()
                print('PASS Pi migration: Durable archive unchanged; local-only restriction carried forward')
                return
            result = run(*ask, f'mark Keep basis done in {folder}/checklist.md', success=not private)
            assert not failures, failures
            if private:
                assert len(received) == 1, received
                if pi:
                    # New process, same Pi conversation: persisted restriction must precede HTTP.
                    run(*ask, 'What about this note?', success=False)
                    assert len(received) == 1
                print(f'PASS {kind} {"Pi" if pi else "Swift"}: counseling blocked before HTTP'+(' across restart' if pi else ''))
                return
            if live:
                print(result.stdout, flush=True)
            else:
                assert len(received) == 3 and 'waiting in the Inbox' in result.stdout
            assert note.read_bytes() == before, 'proposal wrote the note'
            proposals = list((state/'inbox').glob('*.md')); assert len(proposals) == 1
            proposal = '@inbox/'+proposals[0].stem
            if pi and not live:
                run(*ask, 'Is that change applied yet?')
                assert len(received) == 4 and any(m['role']=='tool' for m in received[-1]['messages'])
                assert len(list((state/'inbox').glob('*.md'))) == 1
            run('approve', proposal)
            assert note.read_bytes() == before.replace(b'- [ ] Keep basis', b'- [x] Keep basis')
            run('undo','1'); assert note.read_bytes() == before, 'Undo must restore BOM and CRLF exactly'
            if live:
                print(f'PASS live {live}: regular Pi + real 27B → proposal → approval → byte-exact Undo', flush=True)
                return
            received.clear()
            fresh = ['ask','--no-embed', *(['--pi'] if pi else []), '--research']
            run(*fresh, 'mark Keep basis done in finance/checklist.md')
            newer = [p for p in (state/'inbox').glob('*.md') if p != proposals[0]]
            assert len(newer) == 1
            changed = before+b'\r\nManual edit\r\n'; note.write_bytes(changed)
            run('approve','@inbox/'+newer[0].stem,success=False)
            assert note.read_bytes() == changed
            print(f'PASS {kind} {"Pi" if pi else "Swift"}: proposal → approval → exact Undo; stale refusal'+('; saved follow-up' if pi else ''))
        finally:
            server.shutdown(); server.server_close()
            if state.exists(): shutil.rmtree(state)

if '--live-mlx' in sys.argv:
    scenario('ollama', True, live='mlx')
elif '--live-ollama' in sys.argv:
    scenario('ollama', True, live='ollama')
else:
    for kind in ['ollama','lmstudio','custom']:
        for pi in [False, True]: scenario(kind, pi)
    for pi in [False, True]: scenario('custom', pi, private=True)
    scenario('custom', True, legacy=True)
