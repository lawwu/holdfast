#!/usr/bin/env python3
"""Exercise the reusable Swift target without MLX or Holdfast: real HTTP, SSE and NDJSON."""
import http.server, json, pathlib, shutil, subprocess, tempfile, threading, time

ROOT = pathlib.Path(__file__).resolve().parents[1]
failures, requests = [], []
typed = {"count": 3, "enabled": True, "value": None, "items": ["a", 2]}

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        assert self.headers.get("Authorization") == "Bearer test-secret"
        payload = json.dumps({"models": [{"name": "test-model"}], "data": [{"id": "test-model"}]}).encode()
        self.send_response(200); self.send_header("Content-Length", str(len(payload))); self.end_headers(); self.wfile.write(payload)
    def do_POST(self):
        try:
            requests.append(self.path)
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            assert self.headers.get("Authorization") == "Bearer test-secret"
            native = self.path.endswith("/api/chat")
            args = body["messages"][2]["tool_calls"][0]["function"]["arguments"]
            assert (args if native else json.loads(args)) == typed
            assert body["messages"][-1]["tool_call_id"] == "prior"
            case = self.path.split('/')[1]
            if case == 'redirect':
                self.send_response(307); self.send_header('Location', '/leaked'); self.end_headers(); return
            if case == 'auth': self.send_response(401); self.end_headers(); return
            self.send_response(200)
            self.send_header("Content-Type", "application/x-ndjson" if native else "text/event-stream")
            self.end_headers()
            if case == 'cancel': time.sleep(1)
            tool = {"id": "call", "index": 0, "function": {"name": "typed", "arguments": typed if native else json.dumps(typed)}}
            if native:
                assert body['think'] is False and body['options']['num_ctx'] == 32768
                events = [{"message": {"content": "Hello 🌿\u2028world", "thinking": "thought", "tool_calls": [tool]}},
                          {"done": True, "done_reason": "length" if case == 'truncated' else 'stop', "prompt_eval_count": 10, "eval_count": 5}]
                if case == 'invalid': events[0]['message']['tool_calls'][0]['function']['arguments'] = 'not-json'
                if case == 'interrupted': events.pop()
                wire = ''.join(json.dumps(e, ensure_ascii=False)+'\r\n' for e in events).encode()
            else:
                raw = json.dumps(typed)
                tool['function']['arguments'] = raw[:12]
                events = [{"choices": [{"delta": {"content": "Hello 🌿\u2028world", "reasoning_content": "thought", "tool_calls": [tool]}}]},
                          {"choices": [{"delta": {"tool_calls": [{"index": 0, "function": {"arguments": raw[12:]}}]}}]},
                          {"choices": [{"delta": {}, "finish_reason": "length" if case == 'truncated' else 'tool_calls'}], "usage": {"prompt_tokens": 10, "completion_tokens": 5}}]
                if case == 'invalid': events[1]['choices'][0]['delta']['tool_calls'][0]['function']['arguments'] = '!'
                if case == 'interrupted': events.pop()
                wire = (''.join('data: '+json.dumps(e, ensure_ascii=False)+'\r\n\r\n' for e in events)+'data: [DONE]\r\n\r\n').encode()
            # Deliberately split UTF-8 and JSON tokens across transport writes.
            for i in range(0, len(wire), 7): self.wfile.write(wire[i:i+7]); self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError): pass
        except Exception as e: failures.append(repr(e))

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='holdfast-providers-') as temp:
        # Compile a separate consumer against the package's public API, with no app or MLX.
        package = pathlib.Path(temp)
        source = package/'Sources/ProviderTransportCheck'
        source.mkdir(parents=True)
        shutil.copy2(ROOT/'Tests/ModelProviderTests.swift', source/'ProviderTests.swift')
        dependency = json.dumps(str(ROOT/'Packages/ModelProviders'), ensure_ascii=False)
        (package/'Package.swift').write_text(f'''// swift-tools-version:6.2
import PackageDescription
let package = Package(name: "ProviderTransportCheck", platforms: [.macOS(.v15)],
    dependencies: [.package(path: {dependency})],
    targets: [.executableTarget(name: "ProviderTransportCheck",
        dependencies: [.product(name: "ModelProviders", package: "modelproviders")],
        swiftSettings: [.swiftLanguageMode(.v5)])])
''')
        graph = json.loads(subprocess.check_output(['swift', 'package', '--package-path', temp, 'show-dependencies', '--format', 'json']))
        assert len(graph['dependencies']) == 1
        assert graph['dependencies'][0]['name'] == 'ModelProviders'
        assert graph['dependencies'][0]['dependencies'] == [], 'HTTP-only consumers must not resolve MLX'
        subprocess.run(['swift', 'build', '--package-path', temp], check=True)
        binary = str(package/'.build/debug/ProviderTransportCheck')
        for kind in ['ollama', 'lmStudio', 'custom']:
            for case in ['models', 'ok', 'invalid', 'truncated', 'interrupted', 'auth', 'redirect', 'cancel']:
                mode = case if case in ['models', 'ok', 'cancel'] else 'error'
                url = f'http://127.0.0.1:{server.server_port}/{case}' + ('' if kind == 'ollama' else '/v1')
                subprocess.run([binary, mode, url, kind], timeout=10, check=True)
        assert not failures, failures
        assert '/leaked' not in requests
finally:
    server.shutdown(); server.server_close()
