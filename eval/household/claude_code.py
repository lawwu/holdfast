"""Claude Code as a baseline on the household fixture.

Runs each question (and each document to file) through Claude Code in
headless mode, in a scratch copy of the vault, and scores the replies the way
`mackb eval` / `mackb eval-filing` score the local models. Results land in
results/qa/<label>.json and results/filing/<label>.json, so report.py and
page.py pick them up. Stdlib only.

  python3 eval/household/claude_code.py --model claude-sonnet-5-5 --label claude-sonnet [--parallel 3] [--only h01 ...]
  python3 eval/household/claude_code.py --model claude-sonnet-5-5 --label claude-sonnet --filing

Isolation: --setting-sources project (no user settings, hooks or plugins),
--strict-mcp-config (no MCP servers), --no-session-persistence, a scratch
folder (no CLAUDE.md, no memory). Tools: Read, Grep, Glob and read-only Bash
(cat, ls, sqlite3, python3) for the CSVs; writing and the web are disallowed.
It runs under the Claude login (ANTHROPIC_API_KEY is unset for the child), so
it counts against the plan's usage; total_cost_usd is recorded as the API price.

Filing gets the same instructions as the app (FILING_INSTRUCTIONS mirrors
Drop.instructions in Sources/mackb/Drop.swift: keep them in step) and the
document's text (the .txt original; the app reads the PDF/PNG/DOCX copies).
Claude reads the READMEs and notes itself instead of being handed them.
"""
import argparse, concurrent.futures as cf, json, os, pathlib, re, shutil, subprocess, tempfile, time

import os
# The fixture: this folder, or another with the same layout (MACKB_FIXTURE=eval/household-hard).
HERE = pathlib.Path(os.environ.get("MACKB_FIXTURE") or pathlib.Path(__file__).parent).resolve()
TODAY = "2026-11-05"
MAX_TURNS = 30
TIMEOUT_S = 600
TOOLS = ["Read", "Grep", "Glob", "Bash(cat:*)", "Bash(ls:*)", "Bash(sqlite3:*)", "Bash(python3:*)"]
BLOCKED = ["Write", "Edit", "NotebookEdit", "WebFetch", "WebSearch", "Task"]

QA_PROMPT = f"""You answer questions from a family's knowledge base: the Markdown notes and CSV files in the current folder.
Each top-level folder's README.md says what lives where. Today is {TODAY} (America/Los_Angeles).
Answer only from these files. If they don't contain the answer, say the notes don't cover it.
Be concise. End with one line starting "Sources:" listing the vault-relative paths you used."""

FILING_INSTRUCTIONS = """You file a document that was dropped into this knowledge base. Decide where it belongs and write what should be saved.

- Follow the folder READMEs: they say where each kind of thing is recorded (a log, a dated table, one note per item).
- If a README says events of this kind go in an existing log or note, append to that note ("append"). Otherwise create a new note ("new") in the right folder, named like its neighbours (lowercase, hyphens, dated YYYY-MM-DD or YYYYMM_ prefixes when the folder uses them).
- Write a short summary and the facts worth finding later: dates, amounts, providers or businesses, decisions, follow-ups. Do not paste the whole document.
- For "append", write only the lines to add: a table row matching that table's columns, or a dated section.
- For "new", write the whole note, starting with a "# " title.
- Never include account numbers, card numbers, policy or member ids, passwords or other credentials.
- Anything about counseling or the care of a person (ministry folders): initials only, never full names.
- Dates as YYYY-MM-DD, America/Los_Angeles.
- If the notes already record this document (same date and event), reply with "action": "skip" and say where in "why".

Reply with one JSON object and nothing else:
{"action": "new" | "append" | "skip", "path": "folder/sub/file.md", "title": "…", "markdown": "…", "why": "one sentence: why this place"}"""


def claude(prompt, system, model, cwd):
    env = {k: v for k, v in os.environ.items() if k != "ANTHROPIC_API_KEY"}
    cmd = ["claude", "-p", "--setting-sources", "project", "--strict-mcp-config", "--no-session-persistence",
           "--model", model, "--output-format", "json", "--max-turns", str(MAX_TURNS),
           "--append-system-prompt", system, "--allowedTools", *TOOLS, "--disallowedTools", *BLOCKED, "--", prompt]
    t0 = time.time()
    p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, timeout=TIMEOUT_S)
    secs = time.time() - t0
    try:
        d = json.loads(p.stdout)
    except json.JSONDecodeError:
        return {"result": "", "error": (p.stderr or p.stdout)[-400:], "seconds": secs}
    d["seconds"] = secs
    if d.get("is_error"):
        d["error"] = d.get("result", "error")
    return d


def found(pat, text):
    return re.search(pat, text, re.I) is not None


