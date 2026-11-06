# Life — operating manual

## Files

| Path | What it is |
| --- | --- |
| [calendar.md](calendar.md) | Upcoming family calendar (future only; past rows pruned monthly) |
| [people.md](people.md) | Who's who, including nicknames |
| `journal/YYYY-MM-DD.md` | Short daily entries, written when something happens |
| `trips/` | One folder per trip, `YYYYMM_slug/plan.md`; index in [trips/README.md](trips/README.md) |
| `recipes/` | One note per recipe |
| `books/` | Reading notes |
| `school/` | One note per child plus logistics |
| `small-group/` | Our church small group: who, when, what we're studying, notes per term |
| `pets/pepper.md` | Pepper the dog: vet, vaccines, food, incidents |

## Where to look

| Question | File |
| --- | --- |
| What's coming up? | [calendar.md](calendar.md) |
| When did X happen? | `journal/` (entries use relative dates — "yesterday" means the day before the entry's date) |
| Who is "Grandpa E.", "Mormor", "Uncle Nils"? | [people.md](people.md) |
| Trip dates, bookings, plans | the trip's `plan.md`; dates also in [trips/README.md](trips/README.md) |
| When are Pepper's shots due? | [pets/pepper.md](pets/pepper.md) |

## Rules

- **Journal:** one file per day, `journal/YYYY-MM-DD.md`, a few informal sentences. If the
  day's file exists, append. Don't write the same event twice.
- **Calendar:** future events only, in the month's table, sorted by date.
- **School papers** (report cards, progress reports, teacher notes) go in that child's
  `school/<name>.md`. Flyers with dates go on the calendar.
- **Pepper's vet visits, vaccines, grooming and boarding go in [pets/pepper.md](pets/pepper.md)**,
  never in `health/` and never as a separate file.
- **Recipes:** `recipes/<dish-slug>.md`; ingredients, method, oven temperature and time,
  who it came from (first name only). No phone numbers or emails.
- **Trips:** bookings go in the trip's own `plan.md` under "Bookings" — confirmation numbers
  and card numbers are not recorded.
