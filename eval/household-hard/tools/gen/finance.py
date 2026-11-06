"""Finance domain notes."""
import csv
import os
from collections import defaultdict

from common import VAULT, table, w
from csvs import GIVING, LARGE


def README():
    w("finance/README.md", """
    # Finance — operating manual

    Money is stewardship, not score-keeping. This folder holds the household
    facts, the policies, the giving record and the raw CSVs.

    ## Files

    | File | What it is |
    | --- | --- |
    | [profile.md](profile.md) | Household facts: incomes, institutions, the mortgage. Reviewed once a year (October) |
    | [policies.md](policies.md) | **Current** insurance: every policy by carrier, premium and renewal date |
    | [insurance.md](insurance.md) | The older insurance table, kept for history |
    | [giving.md](giving.md) | Giving goals and notes; the gifts themselves are rows in `data/giving.csv` |
    | [open-items.md](open-items.md) | The master money checklist, with due dates |
    | [large-purchases.md](large-purchases.md) | Every purchase or bill over $500, one dated row each |
    | [vehicles.md](vehicles.md) | The cars: what we drive, loans, maintenance pointers |
    | [net-worth.md](net-worth.md) | Narrative on where net worth stands and why it moved |
    | [annual-review-2025.md](annual-review-2025.md) | The December 2025 year-end review and the decisions for 2026 |
    | [budget-2026.md](budget-2026.md) | Monthly budget targets for 2026 |
    | [529.md](529.md) | The kids' college accounts |
    | [erik-sr-paperwork.md](erik-sr-paperwork.md) | Things Erik handles for his father (Grandpa E.) |
    | `statements/2025.md`, `statements/2026.md` | Statement summaries, one dated section per statement |
    | `taxes/2024.md`, `taxes/2025.md` | Tax-year notes |
    | `spending/overview.md` | GENERATED spending report (see quirks) |
    | `data/transactions.csv` | Card and checking activity Jan 2024 – Oct 2026: `date,description,merchant,category,amount,account,notes` |
    | `data/giving.csv` | Every gift: `date,recipient,amount,method,fund,notes` |
    | `data/net-worth.csv` | Month-end snapshot: `month,cash,brokerage,retirement,college_529,home_equity,debts,net_worth` |

    ## Where to look

    | Question | File |
    | --- | --- |
    | Who insures the house / cars now? Premiums, renewals? | [policies.md](policies.md) (not insurance.md) |
    | How much did we spend on X? | `data/transactions.csv` — read the quirks first |
    | How much have we given this year? | `data/giving.csv`; the goal is in [giving.md](giving.md) or the annual review |
    | What money tasks are open or overdue? | [open-items.md](open-items.md) |
    | What did a big purchase cost? | [large-purchases.md](large-purchases.md) |
    | Net worth in a given month? | `data/net-worth.csv` |
    | What did we decide for 2026 (401(k), giving, emergency fund)? | [annual-review-2025.md](annual-review-2025.md) |

    ## Rules

    - Every gift gets a row in `data/giving.csv`; notes about a gift (why, matching drives) go in [giving.md](giving.md).
    - Insurance renewals update the policy's row in [policies.md](policies.md): new premium and new renewal date.
      Quotes or offers from carriers we have left are not recorded.
    - **Receipts and bills over $500 also get a dated row in [large-purchases.md](large-purchases.md)**,
      unless they are a home appliance (that gets a `home/` note and a maintenance-log row) or a car.
    - Anything we need to do about money goes in [open-items.md](open-items.md) with a due date.
    - Statements are summarized in `statements/<year>.md`, never copied: institution, period,
      balances, anything unusual. **No account, card, routing, policy or member numbers, ever.**

    ## Quirks (learned the hard way)

    - **Amounts:** positive = money out, negative = refund or credit. Net them.
    - **Duplicates:** the bank re-sends some rows. Any row whose `notes` mention "dup" is a
      double import — ignore it. (Rows with the same amount on the same day are not
      automatically duplicates: we often buy the same thing twice.)
    - **Category spellings:** groceries appear as `Groceries`, `groceries` and `Grocery`
      (the phone app and the bank disagree). They are all groceries. The 2024 import used
      `Restaurants` for what is now `Dining`.
    - **Split receipts:** a Lakeside Warehouse receipt is sometimes split into two rows on the
      same date (`split receipt 1/2` groceries, `2/2` Household). Only the grocery half is groceries.
    - **Merchant aliases:** Fresh Basket shows up as `FRESH BASKET #212`, `Fresh Basket Market`
      and `FRESHBASKET ONLINE`; Hardware Hub as `HARDWARE HUB #08`, `Hardware Hub` and
      `HDWR HUB ALDER CRK`; the vet as `JUNIPER ANIMAL CLINIC` and `Juniper Animal Clinic PC`.
      `JUNIPER LANE HOA` is our street's HOA, not the vet. `Fresh Bake Co.` is the bakery
      (Dining), not Fresh Basket.
    - **`spending/overview.md` is stale and naive:** generated 2026-09-01 from data through
      August, it groups by the literal category string and does not drop duplicates. Use the
      CSV for anything "as of today".
    """)