def run_qa(args, vault):
    qs = json.loads((HERE / "questions.json").read_text())
    if args.only:
        qs = [q for q in qs if q["id"] in args.only]

    def one(q):
        d = claude(q["question"], QA_PROMPT, args.model, vault)
        ans = d.get("result", "")
        hits = [p for p in q["expect"] if found(p, ans)]
        m = re.search(r"^\s*\**Sources:?\**:?\s*(.+)$", ans, re.I | re.M)
        srcs = re.findall(r"[\w./-]+\.(?:md|csv)", m.group(1)) if m else []
        paths = q.get("paths") or []
        pr = (sum(1 for p in paths if any(s.endswith(p) or p.endswith(s) for s in srcs)) / len(paths)) if paths else None
        u = d.get("usage") or {}
        out_tok = u.get("output_tokens", 0)
        wrong = [p for p in q.get("reject", []) if found(p, ans)]
        return {"id": q["id"], "kind": q["kind"], "question": q["question"], "answer": ans, "wrong": wrong,
                "facts": 0.0 if wrong else len(hits) / max(len(q["expect"]), 1), "missed": [p for p in q["expect"] if p not in hits],
                "recall": None, "contextRecall": None, "badCitations": [], "cited": bool(srcs),
                "promptTokens": u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0),
                "outputTokens": out_tok, "tokPerSec": out_tok / max(d["seconds"], 0.001), "seconds": d["seconds"],
                "sources": srcs, "domain": q.get("domain"), "pathRecall": pr, "model": args.model, "mode": "claude-code",
                "embedder": None, "reranker": None, "turns": d.get("num_turns"), "costUSD": d.get("total_cost_usd"),
                "error": d.get("error")}

    with cf.ThreadPoolExecutor(args.parallel) as ex:
        results = list(ex.map(one, qs))
    for r in results:
        print(f"{r['id']} facts {r['facts']*100:.0f}% · {r['turns']} turns · {r['seconds']:.0f}s · ${r['costUSD'] or 0:.3f}"
              + (f" · ERROR {r['error'][:80]}" if r.get("error") else ""))
    out = HERE / "results" / "qa" / f"{args.label}.json"
    out.write_text(json.dumps(results, indent=2, sort_keys=True))
    n = len(results)
    ans = [r for r in results if r["kind"] != "unanswerable"]
    print(f"\n{args.label}: facts {sum(r['facts'] for r in ans)/len(ans)*100:.0f}% · "
          f"median {sorted(r['seconds'] for r in results)[n//2]:.0f}s · ${sum(r['costUSD'] or 0 for r in results):.2f} · "
          f"errors {sum(1 for r in results if r.get('error'))}")


def run_filing(args, vault):
    cases = json.loads((HERE / "filing.json").read_text())
    if args.only:
        cases = [c for c in cases if c["id"] in args.only]

    def one(c):
        src = HERE / c["file"]
        text = src.read_text()
        prompt = (f"Dropped file: {src.name}\n\n{text}\n\nRead the folder READMEs and related notes you need, "
                  "then reply with the JSON object only. Do not edit any file.")
        d = claude(prompt, FILING_INSTRUCTIONS + f"\n\nToday is {TODAY} (America/Los_Angeles).", args.model, vault)
        reply = d.get("result", "")
        r = {"id": c["id"], "file": src.name, "expectAction": c["expect_action"], "action": "error", "path": "",
             "actionOK": False, "placeOK": False, "facts": 0.0, "missed": c["expect_facts"], "leaks": [], "flags": [],
             "why": "", "markdown": "", "error": d.get("error"), "outputTokens": (d.get("usage") or {}).get("output_tokens", 0),
             "seconds": d["seconds"], "model": args.model, "turns": d.get("num_turns"), "costUSD": d.get("total_cost_usd")}
        try:
            a, b = reply.index("{"), reply.rindex("}")
            f = json.loads(reply[a:b + 1])
        except (ValueError, json.JSONDecodeError):
            r["error"] = r["error"] or f"no JSON in reply: {reply[:160]}"
            return r
        act = str(f.get("action", "")).lower()
        path = str(f.get("path", "")).strip().lstrip("./").lstrip("/")
        if act != "skip" and path and not path.endswith(".md"):
            path += ".md"
        if act == "append" and not (vault / path).exists():
            act = "new"
        r.update(action=act, path=path, why=f.get("why", ""), markdown=f.get("markdown", ""))
        r["actionOK"] = act in c["expect_action"].split("|")
        if c["expect_action"] == "skip":
            r["placeOK"] = r["actionOK"]
            r["facts"] = 1.0 if r["actionOK"] else 0.0
            r["missed"] = []
        else:
            r["placeOK"] = act != "skip" and found(c["expect_path"], path)
            saved = f"{f.get('title', '')}\n{f.get('markdown', '')}"
            r["missed"] = [p for p in c["expect_facts"] if not found(p, saved)]
            r["facts"] = 1.0 if not c["expect_facts"] else (len(c["expect_facts"]) - len(r["missed"])) / len(c["expect_facts"])
            r["leaks"] = [p for p in c["forbid"] if found(p, saved)]
        return r

    with cf.ThreadPoolExecutor(args.parallel) as ex:
        results = list(ex.map(one, cases))
    for r in results:
        print(f"{r['id']} {r['file']} → {r['action']} {r['path']} · action {'ok' if r['actionOK'] else 'MISS'} "
              f"place {'ok' if r['placeOK'] else 'MISS'} facts {r['facts']*100:.0f}% leaks {len(r['leaks'])} · {r['seconds']:.0f}s"
              + (f" · ERROR {r['error'][:80]}" if r.get("error") else ""))
    out = HERE / "results" / "filing" / f"{args.label}.json"
    out.write_text(json.dumps(results, indent=2, sort_keys=True))
    n = len(results)
    print(f"\n{args.label}: action {sum(r['actionOK'] for r in results)/n*100:.0f}% · place {sum(r['placeOK'] for r in results)/n*100:.0f}% · "
          f"facts {sum(r['facts'] for r in results)/n*100:.0f}% · leaks {sum(len(r['leaks']) for r in results)} · "
          f"${sum(r['costUSD'] or 0 for r in results):.2f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--label", required=True)
    ap.add_argument("--parallel", type=int, default=3)
    ap.add_argument("--only", nargs="*", default=[])
    ap.add_argument("--filing", action="store_true")
    args = ap.parse_args()
    with tempfile.TemporaryDirectory(prefix="mackb-cc-") as tmp:
        vault = pathlib.Path(tmp) / "vault"
        shutil.copytree(HERE / "vault", vault)
        (run_filing if args.filing else run_qa)(args, vault)


if __name__ == "__main__":
    main()
