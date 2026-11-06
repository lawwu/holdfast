# Home — operating manual

1,950 sq ft, built 1998, on Juniper Lane in Alder Creek. Bought 2019. Pepper (the dog)
lives here too; her records are in `life/pets/`.

## Files

| File | What it is |
| --- | --- |
| [maintenance-log.md](maintenance-log.md) | Every repair, service visit and DIY fix, one dated row each |
| [projects.md](projects.md) | Planning scratchpad: ideas, quotes, rough budgets |
| [fence-project.md](fence-project.md) | The back fence, 2026, start to finish |
| [projects-history.md](projects-history.md) | Long history of everything done to the house since 2019 |
| [contractors.md](contractors.md) | Who we call for what |
| [hvac.md](hvac.md) | Furnace and AC |
| [water-heater.md](water-heater.md) | Water heater |
| [dishwasher.md](dishwasher.md) | Dishwasher |
| [refrigerator.md](refrigerator.md) | Refrigerator (Frostline) |
| [refrigerator-corvell.md](refrigerator-corvell.md) | Refrigerator (Corvell) |
| [washer-dryer.md](washer-dryer.md) | Washer and dryer |
| [garage-door.md](garage-door.md) | Garage door, opener, springs |
| [sprinklers.md](sprinklers.md) | Irrigation zones and the fall blowout |
| [chimney.md](chimney.md) | Fireplace and chimney |
| [yard.md](yard.md) | Garden beds, trees, the lawn |

## Where to look

| Question | File |
| --- | --- |
| When was X last fixed / serviced, by whom, for how much? | [maintenance-log.md](maintenance-log.md) |
| What model is the appliance, is it under warranty, what filter? | the appliance's own note |
| Who do we call for X? | [contractors.md](contractors.md) |
| What did a project cost in total? | the project's note, then `../finance/data/transactions.csv` |
| What color is the house / when was it painted? | [projects-history.md](projects-history.md) |

## Rules

- **Every repair or service visit gets a dated row in [maintenance-log.md](maintenance-log.md)**:
  Date | What | Who | Cost | Notes. Keep it sorted by date. Don't add a row twice — check
  for the same date, vendor and cost first. If a vendor sends a corrected invoice, fix the
  row's cost and say so in Notes ("corrected invoice YYYY-MM-DD, was $X").
- A new major appliance gets its own note (brand, model, purchase date and store, price,
  warranty terms and end dates, filters). When an appliance is replaced, write the new
  note; the old note can stay.
- Invoice numbers and card numbers are never recorded.