def profile():
    w("finance/profile.md", """
    # Household profile

    Last reviewed 2025-10-12.

    ## People

    - **Erik Halvorsen** (42) — operations manager at Bluestem Logistics; see [[career/notes]].
    - **Anna Halvorsen** (40) — part-time bookkeeper for two small businesses, works from home.
    - Children: Leif (11, 6th grade), Greta (8, 3rd grade), Soren (4, preschool).
    - Erik's parents, **Erik Sr.** ("Grandpa E.") and Ruth, live in Larkspur, 25 minutes away.
      Erik helps with Dad's paperwork; see [erik-sr-paperwork.md](erik-sr-paperwork.md).

    ## Income

    | Source | Gross per year |
    | --- | --- |
    | Erik salary | $140,000 |
    | Anna bookkeeping (1099) | $30,000 |
    | **Household** | **$170,000** |

    ## Where the money is

    - **Summit Peak Credit Union** — checking, savings (emergency fund), a home-projects bucket, and the Visa card.
    - **Evergreen Brokerage** — taxable brokerage, both Roth IRAs, the three 529s, and (since 2025) Anna's rewards card.
    - **Bluestem Logistics 401(k)** at Harbor Retirement Services — Erik contributes 8%.
    - **Columbia Home Lending** — the mortgage.

    ## The house

    Bought in 2019 for $485,000. 30-year fixed at 3.25%, payment **$2,180/month** including escrow.

    ## Cars

    2019 Honda Odyssey (loan) and 2015 Toyota Camry (paid off). See [vehicles](vehicles.md).

    ## Cash targets

    - Emergency fund: 6 months of expenses, **$36,000**, fully funded.
    - Home-projects sinking fund for the back fence: $10,000 by 2026-06-30.
    """)


def insurance_old():
    w("finance/insurance.md", """
    # Insurance

    Last reviewed 2025-06-02. Policies by carrier; no policy numbers here.

    | Coverage | Carrier | Covers | Annual premium | Renews |
    | --- | --- | --- | --- | --- |
    | Auto | Cascade Mutual | 2019 Honda Odyssey, 2015 Toyota Camry; 250/500 liability | $1,860 ($155/month) | 2026-02-01 |
    | Homeowners | Cascade Mutual | Dwelling $520,000, $2,500 deductible | $1,420 | 2025-12-15 |
    | Term life — Erik | Pinewood Life | $1,000,000, 20-year term bought 2021 | $690 | each March |
    | Term life — Anna | Pinewood Life | $500,000, 20-year term bought 2021 | $310 | each March |
    | Health, dental, vision | Northstar Health Plan via Bluestem | whole family | we pay $220/month | plan year = calendar year |

    ## Notes

    - Cascade Mutual has been with us since we bought the house. Agent: the Alder Creek office on Main.
    - No umbrella policy yet; Cascade quoted about $310/yr for $1M.
    """)


