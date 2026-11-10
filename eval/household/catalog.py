"""Writes Sources/holdfast/ModelCatalog.swift from this eval's saved results, so Holdfast's
model recommendations come from measurements on a real Mac, not from guesses. Stdlib only.

  python3 eval/household/catalog.py

Reads, per local model (the labels in results/memory.json):
- results/qa/<label>.json            answers: mean facts over the answerable questions
- results/qa/<label>-research.json   hard questions with Research: mean facts over the hard ones
Answers and filing places are re-scored against the current questions.json and filing.json,
the same way report.py does, so the app shows the report's numbers.
- results/filing/<label>.json        filing: share put in the right place, facts kept, leaks
- results/memory.json                peak memory (the larger of plain and Research) and tokens/s
Download sizes come from the Hugging Face cache when the model is there, else SIZES below.
Re-run after new eval runs; the app reads only the generated file.
"""
import json, os, pathlib, statistics

HERE = pathlib.Path(__file__).parent
OUT = HERE.parent.parent / "Sources" / "holdfast" / "ModelCatalog.swift"
MEASURED_ON = "M1 Max, 64 GB"
HF = pathlib.Path.home() / ".cache/huggingface/hub"

# Display names; download sizes (GB) for models not in the local cache.
NAMES = {
    "qwen27b": ("Qwen 3.8 27B", "4-bit", 16.1),
    "qwen36d27b": ("Qwen 3.6 27B", "4-bit", 16.1),
    "qwen36moe": ("Qwen 3.6 35B A3B", "4-bit · MoE", 20.4),
    "qwen35-9b": ("Qwen 3.5 9B", "4-bit", 6.0),
    "qwen35-4b": ("Qwen 3.5 4B", "4-bit", 2.5),
    "qwen35-2b": ("Qwen 3.5 2B", "4-bit", 1.3),
    "gemma31b": ("Gemma 4 31B", "4-bit", 18.4),
    "gemma26b": ("Gemma 4 26B A4B", "4-bit · MoE", 15.4),
    "gemmae4b": ("Gemma 4 E4B", "4-bit", 4.8),
    "gemmae2b": ("Gemma 4 E2B", "4-bit", 3.0),
    "gptoss20b": ("gpt-oss 20B", "MXFP4", 12.1),
}


import re
QS = {q["id"]: q for q in json.loads((HERE / "questions.json").read_text())}
CASES = {c["id"]: c for c in json.loads((HERE / "filing.json").read_text())}


def rescore_qa(rs):
    """Facts over answerable questions, against the current questions.json (as report.py does)."""
    out = []
    for r in rs:
        q = QS.get(r["id"])
        if not q or q["kind"] == "unanswerable":
            continue
        hits = [x for x in q["expect"] if re.search(x, r["answer"], re.I)]
        wrong = [x for x in q.get("reject", []) if re.search(x, r["answer"], re.I)]
        out.append(0.0 if wrong else len(hits) / max(len(q["expect"]), 1))
    return out


def rescore_filing(rs):
    """Right place and leaks against the current filing.json (as report.py does)."""
    for r in rs:
        c = CASES.get(r["id"])
        if c and c["expect_action"] != "skip" and not r.get("error"):
            r["placeOK"] = r["action"] != "skip" and re.search(c["expect_path"], r["path"], re.I) is not None
            r["leaks"] = [x for x in c["forbid"] if re.search(x, r.get("markdown", ""), re.I)]
    return rs


def load(p):
    try:
        return json.loads(p.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def mean(xs):
    return round(sum(xs) / len(xs) * 100, 1) if xs else None


def cache_size(repo):
    snaps = HF / ("models--" + repo.replace("/", "--")) / "snapshots"
    if not snaps.is_dir():
        return None
    latest = sorted(snaps.iterdir())[-1]
    total = sum(os.path.getsize(os.path.realpath(f)) for f in latest.rglob("*") if f.is_file() or f.is_symlink())
    return round(total / 1e9, 1) if total > 1e8 else None


def swift(v):
    return "nil" if v is None else (f"{v}" if not isinstance(v, str) else json.dumps(v, ensure_ascii=False))


def main():
    memory = load(HERE / "results/memory.json") or {}
    rows = []
    for label, m in sorted(memory.items()):
        if label not in NAMES:
            continue
        name, detail, size = NAMES[label]
        size = cache_size(m["repo"]) or size
        qa = load(HERE / f"results/qa/{label}.json") or []
        rs = load(HERE / f"results/qa/{label}-research.json") or []
        fl = rescore_filing(load(HERE / f"results/filing/{label}.json") or [])
        peaks = [r.get("peakGB") for r in (m.get("plain") or {}, m.get("research") or {}) if r.get("ok") and r.get("peakGB")]
        secs = [r["seconds"] for r in qa if "seconds" in r]
        rows.append(dict(
            label=label, repo=m["repo"], name=name, detail=detail, sizeGB=size,
            answers=mean(rescore_qa(qa)),
            research=mean(rescore_qa(rs)),
            filingPlace=mean([1.0 if r["placeOK"] else 0.0 for r in fl]),
            filingFacts=mean([r["facts"] for r in fl]),
            leaks=sum(len(r.get("leaks", [])) for r in fl) if fl else None,
            peakGB=round(max(peaks), 1) if peaks else None,
            tokPerSec=(m.get("plain") or {}).get("tokPerSec"),
            medianSeconds=round(statistics.median(secs), 1) if secs else None,
        ))
    fields = ["label", "repo", "name", "detail", "sizeGB", "answers", "research", "filingPlace", "filingFacts",
              "leaks", "peakGB", "tokPerSec", "medianSeconds"]
    body = ",\n".join("        ModelScore(" + ", ".join(f"{k}: {swift(r[k])}" for k in fields) + ")" for r in rows)
    OUT.write_text(f"""// > GENERATED by eval/household/catalog.py from eval/household/results. Do not edit:
// > run more evals, then `python3 eval/household/catalog.py`.

/// One local model as the household eval measured it ({MEASURED_ON}). Scores are percentages.
struct ModelScore: Hashable {{
    let label: String
    let repo: String
    let name: String
    let detail: String
    let sizeGB: Double
    /// Facts found, all 40 questions, direct answers.
    let answers: Double?
    /// Facts found, the 14 hard questions, with Research.
    let research: Double?
    /// Dropped documents filed in the right place, and their facts kept.
    let filingPlace: Double?
    let filingFacts: Double?
    /// Account numbers or names written into a filing where they shouldn't be.
    let leaks: Int?
    /// Peak memory while answering (GB), and generation speed.
    let peakGB: Double?
    let tokPerSec: Double?
    let medianSeconds: Double?
}}

enum ModelCatalog {{
    static let measuredOn = "{MEASURED_ON}"
    static let entries: [ModelScore] = [
{body},
    ]
}}
""")
    print(f"wrote {OUT} ({len(rows)} models)")


if __name__ == "__main__":
    main()
