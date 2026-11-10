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
from urllib.parse import urlsplit

PREFIX = "/artifactory/api/huggingfaceml/hf-remote"
REPO = "test/tiny"
TOKEN = "test-artifactory-token"
FILES = {
    "config.json": b'{"model_type":"test"}',
    "model.safetensors": b"fixture weights; not a real model",
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
        elif path.startswith(f"{PREFIX}/{REPO}/resolve/main/"):
            name = path.removeprefix(f"{PREFIX}/{REPO}/resolve/main/")
            if name not in FILES or (self.server.fail_file and name == "model.safetensors"):
                self.send_error(404)
                return
            data = FILES[name]
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("ETag", f'"{hashlib.sha256(data).hexdigest()}"')
        self.send_header("X-Repo-Commit", "a" * 40)
        self.end_headers()
        if not head:
            self.wfile.write(data)


def main():
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Mirror)
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
            for case in ["authenticated", "anonymous", "unauthorized", "missing-file", "empty-repo"]:
                server.requests = []
                server.auth = case != "anonymous"
                server.fail_file = case == "missing-file"
                server.empty = case == "empty-repo"
                if server.auth:
                    env["HF_TOKEN"] = "wrong-token" if case == "unauthorized" else TOKEN
                else:
                    env.pop("HF_TOKEN", None)
                output = Path(temp) / case
                result = subprocess.run([sys.argv[1], str(output)], env=env, text=True,
                                        capture_output=True, timeout=45)
                model = output / "models" / REPO
                if case in ("authenticated", "anonymous"):
                    assert result.returncode == 0, (case, result.stderr)
                    assert (model / ".complete").is_file(), case
                    for name, body in FILES.items():
                        if name == "README.md":
                            assert not (model / name).exists(), "unneeded files were downloaded"
                        else:
                            assert (model / name).read_bytes() == body, (case, name)
                    expected_auth = f"Bearer {TOKEN}" if server.auth else None
                    assert all(auth == expected_auth for _, _, auth in server.requests), case
                    assert any(method == "GET" and "/resolve/main/" in path
                               for method, path, _ in server.requests), case
                else:
                    assert result.returncode != 0, (case, "expected failure")
                    assert not (model / ".complete").exists(), (case, "partial download marked complete")
                    assert TOKEN not in result.stderr and "wrong-token" not in result.stderr, "token in error"
                assert server.requests and all(path.startswith(PREFIX + "/")
                                               for _, path, _ in server.requests), case
                print(f"PASS: mirror {case}")
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


if __name__ == "__main__":
    main()
