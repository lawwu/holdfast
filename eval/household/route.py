"""Scores the router (Sources/holdfast/Router.swift) against saved results: for each
question, did a direct answer or Research do better? Stdlib only.

  holdfast route --file eval/household/questions.json > /tmp/routes.tsv
  python3 eval/household/route.py /tmp/routes.tsv [--models qwen27b gemma26b ...]

Every answerable question counts. Where a model has both a plain and a research
result (the 14 "hard" questions), the better mode is the one with more facts;
ties prefer the direct answer (it is 2-4x faster). Where research wasn't run,
its score is unknown and taken to equal the direct answer's: the script says
how many questions that assumption covers.
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
        # Every answerable question counts. Research was only run on some of them; where it wasn't,
        # its score is unknown and is taken to equal the direct answer's (reported as "assumed").
        got = {"router": [], "always-direct": [], "always-research": [], "best": []}
        right = judged = assumed = 0
        for qid, p in plain.items():
            r = research.get(qid)
            route = routes.get(qid, "answer")
            if r is None:
                assumed += 1
                r = p
            else:
                judged += 1
                right += (route == "research") == (r > p)
            got["router"].append(r if route == "research" else p)
            got["always-direct"].append(p)
            got["always-research"].append(r)
            got["best"].append(max(p, r))
        avg = {k: sum(v) / max(len(v), 1) * 100 for k, v in got.items()}
        print(f"{m}: {len(plain)} answerable questions · facts: router {avg['router']:.0f}% · always direct {avg['always-direct']:.0f}% · "
              f"always research {avg['always-research']:.0f}% · best possible {avg['best']:.0f}% · router picked the better mode on "
              f"{right}/{judged} questions with both results; {assumed} without a research run assume it equals the direct answer")

if __name__ == "__main__":
    main()
