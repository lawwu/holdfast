#!/usr/bin/env python3
"""Three-arm, synthetic-only agent evaluation using the installed Pi and Ollama.

The loopback proxy gives both Ollama clients identical sampling settings and logs
wire requests. It forwards real streaming/nonstreaming responses unchanged.
"""
import argparse
import hashlib
import http.server
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OLLAMA = "http://127.0.0.1:11434"


def api(path, value=None, timeout=600):
    request = urllib.request.Request(OLLAMA + path, data=None if value is None else json.dumps(value).encode(),
                                     headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def state_path(vault):
    h = 1469598103934665603
    for byte in str(vault).encode():
        h = ((h ^ byte) * 1099511628211) & ((1 << 64) - 1)
    return Path.home() / "Library/Application Support/Holdfast/vaults" / (vault.name + "-" + format(h, "x")[:8])


def execute(command, env, timeout=600, input=None):
    start = time.monotonic()
    result = subprocess.run(command, env=env, input=input, capture_output=True, text=True, timeout=timeout)
    return result, time.monotonic() - start


def bridge(binary, env, operation):
    process, elapsed = execute([str(binary), "_agent-eval"], env, input=json.dumps(operation) + "\n")
    if process.returncode:
        raise RuntimeError(process.stderr)
    value = json.loads(process.stdout.strip().splitlines()[-1])
    if "error" in value:
        raise RuntimeError(value["error"])
    return value, elapsed, process.stderr


class Proxy(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, model, seed):
        super().__init__(("127.0.0.1", 0), Handler)
        self.model = model
        self.seed = seed
        self.records = []
        self.failures = []


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        started = time.monotonic()
        record = {"seconds": 0}
        try:
            if self.path != "/v1/chat/completions" or len(self.server.records) >= 9:
                raise ValueError("Unexpected endpoint or model request budget exceeded")
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            if body.get("model") != self.server.model:
                raise ValueError("Unexpected model; no provider fallback is allowed")
            # Common provider configuration. The native MLX path uses these same
            # sampling values, but its quantization and random generator differ.
            for key in ["max_completion_tokens", "chat_template_kwargs", "store"]:
                body.pop(key, None)
            body.update(temperature=0.7, top_p=0.8, presence_penalty=1.5,
                        max_tokens=2000, reasoning_effort="none", seed=self.server.seed)
            if "tools" in body:
                body["tools"] = sorted(body["tools"], key=lambda tool: tool["function"]["name"])
                for tool in body["tools"]:
                    tool["function"].pop("strict", None)
            # Canonical JSON gives both harnesses the same schema/property order.
            wire = json.dumps(body, sort_keys=True).encode()
            comparable = {k: v for k, v in body.items() if k not in ["stream", "stream_options"]}
            record.update(payload=body, comparableHash=hashlib.sha256(json.dumps(comparable, sort_keys=True).encode()).hexdigest())
            self.server.records.append(record)
            request = urllib.request.Request(OLLAMA + self.path, data=wire, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(request, timeout=600) as response:
                record["firstByteSeconds"] = time.monotonic() - started
                self.send_response(response.status)
                self.send_header("Content-Type", response.headers.get("Content-Type", "application/json"))
                self.end_headers()
                chunks = []
                for line in response:
                    chunks.append(line)
                    self.wfile.write(line)
                    self.wfile.flush()
                raw = b"".join(chunks).decode()
                record["response"] = raw
                if body.get("stream"):
                    events = [json.loads(line[6:]) for line in raw.splitlines() if line.startswith("data: ") and line != "data: [DONE]"]
                    record["usage"] = next((event["usage"] for event in reversed(events) if event.get("usage")), {})
                else:
                    record["usage"] = json.loads(raw).get("usage", {})
        except Exception as error:
            record["error"] = repr(error)
            self.server.failures.append(repr(error))
            try:
                self.send_error(502, str(error))
            except (BrokenPipeError, ConnectionResetError):
                pass
        finally:
            record["seconds"] = time.monotonic() - started


def files(vault):
    return {str(path.relative_to(vault)): path.read_bytes() for path in vault.rglob("*") if path.is_file()}


def proposal(path):
    raw = path.read_text()
    parts = raw.split("---\n", 2)
    if len(parts) != 3:
        raise ValueError("Invalid proposal frontmatter")
    return {"file": path.name, "raw": raw, "body": parts[2].lstrip("\n")}


def score(task, result, vault, before, state, binary, env):
    checks = {"vaultUnchangedBeforeApproval": files(vault) == before}
    proposals = [proposal(path) for path in sorted((state / "inbox").glob("*.md"))]
    answer = result.get("answer", "")
    if task["kind"] in ["checkbox", "insert", "combined"]:
        checks["oneProposal"] = len(proposals) == 1
        checks["approvalExplained"] = bool(re.search(r"inbox|approv|pending", answer, re.I))
        original = before["finance/checklist.md"].decode()
        body = proposals[0]["body"] if len(proposals) == 1 else ""
        if task["kind"] == "checkbox":
            expected = original.replace("- [ ] Protect pretax", "- [x] Protect pretax")
            checks["exactRequestedEdit"] = body == expected
        elif task["kind"] == "combined":
            expected = original.replace("- [ ] Protect pretax", "- [x] Protect pretax").replace("Review umbrella insurance", "Review umbrella insurance with Alex")
            checks["exactRequestedEdit"] = body == expected
        else:
            lines = body.splitlines()
            item = "- [ ] Check HSA beneficiary"
            checks["itemOnceInCorrectSection"] = lines.count(item) == 1 and "## Later" in lines and "## Do this quarter" in lines and lines.index("## Do this quarter") < lines.index(item) < lines.index("## Later")
            # Ignore blank-line placement, but require every existing line and section to remain.
            checks["otherContentUnchanged"] = [line for line in lines if line.strip() and line != item] == [line for line in original.splitlines() if line.strip()]
        if len(proposals) == 1:
            id = "@inbox/" + Path(proposals[0]["file"]).stem
            # Exercise stale-note protection, then put the scratch note back and apply.
            note = vault / "finance/checklist.md"
            changed = original + "\nManual concurrent edit.\n"
            note.write_text(changed)
            rejected, _ = execute([str(binary), "approve", id], env)
            checks["staleApplyRefused"] = rejected.returncode != 0 and note.read_text() == changed
            note.write_text(original)
            approved, _ = execute([str(binary), "approve", id], env)
            checks["applyMatchesProposal"] = approved.returncode == 0 and note.read_text() == body
            undone, _ = execute([str(binary), "undo", "1"], env)
            checks["undoExact"] = undone.returncode == 0 and files(vault) == before
    elif task["kind"] == "table":
        checks["noProposal"] = not proposals
        checks["correctTotal"] = bool(re.search(r"1,?300(?:\.00)?\b", answer))
        checks["citation"] = bool(re.search(r"\[\d+\]", answer))
        checks["queriedCSV"] = any(call.get("name") == "query_table" for call in result.get("calls", []))
    else:
        checks["noProposal"] = not proposals
        checks["generatedExplained"] = bool(re.search(r"generat", answer, re.I))
        checks["sourceOrScriptExplained"] = bool(re.search(r"script|source|spending\.py", answer, re.I))
    return checks, proposals


def swift_calls(state):
    calls = []
    for path in (state / "agent-runs").glob("*.jsonl"):
        for line in path.read_text().splitlines():
            event = json.loads(line)["payload"].get("event", {}).get("_0", {})
            if "toolFinished" in event:
                value = event["toolFinished"]
                calls.append({"name": value["_0"]["name"], "arguments": json.loads(value["_0"]["arguments"]), "result": value["_1"]})
    return calls


def report(out, rows, metadata):
    # Pi encodes user content as text blocks, Swift as a string. Ollama renders
    # both identically. Compare their meaning separately from raw wire bytes.
    groups = {}
    for row in rows:
        path = out / f"{row['task']}-{row['repeat']}-{row['arm']}" / "requests.json"
        if path.exists() and (requests := json.loads(path.read_text())):
            first = {key: value for key, value in requests[0].get("payload", {}).items() if key not in ["stream", "stream_options"]}
            first = json.loads(json.dumps(first))
            for message in first.get("messages", []):
                if isinstance(message.get("content"), list) and all(block.get("type") == "text" for block in message["content"]):
                    message["content"] = "".join(block["text"] for block in message["content"])
            row["firstSemanticRequestHash"] = hashlib.sha256(json.dumps(first, sort_keys=True).encode()).hexdigest()
            groups.setdefault((row["task"], row["repeat"]), {})[row["arm"]] = row["firstSemanticRequestHash"]
    lines = ["# Pi / Ollama / Swift comparison", "", "Synthetic notes only. One fresh conversation and vault per case; no default Pi tools or cloud providers.", "",
             "| Setup | Passed | Mean agent seconds | Median agent seconds |", "|---|---:|---:|---:|"]
    for arm in ["pi-ollama", "swift-ollama", "swift-mlx"]:
        selected = [row for row in rows if row["arm"] == arm]
        timings = [row["loopSeconds"] for row in selected if "loopSeconds" in row]
        if timings:
            lines.append(f"| {arm} | {sum(bool(row.get('passed')) for row in selected)}/{len(selected)} | {statistics.mean(timings):.1f} | {statistics.median(timings):.1f} |")
    lines += ["", "Timings describe completed runs only; a single pass per case is exploratory, not a stable speed ranking.", "",
              "| Task | Run | Setup | Pass | Agent seconds | Tool calls | Output tokens |", "|---|---:|---|---|---:|---:|---:|"]
    for row in rows:
        lines.append(f"| {row['task']} | {row['repeat']} | {row['arm']} | {'yes' if row.get('passed') else 'NO'} | {row.get('loopSeconds', 0):.1f} | {len(row.get('calls', []))} | {row.get('outputTokens', 0)} |")
    lines += ["", "Agent seconds exclude model loading and process startup. Ollama is unloaded then warmed on an unrelated one-token prompt before each trial, so the second harness does not inherit the first harness's task cache.", "",
              "The two Ollama arms use identical weights, sampling, seed, system prompt and tool implementations. Streaming differs: Pi streams; Swift's HTTP adapter receives complete turns. The proxy records their actual requests and normalizes only provider settings/schema order.", "",
              "MLX uses the app's 4-bit Qwen3.8-27B; Ollama uses the existing 31.5 GB imported GGUF. Its Q8 tag and Q4_K_M metadata disagree; the attached gguf-types.json, when present, records actual tensor types (Q8_0 plus BF16/F32 in this run). Cross-engine results therefore compare the installed stacks, not equal quantization. No model download or global configuration change is made.", "",
              "Compaction, long conversations, crash recovery, steering, private locality and concurrent workloads are outside this short-task evaluation. Peak physical/GPU memory is not measured; model sizes are not runtime memory measurements."]
    pairs = [values for values in groups.values() if "pi-ollama" in values and "swift-ollama" in values]
    if pairs:
        equal = sum(values["pi-ollama"] == values["swift-ollama"] for values in pairs)
        lines += ["", f"Initial-request audit: {equal}/{len(pairs)} Ollama pairs match after normalizing string versus text-block content and excluding streaming flags. Full wire requests are retained."]
    for note in metadata.get("reviewNotes", []):
        lines += ["", note]
    (out / "report.md").write_text("\n".join(lines) + "\n")
    save(out / "results.json", {"metadata": metadata, "results": rows})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, default=ROOT / ".build/harness-xcode/Build/Products/Release/holdfast")
    parser.add_argument("--model", default="qwen38-27b-q8-32k:latest")
    parser.add_argument("--mlx-model", default="mlx-community/Qwen3.8-27B-4bit")
    parser.add_argument("--arms", nargs="+", default=["swift-mlx", "swift-ollama", "pi-ollama"], choices=["swift-mlx", "swift-ollama", "pi-ollama"])
    parser.add_argument("--only", nargs="*")
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    args.binary = args.binary.resolve()
    args.out.mkdir(parents=True, exist_ok=False)
    pi_package = Path(shutil.which("pi")).resolve().parents[1]
    tasks = json.loads((HERE / "tasks.json").read_text())
    if args.only:
        tasks = [task for task in tasks if task["id"] in args.only]
    if not tasks or args.repeats < 1:
        raise ValueError("Select at least one task and a positive repeat count")
    show = api("/api/show", {"model": args.model})
    if show.get("remote_model") or show.get("remote_host") or ":cloud" in args.model:
        raise ValueError("This comparison requires a downloaded local Ollama model")
    metadata = {"created": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "ollama": api("/api/version"),
                "model": args.model, "modelDetails": show.get("details"), "thinking": show.get("thinking"),
                "parameters": show.get("parameters"), "mlxModel": args.mlx_model,
                "piVersion": json.loads((pi_package / "package.json").read_text())["version"],
                "gitHead": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "dirtyTree": True, "binarySHA256": hashlib.sha256(args.binary.read_bytes()).hexdigest(),
                "tags": api("/api/tags"), "repeats": args.repeats,
                "hardware": {"chip": subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip(),
                             "memoryBytes": int(subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True))}}
    save(args.out / "metadata.json", metadata)
    if api("/api/ps").get("models"):
        raise RuntimeError("Ollama already has loaded models; avoid disturbing another workload")
    rows = []
    scratch = Path.home() / ".cache"
    scratch.mkdir(exist_ok=True)
    for repeat in range(1, args.repeats + 1):
        for task in tasks:
            arms = list(args.arms)
            if repeat % 2 == 0:
                arms.reverse()
            for arm in arms:
                label = f"{task['id']}-{repeat}-{arm}"
                artifact = args.out / label
                artifact.mkdir()
                row = {"task": task["id"], "repeat": repeat, "arm": arm, "question": task["question"]}
                print(f"START {label}", flush=True)
                with tempfile.TemporaryDirectory(prefix="holdfast-agent-eval-", dir=scratch) as temporary:
                    vault = Path(temporary) / "vault"
                    shutil.copytree(HERE / "fixture", vault)
                    (vault / ".agent-eval-synthetic").write_text("synthetic holdfast agent evaluation\n")
                    state = state_path(vault)
                    assert not state.exists()
                    env = {**os.environ, "HOLDFAST_VAULT": str(vault), "HOLDFAST_AGENT_EVAL": "1",
                           "HOLDFAST_PACKS": "none", "HOLDFAST_EMBED": "none", "HOLDFAST_RERANK": "0", "HOLDFAST_THINK": "0",
                           "HOLDFAST_TODAY": "2026-11-09", "HOLDFAST_MLX_REPO": args.mlx_model,
                           "HOLDFAST_REMOTE_MODEL": args.model}
                    proxy = Proxy(args.model, 42 + repeat)
                    thread = threading.Thread(target=proxy.serve_forever, daemon=True)
                    thread.start()
                    env["HOLDFAST_REMOTE_URL"] = f"http://127.0.0.1:{proxy.server_port}"
                    try:
                        config, _, stderr = bridge(args.binary, env, {"op": "config"})
                        assert config["stateDir"] == str(state)
                        save(artifact / "config.json", config)
                        before = files(vault)
                        if arm != "swift-mlx":
                            warm = api("/api/chat", {"model": args.model, "messages": [{"role": "user", "content": "Hello."}],
                                "stream": False, "think": False, "keep_alive": "15m", "options": {"num_predict": 1, "num_ctx": 32768}})
                            row["warmupSeconds"] = warm.get("total_duration", 0) / 1e9
                            row["ollamaLoaded"] = api("/api/ps")
                        if arm == "pi-ollama":
                            input = {"binary": str(args.binary), "piPackage": str(pi_package), "baseUrl": env["HOLDFAST_REMOTE_URL"] + "/v1",
                                     "model": args.model, "question": task["question"], "vault": str(vault),
                                     "agentDir": temporary + "/pi", "transcript": str((artifact / "pi-transcript.json").resolve())}
                            save(artifact / "input.json", input)
                            process, elapsed = execute(["node", str(HERE / "pi.mjs"), str(artifact / "input.json")], env)
                            (artifact / "stderr.log").write_text(process.stderr)
                            (artifact / "stdout.log").write_text(process.stdout)
                            if process.returncode:
                                raise RuntimeError(process.stderr[-4000:])
                            result = json.loads(process.stdout.strip().splitlines()[-1])
                        else:
                            result, elapsed, stderr = bridge(args.binary, env, {"op": "run", "engine": arm.split("-")[1], "question": task["question"]})
                            (artifact / "stderr.log").write_text(stderr)
                            result["calls"] = swift_calls(state)
                        row.update(result, processSeconds=elapsed)
                        checks, proposals = score(task, result, vault, before, state, args.binary, env)
                        row["checks"] = checks
                        row["passed"] = all(checks.values()) and not proxy.failures
                        save(artifact / "proposals.json", proposals)
                    except Exception as error:
                        row.update(error=repr(error), passed=False)
                    finally:
                        proxy.shutdown()
                        proxy.server_close()
                        save(artifact / "requests.json", proxy.records)
                        if proxy.records:
                            row["firstRequestHash"] = proxy.records[0].get("comparableHash")
                            row["modelRequests"] = len(proxy.records)
                        if proxy.failures:
                            row["proxyFailures"] = proxy.failures
                        if state.exists():
                            shutil.copytree(state, artifact / "state")
                            shutil.rmtree(state)
                        if arm != "swift-mlx":
                            api("/api/generate", {"model": args.model, "keep_alive": 0})
                rows.append(row)
                save(artifact / "result.json", row)
                report(args.out, rows, metadata)
                print(f"END {label}: {'PASS' if row['passed'] else 'FAIL'} {row.get('loopSeconds', 0):.1f}s " + row.get("error", ""), flush=True)
    print(f"Report: {args.out / 'report.md'}", flush=True)
    if any(not row.get("passed") for row in rows):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