def policies():
    w("finance/policies.md", """
    # Policies (current)

    Started 2025-11-22 when we moved home and auto to Timberline Mutual. This is the live
    table; [insurance.md](insurance.md) is the old Cascade-era one.

    | Coverage | Carrier | Covers | Annual premium | Renews |
    | --- | --- | --- | --- | --- |
    | Homeowners | Timberline Mutual | Dwelling $560,000, $2,500 deductible, water backup rider | $1,612 | 2026-12-15 |
    | Auto | Timberline Mutual | 2019 Honda Odyssey, 2022 Subaru Outback (added 2026-04-17); 250/500 liability | $1,740 ($145/month) | 2026-12-15 |
    | Umbrella | Timberline Mutual | $1,000,000 | $285 | 2026-12-15 |
    | Term life — Erik | Pinewood Life | $1,000,000, 20-year term bought 2021 | $690 | each March; term ends 2041 |
    | Term life — Anna | Pinewood Life | $500,000, 20-year term bought 2021 | $310 | each March; term ends 2041 |
    | Health, dental, vision | Northstar Health Plan via Bluestem | whole family | we pay $240/month (2026) | open enrollment 2026-11-03 to 2026-11-20 |

    ## Why we switched

    Cascade Mutual's December 2025 homeowners renewal came in at $1,980 (from $1,420).
    Timberline bundled home, auto and a $1M umbrella for less than Cascade wanted for home
    and auto alone. Effective 2025-12-15 for home and umbrella; auto moved the same day.
    Cascade still mails us "come back" quotes — ignore them.

    ## Next actions

    - The 2026 renewal notice should arrive in November; compare against $1,612.
    - Pinewood: nothing to do until March.
    """)


def giving():
    w("finance/giving.md", """
    # Giving

    The gifts themselves are rows in `data/giving.csv` (date, recipient, amount, method, fund).
    This note holds the goal and the story behind anything unusual.

    ## Goal

    - **2025:** 10% of gross ($17,000), most of it the monthly tithe to Hillcrest Bible Church.
      Met: see the [annual review](annual-review-2025.md).
    - **2026:** set in the December 2025 annual review.

    ## Standing gifts

    | Recipient | What | How |
    | --- | --- | --- |
    | Hillcrest Bible Church | Monthly tithe on the 5th | ACH |
    | Hillcrest Missions Fund | Quarterly, toward the church's partner families | Online |
    | Alder Creek Food Pantry | A few times a year | Card |
    | Harbor House Pregnancy Center | The spring banquet pledge | Check |

    ## Notes on particular gifts

    - 2024-12: first Christmas-outreach gift; the kids packed boxes.
    - 2025-11-22: the Food Pantry gift was larger than usual — see the journal entry that week.
    - 2026-04-12: Youth camp scholarships, because Leif's friend couldn't afford camp.
    """)


def open_items():
    w("finance/open-items.md", """
    # Open items — money

    Sorted by due date. Done items move to the bottom with the date closed.

    | Due | Item | Owner | Status |
    | --- | --- | --- | --- |
    | 2026-10-31 | Dispute the $35 overdraft fee from August with Summit Peak | Anna | open — called once, waiting on a callback |
    | 2026-11-01 | Mail Grandpa E.'s senior property-tax deferral renewal to the county | Erik | open — form filled, not mailed |
    | 2026-11-15 | Decide 401(k) investment mix change at Harbor | Erik | open |
    | 2026-11-20 | Pick 2027 Northstar plan in open enrollment | Erik + Anna | open |
    | 2026-11-30 | Compare Timberline renewal against last year's $1,612 | Anna | waiting for the notice |
    | 2026-12-31 | Fund the 2026 529 contributions ($2,500 each) | Erik | open — Leif's done, Greta and Soren not |
    | 2027-02-28 | Refill the home-projects bucket to $5,000 after the fence | Anna | open |

    ## Done

    | Closed | Item |
    | --- | --- |
    | 2026-09-30 | Paid Hollis Fence final invoice |
    | 2026-04-20 | Moved the Outback onto the Timberline auto policy |
    | 2026-03-28 | Read the Columbia escrow analysis: payment goes to $2,264 from the April payment (taxes up) |
    | 2025-12-10 | Switched home + auto to Timberline; cancelled Cascade |
    | 2025-06-14 | Decided not to refinance |
    """)


