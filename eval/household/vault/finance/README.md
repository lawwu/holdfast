# Finance — operating manual

## Files

| File | What it is |
| --- | --- |
| [profile.md](profile.md) | Household facts: incomes, which institutions hold what, the mortgage |
| [open-items.md](open-items.md) | The master money checklist, with due dates |
| [giving.md](giving.md) | Dated log of every gift (tithe, offerings, other causes) and the annual goal |
| [insurance.md](insurance.md) | Every policy by carrier, premium and renewal date |
| [net-worth.md](net-worth.md) | Narrative on where net worth stands and why it moved |
| `data/transactions.csv` | Card and checking outflows Jan–Oct 2026: `date,description,category,amount` (amounts are positive USD spent) |
| `data/net-worth.csv` | Month-end snapshot: `month,cash,investments,home_equity,debts,net_worth` |

## Where to look

| Question | File |
| --- | --- |
| How much do we earn? Where is the money held? | [profile.md](profile.md) |
| What money tasks are open or overdue? | [open-items.md](open-items.md) |
| How much have we given, and to whom? | [giving.md](giving.md) |
| Who insures the cars, the house, our lives? When do they renew? | [insurance.md](insurance.md) |
| How much did we spend on X in month Y? | `data/transactions.csv` |
| What was net worth in a given month? | `data/net-worth.csv` |

## Rules

- Every gift gets a dated row in [giving.md](giving.md) (Date | Recipient | Amount | Method | Notes).
- Insurance renewals update the policy's row in [insurance.md](insurance.md): new premium and new renewal date.
- Anything we need to do about money (a call to make, a fee to dispute, a form to file) goes in [open-items.md](open-items.md) with a due date.
- Statements are summarized, never copied: institution name, period, balances, anything unusual. **No account, card, routing or policy numbers, ever.**
- Category names in the transactions CSV: Mortgage, Giving, Utilities, Insurance, Groceries, Dining, Gas, Home.
