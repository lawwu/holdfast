# Life — operating manual

## Files

| Path | What it is |
| --- | --- |
| [calendar.md](calendar.md) | Upcoming family commitments (school, church, appointments, hosting), sorted by date |
| [trips/README.md](trips/README.md) | Index of every trip: dates, status, link to its plan |
| `trips/YYYYMM_slug/plan.md` | One plan per trip: logistics, bookings, budget, lessons learned |
| `recipes/` | One note per recipe the family actually makes |

## Where to look

| Question | File |
| --- | --- |
| What's coming up? What's on the calendar this month? | [calendar.md](calendar.md) |
| When is the next trip? What still needs booking? | [trips/README.md](trips/README.md), then the trip's `plan.md` |
| What did we learn last time we traveled? | the past trip's `plan.md`, "Lessons" section |
| How do we make X? | `recipes/` |

## Rules

- **Events with a date go in [calendar.md](calendar.md)** as a row in the right month, sorted by date
  (Date | Time | What | Who | Notes). School and church flyers are summarized there, one row per event.
- **Bookings (flights, cars, lodging) go in that trip's `plan.md`** under Bookings, with the confirmation
  code and times — but never the card used or loyalty numbers. Update the trip's status in
  [trips/README.md](trips/README.md) if it changes.
- A new recipe gets its own note `recipes/<short-name>.md`: source (who gave it), servings,
  ingredients, steps, and family notes.
- Medical appointments are listed on the calendar too, but the visit itself is recorded in `../health/visits/`.