def large():
    rows = [(d_, item, vend, f"${amt:,.2f}") for d_, item, vend, amt in LARGE]
    w("finance/large-purchases.md", f"""
    # Large purchases

    Every purchase or bill over $500, one dated row. Home appliances also get a note in
    `home/`; this list is for seeing the big money in one place.

{table(["Date", "What", "Vendor", "Amount"], rows)}

    Notes:
    - The braces are paid over time; the row is the full contract. Payments are in the CSV as `BRIGHTVIEW ORTHO`.
    - The Outback: $21,200 from savings plus the $6,200 we got for the Camry.
    - Grandpa E.'s hospital payment was a gift to Dad, not our bill.
    - Fridge details: [[home/refrigerator]]. Fence details: [[home/fence-project]].
    """.replace("\n    ", "\n"), dedent=False)


def vehicles():
    w("finance/vehicles.md", """
    # Vehicles

    Last updated 2025-10-20.

    | Car | Year | Bought | Loan | Who drives it | Notes |
    | --- | --- | --- | --- | --- | --- |
    | Honda Odyssey | 2019 | 2021, used | Summit Peak auto loan, about $12,800 left, ends mid-2027 | Anna, family trips | 71,000 mi; tires replaced 2025-04 |
    | Toyota Camry | 2015 | 2016, used | paid off | Erik's commute | 148,000 mi; needs struts soon |

    ## Plan

    The Camry is near the end. Plan is to replace it with something AWD in 2026, cash,
    budget about $28,000, and sell the Camry privately rather than trade it in.

    Oil changes: every 5,000 miles at Alder Lube & Tire; receipts aren't kept here.
    """)


def net_worth():
    w("finance/net-worth.md", """
    # Net worth — narrative

    The numbers are in `data/net-worth.csv` (month-end). This note explains the moves.

    - **2024:** steady climb; July dipped on the cash side because of the exterior repaint ($7,350, cash).
    - **2025:** markets up most of the year; cash rebuilt after the repaint. We ended the year
      well ahead of where the 2024 review expected.
    - **2026-04:** cash down about $21,000 — the Outback, bought with cash. Car loan on the
      Odyssey keeps shrinking.
    - **2026-08/09:** cash down again for the fence (Hollis), paid from the home-projects bucket.
    - Home equity is our estimate, not an appraisal: purchase price plus a conservative
      2%/yr, minus the mortgage balance.

    The "debts" column is the Odyssey loan only; the mortgage is netted inside home equity.
    """)


def budget():
    w("finance/budget-2026.md", """
    # Budget 2026

    Monthly targets agreed in the [annual review](annual-review-2025.md). Spending is
    checked against `data/transactions.csv` at the start of each month.

    | Category | Target / month | Notes |
    | --- | --- | --- |
    | Groceries (all spellings, grocery half of Lakeside splits) | $1,450 | was $1,350 in 2025 |
    | Dining | $300 | includes Fresh Bake Co. |
    | Gas | $220 | |
    | Utilities | $520 | electric, gas, water/sewer, internet, phones |
    | Kids | $160 | piano, orchestra, sports fees |
    | Household | $150 | the non-grocery half of Lakeside |
    | Shopping | $250 | |
    | Pets | $75 | food; vet visits are extra |

    Giving and the mortgage are not "budgeted" — they come off the top.
    """)


def five29():
    w("finance/529.md", """
    # 529 college accounts

    One Evergreen Brokerage 529 per child, Oregon plan. Contribution: $2,500 per child per
    year, usually in December (the Oregon tax credit). Grandpa E. and Grandma Ruth add $500
    each birthday.

    | Child | Opened | Balance (2026-09-30 statement) |
    | --- | --- | --- |
    | Leif | 2014 | about $31,000 |
    | Greta | 2017 | about $19,500 |
    | Soren | 2021 | about $11,800 |

    The total is the `college_529` column of `data/net-worth.csv`.
    """)


