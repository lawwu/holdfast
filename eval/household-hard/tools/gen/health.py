"""Health domain notes."""
import csv
import datetime as dt
import os
from collections import defaultdict

from common import VAULT, table, w


def README():
    w("health/README.md", """
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
    """)


def goals():
    w("health/goals.md", """
    # Fitness goals

    ## Erik

    **3 runs and 2 strength sessions every week. That's the whole goal.**

    Set in January 2026 after the 2025 half-marathon year, when chasing a time had become
    more about pride than health ([the 2025 plan](goals-2025.md)). The goal is consistency,
    not performance: no race calendar, no pace targets, no mileage ramps. A week counts as
    "met" with at least 3 runs and 2 strength sessions (Monday–Sunday weeks). Sunday family
    walks are welcome but don't count.

    - Runs: two easy weekday runs (3–4.5 mi) and a longer Saturday run (5.5–7.5 mi).
    - Strength: Monday and Friday, 35–45 minutes, at home.
    - Missed weeks happen. Don't make up for them by doubling the next week.

    ## Anna

    A walk most days and a Saturday hike with the kids when the weather allows. Since
    September 2026 she joined the Tuesday-morning women's walking group from church.

    ## Kids

    No goals — they play. Leif has soccer in the fall; Greta swims in the summer.

    ## Revision — 2026-09-09 (Erik)

    After the Achilles strain on 2026-08-10 and the follow-up with Dr. Ostrowski on
    2026-09-09 (see [visit](visits/2026-09-09_erik_cascade-orthopedics.md)), the goal until
    the end of January 2027 is:

    - **2 runs a week, 30 minutes or less, flat, easy** (Tuesday and Saturday), starting the week of 2026-09-14;
    - **2 strength sessions** (Monday and Friday, now including the calf-raise program);
    - **1 swim** (Thursday, Cascade Aquatic Center).

    A week counts as "met" with 2 runs + 2 strength + 1 swim. Revisit at the end of January
    with Dr. Ostrowski before going back to 3 runs.
    """)
    w("health/goals-2025.md", """
    # Training plan — 2025

    Goal: run the **Alder Creek Half Marathon on 2025-10-12 under 1:50**.

    - 4 runs a week, building from 18 to 28 miles a week by September.
    - Long run on Saturdays, up to 12 miles.
    - Strength once a week (Friday).
    - Taper the last two weeks.

    Result: 1:52:40. See the journal for how that day went and why the goal changed for 2026.
    """)


def labs():
    w("health/labs.md", """
    # Labs — Erik

    Erik only. Grandpa E.'s labs are in [erik-sr/README.md](erik-sr/README.md).

    | Date | Where | Total chol. | LDL | HDL | Triglycerides | A1c | Notes |
    | --- | --- | --- | --- | --- | --- | --- | --- |
    | 2024-05-14 | Ridgeview Family Medicine | 228 | 151 | 48 | 145 | 5.4 | first time LDL flagged |
    | 2025-06-10 | Ridgeview Family Medicine | 224 | 148 | 51 | 125 | 5.4 | diet first |
    | 2026-06-04 | Ridgeview Family Medicine | 218 | 142 | 52 | 120 | 5.5 | recheck fasting in 6 months |

    Next: **fasting lipid panel 2026-12-08**, Ridgeview. If LDL is still over 130, Dr. Soltani
    will talk about a statin. Family history matters here: Grandpa E. is on one.
    """)


def history():
    w("health/history.md", """
    # Erik — health history

    - 2009: broken right wrist (bike). Healed fine.
    - 2017: plantar fasciitis, left foot, during a marathon build. Resolved with rest and new shoes.
    - 2024-05: LDL flagged high for the first time. See [labs](labs.md).
    - 2025-10: Alder Creek Half Marathon, 1:52:40. Sore left Achilles for a week after.
    - **2026-08-10: left Achilles strain** on a Monday run; stopped at 2 miles. Cascade
      Orthopedics 2026-08-12 (Dr. Lena Ostrowski): mid-portion Achilles tendinopathy, no tear.
      Plan: no running for four weeks, heel lifts, eccentric calf raises daily, six PT
      sessions at Alder Creek Physical Therapy, swim and bike are fine. Follow-up 2026-09-09:
      cleared for easy runs of 30 minutes or less, twice a week, through January.
    """)


