# Home — operating manual

Our house: 1,950 sq ft, built 1998, on Juniper Lane in Alder Creek. Bought 2019.

## Files

| File | What it is |
| --- | --- |
| [maintenance-log.md](maintenance-log.md) | Every repair, service visit and DIY fix, one dated row each |
| [water-heater.md](water-heater.md) | Water heater: model, install date, warranty, upkeep |
| [hvac.md](hvac.md) | Furnace and air conditioner: ages, filter size, service schedule |
| [dishwasher.md](dishwasher.md) | Dishwasher: model, repairs, quirks |
| [refrigerator.md](refrigerator.md) | Refrigerator: model, water filter, warranty |
| [projects.md](projects.md) | Planned projects and contractor quotes |

## Where to look

| Question | File |
| --- | --- |
| When was X last fixed / serviced, by whom, for how much? | [maintenance-log.md](maintenance-log.md) |
| What model is the appliance, is it under warranty? | the appliance's own note |
| What filter does the furnace take? | [hvac.md](hvac.md) |
| What are we planning to build or replace? Which quote did we pick? | [projects.md](projects.md) |
| What did a repair cost on the card? | also `../finance/data/transactions.csv` (category Home) |

## Rules

- **Every repair or service visit gets a dated row in [maintenance-log.md](maintenance-log.md)**:
  Date | What | Who | Cost | Notes. Keep the table sorted by date. Do not add a row twice —
  check for the same date, vendor and cost first.
- A new major appliance (purchase or warranty registration) gets its own note named after the
  appliance, e.g. `home/washing-machine.md`: brand and model, purchase date and store, price,
  warranty terms and end dates. Serial numbers are fine; **never** card numbers or account logins.
- Invoice and card numbers are not recorded; the vendor, date, work done and total are enough.
