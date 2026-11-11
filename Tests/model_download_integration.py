"""Exercise the production downloader against a small, loopback-only HF mirror."""
import hashlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import urlsplit

PREFIX = "/artifactory/api/huggingfaceml/hf-remote"
REPO = "test/tiny"
TOKEN = "test-artifactory-token"
FILES = {
    "config.json": b'{"model_type":"test"}',
    "model.safetensors": b"fixture weights; not a real model" * 32768,
    "tokenizer.json": b"{}",
    "chat_template.jinja": b"{{ messages }}",
    "vocab.txt": b"hello\nworld\n",
    "tokenizer.model": b"fixture tokenizer",
    "nested/settings.json": b"{}",
    "README.md": b"This file should not be downloaded.",
}


class Mirror(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_HEAD(self):
        self.respond(head=True)

    def do_GET(self):
        self.respond()

    def respond(self, head=False):
        path = urlsplit(self.path).path
        auth = self.headers.get("Authorization")
        self.server.requests.append((self.command, path, auth))
        expected = f"Bearer {TOKEN}" if self.server.auth else None
        if auth != expected:
            self.send_error(401)
            return
        if path == f"{PREFIX}/api/models/{REPO}/revision/main":
            names = [] if self.server.empty else list(FILES)
            data = json.dumps({"siblings": [{"rfilename": name} for name in names]}).encode()
        elif path.startswith(f"{PREFIX}/{REPO}/resolve/"):
            name = path.removeprefix(f"{PREFIX}/{REPO}/resolve/").split("/", 1)[1]
            if name not in FILES or (self.server.fail_file and name == "model.safetensors"):
                self.send_error(404)
                return
            data = FILES[name]
        else:
            self.send_error(404)
            return
        full_size = len(data)
        offset = 0
        requested = self.headers.get("Range") if not head else None
        if requested:
            self.server.ranges.append(requested)
            if not self.server.ignore_range:
                offset = int(requested.removeprefix("bytes=").removesuffix("-"))
                data = data[offset:]
        self.send_response(206 if offset else 200)
        if offset:
            self.send_header("Content-Range", f"bytes {offset}-{full_size - 1}/{full_size}")
        if not self.server.unknown:
            self.send_header("Content-Length", str(len(data)))
        self.send_header("ETag", f'"{hashlib.sha256(data).hexdigest()}"')
        self.send_header("X-Repo-Commit", "a" * 40)
        self.end_headers()
        if not head:
            if path.endswith("model.safetensors"):
                for offset in range(0, len(data), 65536):
                    try:
                        self.wfile.write(data[offset:offset + 65536]); self.wfile.flush()
                    except (BrokenPipeError, ConnectionResetError):
                        return
                    time.sleep(0.08)
            else:
                self.wfile.write(data)


def main():
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Mirror)
    server.ranges = []; server.ignore_range = False
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix="holdfast-mirror-") as temp:
            env = {k: v for k, v in os.environ.items() if not k.startswith(("HF_", "HUGGING_FACE_"))}
            env["HF_ENDPOINT"] = f"http://127.0.0.1:{server.server_port}{PREFIX}/"
            # An anonymous mirror must not inherit this unrelated HF credential.
            token_file = Path(temp) / "cached-token"
            token_file.write_text("unrelated-cached-hf-token")
            env["HF_TOKEN_PATH"] = str(token_file)
            for case in ["authenticated", "anonymous", "unauthorized", "missing-file", "empty-repo", "unknown-size"]:
                server.requests = []
                server.auth = case != "anonymous"
                server.fail_file = case == "missing-file"
                server.empty = case == "empty-repo"
                server.unknown = case == "unknown-size"
                if server.auth:
                    env["HF_TOKEN"] = "wrong-token" if case == "unauthorized" else TOKEN
                else:
                    env.pop("HF_TOKEN", None)
                output = Path(temp) / case
                result = subprocess.run([sys.argv[1], str(output)], env=env, text=True,
                                        capture_output=True, timeout=45)
                model = output / "models" / REPO
                if case in ("authenticated", "anonymous", "unknown-size"):
                    assert result.returncode == 0, (case, result.stderr)
                    assert (model / ".complete").is_file(), case
                    for name, body in FILES.items():
                        if name == "README.md":
                            assert not (model / name).exists(), "unneeded files were downloaded"
                        else:
                            assert (model / name).read_bytes() == body, (case, name)
                    snapshots = [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]
                    transfers = [s for s in snapshots if s["phase"] == "downloading"]
                    assert len(transfers) > 2, (case, "missing live progress")
                    assert any(s.get("bytesPerSecond", 0) > 0 for s in transfers), (case, "missing speed")
                    assert all(a["completedBytes"] <= b["completedBytes"] for a, b in zip(transfers, transfers[1:])), "progress went backwards"
                    if not server.unknown:
                        expected_size = sum(len(v) for k, v in FILES.items() if k != "README.md")
                        assert all(s["totalBytes"] == expected_size for s in transfers), "total is not actual selected bytes"
                        assert snapshots[-1]["completedBytes"] == expected_size
                    else:
                        assert any("totalBytes" not in s for s in transfers), "unknown size was invented"
                    assert snapshots[-1]["phase"] == "checking"
                    expected_auth = f"Bearer {TOKEN}" if server.auth else None
                    assert all(auth == expected_auth for _, _, auth in server.requests), case
                    assert any(method == "GET" and "/resolve/" in path
                               for method, path, _ in server.requests), case
                else:
                    assert result.returncode != 0, (case, "expected failure")
                    assert not (model / ".complete").exists(), (case, "partial download marked complete")
                    assert TOKEN not in result.stderr and "wrong-token" not in result.stderr, "token in error"
                assert server.requests and all(path.startswith(PREFIX + "/")
                                               for _, path, _ in server.requests), case
                if case == "authenticated":
                    server.requests = []
                    retry = subprocess.run([sys.argv[1], str(output)], env=env, text=True, capture_output=True, timeout=45)
                    assert retry.returncode == 0, retry.stderr
                    assert not any(method == "GET" and "/resolve/" in path for method, path, _ in server.requests), "cached files were downloaded again"
                    server.fail_file = True
                    failure = subprocess.run([sys.argv[1], str(output)], env=env, text=True, capture_output=True, timeout=45)
                    assert failure.returncode != 0 and not (model / ".complete").exists(), "failed retry kept a stale completion marker"
                print(f"PASS: mirror {case}")
            for case in ["resume", "ignored-range", "changed-revision"]:
                server.requests = []; server.ranges = []
                server.auth = True; server.fail_file = False; server.empty = False; server.unknown = False
                server.ignore_range = case == "ignored-range"
                env["HF_TOKEN"] = TOKEN; env["TEST_CANCEL_MS"] = "650"
                output = Path(temp) / case
                result = subprocess.run([sys.argv[1], str(output)], env=env, capture_output=True, timeout=15)
                assert result.returncode != 0, "Expected cancellation"
                model = output / "models" / REPO
                partial = model / "model.safetensors.partial"
                assert partial.is_file() and 0 < partial.stat().st_size < len(FILES["model.safetensors"]), case
                assert not (model / ".complete").exists()
                old = FILES["model.safetensors"]
                if case == "changed-revision": FILES["model.safetensors"] = b"X" + old[1:]
                env.pop("TEST_CANCEL_MS")
                result = subprocess.run([sys.argv[1], str(output)], env=env, capture_output=True, timeout=15)
                assert result.returncode == 0, (case, result.stderr)
                assert (model / "model.safetensors").read_bytes() == FILES["model.safetensors"], case
                assert not partial.exists() and (model / ".complete").exists()
                assert bool(server.ranges) == (case != "changed-revision"), (case, server.ranges)
                FILES["model.safetensors"] = old
                print(f"PASS {case}")
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


if __name__ == "__main__":
    main()
