"""Compare `mackb eval` runs side by side.

Reads eval/results/*.json (one file per run, written by `mackb eval --label X`)
and prints a Markdown table: per-question fact coverage for each run, then
totals for facts, citation rate, speed and time. Stdlib only.

  python3 eval/compare.py [results_dir]
"""
import json, pathlib, statistics, sys

d = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).parent / "results")
runs = {p.stem: json.loads(p.read_text()) for p in sorted(d.glob("*.json"))}
if not runs:
    sys.exit(f"no results in {d}")
labels = list(runs)
qids = [r["id"] for r in runs[labels[0]]]
by = {lab: {r["id"]: r for r in rs} for lab, rs in runs.items()}

print("| Question | Kind | " + " | ".join(labels) + " |")
print("| --- | --- | " + " | ".join("---" for _ in labels) + " |")
for q in qids:
    first = by[labels[0]][q]
    cells = []
    for lab in labels:
        r = by[lab].get(q)
        cells.append("—" if r is None else f"{r['facts']*100:.0f}%" + ("" if r["cited"] else " (no cite)"))
    print(f"| {q}: {first['question'][:70]} | {first['kind']} | " + " | ".join(cells) + " |")

print()
print("| Run | Facts found | Context recall | Cited | Gen tok/s | Median s/answer | Total min |")
print("| --- | --- | --- | --- | --- | --- | --- |")
for lab, rs in runs.items():
    facts = statistics.mean(r["facts"] for r in rs)
    # Context recall: share of expected facts present in the passages the model saw.
    # Older runs only have session-level "recall"; fall back to it, marked with *.
    rec = [r["contextRecall"] for r in rs if r.get("contextRecall") is not None]
    star = ""
    if not rec:
        rec = [r["recall"] for r in rs if r.get("recall") is not None]
        star = "*"
    out = sum(r["outputTokens"] for r in rs)
    gen = sum(r["outputTokens"] / max(r["tokPerSec"], 1e-3) for r in rs)
    secs = [r["seconds"] for r in rs]
    print(f"| {lab} | {facts*100:.0f}% | {statistics.mean(rec)*100:.0f}%{star} | {sum(r['cited'] for r in rs)}/{len(rs)} "
          f"| {out/gen:.1f} | {statistics.median(secs):.0f} | {sum(secs)/60:.1f} |")
print()
print("* session-level recall (the run predates context recall), which overstates retrieval.")