VISITS = [
    ("2024-03-20", "greta", "alder-creek-pediatrics", "Alder Creek Pediatrics", "7-year well-child check",
     "Growth on her curve (50th percentile height). Vision 20/20. Flu shot given.", "Next well-child at 8.", "$0"),
    ("2024-05-14", "erik", "ridgeview-family-medicine", "Ridgeview Family Medicine", "Annual physical (Dr. Soltani)",
     "BP 126/80. LDL 151 — first time flagged. Weight 184 lb.", "Diet changes; recheck lipids in a year.", "$0"),
    ("2024-10-03", "soren", "alder-creek-pediatrics", "Alder Creek Pediatrics", "Barky cough at night",
     "Croup, mild. Oxygen normal.", "One dose of dexamethasone in clinic; cool night air; return if stridor at rest.", "$25 copay"),
    ("2024-11-12", "anna", "bright-smile-dental", "Bright Smile Dental", "Cleaning and exam",
     "No cavities. Slight gum recession lower front.", "Soft brush; next cleaning in six months.", "$0"),
    ("2025-02-19", "leif", "bright-smile-dental", "Bright Smile Dental", "Cleaning, sealants on molars",
     "No cavities. Crowding upper front — referral to an orthodontist.", "Ortho consult (we chose Brightview Orthodontics).", "$45"),
    ("2025-04-10", "soren", "bright-smile-dental", "Bright Smile Dental", "Cleaning",
     "Soren panicked in the chair and the cleaning was cut short. Dr. Haber suggested a pediatric dentist.",
     "Moving all three kids to Little Oaks Pediatric Dentistry. Adults stay at Bright Smile.", "$0"),
    ("2025-06-10", "erik", "ridgeview-family-medicine", "Ridgeview Family Medicine", "Annual physical (Dr. Soltani)",
     "BP 124/78. LDL 148.", "Diet; recheck in a year.", "$0"),
    ("2025-07-22", "anna", "ridgecrest-urgent-care", "Ridgecrest Urgent Care", "Sinus pain, 10 days, fever",
     "Bacterial sinusitis.", "Amoxicillin-clavulanate 10 days. Follow up with Ridgeview if not better in a week (it was).", "$75 copay"),
    ("2025-08-14", "leif", "brightview-orthodontics", "Brightview Orthodontics", "Braces on (upper and lower)",
     "Dr. Patel placed full braces. Expected 22–24 months.", "Adjustments every 6–8 weeks. Contract $5,400: $600 down, $200/month for 24 months.", "$600 down payment"),
    ("2025-10-08", "greta", "little-oaks-pediatric-dentistry", "Little Oaks Pediatric Dentistry", "First visit, cleaning",
     "No cavities. Great with Dr. Ruiz.", "Six-month recall.", "$0"),
    ("2025-10-08", "soren", "little-oaks-pediatric-dentistry", "Little Oaks Pediatric Dentistry", "First visit, cleaning (the 'happy visit')",
     "Sat in the chair the whole time. One small cavity watch, lower left molar.", "Six-month recall; fluoride varnish.", "$0"),
    ("2025-10-15", "leif", "little-oaks-pediatric-dentistry", "Little Oaks Pediatric Dentistry", "Cleaning with braces",
     "Plaque around brackets.", "Water flosser; six-month recall.", "$0"),
    ("2026-02-27", "soren", "ridgecrest-urgent-care", "Ridgecrest Urgent Care", "Cut chin (fell off the couch arm onto the coffee table)",
     "1.5 cm laceration under the chin.", "Three stitches; out in 5 days at Alder Creek Pediatrics or home. Tetanus up to date.", "$75 copay"),
    ("2026-03-18", "greta", "alder-creek-pediatrics", "Alder Creek Pediatrics", "9-year well-child",
     "Growth on curve. Vision 20/25 right eye — recheck next year.", "Next well-child March 2027.", "$0"),
    ("2026-04-21", "greta", "little-oaks-pediatric-dentistry", "Little Oaks Pediatric Dentistry", "Cleaning; one filling",
     "Small cavity, upper right molar, filled same day (white filling).", "Six-month recall in October/November.", "$68"),
    ("2026-04-21", "soren", "little-oaks-pediatric-dentistry", "Little Oaks Pediatric Dentistry", "Cleaning",
     "The watched spot is unchanged.", "Six-month recall.", "$0"),
    ("2026-05-19", "erik", "bright-smile-dental", "Bright Smile Dental", "Cleaning and exam",
     "No cavities. Old filling lower left fine.", "Next cleaning November 2026.", "$0"),
    ("2026-06-04", "erik", "ridgeview-family-medicine", "Ridgeview Family Medicine", "Annual physical (Dr. Soltani)",
     "BP 124/78. LDL 142, HDL 52. Weight 181 lb.", "Recheck fasting lipids in six months (scheduled 2026-12-08).", "$0"),
    ("2026-08-12", "erik", "cascade-orthopedics", "Cascade Orthopedics", "Left Achilles pain since a run on 2026-08-10 (Dr. Lena Ostrowski, sports medicine)",
     "Mid-portion Achilles tendinopathy; no tear on ultrasound.", "No running for 4 weeks. Heel lifts, eccentric calf raises daily, 6 PT sessions at Alder Creek Physical Therapy. Swimming and cycling fine. Follow-up 2026-09-09.", "$50 copay"),
    ("2026-08-21", "soren", "alder-creek-pediatrics", "Alder Creek Pediatrics", "Ear pain and fever",
     "Right ear infection.", "Amoxicillin 10 days. Recheck only if not better in 3 days.", "$25 copay"),
    ("2026-09-09", "erik", "cascade-orthopedics", "Cascade Orthopedics", "Achilles follow-up (Dr. Ostrowski)",
     "Pain-free walking and hopping; tender only with deep pressure.", "Cleared for easy runs of 30 minutes or less, twice a week, flat, through January. Keep calf raises. Swim once a week. Recheck end of January 2027.", "$0"),
    ("2026-09-30", "anna", "bright-smile-dental", "Bright Smile Dental", "Cleaning and exam",
     "One small cavity, lower right.", "Filling scheduled 2026-11-12.", "$0"),
    ("2026-10-22", "leif", "cascade-orthopedics", "Cascade Orthopedics", "Right wrist, fell at soccer",
     "Wrist sprain; X-ray negative for fracture.", "Brace 2 weeks, no soccer until cleared. Follow-up 2026-11-10.", "$50 copay"),
]

