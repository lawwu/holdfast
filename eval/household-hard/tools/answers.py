"""Compute every CSV-derived expected answer for household-hard/questions.json.

Run:  python3 eval/household-hard/tools/answers.py

Rules (the same ones the vault's finance/README.md and health/README.md state):
- transactions.csv: amounts are positive outflows, negatives are refunds/credits.
  A row whose notes contain "dup" is a double import and is ignored.
- Grocery categories are spelled Groceries / groceries / Grocery; all count.
  Split Lakeside receipts count only the grocery half.
- "Restaurants" (the 2024 import) means Dining.
- activities.csv: person "Grandpa E." is Erik Sr.; "Erik" is Erik alone.
"""
import csv
import datetime as dt
import os
from collections import defaultdict

V = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "vault")


def rows(rel):
    with open(os.path.join(V, rel), newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


T = [t for t in rows("finance/data/transactions.csv") if "dup" not in t["notes"].lower()]
for t in T:
    t["amount"] = float(t["amount"])
A = rows("health/data/activities.csv")
NW = {r["month"]: r for r in rows("finance/data/net-worth.csv")}
G = rows("finance/data/giving.csv")

key = lambda s: s.lower().replace(" ", "").replace("-", "")
is_groc = lambda t: t["category"].lower() in ("groceries", "grocery")
out = {}

# A1 groceries 2025
out["A1 groceries 2025"] = sum(t["amount"] for t in T if t["date"].startswith("2025") and is_groc(t))
# A2 Fresh Basket 2026 (Jan-Oct), all aliases, net of refunds
out["A2 Fresh Basket 2026"] = sum(t["amount"] for t in T if t["date"].startswith("2026") and "freshbasket" in key(t["merchant"]))
# A3 Hardware Hub all-time
out["A3 Hardware Hub 2024-2026"] = sum(t["amount"] for t in T if any(k in key(t["merchant"]) for k in ("hardwarehub", "hdwrhub")))
# A4 fence per fence-project.md
fence = [t for t in T if ("hollis" in key(t["merchant"]) or "cedar&sons" in key(t["merchant"])
                          or ("ridgeway" in key(t["merchant"]) and t["date"] in ("2026-08-22", "2026-08-29")))]
out["A4 fence total"] = sum(t["amount"] for t in fence)
out["A4 fence rows"] = len(fence)
# A5 Erik run miles Oct 2026
out["A5 Erik run mi 2026-10"] = sum(float(a["distance_mi"]) for a in A if a["person"] == "Erik" and a["type"] == "run" and a["date"].startswith("2026-10"))
out["A5 trap: all persons run mi 2026-10"] = sum(float(a["distance_mi"]) for a in A if a["type"] == "run" and a["date"].startswith("2026-10"))
# A6 Erik Sr walk miles Sept 2026
sr = ("Erik Sr.", "Grandpa E.")
out["A6 Erik Sr walk mi 2026-09"] = sum(float(a["distance_mi"]) for a in A if a["person"] in sr and a["type"] == "walk" and a["date"].startswith("2026-09"))
out["A6 trap: only 'Erik Sr.' label"] = sum(float(a["distance_mi"]) for a in A if a["person"] == "Erik Sr." and a["type"] == "walk" and a["date"].startswith("2026-09"))
out["A6 walks count"] = sum(1 for a in A if a["person"] in sr and a["type"] == "walk" and a["date"].startswith("2026-09"))
# A7 weeks (Mon-Sun) 2026-07-06 .. 2026-08-30 meeting 3 runs + 2 strength
met = []
for i in range(8):
    s = dt.date(2026, 7, 6) + dt.timedelta(days=7 * i)
    e = s + dt.timedelta(days=6)
    wk = [a for a in A if a["person"] == "Erik" and s.isoformat() <= a["date"] <= e.isoformat()]
    runs = sum(a["type"] == "run" for a in wk)
    st = sum(a["type"] == "strength" for a in wk)
    met.append((s.isoformat(), runs, st, runs >= 3 and st >= 2))
out["A7 weeks met Jul6-Aug30"] = sum(m[3] for m in met)
out["A7 detail"] = met
# A8 net worth
out["A8 NW 2025-12"] = int(NW["2025-12"]["net_worth"])
out["A8 NW 2026-10"] = int(NW["2026-10"]["net_worth"])
out["A8 change"] = out["A8 NW 2026-10"] - out["A8 NW 2025-12"]
# A9 giving 2026 YTD vs $20,400 goal
g26 = sum(float(g["amount"]) for g in G if g["date"].startswith("2026"))
out["A9 giving 2026 YTD"] = g26
out["A9 pct of 20400"] = 100 * g26 / 20400
# A10 utilities 2025 average per month
u25 = sum(t["amount"] for t in T if t["date"].startswith("2025") and t["category"] == "Utilities")
out["A10 utilities 2025 total"] = u25
out["A10 utilities 2025 avg/mo"] = u25 / 12

# other numbers used by questions
out["D3 Fresh Bake Co 2026"] = sum(t["amount"] for t in T if t["date"].startswith("2026") and t["merchant"] == "Fresh Bake Co.")
out["M1 braces paid through 2026-10"] = sum(t["amount"] for t in T if t["merchant"] == "BRIGHTVIEW ORTHO")
out["M5 food pantry 2025"] = sum(float(g["amount"]) for g in G if g["date"].startswith("2025") and "Food Pantry" in g["recipient"])
out["M9 vet 2026"] = sum(t["amount"] for t in T if t["date"].startswith("2026") and "juniperanimal" in key(t["merchant"]))
out["M9 trap: all 'juniper' 2026"] = sum(t["amount"] for t in T if t["date"].startswith("2026") and "juniper" in key(t["merchant"]))
out["Erik run mi 2026 YTD (Jan-Oct)"] = sum(float(a["distance_mi"]) for a in A if a["person"] == "Erik" and a["type"] == "run" and a["date"].startswith("2026"))
out["Erik run mi 2026 Jan-Aug (overview)"] = sum(float(a["distance_mi"]) for a in A if a["person"] == "Erik" and a["type"] == "run" and "2026-01" <= a["date"][:7] <= "2026-08")
out["dining 2024 (Restaurants)"] = sum(t["amount"] for t in T if t["date"].startswith("2024") and t["category"] in ("Dining", "Restaurants"))

if __name__ == "__main__":
    for k, v in out.items():
        if isinstance(v, float):
            print(f"{k}: {v:,.2f}")
        else:
            print(f"{k}: {v}")
