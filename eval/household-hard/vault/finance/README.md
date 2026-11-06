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