SR_VISITS = [
    ("2025-01-28", "cascade-orthopedics", "Cascade Orthopedics", "Pre-op visit for right knee replacement (Dr. Teodor Brandt)",
     "Severe right knee osteoarthritis. Surgery set for 2025-03-11 at Mercy Valley Hospital.", "Pre-op labs; prehab exercises; arrange a ride (Erik)."),
    ("2025-03-11", "mercy-valley-hospital", "Mercy Valley Hospital", "Right total knee replacement (Dr. Brandt)",
     "Surgery uneventful. Home on 2025-03-13.", "Walker two weeks, then cane. Home PT. Post-op visit in 6 weeks."),
    ("2025-04-22", "cascade-orthopedics", "Cascade Orthopedics", "6-week post-op (Dr. Brandt)",
     "Flexion 110°, walking with a cane in the house only.", "Outpatient PT through June; walk daily; stationary bike from September."),
    ("2025-11-06", "willamette-heart-associates", "Willamette Heart Associates", "Cardiology — new patient (Dr. Farah Nadeem)",
     "Referred for a borderline stress test. LDL 104. BP 138/84.", "Start atorvastatin 20 mg. Low-sodium diet. Recheck in 5 months."),
    ("2026-04-14", "willamette-heart-associates", "Willamette Heart Associates", "Cardiology follow-up (Dr. Nadeem)",
     "LDL 98. BP 134/82.", "Increase atorvastatin to 40 mg. Recheck in 6 months (booked 2026-10-06)."),
    ("2026-10-20", "willamette-heart-associates", "Willamette Heart Associates", "Cardiology follow-up (Dr. Nadeem) — moved from 2026-10-06",
     "LDL 91. BP 132/80. Echo unchanged. Feels well; walking 3–4 times a week and doing jog/walk intervals.", "Continue atorvastatin 40 mg. Next visit April 2027."),
]


