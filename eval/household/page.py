"""The household eval as a web page: eval/household/page.html.

Reads the same results as report.py (results/qa, results/filing), re-scores
them against the current questions.json and filing.json, and writes one
self-contained HTML page with paired bar charts (quality beside speed, never on
one axis) and the full tables. Stdlib only.

  python3 eval/household/page.py

NAMES maps run labels to readable setups; add a row when run.sh gains a setup.
HARDWARE is where the numbers were measured.
"""
import html, json, pathlib, re, statistics

import os
# The fixture: this folder, or another with the same layout (MACKB_FIXTURE=eval/household-hard).
HERE = pathlib.Path(os.environ.get("MACKB_FIXTURE") or pathlib.Path(__file__).parent).resolve()
RES = HERE / "results"
HARDWARE = "MacBook Pro, M1 Max, 64 GB"
RUN_DATE = "2026-11-05"

NAMES = {
    "qwen27b": ("Qwen 3.8 27B", "4-bit · dense"),
    "gemma26b": ("Gemma 4 26B A4B", "4-bit · mixture of experts"),
    "gemmae4b": ("Gemma 4 E4B", "4-bit · small"),
    "google26b": ("Google only", "Gemma 4 26B + EmbeddingGemma, no reranker"),
    "qwen27b-research": ("Qwen 3.8 27B", "Research mode"),
    "gemma26b-research": ("Gemma 4 26B A4B", "Research mode"),
    "search-qwen3emb-rerank": ("Qwen3-Embedding 0.6B", "+ Qwen3-Reranker 0.6B"),
    "search-qwen3emb-norerank": ("Qwen3-Embedding 0.6B", "no reranker"),
    "search-embgemma-rerank": ("EmbeddingGemma 300M", "+ Qwen3-Reranker 0.6B"),
    "search-embgemma-norerank": ("EmbeddingGemma 300M", "no reranker"),
    "qwen36moe": ("Qwen 3.6 35B A3B", "4-bit · mixture of experts"),
    "gptoss20b": ("gpt-oss 20B", "MXFP4 · mixture of experts"),
    "gemma31b": ("Gemma 4 31B", "4-bit · dense"),
    "qwen36d27b": ("Qwen 3.6 27B", "4-bit · dense"),
    "qwen35-9b": ("Qwen 3.5 9B", "4-bit · small"),
    "qwen35-4b": ("Qwen 3.5 4B", "4-bit · small"),
    "qwen35-2b": ("Qwen 3.5 2B", "4-bit · small"),
    "gemmae2b": ("Gemma 4 E2B", "4-bit · small"),
    "qwen36moe-research": ("Qwen 3.6 35B A3B", "Research mode"),
    "gptoss20b-research": ("gpt-oss 20B", "Research mode"),
    "gemma31b-research": ("Gemma 4 31B", "Research mode"),
    "qwen36d27b-research": ("Qwen 3.6 27B", "Research mode"),
    "search-qwen3emb-rr4b": ("Qwen3-Embedding 0.6B", "+ Qwen3-Reranker 4B"),
    "search-qwen3emb-rr8b": ("Qwen3-Embedding 0.6B", "+ Qwen3-Reranker 8B"),
    "search-embgemma-rr4b": ("EmbeddingGemma 300M", "+ Qwen3-Reranker 4B"),
    "search-embgemma-rr8b": ("EmbeddingGemma 300M", "+ Qwen3-Reranker 8B"),
    "claude-haiku": ("Claude Haiku 5.5", "Claude Code · cloud"),
    "claude-sonnet": ("Claude Sonnet 5.5", "Claude Code · cloud"),
    "claude-opus": ("Claude Opus 5.5", "Claude Code · cloud"),
    "claude-fable": ("Claude Fable 5.1", "Claude Code · cloud"),
    "gemini": ("Gemini", "cloud baseline"),
}
ORDER = ["claude-fable", "claude-opus", "claude-sonnet", "claude-haiku", "qwen27b", "qwen36d27b", "qwen36moe", "gemma31b", "gemma26b", "gemmae4b", "qwen35-9b", "qwen35-4b", "qwen35-2b", "gemmae2b", "gptoss20b", "google26b", "gemini"]


def name(lab):
    return NAMES.get(lab, (lab, ""))


