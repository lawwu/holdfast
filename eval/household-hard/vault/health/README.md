# Health — operating manual

Notes here are preparation for the next conversation with a clinician, never a diagnosis.

## Files

| Path | What it is |
| --- | --- |
| [goals.md](goals.md) | Erik's training goal (read the whole note — it has been revised) and Anna's |
| [goals-2025.md](goals-2025.md) | The 2025 half-marathon plan, kept for history |
| [labs.md](labs.md) | Erik's lab history (lipids) |
| [history.md](history.md) | Erik's injuries and conditions over the years |
| `visits/` | One note per clinic, dental or specialist visit for Erik, Anna and the kids |
| `erik-sr/` | Grandpa E. (Erik Sr.): his own README and `visits/` |
| `running/overview.md` | GENERATED training report (see quirks) |
| `data/activities.csv` | Workouts: `date,person,type,distance_mi,minutes,notes` |

## Where to look

| Question | File |
| --- | --- |
| What is Erik's goal? Is he consistent? | [goals.md](goals.md), then `data/activities.csv` |
| When did someone last see a doctor or dentist? | `visits/` (or `erik-sr/visits/` for Grandpa E.) |
| Erik's cholesterol over time? | [labs.md](labs.md) |
| Grandpa E.'s cardiology, knee, medications? | [erik-sr/README.md](erik-sr/README.md) |

## Clinics we use

| Clinic | For |
| --- | --- |
| Ridgeview Family Medicine | Erik and Anna's primary care (Dr. Amira Soltani) |
| Alder Creek Pediatrics | the kids' primary care |
| Ridgecrest Urgent Care | evenings and weekends — not the same as Ridgeview |
| Bright Smile Dental | family dentist — all five of us, cleanings every six months |
| Brightview Orthodontics | Leif's braces (see [[health/visits/2025-08-14_leif_brightview-orthodontics]]) |
| Cascade Orthopedics | sprains, Erik's Achilles, and Grandpa E.'s knee surgeon |

## Rules

- **Each visit gets its own note: `health/visits/YYYY-MM-DD_person_clinic.md`** (lowercase
  first name, clinic as a short slug). Reason, findings, plan, follow-up date, what we paid.
  One note per person: if one appointment covers two kids, write two notes.
- **Grandpa E.'s visits go in `health/erik-sr/visits/YYYY-MM-DD_erik-sr_clinic.md`** — never
  in `visits/`, and never mixed into Erik's own notes or labs. Two Eriks; keep them apart.
- **Never record insurance member IDs, group numbers or card numbers.**
- Pepper's vet visits are not health records; they go in `life/pets/pepper.md`.

## Quirks

- In `activities.csv`, `person` is `Erik`, `Erik Sr.` or — for rows Erik copied from Dad's
  watch — `Grandpa E.` (same person as `Erik Sr.`). Grandpa E. logs walks, bike rides and,
  since August 2026, jog/walk intervals typed as `run`. "Erik's miles" means person = `Erik` only.
- `running/overview.md` was generated 2026-09-01 and covers data through August only.