def visits():
    for d, who, slug, clinic, reason, findings, plan, paid in VISITS:
        name = {"erik": "Erik", "anna": "Anna", "leif": "Leif", "greta": "Greta", "soren": "Soren"}[who]
        w(f"health/visits/{d}_{who}_{slug}.md", f"""
        # {d} — {name} — {clinic}

        **Reason:** {reason}

        **Findings:** {findings}

        **Plan:** {plan}

        **Paid:** {paid}
        """)
    for d, slug, clinic, reason, findings, plan in SR_VISITS:
        w(f"health/erik-sr/visits/{d}_erik-sr_{slug}.md", f"""
        # {d} — Erik Sr. (Grandpa E.) — {clinic}

        **Reason:** {reason}

        **Findings:** {findings}

        **Plan:** {plan}

        Erik went with him and took these notes.
        """)
    w("health/erik-sr/README.md", """
    # Grandpa E. — Erik Halvorsen Sr.

    Erik's father, born 1954, lives in Larkspur with Ruth (Grandma Ruth). Erik goes to the
    important appointments with him and keeps these notes with his permission. Not to be
    confused with Erik's own notes in `../visits/` and `../labs.md`.

    ## Doctors

    | Who | Where | For |
    | --- | --- | --- |
    | Dr. Teodor Brandt | Cascade Orthopedics | the right knee replacement (2025-03-11) |
    | Dr. Farah Nadeem | Willamette Heart Associates | cardiology since 2025-11 |
    | Dr. Paul Gray | Larkspur Family Clinic | primary care |

    ## Medications (as of 2026-10-20)

    - Atorvastatin 40 mg nightly (from 2026-04; was 20 mg).
    - Lisinopril 10 mg.
    - Baby aspirin.

    ## Lipids

    | Date | LDL |
    | --- | --- |
    | 2025-11-06 | 104 |
    | 2026-04-14 | 98 |
    | 2026-10-20 | 91 |

    ## Activity

    His walks, bike rides and (since August 2026) jog/walk intervals are in
    `../data/activities.csv` as `Erik Sr.` or `Grandpa E.`.

    Visits: [visits/](visits/).
    """)


def running_overview():
    path = os.path.join(VAULT, "health/data/activities.csv")
    A = [a for a in csv.DictReader(open(path, encoding="utf-8"))]
    mi = defaultdict(float); n = defaultdict(int); st = defaultdict(int)
    for a in A:
        if a["person"] != "Erik" or not ("2026-01" <= a["date"][:7] <= "2026-08"):
            continue
        m = a["date"][:7]
        if a["type"] == "run":
            mi[m] += float(a["distance_mi"]); n[m] += 1
        if a["type"] == "strength":
            st[m] += 1
    rows = [(m, n[m], f"{mi[m]:.1f}", st[m]) for m in sorted(set(mi) | set(st))]
    # weeks met (3 runs + 2 strength), Mon-Sun weeks fully inside Jan 5 - Aug 30
    met = total = 0
    s = dt.date(2026, 1, 5)
    while s + dt.timedelta(days=6) <= dt.date(2026, 8, 30):
        e = (s + dt.timedelta(days=6)).isoformat()
        wk = [a for a in A if a["person"] == "Erik" and s.isoformat() <= a["date"] <= e]
        total += 1
        met += sum(a["type"] == "run" for a in wk) >= 3 and sum(a["type"] == "strength" for a in wk) >= 2
        s += dt.timedelta(days=7)
    tot = sum(mi.values())
    w("health/running/overview.md", f"""> GENERATED by tools/running_report.py on 2026-09-01 — do not edit.

# Training overview — Erik, 2026

Goal: 3 runs + 2 strength per week. Data through 2026-08-31.

**Weeks met: {met} of {total}.** Run miles 2026 to date: **{tot:.1f}**.

{table(["Month", "Runs", "Run miles", "Strength sessions"], rows)}
""", dedent=False)


def main():
    README(); goals(); labs(); history(); visits(); running_overview()


if __name__ == "__main__":
    main()