def load(kind):
    d = RES / kind
    return {p.stem: json.loads(p.read_text()) for p in sorted(d.glob("*.json"))} if d.exists() else {}


def mean(xs):
    xs = [x for x in xs if x is not None]
    return statistics.mean(xs) if xs else None


def median(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


# ---- data, re-scored as in report.py
QS = {q["id"]: q for q in json.loads((HERE / "questions.json").read_text())}
CASES = {c["id"]: c for c in json.loads((HERE / "filing.json").read_text())}
qa, filing = load("qa"), load("filing")
for rs in qa.values():
    for r in rs:
        q = QS.get(r["id"])
        if q and r.get("mode") != "retrieval":
            r["facts"] = sum(1 for p in q["expect"] if re.search(p, r["answer"], re.I)) / max(len(q["expect"]), 1)
            # A wrong-answer signature (a superseded value, the other Erik's number) zeroes it.
            r["wrong"] = [p for p in q.get("reject", []) if re.search(p, r["answer"], re.I)]
            if r["wrong"]:
                r["facts"] = 0.0
for rs in filing.values():
    for r in rs:
        c = CASES.get(r["id"])
        if c and not r.get("error"):
            r["actionOK"] = r["action"] in c["expect_action"].split("|")
            if c["expect_action"] != "skip":
                r["placeOK"] = r["action"] != "skip" and re.search(c["expect_path"], r["path"], re.I) is not None
                r["leaks"] = [x for x in c["forbid"] if re.search(x, r.get("markdown", ""), re.I)]

plain = {k: v for k, v in qa.items() if v and v[0].get("mode") == "plain"}
research = {k: v for k, v in qa.items() if v and v[0].get("mode") == "research"}
search = {k: v for k, v in qa.items() if v and v[0].get("mode") == "retrieval"}
cloud = {k: v for k, v in qa.items() if v and v[0].get("mode") == "claude-code"}


def ordered(d):
    return sorted(d, key=lambda k: (ORDER.index(k.replace("-research", "")) if k.replace("-research", "") in ORDER else 99, k))


def qa_row(rs):
    ans = [r for r in rs if r["kind"] != "unanswerable"]
    un = [r for r in rs if r["kind"] == "unanswerable"]
    simple = [r for r in rs if r["kind"] == "fact"]
    return {
        "facts": mean(r["facts"] for r in ans), "simple": mean(r["facts"] for r in simple),
        "abstain": mean(r["facts"] for r in un) if un else None,
        "context": mean(r.get("contextRecall") for r in ans), "files": mean(r.get("pathRecall") for r in ans),
        "cited": mean(1.0 if r["cited"] else 0.0 for r in ans), "median": median(r["seconds"] for r in rs),
        "n": len(rs), "cost": sum(r.get("costUSD") or 0 for r in rs) if any("costUSD" in r for r in rs) else None,
    }


def filing_row(rs):
    n = len(rs)
    return {"action": sum(r["actionOK"] for r in rs) / n, "place": sum(r["placeOK"] for r in rs) / n,
            "facts": mean(r["facts"] for r in rs), "leaks": sum(len(r["leaks"]) for r in rs),
            "errors": sum(1 for r in rs if r.get("error")), "median": median(r["seconds"] for r in rs), "n": n,
            "cost": sum(r.get("costUSD") or 0 for r in rs) if any("costUSD" in r for r in rs) else None}


# ---- rendering helpers
def esc(s):
    return html.escape(str(s))


def pct(x):
    return "—" if x is None else f"{x * 100:.0f}%"


def secs(x):
    return "—" if x is None else f"{x:.0f} s"


def bars(title, rows, maxv, fmt, unit_note=""):
    """Horizontal bars, one series, value labels at the bar end. rows: [(label, sub, value)]."""
    row_h, label_w, w, pad = 34, 0, 360, 4
    h = len(rows) * row_h + 26
    out = [f'<figure class="chart"><figcaption>{esc(title)}<span>{esc(unit_note)}</span></figcaption>',
           f'<svg viewBox="0 0 {w} {h}" role="img" aria-label="{esc(title)}">']
    # recessive gridlines at quarters
    for i in range(5):
        x = pad + (w - 70 - pad) * i / 4
        out.append(f'<line class="grid" x1="{x:.1f}" y1="0" x2="{x:.1f}" y2="{h - 22}"/>')
        out.append(f'<text class="tick" x="{x:.1f}" y="{h - 6}" text-anchor="middle">{esc(fmt(maxv * i / 4))}</text>')
    for i, (lab, sub, v) in enumerate(rows):
        y = i * row_h + 6
        bw = 0 if v is None else max(2, (w - 70 - pad) * v / maxv)
        tip = f"{lab} · {sub}: {fmt(v) if v is not None else 'not run'}"
        out.append(f'<g class="bar" data-tip="{esc(tip)}"><rect class="hit" x="0" y="{y - 3}" width="{w}" height="{row_h}"/>'
                   f'<path class="mark" d="{rounded(pad, y + 4, bw, 16)}"/>'
                   f'<text class="val" x="{pad + bw + 6:.1f}" y="{y + 16}">{esc(fmt(v)) if v is not None else "—"}</text></g>')
    out.append("</svg></figure>")
    return "\n".join(out)


def rounded(x, y, w, h, r=4):
    """A bar anchored on the left with a 4px rounded data end."""
    r = min(r, w / 2, h / 2)
    return (f"M{x:.1f},{y:.1f} H{x + w - r:.1f} Q{x + w:.1f},{y:.1f} {x + w:.1f},{y + r:.1f} "
            f"V{y + h - r:.1f} Q{x + w:.1f},{y + h:.1f} {x + w - r:.1f},{y + h:.1f} H{x:.1f} Z")


def legend_rows(labels):
    return "".join(f'<li><b>{esc(name(l)[0])}</b><span>{esc(name(l)[1])}</span></li>' for l in labels)


def chart_pair(labels, left, right):
    """Row labels once, then two charts that share the row order."""
    return (f'<div class="pair"><ol class="rowlabels">{legend_rows(labels)}</ol>{left}{right}</div>')


# ---- sections
P = {k: qa_row(v) for k, v in plain.items()}
C = {k: qa_row(v) for k, v in cloud.items()}
cl = ordered(C)
R = {k: qa_row(v) for k, v in research.items()}
S = {k: qa_row(v) for k, v in search.items()}
F = {k: filing_row(v) for k, v in filing.items()}
pl, rl, sl, fl = ordered(P), ordered(R), ordered(S), ordered(F)
max_s = max([P[k]["median"] for k in pl] + [R[k]["median"] for k in rl] + [C[k]["median"] for k in cl] + [1])
max_fs = max([F[k]["median"] for k in fl] + [1])


def nice(x):
    for step in (10, 20, 25, 50, 100):
        if x <= step * 4:
            return step * 4
    return x


qa_section = chart_pair(
    pl,
    bars("Facts found", [(name(k)[0], name(k)[1], P[k]["facts"]) for k in pl], 1, pct, "all answerable questions"),
    bars("Seconds per answer", [(name(k)[0], name(k)[1], P[k]["median"]) for k in pl], nice(max_s), lambda v: f"{v:.0f}", "median"),
)
research_section = chart_pair(
    rl,
    bars("Facts found", [(name(k)[0], name(k)[1], R[k]["facts"]) for k in rl], 1, pct, f"{max((len(v) for v in research.values()), default=0)} hardest questions"),
    bars("Seconds per answer", [(name(k)[0], name(k)[1], R[k]["median"]) for k in rl], nice(max_s), lambda v: f"{v:.0f}", "median"),
)
cloud_section = chart_pair(
    cl,
    bars("Facts found", [(name(k)[0], name(k)[1], C[k]["facts"]) for k in cl], 1, pct, "all answerable questions"),
    bars("Seconds per answer", [(name(k)[0], name(k)[1], C[k]["median"]) for k in cl], nice(max_s), lambda v: f"{v:.0f}", "median"),
) if cl else ""
filing_section = chart_pair(
    fl,
    bars("Filed in the right place", [(name(k)[0], name(k)[1], F[k]["place"]) for k in fl], 1, pct, f"{len(CASES)} documents"),
    bars("Seconds per document", [(name(k)[0], name(k)[1], F[k]["median"]) for k in fl], nice(max_fs), lambda v: f"{v:.0f}", "median"),
)
search_section = chart_pair(
    sl,
    bars("Expected facts in the passages", [(name(k)[0], name(k)[1], S[k]["context"]) for k in sl], 1, pct, "8 passages per question"),
    bars("Answer files among the passages", [(name(k)[0], name(k)[1], S[k]["files"]) for k in sl], 1, pct, ""),
)


def table(head, rows, cls=""):
    th = "".join(f"<th>{esc(h)}</th>" for h in head)
    trs = "".join("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>" for r in rows)
    return f'<div class="scroll"><table class="{cls}"><thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table></div>'


def setup_cell(k):
    return f"<b>{esc(name(k)[0])}</b><small>{esc(name(k)[1])}</small>"


qa_table = table(["Setup", "Facts", "Simple facts", "Says “not in your notes”", "Facts in passages", "Cited", "s / answer"],
                 [[setup_cell(k), pct(P[k]["facts"]), pct(P[k]["simple"]), pct(P[k]["abstain"]), pct(P[k]["context"]),
                   pct(P[k]["cited"]), secs(P[k]["median"])] for k in pl] +
                 [[setup_cell(k), pct(R[k]["facts"]), "—", "—", pct(R[k]["context"]), pct(R[k]["cited"]), secs(R[k]["median"])] for k in rl] +
                 [[setup_cell(k), pct(C[k]["facts"]), pct(C[k]["simple"]), pct(C[k]["abstain"]), "—", pct(C[k]["cited"]), secs(C[k]["median"])] for k in cl],
                 "num")
def money(x):
    return "—" if x is None else f"${x:.2f}"
cloud_table = table(["Setup", "Facts", "Says “not in your notes”", "s / answer", "Filing: right place", "Filing: facts kept", "Leaks",
                     "API price, 40 questions + 12 documents"],
                    [[setup_cell(k), pct(C[k]["facts"]), pct(C[k]["abstain"]), secs(C[k]["median"]),
                      pct(F.get(k, {}).get("place")), pct(F.get(k, {}).get("facts")), str(F.get(k, {}).get("leaks", "—")),
                      money((C[k]["cost"] or 0) + (F.get(k, {}).get("cost") or 0))] for k in cl], "num") if cl else ""
filing_table = table(["Setup", "Right action", "Right place", "Facts kept", "IDs or names leaked", "s / document"],
                     [[setup_cell(k), pct(F[k]["action"]), pct(F[k]["place"]), pct(F[k]["facts"]),
                       f'<span class="{"bad" if F[k]["leaks"] else ""}">{F[k]["leaks"]}</span>', secs(F[k]["median"])] for k in fl], "num")

domains = sorted({r.get("domain") or "?" for rs in plain.values() for r in rs})
domain_table = table(["Setup"] + domains,
                     [[setup_cell(k)] + [pct(mean(r["facts"] for r in plain[k] if (r.get("domain") or "?") == d and r["kind"] != "unanswerable")) for d in domains] for k in pl],
                     "num")
KIND_ORDER = ["fact", "synthesis", "table", "temporal", "cross"]  # household; other fixtures sort their own
kinds = sorted({q["kind"] for q in QS.values()}, key=lambda k: (k == "unanswerable", KIND_ORDER.index(k) if k in KIND_ORDER else 9, k))
kind_table = table(["Setup"] + kinds,
                   [[setup_cell(k)] + [pct(mean(r["facts"] for r in qa[k] if r["kind"] == kd)) for kd in kinds] for k in cl + pl + rl], "num")

docs = []
for cid, c in CASES.items():
    cells = [f"<b>{esc(cid)}</b><small>{esc(pathlib.Path(c['file']).stem.replace('-', ' '))}</small>",
             esc(c["expect_action"].replace("|", " or "))]
    for k in fl:
        r = next((x for x in filing[k] if x["id"] == cid), None)
        if r is None:
            cells.append("—")
        elif r.get("error"):
            cells.append('<span class="bad">error</span>')
        else:
            ok = r["actionOK"] and r["placeOK"]
            leak = f' <span class="bad">leaked {len(r["leaks"])}</span>' if r["leaks"] else ""
            cells.append(f'<span class="{"ok" if ok else "bad"}">{"✓" if ok else "✗"}</span> '
                         f'<code>{esc(r["path"] or r["action"]).replace("/", "/<wbr>")}</code>{leak}')
    docs.append(cells)
doc_table = table(["Document", "Expected"] + [name(k)[0] + (" (Google only)" if k == "google26b" else "") for k in fl], docs, "docs")

# ---- which Mac: peak memory from memory.py; speed on other chips scaled by memory bandwidth.
# Token generation on Apple silicon is bound by memory bandwidth, so tok/s scales roughly with it.
# An estimate, not a measurement: prompt processing (compute-bound) slows down more on base chips.
MEM = json.loads((RES / "memory.json").read_text()) if (RES / "memory.json").exists() else {}
MACS_GB = [8, 16, 24, 32, 64]
MEASURED_BW = 400  # GB/s, M1 Max: the machine every run here used
OTHER_CHIPS = [("M4", 120), ("M4 Pro", 273)]  # GB/s, Apple's published figures


def worst_gb(k):
    xs = [MEM.get(k, {}).get(m, {}).get("peakGB") for m in ("plain", "research")]
    xs = [x for x in xs if x]
    return max(xs) if xs else None


def tok_s(k):
    return median(r.get("tokPerSec") for r in plain.get(k, []) if r.get("tokPerSec"))


def fit_cell(v):
    cls = {"fits": "ok", "no": "bad"}.get(v, "")
    return f'<span class="{cls}">{esc(v)}</span>'


ml = sorted((k for k in MEM if k != "search" and worst_gb(k)), key=worst_gb)
mem_table = table(
    ["Setup", "Peak memory", "Facts", "Filed right"] + [f"{g} GB Mac" for g in MACS_GB] + [f"tok/s, {c}" for c, _ in OTHER_CHIPS],
    [[setup_cell(k), f"{worst_gb(k):.1f} GB", pct(P.get(k, {}).get("facts")), pct(F.get(k, {}).get("place"))]
     + [fit_cell(MEM[k]["fit"].get(str(g), "?")) for g in MACS_GB]
     + [("~" + f"{tok_s(k) * bw / MEASURED_BW:.0f}") if tok_s(k) else "—" for _, bw in OTHER_CHIPS] for k in ml],
    "num") if ml else ""
search_gb = MEM.get("search", {}).get("plain", {}).get("peakGB")
mem_section = f"""<section>
  <h2>Which Mac can run this?</h2>
  <p>Peak memory of the whole app process (answer model, embedder, reranker and the context) on the longest prompt it
  makes, Research mode. macOS lets the GPU use about two-thirds of memory on Macs up to 36 GB, and macOS with a browser
  open needs about 4 GB, so a setup <b>fits</b> when it peaks under 90% of the smaller of those two limits and is
  <b>tight</b> up to 100%. Search alone{f" peaks at {search_gb:.1f} GB" if search_gb else ""}. Speeds on other chips are
  the M1 Max's measured speed scaled by memory bandwidth, an estimate.</p>
  {mem_table}
</section>""" if ml else ""

nq = len(QS)
nd = len(CASES)
page = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Local Models on a Family Knowledge Base</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&family=Literata:opsz,wght@7..72,500;7..72,600&display=swap" rel="stylesheet">
<style>
/* Layout: one reading column; charts as paired bar strips sharing row labels. */
:root {{
  color-scheme: light;
  --bg: #f7f8fa; --surface: #ffffff; --ink: #14171c; --ink-2: #4c535e; --ink-3: #7c838e;
  --line: #e2e5ea; --accent: #2a78d6; --good: #1a7f4b; --bad: #c2362f;
  --display: "Literata", Georgia, serif; --body: "IBM Plex Sans", system-ui, sans-serif; --mono: "IBM Plex Mono", ui-monospace, monospace;
}}
@media (prefers-color-scheme: dark) {{
  :root:not([data-theme="light"]) {{
    color-scheme: dark;
    --bg: #15171b; --surface: #1c1f24; --ink: #eef0f3; --ink-2: #b8bec8; --ink-3: #8b929d;
    --line: #2c3038; --accent: #3987e5; --good: #4cc38a; --bad: #f07a72;
  }}
}}
:root[data-theme="dark"] {{
  color-scheme: dark;
  --bg: #15171b; --surface: #1c1f24; --ink: #eef0f3; --ink-2: #b8bec8; --ink-3: #8b929d;
  --line: #2c3038; --accent: #3987e5; --good: #4cc38a; --bad: #f07a72;
}}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--bg); color: var(--ink); font: 15.5px/1.6 var(--body); }}
main {{ max-width: 980px; margin: 0 auto; padding: 48px 20px 80px; display: grid; gap: 40px; }}
h1, h2 {{ font-family: var(--display); font-weight: 600; text-wrap: balance; margin: 0; }}
h1 {{ font-size: 34px; line-height: 1.2; }}
h2 {{ font-size: 23px; }}
h3 {{ font-size: 15px; margin: 18px 0 6px; color: var(--ink-2); font-weight: 600; }}
p, li {{ max-width: 68ch; }}
p {{ margin: 0 0 10px; }}
.lede {{ color: var(--ink-2); font-size: 17px; }}
.meta {{ font: 13px var(--mono); color: var(--ink-3); }}
section {{ display: grid; gap: 14px; }}
.findings {{ margin: 0; padding-left: 20px; display: grid; gap: 8px; }}
.card {{ background: var(--surface); border: 1px solid var(--line); border-radius: 12px; padding: 18px; }}
.pair {{ display: grid; grid-template-columns: 210px 1fr 1fr; gap: 0 18px; align-items: start; }}
.rowlabels {{ list-style: none; margin: 34px 0 0; padding: 0; }}
.rowlabels li {{ height: 34px; display: flex; flex-direction: column; justify-content: center; line-height: 1.2; }}
.rowlabels b {{ font-weight: 600; font-size: 14px; }}
.rowlabels span {{ font-size: 12px; color: var(--ink-3); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }}
.chart {{ margin: 0; }}
.chart figcaption {{ font-size: 13px; font-weight: 600; height: 28px; display: flex; gap: 8px; align-items: baseline; }}
.chart figcaption span {{ font-weight: 400; color: var(--ink-3); font-size: 12px; }}
.chart svg {{ width: 100%; height: auto; overflow: visible; }}
.grid {{ stroke: var(--line); stroke-width: 1; }}
.tick {{ fill: var(--ink-3); font: 10.5px var(--mono); }}
.mark {{ fill: var(--accent); }}
.val {{ fill: var(--ink); font: 500 12px var(--mono); }}
.hit {{ fill: transparent; }}
.bar:hover .mark {{ opacity: .8; }}
.scroll {{ overflow-x: auto; }}
table {{ border-collapse: collapse; width: 100%; font-size: 13.5px; background: var(--surface); }}
th, td {{ text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--line); vertical-align: top; }}
th {{ font-weight: 600; color: var(--ink-2); font-size: 12.5px; }}
table.num td:not(:first-child) {{ font-family: var(--mono); font-variant-numeric: tabular-nums; }}
td small {{ display: block; color: var(--ink-3); font-size: 11.5px; }}
code {{ font: 12px var(--mono); color: var(--ink-2); word-break: normal; overflow-wrap: anywhere; }}
table.docs td {{ min-width: 150px; }}
.ok {{ color: var(--good); font-weight: 600; }}
.bad {{ color: var(--bad); font-weight: 600; }}
#tip {{ position: fixed; pointer-events: none; background: var(--ink); color: var(--bg); font: 12px var(--body);
  padding: 5px 8px; border-radius: 6px; opacity: 0; transition: opacity .1s; z-index: 9; }}