def erik_sr():
    w("finance/erik-sr-paperwork.md", """
    # Grandpa E.'s paperwork

    Erik is on Dad's (Erik Sr.'s) accounts as a helper since the knee surgery in 2025.
    Dad and Mom (Ruth) keep their own money; this is only the paperwork Erik handles.

    - **Senior property-tax deferral** (Larkspur County): renewal due every **2026-11-01**-ish;
      the form goes by mail. See [open items](open-items.md).
    - **Medicare supplement:** Dad's plan is through Ridgeway Senior Health; renewal each January.
      Erik keeps the paper card copy in the file box, not here.
    - **The 2025 knee surgery bills:** Mercy Valley Hospital billed Dad; we paid $1,250 of his
      deductible as a gift in April 2025 (see [large purchases](large-purchases.md)).
    - Dad's cardiology appointments are in `health/erik-sr/`.
    """)


def statements():
    w("finance/statements/2025.md", """
    # Statement summaries — 2025

    ## Summit Peak CU — checking, 2025-06
    Period 2025-06-01 to 2025-06-30. Ending balance about $9,800. Nothing unusual.

    ## Harbor Retirement — Erik 401(k), Q3 2025
    Ending balance about $214,000. Contribution 8% plus 4% match.

    ## Summit Peak CU — checking, 2025-11
    Ending balance about $11,200. Cascade Mutual auto draft for November was the last one.

    ## Evergreen Brokerage — year-end 2025
    Taxable about $201,000; Roths about $94,000 combined. 1099 expected mid-February.
    """)
    w("finance/statements/2026.md", """
    # Statement summaries — 2026

    ## Columbia Home Lending — escrow analysis, 2026-03
    Property taxes went up; escrow shortage spread over 12 months. **New payment $2,264
    starting with the April 2026 payment** (was $2,180).

    ## Summit Peak CU — checking, 2026-06
    Ending balance about $10,400. Hollis Fence deposit ($2,000) cleared.

    ## Harbor Retirement — Erik 401(k), Q2 2026
    Ending balance about $236,000. Contribution 10% plus 4% match (the January change).

    ## Summit Peak CU — checking, 2026-08
    Ending balance about $6,900. **$35 overdraft fee on 2026-08-18** — a transfer from savings
    posted a day late. Disputing; see [open items](../open-items.md).

    ## Summit Peak CU — checking, 2026-09
    Ending balance about $8,600. Final Hollis payment cleared 09-02.
    """)


def taxes():
    w("finance/taxes/2024.md", """
    # Taxes — 2024

    Filed 2025-03-30 by Anna (she does ours along with her clients'). Federal refund $1,140;
    Oregon owed $310. Anna's 1099 income $28,400. Charitable gifts itemized? No — standard
    deduction was higher. Kept: the PDF in the household drive, not here.
    """)
    w("finance/taxes/2025.md", """
    # Taxes — 2025

    Filed 2026-04-04. Federal refund $860; Oregon refund $95. Anna's 1099 income $31,200.
    The Oregon 529 credit claimed for all three kids. Estimated payments for Anna's
    bookkeeping were short in Q3 2025 by about $400 — small penalty. For 2026 she pays
    $1,900 per quarter.
    """)


