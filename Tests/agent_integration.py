#!/usr/bin/env python3
"""Exercise the real CLI/remote adapter/Inbox against synthetic notes and a fake model."""
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading

binary = Path(sys.argv[1]).resolve()
assert binary.is_file(), binary

scratch = Path.home() / ".cache"
scratch.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="holdfast-harness-", dir=scratch) as temporary:
    vault = Path(temporary).resolve() / "vault"
    (vault / "finance").mkdir(parents=True)
    note = vault / "finance/checklist.md"
    before = "# Checklist\n\n- [ ] Protect pretax 401(k) basis\n- [ ] Keep this open\n"
    note.write_text(before)
    h = 1469598103934665603
    for byte in str(vault).encode():
        h = ((h ^ byte) * 1099511628211) & ((1 << 64) - 1)
    state = Path.home() / "Library/Application Support/Holdfast/vaults" / ("vault-" + format(h, "x")[:8])
    assert not state.exists(), "test state must be new"
    received = []
    failures = []

    def tool(name, arguments, id):
        return {"id": id, "type": "function", "function": {"name": name, "arguments": json.dumps(arguments)}}

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            try:
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                stage = len(received)
                received.append(body)
                if stage == 0:
                    assert len(body["tools"]) == 6
                    message = {"content": "", "tool_calls": [tool("read_note", {"path": 42}, "invalid")]}
                elif stage == 1:
                    assert "string values" in body["messages"][-1]["content"]
                    assert body["messages"][-1]["tool_call_id"] == "invalid"
                    message = {"content": "", "tool_calls": [tool("read_note", {"path": "finance/checklist.md"}, "read")]}
                elif stage == 2:
                    assert "- [ ] Protect pretax 401(k) basis" in body["messages"][-1]["content"]
                    assert body["messages"][-1]["tool_call_id"] == "read"
                    message = {"content": "", "tool_calls": [tool("propose_edit", {
                        "path": "finance/checklist.md", "old_text": "- [ ] Protect pretax 401(k) basis",
                        "new_text": "- [x] Protect pretax 401(k) basis", "why": "Mark this one item done"
                    }, "propose")]}
                else:
                    assert stage == 3
                    assert "nothing is changed until then" in body["messages"][-1]["content"]
                    assert body["messages"][-1]["tool_call_id"] == "propose"
                    message = {"content": "The change is waiting in the Inbox. [1]"}
                response = {"choices": [{"message": {"role": "assistant", **message}, "finish_reason": "stop"}],
                            "usage": {"prompt_tokens": 100, "completion_tokens": 10}}
                payload = json.dumps(response).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            except Exception as error:
                failures.append(repr(error))
                self.send_error(500)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env = {**os.environ, "HOLDFAST_VAULT": str(vault), "HOLDFAST_BACKEND": "remote",
           "HOLDFAST_REMOTE_URL": f"http://127.0.0.1:{server.server_port}",
           "HOLDFAST_REMOTE_MODEL": "synthetic-test-model", "HOLDFAST_EMBED": "none", "HOLDFAST_RERANK": "0",
           "HOLDFAST_PACKS": "none", "HOLDFAST_AGENT_HARNESS": "swift"}

    def run(*args, check=True):
        result = subprocess.run([str(binary), *args], env=env, text=True, capture_output=True, timeout=60)
        if check and result.returncode:
            raise AssertionError(result.stdout + result.stderr + repr(failures))
        return result

    try:
        answer = run("ask", "--no-embed", "mark Protect pretax 401(k) basis done in finance/checklist.md")
        assert not failures, failures
        assert len(received) == 4
        assert "waiting in the Inbox" in answer.stdout
        assert note.read_text() == before, "proposals must not change the note"
        proposals = list((state / "inbox").glob("*.md"))
        assert len(proposals) == 1, run("inbox").stdout
        proposal_id = "@inbox/" + proposals[0].stem
        run("approve", proposal_id)
        expected = before.replace("- [ ] Protect pretax", "- [x] Protect pretax")
        assert note.read_text() == expected, "apply only the requested edit"
        run("undo", "1")
        assert note.read_text() == before, "undo restores exact content"
        journals = list((state / "agent-runs").glob("*.jsonl"))
        assert len(journals) == 1
        entries = [json.loads(line) for line in journals[0].read_text().splitlines()]
        assert [e["sequence"] for e in entries] == list(range(len(entries)))
        event_names = [next(iter(e["payload"]["event"]["_0"])) for e in entries if "event" in e["payload"]]
        assert event_names.count("toolStarted") == 3 and event_names.count("toolFinished") == 3
        assert event_names[-1] == "finished"
        print("PASS: real CLI → remote adapter → validation/repair → read → Inbox proposal → approve → exact undo; durable journal verified")
    finally:
        server.shutdown()
        server.server_close()
        if state.exists():
            shutil.rmtree(state)
