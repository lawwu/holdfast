# Health — operating manual

## Files

| File | What it is |
| --- | --- |
| [goals.md](goals.md) | The family's fitness goal (Erik's training goal and what we count) |
| `visits/` | One note per clinic, dental or specialist visit, any family member |
| `data/activities.csv` | Erik's workouts Jul–Oct 2026: `date,type,distance_mi,minutes` (type is run, strength or walk) |

## Where to look

| Question | File |
| --- | --- |
| What is the goal? Am I being consistent? | [goals.md](goals.md), then `data/activities.csv` |
| When did someone last see a doctor or dentist, and what was the plan? | `visits/` |
| How many miles / sessions in a month? | `data/activities.csv` |

## Rules

- **Each clinic visit gets its own note: `health/visits/YYYY-MM-DD_person_clinic.md`**
  (lowercase first name, clinic as a short slug), e.g. `2026-08-21_soren_alder-creek-pediatrics.md`.
  Record the reason, findings, plan, any follow-up date and what we paid.
- **Never record insurance member IDs, group numbers or card numbers.**
- Each person's visits stay their own; don't merge the kids' notes into a parent's.
- Notes are preparation for the next conversation with a clinician, not a diagnosis.

## Visits so far in 2026

| Date | Who | Where | Note |
| --- | --- | --- | --- |
| 2026-03-18 | Greta | Alder Creek Pediatrics | [9-year well-child](visits/2026-03-18_greta_alder-creek-pediatrics.md) |
| 2026-06-04 | Erik | Ridgeview Family Medicine | [annual physical](visits/2026-06-04_erik_ridgeview-family-medicine.md) |
| 2026-08-21 | Soren | Alder Creek Pediatrics | [ear infection](visits/2026-08-21_soren_alder-creek-pediatrics.md) |
| 2026-09-30 | Anna | Bright Smile Dental | [cleaning and exam](visits/2026-09-30_anna_bright-smile-dental.md) |
| 2026-10-22 | Leif | Cascade Orthopedics | [wrist sprain](visits/2026-10-22_leif_cascade-orthopedics.md) |
