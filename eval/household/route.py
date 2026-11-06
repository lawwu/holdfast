"""Scores the router (Sources/mackb/Router.swift) against saved results: for each
question, did a direct answer or Research do better? Stdlib only.

  mackb route --file eval/household/questions.json > /tmp/routes.tsv
  python3 eval/household/route.py /tmp/routes.tsv [--models qwen27b gemma26b ...]

For a question that has both a plain and a research result for a model (the 14
"hard" questions), the better mode is the one with more facts; ties prefer the
direct answer (it is 2-4x faster). Questions with only a plain result count as
"direct is enough" when the plain answer got every fact. Reports how often the
router picks the better mode, and the facts it would have scored.
Re-scores answers with the same reject rules as report.py.
"""
import argparse, json, pathlib, re

HERE = pathlib.Path(__file__).parent
QS = {q["id"]: q for q in json.loads((HERE / "questions.json").read_text())}


def facts(r):
    q = QS[r["id"]]
    if any(re.search(p, r["answer"], re.I) for p in q.get("reject", [])):
        return 0.0
    return sum(1 for p in q["expect"] if re.search(p, r["answer"], re.I)) / max(len(q["expect"]), 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("routes")
    ap.add_argument("--models", nargs="*", default=["qwen27b", "gemma26b", "gemma31b", "qwen36moe", "qwen36d27b"])
    a = ap.parse_args()
    routes = {}
    for line in pathlib.Path(a.routes).read_text().splitlines():
        parts = line.split("\t")
        if len(parts) >= 2:
            routes[parts[0]] = parts[1]
    for m in a.models:
        pf, rf = HERE / f"results/qa/{m}.json", HERE / f"results/qa/{m}-research.json"
        if not pf.exists():
            continue
        plain = {r["id"]: facts(r) for r in json.loads(pf.read_text()) if r["kind"] != "unanswerable"}
        research = {r["id"]: facts(r) for r in json.loads(rf.read_text())} if rf.exists() else {}
        right = judged = 0
        got = {"router": [], "always-direct": [], "always-research": [], "best": []}
        for qid, p in plain.items():
            r = research.get(qid)
            route = routes.get(qid, "answer")
            if r is None:
                if p < 1:
                    continue  # can't tell whether research would have helped
                better = "answer"
                r_eff = p
            else:
                better = "research" if r > p else "answer"
                r_eff = r
            judged += 1
            right += (route == "research") == (better == "research")
            got["router"].append(r_eff if route == "research" else p)
            got["always-direct"].append(p)
            got["always-research"].append(r_eff)
            got["best"].append(max(p, r_eff))
        avg = {k: sum(v) / max(len(v), 1) * 100 for k, v in got.items()}
        print(f"{m}: router picks the better mode {right}/{judged} · facts: router {avg['router']:.0f}% · "
              f"always direct {avg['always-direct']:.0f}% · always research {avg['always-research']:.0f}% · best possible {avg['best']:.0f}%")


if __name__ == "__main__":
    main()