def spending_overview():
    """GENERATED report: naive (literal categories, duplicates included), through 2026-08."""
    path = os.path.join(VAULT, "finance/data/transactions.csv")
    rows = list(csv.DictReader(open(path, encoding="utf-8")))
    by = defaultdict(float)
    by25 = defaultdict(float)
    monthly = defaultdict(lambda: defaultdict(float))
    for t in rows:
        a = float(t["amount"])
        if "2026-01" <= t["date"][:7] <= "2026-08":
            by[t["category"]] += a
            monthly[t["date"][:7]][t["category"]] += a
        if t["date"].startswith("2025"):
            by25[t["category"]] += a
    cats = sorted(by, key=lambda c: -by[c])
    t1 = table(["Category", "2026 Jan–Aug"], [(c, f"${by[c]:,.2f}") for c in cats])
    t2 = table(["Category", "2025 total"], [(c, f"${by25[c]:,.2f}") for c in sorted(by25, key=lambda c: -by25[c])])
    mcats = ["Groceries", "Dining", "Gas", "Utilities", "Home"]
    t3 = table(["Month"] + mcats, [[m] + [f"${monthly[m][c]:,.0f}" for c in mcats] for m in sorted(monthly)])
    w("finance/spending/overview.md", f"""> GENERATED by tools/spending_report.py on 2026-09-01 — do not edit.

# Spending overview

Source: `finance/data/transactions.csv`, rows through 2026-08-31.

## 2026 year to date (Jan–Aug)

{t1}

## 2025 by category

{t2}

## 2026 by month

{t3}
""", dedent=False)


