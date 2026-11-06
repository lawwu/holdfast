"""Career domain and the vault root README."""
from common import w


def main():
    w("README.md", """
    # Halvorsen household knowledge base

    SYNTHETIC test fixture. The Halvorsen family and everyone in this vault are fictional.

    ## Purpose

    We are a Christian family in Alder Creek, Oregon: Erik (43), Anna (41), and our three
    children Leif (12), Greta (9) and Soren (5). Our aim is to love God with all our heart,
    soul, strength and mind, and to love our neighbors as ourselves. The money, the house,
    our health and our calendar are stewardship in service of that, never ends in themselves.

    This vault is our family assistant's memory. Answer from what is written here; when
    something new happens, record it where the domain README says.

    ## Domains

    | Domain | What it holds | Start at |
    | --- | --- | --- |
    | `finance/` | Profile, policies, giving, large purchases, statements, CSVs of transactions, giving and net worth | [finance/README.md](finance/README.md) |
    | `home/` | Maintenance log, appliances, projects (the fence), project history | [home/README.md](home/README.md) |
    | `health/` | Goals, labs, visits for all five of us, Grandpa E.'s records, the activity CSV | [health/README.md](health/README.md) |
    | `life/` | Calendar, journal, trips, recipes, books, school, small group, Pepper | [life/README.md](life/README.md) |
    | `career/` | Erik's work and decisions | [career/README.md](career/README.md) |
    | `ministry/` | Erik's biblical-counseling case reports (initials only) | [ministry/README.md](ministry/README.md) |

    ## Conventions

    - Today's date for this fixture is **2026-11-05**; timezone America/Los_Angeles.
    - Dates are YYYY-MM-DD. The journal uses relative dates ("yesterday") — count from the entry's date.
    - Two Eriks: **Erik** is the dad of this house; his father is **Erik Sr.**, called **Grandpa E.**
    - Never record account, card, policy or member numbers anywhere in this vault.
    - CSVs under `<domain>/data/` are the source of truth for numbers; files marked
      `GENERATED` are snapshots and may be stale. Older notes are not always marked when
      something changes — prefer the newest dated source.
    """)
    w("career/README.md", """
    # Career — operating manual

    | File | What it is |
    | --- | --- |
    | [notes.md](notes.md) | Current role and the open decision |
    | [history.md](history.md) | Erik's work history |
    | [deciding.md](deciding.md) | How we decide about work: motive, family, church, then the role |

    Decisions about work go through [deciding.md](deciding.md) first.
    No employer-confidential details here (customers, revenue, colleagues' personnel matters).
    """)
    w("career/notes.md", """
    # Career notes

    Updated 2026-10-26.

    ## Now

    Operations manager, Bluestem Logistics, Alder Creek distribution center. 19 direct and
    indirect reports since the May 2025 reorganization. Salary $140,000. Boss: Dana.

    ## The open decision

    On 2026-10-23 Dana offered Erik the **regional director** role based at the Salem hub:
    four sites, about $168,000, more travel (two nights a month away), and a 45-minute
    commute three days a week. **Answer needed by 2026-11-20.**

    Questions we're asking (see [deciding.md](deciding.md)):
    - Why do I want it? (Some of it is wanting to be the one in charge. Name that.)
    - What does it do to Tuesday/Thursday mornings with the kids, to small group, to the counseling training?
    - Is there a church-life cost to the commute, or a move? (No move — we said so.)
    """)
    w("career/history.md", """
    # Work history — Erik

    | Years | Role | Where |
    | --- | --- | --- |
    | 2005–2009 | Warehouse associate → shift lead | Columbia Freight, Portland |
    | 2009–2014 | Operations supervisor | Columbia Freight |
    | 2014–2019 | Operations manager | Riverbend Distribution, Salem |
    | 2019– | Operations manager | Bluestem Logistics, Alder Creek |

    Moved to Alder Creek in 2019 for the Bluestem job and to be near Dad and Mom.
    """)
    w("career/deciding.md", """
    # How we decide about work

    In this order:

    1. **Motive.** Why do I want this? Pride, fear, money, or service? Write it down honestly.
    2. **Formation.** What will it do to my walk with God — time in the Word, church, the counseling?
    3. **Family.** Anna first. Then the kids' ages and what they need from me now.
    4. **The role itself.** Only now: the work, the pay, the people.

    Talk to Pastor J. before saying yes to anything that changes the shape of the week.
    """)


if __name__ == "__main__":
    main()
