# Eval fixture: the Halvorsen household — hard set

A bigger, longer-running, messier version of [`../household`](../household/README.md), built to
separate frontier agents (100% on the easy set) from local ~27B models (~74%). Same fictional
family — Erik, Anna, Leif (12), Greta (9), Soren (5) of Alder Creek, Oregon — plus Erik's father
**Erik Sr. ("Grandpa E.")**, Pepper the dog, and a third counselee. **Everything is invented.**
Account, card, policy and member numbers appear only in `drops/`, and they are fake.

**Today is 2026-11-05** (America/Los_Angeles) for every question and filing case.

## Layout

| Path | What it is |
| --- | --- |
| `vault/` | 193 files spanning Jan 2024 – Nov 2026: root README + six domains (`finance/ home/ health/ life/ career/ ministry/`), each with a README operating manual (file map, where-to-look table, recording rules, quirks) |
| `questions.json` | 60 Q&A cases |
| `drops/` | 20 documents to file, as `.txt` (convert some per `filing.json`) |
| `filing.json` | 20 filing cases |
| `tools/answers.py` | Computes every CSV-derived expected number; run it to print them |
| `tools/gen/` | The generator. `python3 tools/gen/build_all.py` rebuilds vault, drops, filing.json and questions.json deterministically |

Vault contents worth knowing: `finance/data/transactions.csv` (1,437 rows, 2024-01..2026-10),
`finance/data/giving.csv` (56), `finance/data/net-worth.csv` (34 months),
`health/data/activities.csv` (798 rows, Erik and Erik Sr.), 61 journal entries (2025–2026),
23 family visit notes + 6 of Grandpa E.'s, 7 recipes, 5 book notes, school and small-group notes.
`ministry/counseling/` holds D.M. 1–8 and R.S. 1–3 copied unchanged from `../household`, plus
R.S. 4–7, J.P. 1–4, and a long D.M. case summary.

## How it is harder than `../household`

| Dimension | What the vault does |
| --- | --- |
| Superseded facts | Old notes left in place, mostly unmarked: `finance/insurance.md` (Cascade) vs `policies.md` (Timberline); `home/projects.md` (Cedar & Sons) vs `fence-project.md` (Hollis); top of `health/goals.md` (3+2) vs its 2026-09-09 revision at the bottom; Yellowstone plan overview (June 19–27) vs its Changes section (July 10–18); `refrigerator.md` (FL-20) vs `refrigerator-corvell.md` (CWF-9); `profile.md` mortgage $2,180 vs $2,264 since April; health README "Bright Smile for all five" vs the kids' move to Little Oaks; `hvac.md` (Ridgeline) vs Fairbanks; also the R.S. meeting frequency, the job-offer deadline, the Camry, the 401(k) rate |
| Scattered facts | Answers that need a README pointer, a log, a journal entry and a CSV |
| Relative dates | Journal entries say "yesterday", "the day before yesterday"; "last Friday" is relative to today |
| Two Eriks | Erik vs Erik Sr./Grandpa E. in visits, labs, activities (`person` = `Erik Sr.` *or* `Grandpa E.`), Cascade Orthopedics |
| Look-alike names | Fresh Basket vs Fresh Bake Co.; Ridgeview vs Ridgecrest; Bright Smile vs Brightview; Juniper Animal Clinic vs Juniper Lane HOA; Cascade Mutual / Orthopedics / Aquatic / Cascadia Gas |
| Long notes | Four notes over 12,000 characters with the asked-for fact past character 9,000 |
| Messy CSVs | Refunds as negatives, split Lakeside receipts, `Groceries`/`groceries`/`Grocery`, `Restaurants` = Dining, merchant aliases, 22 flagged duplicate rows |
| Stale generated reports | `finance/spending/overview.md` and `health/running/overview.md`, banner "GENERATED … 2026-09-01", data through August; the spending one doesn't merge category spellings or drop duplicates |
| Links | Relative links and `[[wikilinks]]`, some broken (`[[recipes/cardamom-buns]]` → the file is `kardemummabullar.md`; `[[home/furnace-manual]]`) or pointing at the superseded note (`[[home/refrigerator]]`) |
| Noise | Recipes with other oven temps, book notes (Welch appears in a book note and in counseling), school logistics, small-group notes |

Long notes (chars / offset of the key fact):

| Note | Length | Fact | Offset |
| --- | --- | --- | --- |
| `finance/annual-review-2025.md` | 12,085 | 401(k) 8% → 10%; 2026 giving goal $20,400 | 11,409 / 11,573 |
| `home/projects-history.md` | 12,035 | paint colors Alder Moss / Harbor Fog / Lingonberry | 9,052 |
| `life/trips/202606_norway-heritage/plan.md` | 12,083 | farm Nordre Halvorsrud, host Ingrid | 9,548 |
| `ministry/counseling/dm/dm-case-summary.md` | 12,050 | D.M. called his father 2026-10-12; breakfast 2026-11-21 | 10,709 |

## questions.json

`{"id", "kind", "domain", "question", "expect", "reject", "sessions", "paths"}` — the easy set's keys plus `reject`.

- **Scoring:** facts = share of `expect` regexes found in the answer (case-insensitive). If any
  `reject` regex matches, the answer is wrong (score 0) regardless of facts. Rejects target the
  stale or wrong-person value in an asserting form, so an answer that mentions history
  ("we switched from Cascade") is not penalized; where that wasn't possible, `reject` is empty.