@media (max-width: 760px) {{
  .pair {{ grid-template-columns: 1fr; }}
  .rowlabels {{ display: none; }}
  .chart svg .bar .val {{ font-size: 11px; }}
}}
@media (prefers-reduced-motion: reduce) {{ #tip {{ transition: none; }} }}
</style>
</head>
<body>
<main>
<header>
  <p class="meta">mac-kb household eval · run {RUN_DATE} · {esc(HARDWARE)}</p>
  <h1>Local models on a family knowledge base</h1>
  <p class="lede">How well do models that run entirely on a Mac answer questions from a family's notes, and file new
  documents into them? Every model here runs on-device with MLX; nothing leaves the laptop.</p>
</header>

<section class="card">
  <h2>What we found</h2>
  <ul class="findings">
    <li><b>Qwen 3.8 27B is the most accurate</b> at everything tested, and the slowest:
      {pct(P.get('qwen27b', {}).get('facts'))} of facts in plain answers, {pct(R.get('qwen27b-research', {}).get('facts'))} on the hardest questions in Research mode,
      and every one of {nd} documents filed in the right place.</li>
    <li><b>Gemma 4 26B is nearly as good and 3–5× faster</b>: {pct(P.get('gemma26b', {}).get('facts'))} of facts at
      {secs(P.get('gemma26b', {}).get('median'))} per answer, against {secs(P.get('qwen27b', {}).get('median'))} for Qwen. It slips on harder work:
      {pct(R.get('gemma26b-research', {}).get('facts'))} in Research mode.</li>
    <li><b>The small Gemma 4 E4B answers simple questions as well as the big models</b>, but when filing it
      kept two full names in a counseling report that should use initials only, and filed a duplicate.</li>
    <li><b>Search quality comes from the reranker.</b> Google's EmbeddingGemma ties Qwen's embedder once Qwen's
      reranker sorts the results; without it, the Google-only setup found fewer of the right passages and its answers fell to
      {pct(P.get('google26b', {}).get('facts'))}.</li>
    <li><b>Numbers need Research mode.</b> No model can total a CSV from search passages; with tools to query the
      CSVs, Qwen answered all six spending and workout questions.</li>
  </ul>
</section>

<section>
  <h2>Answering questions</h2>
  <p>{nq} questions over the vault: facts from one note, summaries across notes, totals from CSVs, questions that depend on
  today's date, questions that span two areas of life, and four the notes can't answer. An answer scores the share of
  expected facts it contains.</p>
  {qa_section}
  <h3>Research mode</h3>
  <p>The model searches, reads whole notes, lists folders and runs SQL over CSVs, in up to eight steps, before answering.</p>
  {research_section}
  {qa_table}
  <h3>By area of life (plain answers)</h3>
  {domain_table}
  <h3>By kind of question</h3>
  {kind_table}
</section>

{'' if not cl else f'''<section>
  <h2>Claude Code as a baseline</h2>
  <p>The same questions and documents, given to Claude Code in a scratch copy of the vault: it reads the READMEs, searches and
  opens notes, and queries the CSVs itself, with read-only tools. These models run in the cloud, so they show what the local
  setups are aiming at, not something the app sends data to. Prices are what the run would cost on the API.</p>
  {cloud_section}
  {cloud_table}
</section>'''}

<section>
  <h2>Filing dropped documents</h2>
  <p>{nd} documents dropped into the knowledge base: invoices, receipts, a clinic visit summary, an insurance renewal, a bank
  statement, a counseling session report, a flyer, a recipe, and one duplicate. The model reads each with the folder
  READMEs and proposes a new note or a row in an existing log. Scored on the action, the place, the facts kept, and any
  account numbers, member IDs or full names that should have been left out.</p>
  {filing_section}
  {filing_table}
  <h3>Every document</h3>
  {doc_table}
</section>

<section>
  <h2>Search</h2>
  <p>The step before the model: which 8 passages each question gets. No answer model involved.</p>
  {search_section}
</section>

{mem_section}

<section class="card">
  <h2>How this was run</h2>
  <p>The knowledge base is invented: a family of five with finance notes and spending CSVs, home maintenance logs,
  health visits and a workout CSV, trips, a career note, and biblical-counseling case reports that follow an initials-only rule.
  Today's date is fixed at {RUN_DATE}. Answers and filings are scored by text patterns, with no model judging another.
  Each setup ran once on {esc(HARDWARE)}; with {nq} questions and {nd} documents, differences of a few points are noise.</p>
  <p>Not yet run: Gemini (no API key set), larger Qwen embedders, and a harder fixture with longer histories,
  superseded facts and more CSV arithmetic.</p>
</section>
</main>
<div id="tip" role="tooltip"></div>
<script>
const tip = document.getElementById("tip");
document.querySelectorAll(".bar").forEach(g => {{
  g.addEventListener("mousemove", e => {{
    tip.textContent = g.dataset.tip; tip.style.opacity = 1;
    tip.style.left = (e.clientX + 12) + "px"; tip.style.top = (e.clientY + 12) + "px";
  }});
  g.addEventListener("mouseleave", () => {{ tip.style.opacity = 0; }});
}});
</script>
</body>
</html>
"""
(HERE / "page.html").write_text(page)
print(f"wrote {HERE / 'page.html'}")
