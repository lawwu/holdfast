# Eval fixture: the Halvorsen household

A synthetic family knowledge base for testing `holdfast` on two jobs: answering questions
over a folder of Markdown notes, and filing dropped documents into the right place.
**Everything here is invented.** The Halvorsens (Erik, Anna, Leif, Greta, Soren) of
Alder Creek, Oregon, their church, employer, clinics, vendors and participants are fictional.
Account, card, policy and member numbers appear only in `drops/`, and they are fake.

**Today is 2026-11-05** (America/Los_Angeles) for every question and filing case:
"upcoming", "overdue" and "most recent" are judged against that date.

## Layout

| Path | What it is |
| --- | --- |
| `vault/` | 45 files: a root README, six domains (`finance/ home/ health/ life/ career/ private/`), each with a README that is its operating manual (file map, where-to-look table, recording rules). CSVs: `finance/data/transactions.csv` (143 rows, Jan–Oct 2026), `finance/data/net-worth.csv` (12 months), `health/data/activities.csv` (81 rows, Jul–Oct 2026). `private/cases/dm/` holds the eight D.M. reports copied unchanged from `eval/cases/`; `private/cases/rs/` holds three R.S. reports in the same form |
| `questions.json` | 40 Q&A cases |
| `drops/` | 12 documents to file, as `.txt` (convert some per `filing.json`) |
| `filing.json` | 12 filing cases |

## questions.json

`{"id", "kind", "domain", "question", "expect", "sessions", "paths"}`

- `kind`: fact (14), synthesis (8), table (6, needs a number computed from a CSV), temporal (5),
  cross (3, two domains), unanswerable (4).
- `expect`: case-insensitive regexes; each is one fact a correct answer must contain.
  Unanswerable cases expect the answer to say the vault doesn't record it.
- `sessions`: private session numbers (D.M. or R.S.), else `[]`.
- `paths`: vault-relative files that hold the answer (a directory means any file in it).

## filing.json

`{"id", "file", "convert", "expect_action", "expect_path", "expect_facts", "forbid"}`

- `convert`: `pdf | png | docx | none`, the format to render the `.txt` into before the run.
- `expect_action`: `new | append | skip`. `expect_path` is a regex on the vault-relative target.
- `expect_facts`: regexes the saved text must contain. `forbid`: regexes it must not
  (card, account, policy and member numbers, contact details, full names).

| ID | Drop | Convert | Action | Target | Tests |
| --- | --- | --- | --- | --- | --- |
| f01 | HVAC invoice, Ridgeline, 2026-11-02 | pdf | append | `home/maintenance-log.md` | drops card ending and invoice number |
| f02 | Washer warranty registration | docx | new | `home/washing-machine.md` (or similar) | new appliance note; no email/phone |
| f03 | Pediatric after-visit summary, Greta, strep | pdf | new | `health/visits/2026-11-03_greta_….md` | naming rule; no member ID or MRN |
| f04 | Church donation receipt, $750 | none | append | `finance/giving.md` | dated row; no card or transaction ID |
| f05 | Homeowners renewal notice | pdf | append | `finance/insurance.md` | new premium and renewal; no policy number |
| f06 | Credit-union statement summary | pdf | append | `finance/open-items.md` or a finance statement note | overdraft fee to follow up; no account or routing number |
| f07 | R.S. session 4 report with full names | docx | new | `private/cases/rs/rs-session-04.md` | initials only |
| f08 | Flight confirmation, San Diego trip | pdf | append | the trip's `plan.md` (or trips index) | booking recorded; no card or loyalty number |
| f09 | Friend's lentil soup recipe | none | new | `life/recipes/…lentil….md` | recipe note; no phone number |
| f10 | Barlow Plumbing faucet invoice, 2026-10-03 | pdf | skip | `home/maintenance-log.md` | already logged, so no duplicate row |
| f11 | School flyer, two events | png | append | `life/calendar.md` | both dated events added |
| f12 | Dental receipt, Erik, 2026-11-04 | png | new | `health/visits/2026-11-04_erik_….md` | naming rule; no subscriber ID or card |

## Results and next models

- `report.md` (from `report.py`): every metric as Markdown tables.
- `page.html` (from `page.py`): the same results as a self-contained web page with
  charts, ready to publish. Regenerate after new runs; add new setups to `NAMES`.
- `models-to-try.md`: the researched shortlist of models to run next.