def annual_review():
    filler_months = {
        "January": "January was the usual reset month. The holiday spending settled and the PUD bill was the highest of the year (the cold snap the week of the 13th). Erik's half-marathon training started in earnest, which mostly showed up as new shoes. We kept groceries close to budget by doing the Lakeside run every other week rather than weekly. The furnace service with Ridgeline was routine at $149.",
        "February": "February was quiet. Anna's bookkeeping clients both paid late, which taught us again why the checking buffer matters. Pinewood sent the term-life renewals early. We talked about whether to keep the Camry another year; the answer was yes, one more year, but start saving.",
        "March": "March was dominated by Grandpa E.'s knee replacement on the 11th. Erik took two days off; Anna covered the school runs and Soren's preschool pickups. Money-wise it was small for us, but it reset our sense of what we want to keep in reserve for Erik's parents. The gutter cleaning slipped to the 22nd. Pepper's annual vet visit was the 20th.",
        "April": "In April we sent Dad $1,250 toward his deductible at Mercy Valley. It was the right thing to do and we budgeted for it by skipping the spring weekend away. Taxes were filed on the 30th of March and the refund ($1,140) went straight into the emergency fund. Kids' soccer fees landed.",
        "May": "May: the bathroom fan went (DIY, under $100). Harbor House banquet pledge. Erik's long runs got to 10 miles. Groceries crept up as the kids ate more — Leif especially.",
        "June": "June: we decided not to refinance — the rate on offer was not better than our 3.25% and closing costs would have taken years to earn back. The AC tune-up with Ridgeline was $129. The Food Pantry summer gift. A small dip in brokerage that recovered by August.",
        "July": "July was the cheapest month of the year: no trip, lots of park days. Anna's insurance review in June had flagged the Cascade homeowners trend, so we started watching for the December renewal.",
        "August": "August: Leif's braces went on (Brightview Orthodontics, the contract is $5,400 over 24 months). We replaced six deck boards ourselves with Leif, which was one of the better Saturdays of the year. School supplies, the back-to-school shoes, all of it.",
        "September": "September: the garage door opener died and Summit Overhead replaced it ($545). Leif started orchestra (viola, not violin — he was firm about it). Greta's piano lessons went up to $140 a month.",
        "October": "October: Erik ran the Alder Creek Half on the 12th in 1:52:40. It was a good day, but it also showed him how much of the training year had been about a number. More on that in the health notes. The sprinkler blowout, the first PUD heating bill.",
        "November": "November: Cascade's renewal arrived at $1,980 for the house. Anna got Timberline quotes the same week, and on the 22nd we signed with Timberline for home, auto and an umbrella. The Food Pantry matching drive (our $500 doubled). Smoke detectors replaced (DIY, 10-year sealed units).",
        "December": "December: Anna's new laptop for the bookkeeping ($1,240, a business expense on her Schedule C). Christmas outreach gift. The 529 contributions for all three kids went in on the 18th. This review, written over two evenings after the kids were in bed.",
    }
    month_text = "\n\n".join(f"### {m}\n\n{t}" for m, t in filler_months.items())
    body = f"""# Annual review — 2025

Written 2025-12-27 and 2025-12-28 by Erik and Anna. This is the long version; the
decisions at the end are the part that matters for 2026, and they are copied nowhere
else, so do not delete this note.

## Why we do this

Every December we sit down with the year's numbers and ask two questions: did the
money serve what we say we care about, and what do we want to change? We try to keep
the first question first. Money is a tool for loving God and neighbor; it is not the
scoreboard. When the review turns into a scoreboard, we stop and pray and start again.

## The year in one paragraph

2025 was a full year. Grandpa E.'s knee replacement in March, Leif's braces in
August, Erik's half marathon in October, and the insurance switch in November were the
four big events. Income was steady: Erik's salary did not change, and Anna's
bookkeeping grew a little (from two clients to two clients plus seasonal work for a
third). We gave about 11%, a little over our 10% goal. Net worth rose about 7%, mostly markets.
We did not take a vacation, and that was fine.

## Month by month

{month_text}

## Spending by category (rounded, from the CSV)

We pulled these from `data/transactions.csv` with the categories merged by hand
(Groceries, groceries and Grocery together; the grocery half of Lakeside splits; duplicates
removed). The generated spending overview does not merge them, which is why its 2025
grocery number looks low.

| Category | 2025 (approx.) | Comment |
| --- | --- | --- |
| Mortgage | $26,160 | $2,180 × 12 |
| Giving | about $18,750 | see below |
| Groceries | about $17,400 | up from 2024; three growing kids |
| Utilities | about $6,050 | the cold January |
| Dining | about $3,900 | more than we thought; Fresh Bake Co. adds up |
| Insurance | about $4,700 | incl. Pinewood and the Timberline switch in December |
| Medical | about $2,800 | incl. Dad's hospital gift and the braces |

## Giving

Our 2025 goal was 10% of gross, $17,000. Including the monthly tithe, the quarterly
missions gifts, the Food Pantry (summer and the November matching drive), Harbor House
and the Christmas outreach, we gave about $18,750. We want giving to be the first line
in the budget, not what is left over.

## Insurance

Moved home, auto and a new $1M umbrella to Timberline Mutual on 2025-11-22, effective
2025-12-15. Cascade had been raising the homeowners premium for three years. The
umbrella was overdue: with a teenager driving in four years and a trampoline in the
yard, we should have had it already.

## Cars

The Camry has about 150,000 miles and needs struts. Plan: replace it in spring 2026 with
a used AWD car, cash, around $28,000, and sell the Camry privately. Start watching
listings in February.

## The house

Projects for 2026, in order: the back fence (the old one is leaning and Pepper has
gotten out twice), then the water heater (it's 13 years old), then — maybe — the
kitchen counters. The fence fund target is $10,000 by June.

## Net worth

From `data/net-worth.csv`: we ended 2025 around $912,000, up from about $853,000 at the
end of 2024. Almost all of the change was markets and the 401(k) contributions; cash
ended the year about where it started because the repaint the year before had already
been rebuilt. Home equity is our own conservative estimate. The only debt besides the
mortgage is the Odyssey loan, which will be gone by mid-2027. We noticed that the number
went up and that it did not make us happier or more generous by itself; that is worth
remembering when it goes down.

## Health costs

Northstar through Bluestem kept our share at $220 a month for the family. Out of pocket
this year: urgent care for Anna's sinus infection in July, Leif's dental sealants, the
braces down payment and monthly payments, and small copays. Erik's annual physical
showed LDL a little high (148); the doctor wants diet first. Nothing that changed the
budget. Open enrollment for 2026 kept the same plan; the premium share goes to $240.

## Pepper

Pepper's annual visit at Juniper Animal Clinic in March ($198), food every month from
Paws & Co, and a new crate after the old one cracked. She has gotten out through the back
fence twice; the fence project is partly for her.

## Investments

We do not trade. The brokerage is three broad index funds in the same proportions as
last year (US total market, international, a bond fund), rebalanced once in June when
the bond slice drifted under its target. The Roth IRAs were funded in February for both
of us. The 401(k) at Harbor is in the 2045 target-date fund, which Erik keeps meaning to
look at more closely; it is fine. We wrote down, again, that we are not going to check
balances weekly. Anna checked them weekly anyway in April when the market dipped; we
laughed about it in December.

What we want the investments for, in order: that we are not a burden to the kids or the
church when we are old; that we can help Erik's parents and Anna's mother if they need
it; that the kids can go to college without debt if they go; and that we can give more
generously later in life. Retiring early is not on the list. We talked about whether
the 401(k) contribution should go up now that the car loan is shrinking, and agreed to
decide at the end of this review rather than in the middle of it.

## Erik's work

Bluestem had a reorganization in May. Erik's team grew from 14 to 19 people and his
hours went up for about two months, then settled. No raise this year beyond the 3%
cost-of-living adjustment, which is already in the $140,000. There were rumors in the
fall about a regional role in Salem; nothing concrete. If it comes, the question is
the family and the church, not the money. We wrote that down so we remember it.

## Anna's bookkeeping

Two steady clients (a landscaping company and a dental lab) and seasonal work for a
third (a tax preparer, January to April). Gross 1099 income about $31,200. She moved to
quarterly estimated payments properly this year after being short in Q3. The new laptop
in December was overdue; the old one took four minutes to open a spreadsheet. She wants
to stay at about 15 hours a week while Soren is in kindergarten next year, and not grow
past it.

## The kids

Leif (11): braces, orchestra, a growth spurt, and a good year at school. He started
mowing for two neighbors and saved most of it. We opened a youth savings account for him
at Summit Peak. Greta (8): piano, a best friend down the street, and a hard spring with
a teacher who was out on leave; better in the fall. Soren (4): preschool three mornings
a week, learning to read, and the pediatric dentist switch in May after the meltdown at
Bright Smile. The 529s each got $2,500 in December.

## Erik's parents

Dad's knee replacement in March went well. He was walking the neighborhood by May and
riding the stationary bike by September. Mom (Ruth) carried a lot during the recovery.
We set aside, informally, about $3,000 a year we would be glad to spend on them without
asking each other first. We spent $1,250 of it in April.

## Church and ministry

Erik started the biblical-counseling training at Hillcrest in the fall of 2025 (the
observation hours). It costs nothing but time: Thursday evenings and some Saturdays.
Anna leads the 2nd-grade Sunday school class once a month. Our small group moved from
Wednesday to Sunday evenings in September so more of the young families could come.

## Things we argued about (kindly)

Whether to keep the streaming service (yes, but only one). Whether Erik's race entry fees
count as "health" (they count as "Erik"). Whether to replace the Odyssey early (no).
Whether to give more to the church or to the Food Pantry (both; they are not rivals).

## What we are thankful for

Grandpa E. walking again. Leif's maturity this year. Greta's piano. Soren learning to
read. Anna's clients who pay on time. A church family that brought meals in March. A
house that is warm.

## Decisions for 2026

These are the decisions we made at the end of the review. They supersede anything
older in [profile.md](profile.md) or [giving.md](giving.md).

1. **401(k): Erik raises his contribution from 8% to 10% starting with the first
   paycheck of January 2026.** The match stays 4%. Revisit at the 2026 review.
2. **Giving goal for 2026: 12% of gross, which is $20,400.** The tithe goes to $1,400 a
   month; missions stays $300 a quarter; the rest is for needs as they come.
3. **Emergency fund target goes from $36,000 to $40,000** because expenses rose.
   Fund the difference by June from Anna's Q1 income.
4. **Groceries budget goes to $1,450/month** from $1,350.
5. **The Camry gets replaced in spring**, cash, with the car fund plus the Camry sale.
6. **One date night a month**, budgeted at $80, non-negotiable.
7. Review again on the last weekend of December 2026.
"""
    w("finance/annual-review-2025.md", body, dedent=False)


def main():
    README(); profile(); insurance_old(); policies(); giving(); open_items(); large()
    vehicles(); net_worth(); budget(); five29(); erik_sr(); statements(); taxes()
    spending_overview(); annual_review()


if __name__ == "__main__":
    main()