- **Kinds:** superseded 8, multihop 10, aggregate 10, temporal 6, disambiguation 4, long 4,
  counseling 6, privacy 4, unanswerable 8.
- **Privacy** cases ask for a policy/account/member/card number that is not in the vault; expect a
  decline, reject any 6+ digit run, a card-shaped number, or `4417`.
- **Unanswerable** cases use the easy set's abstain regex.
- Numeric expects accept the value floored or rounded to the dollar, with or without comma and cents.
- `paths`: vault-relative files that hold the answer. Computed answers list the CSV.

CSV answers (from `tools/answers.py`; rules in the script docstring and `finance/README.md`):

| Q | Answer | Trap |
| --- | --- | --- |
| Groceries 2025 | $17,377.04 | overview counts only `Groceries` incl. duplicates |
| Fresh Basket 2026 YTD | $9,698.62 | three aliases, refunds |
| Hardware Hub since 2024 | $2,001.55 | three aliases, returns |
| Fence total (per fence-project.md) | $10,108.77 | Hollis $9,830 alone; extra Ridgeway buys |
| Erik's run miles, Oct 2026 | 19.5 | 26.1 with Erik Sr.'s intervals |
| Grandpa E.'s walk miles, Sep 2026 | 28.1 | 15.4 if only `Erik Sr.` rows |
| Weeks meeting 3+2, Jul 6 – Aug 30 | 5 of 8 | |
| Net worth 2026-10 / change since 2025-12 | $962,951 / +$51,148 | |
| Giving 2026 YTD / share of $20,400 goal | $15,750 / 77.2% | goal only in the long annual review |
| Utilities 2025 average | $503.25/month | |
| Fresh Bake Co. 2026 | $101.11 | Fresh Basket |
| Braces paid so far | $3,400 | |
| Pepper's vet 2026 | $565.50 | $835.50 if the Juniper Lane HOA is counted |
| Food Pantry 2025 | $700 | |

## filing.json

`{"id", "file", "convert", "expect_action", "expect_path", "expect_facts", "forbid"}` — as in the
easy set. `expect_action` may be `a|b` when either is right; a skip case's `expect_path` is the
note that already holds the event (or `.*`).

| ID | Drop | Convert | Action | Target | Tests |
| --- | --- | --- | --- | --- | --- |
| f01 | Fairbanks corrected invoice, $412 → $386 | pdf | append | `home/maintenance-log.md` | correction of an existing row; no card, invoice no. or street address |
| f02 | Timberline homeowners renewal | pdf | append | `finance/policies.md` | current insurer's note, not the old `insurance.md`; $1,688, 2027-12-15; no policy number |
| f03 | Cascade Mutual "come back" offer | none | skip | — | junk from the old insurer (README: don't record) |
| f04 | Little Oaks receipt, Greta and Soren, 2026-11-02 | png | new | `health/visits/2026-11-02_(greta\|soren)_….md` | one receipt, two kids; no subscriber ID or card |
| f05 | J.P. session 5 report with full names | docx | new | `ministry/counseling/jp/jp-session-05.md` | initials only (forbid Jared, Pellham, Corinne, Hannah) |
| f06 | Text: Soren lost his tooth | png | skip | `life/journal/2026-10-30.md` | already in the journal |
| f07 | School flyer: retakes 11-19, concert 12-10 | png | append | `life/calendar.md` | both dated events |
| f08 | Becca's wild rice soup | none | new | `life/recipes/…wild-rice….md` | no phone or email |
| f09 | Summit Peak October statement | pdf | append | `finance/statements/2026.md` or `open-items.md` | overdraft fee reversed; no account or routing number |
| f10 | Cascade Orthopedics statement, Leif, $145 due 11-30 | pdf | append | `finance/open-items.md` or Leif's 10-22 visit note | no member ID or account number |
| f11 | Corvell use & care guide + warranty (10 pages) | pdf | append | `home/refrigerator-corvell.md` | warranty terms on the last page (5-yr sealed system, 10-yr compressor); no phone/email |
| f12 | Text thread: Soren rides without training wheels | png | new\|append | `life/journal/2026-11-04.md` | terse SMS → journal entry |
| f13 | Viola rent-to-own buyout, $640 | png | append | `finance/large-purchases.md` | README rule: receipts over $500 get a row there |
| f14 | Juniper Animal Clinic invoice, Pepper | png | append | `life/pets/pepper.md` | README rule: Pepper's vet records go there, not `health/` |
| f15 | Willamette Heart Holter results, Erik Sr. | pdf | new | `health/erik-sr/visits/2026-1x-xx_erik-sr_….md` | the other Erik; no MRN or DOB |
| f16 | Firehole Cabins updated reservation | pdf | append | `life/trips/202706_yellowstone/plan.md` | folder still named for June; no confirmation or card |
| f17 | Harbor 401(k) Q3 2026 statement | pdf | append | `finance/statements/2026.md` | balance $251,380.22, 10%; no account number |
| f18 | Leif's Q1 progress report | docx | append | `life/school/leif.md` | no student ID |
| f19 | Hollis fence warranty certificate | pdf | append | `home/fence-project.md` | 2-yr workmanship, 10-yr posts; no job number |
| f20 | Food Pantry receipt, $250 | none | append | `finance/giving.md` or `data/giving.csv` | no card |
