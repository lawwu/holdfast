"""Home domain notes."""
from common import table, w
from csvs import MAINT


def README():
    w("home/README.md", """
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
    """)


def log():
    rows = [(d, what, who, f"${c:,.2f}" if c else "incl.", n) for d, what, who, c, n in MAINT]
    w("home/maintenance-log.md", "# Maintenance log\n\nOne row per repair, service visit or DIY fix, sorted by date. Costs are totals paid.\n\n"
      + table(["Date", "What", "Who", "Cost", "Notes"], rows) + "\n", dedent=False)


def projects():
    w("home/projects.md", """
    # Projects — planning scratchpad

    Last updated 2026-03-22.

    ## Back fence (2026) — DECIDED

    168 ft of leaning cedar along the back and the east side, two gates. Pepper has gotten
    out twice. Quotes:

    | Contractor | Quote | Start | Notes |
    | --- | --- | --- | --- |
    | Cedar & Sons Fencing | $8,900 | 2026-05-11 | family business, good reviews from the Lindqvists |
    | Hollis Fence Co. | $9,450 | August at the earliest | very thorough bid, 2-year workmanship warranty |
    | Pacific Post & Rail | $11,200 | June | steel posts |

    **Chose Cedar & Sons** — $1,000 deposit paid 2026-03-24. Build week of May 11.

    ## Kitchen counters (someday)

    Laminate is chipped by the sink. Rough idea: quartz, $4,500–6,000. Not before 2027.

    ## Water heater

    The tank is 13 years old. Replace before it fails; Barlow quoted $1,850 for a 50-gal gas
    unit. (Done 2026-05-09 — see the log.)

    ## Ideas list

    - Raised garden beds for Greta (she wants strawberries).
    - Basement dehumidifier.
    - Replace the hall carpet.
    """)


def fence():
    w("home/fence-project.md", """
    # Back fence — 2026

    The project, start to finish. This note is the current truth; the planning table in
    [projects.md](projects.md) was written before Cedar & Sons cancelled.

    ## Timeline

    | Date | What happened |
    | --- | --- |
    | 2026-01-18 | Decided to replace the back and east fence (168 ft, two gates) |
    | 2026-02 – 03 | Three quotes: Cedar & Sons $8,900; Hollis Fence Co. $9,450; Pacific Post & Rail $11,200 |
    | 2026-03-22 | Picked Cedar & Sons; $1,000 deposit 2026-03-24 |
    | 2026-05-06 | **Cedar & Sons cancelled.** The owner broke his leg and the crew went to another company. They promised the deposit back |
    | 2026-05-29 | Cedar & Sons deposit refunded in full ($1,000) |
    | 2026-06-08 | **Signed with Hollis Fence Co.** at their $9,450 bid; start date 2026-08-17 |
    | 2026-06-10 | Hollis deposit $2,000 |
    | 2026-08-17 → 08-19 | Hollis built it: old fence out Monday, posts set Monday–Tuesday, panels and gates Wednesday |
    | 2026-08-19 | Change order: side gate widened to 5 ft so the mower trailer fits, +$380. Progress payment $4,000 |
    | 2026-08-22, 08-29 | Erik and Leif stained it (two coats); stain from Ridgeway Lumber |
    | 2026-09-02 | Final payment to Hollis, $3,830 |

    Hollis contract total: $9,450 + $380 = **$9,830**. Workmanship warranty: 2 years.

    ## How to total the project from the CSV

    For the fence total, count in `finance/data/transactions.csv`:
    - every Hollis payment (it appears as `HOLLIS FENCE CO` and `Hollis Fence Company`);
    - the Cedar & Sons deposit **and** its refund (they net to zero, but count both rows);
    - the two Ridgeway Lumber stain purchases on 2026-08-22 and 2026-08-29.

    Do not count the other Ridgeway Lumber purchases (garden-bed boards on 08-25, deck screws
    in September) or anything from Hardware Hub — those were other projects.

    ## Lessons

    - The cheapest bid was also the one with the least margin for anything going wrong.
    - Hollis's crew lead, Dev, walked the line with us before starting and moved one post to
      save the maple. Ask for that next time.
    - Pepper has not gotten out since.
    """)


def history():
    years = {
        "2019 — moving in": [
            "We closed on 2019-06-28 and moved in on July 4th weekend, which in hindsight was a mistake: every friend who could have helped was camping. Leif was five, Greta two, and Soren was not yet born. The house had been a rental for six years before we bought it, and it showed: scuffed walls, a garage full of the previous tenants' paint cans, a yard that had been mowed but never tended.",
            "The inspection report listed the furnace as original (1998) but serviced, the water heater as 2012, the roof as 'serviceable with moss on the north slope,' and the deck as needing boards. We made a list that night on the back of the closing folder and most of this note is the story of working through that list.",
            "First projects, all DIY: the whole interior painted over three weekends in August (Anna's parents came down from Portland for one of them; Mormor painted the bathroom ceiling and refused help); the garage emptied; a hose bib replaced; new locks. We spent about $1,400 on paint and supplies at Hardware Hub, which is how Erik ended up knowing everyone at the paint counter.",
        ],
        "2020 — the year of small fixes": [
            "With everyone home, the house got a lot of attention. Erik built the kids' bunk bed in the spring. We replaced the kitchen light fixtures, the bathroom vanity in the hall bath, and every door knob in the house (the old ones were brass and loose). The backyard became a garden: Anna put in the first two vegetable beds against the south fence, which is part of why the old fence started to lean — the beds held water against the posts.",
            "In September the dishwasher started leaving grit on everything; we replaced it with the Kestrel KD-400 that is still in the kitchen. The installer told us the cabinet under the sink had old water damage, dry now. We have watched it since.",
            "Total spent on the house in 2020, by our rough count: about $5,800, almost all of it materials.",
            "The other 2020 lesson was about the crawlspace under the family room. In November, after a week of heavy rain, Erik went down with a flashlight and found standing water along the north wall. A drainage company quoted $3,900 for a sump and a perimeter drain. We did the cheap thing first: extended both downspouts on that side ten feet out into the yard and regraded the bed against the foundation. It has stayed dry since, which is why the downspout extensions must never be removed when the gutters are cleaned. (Clearflow knows; a new company would not.)",
            "We also learned the house's sounds that year: the furnace's two-stage click, the pipe that knocks when the upstairs toilet fills, the floorboard outside Greta's room that announces every midnight wanderer.",
        ],
        "2021 — Soren, and the basement": [
            "Soren was born in January, so the first half of the year was not about the house. In the summer we finished the basement storage room: shelving, a dehumidifier we later gave away because it was too loud, and a chest freezer. We bought the Odyssey used in May.",
            "The big job of 2021 was the sewer line. In October the downstairs toilet backed up twice in a week; a camera inspection showed tree roots from the street maple in the clay pipe. Barlow Plumbing lined the pipe rather than digging it up: $4,200, the most expensive single repair we had done at that point. It was also when we started using Barlow for everything plumbing.",
            "We also had the first chimney sweep that fall. The sweep said the flue was in good shape and the crown 'fine for now.'",
            "Late in 2021 we replaced the front storm door, which had been held shut with a bungee cord since we moved in, and put a proper handrail on the basement stairs before Soren started crawling. Erik also built the shoe bench by the back door from leftover deck lumber; it is ugly and everyone uses it.",
            "Budget-wise, 2021 is the year we started the home-projects savings bucket at Summit Peak, after the sewer bill came out of the emergency fund and we had to rebuild it. The rule since then: $200 a month into the bucket, more when there is a project coming.",
        ],
        "2022 — Pepper and the yard": [
            "Pepper came home from the shelter in April. Within a month she had found two loose boards in the back fence, and Erik spent a Saturday screwing them back. That was the first sign the fence was going to need replacing; the posts at the southeast corner had rotted at the ground line.",
            "We had the big maple by the street pruned by an arborist (Tall Timber Tree Care, $650) after a branch came down on the car in a windstorm. Anna started composting. The lawn was overseeded in September and did well.",
            "Inside, we replaced the hall carpet runner and painted Leif's room navy at his request. Greta's room got a loft bed. The furnace had its first real repair: a new flame sensor in December, Ridgeline Heating & Air, $180.",
            "The kitchen got a small refresh that fall: new cabinet pulls, a new faucet (which is the one Barlow has since repaired), and under-cabinet lights that Anna loves and Erik installed twice because the first set flickered. We priced new counters and decided against it for now; that idea has been on the projects list ever since.",
            "We also hosted our small group for the first time that year, which is when we noticed that the living room seats ten only if four of them are children on the floor. The second couch came from Facebook Marketplace for $120 and a drive to Larkspur, which is how Grandpa E. ended up helping carry it up the porch steps.",
        ],
        "2023 — insulation and the roof question": [
            "An energy audit through the PUD in February found the attic insulation thin. We had it blown in to R-49 in March (PUD rebate covered about a third). The difference in the January bills afterward was obvious.",
            "The roof came up again in the spring because the moss on the north slope was thick. A roofer we asked for an opinion said the roof had some years left and the moss was the main issue; nobody gave us a firm installation year and the sellers' disclosure did not include one. We decided to treat the moss and revisit later.",
            "Other 2023 work: gutter guards on the front, the garage-door springs adjusted, the bathroom fan in the kids' bath replaced (that fan died again in 2025), and a new mailbox after Soren's tricycle met the old one.",
            "In October 2023 we bought the Corvell washer after the old top-loader walked across the laundry room floor during a spin cycle. The dryer that came with the house is still going. Anna started keeping the appliance manuals in a binder in the laundry room, and the warranty cards go in the same binder.",
            "The other 2023 decision was not to finish the attic into a fourth bedroom. We had a contractor out to look; the cost (around $38,000 with a dormer and stairs) was out of proportion to the need, and the kids are fine sharing for now. Leif and Soren shared a room until Leif turned ten.",
            "We closed out 2023 with a list for 2024 that had three items on it: paint the outside, deal with the moss, and start thinking about the fence. Only the first two happened.",
        ],
    }
    blocks = []
    for y, paras in years.items():
        blocks.append(f"## {y}\n\n" + "\n\n".join(paras))
    paint = """## 2024 — the exterior repaint

The big project of 2024 was painting the outside of the house. The old paint (a tired beige the
previous owners chose) was peeling on the south and west walls, and the trim around the
windows had bare wood showing in places. We got three bids in April: Bright Line Painting
($7,350), Evergreen Coatings ($8,100) and a one-man outfit that never sent a written bid.
We chose Bright Line because they would do the prep properly — scrape, sand, prime bare wood,
caulk every joint — and because their crew lead, Marco, explained the job without selling.

Colors took longer than the bids. Anna painted sample boards and we leaned them against the
house for two weeks to see them in morning and evening light. The kids voted (Greta voted for
purple, every time). We settled on these, all from Northline Paints, satin finish:

- **Body: "Alder Moss"** — a muted gray-green that looks greener in the rain.
- **Trim, window frames, fascia and the porch posts: "Harbor Fog"** — a soft warm white.
- **Front door: "Lingonberry"** — a deep red. Anna's choice, and she was right.

Bright Line started 2024-07-08 and finished 2024-07-19. Deposit $2,000 on 2024-06-20 and the
balance of $5,350 on completion. Leftover paint (about a gallon of each) is on the left
shelf in the garage, labeled. The warranty is three years on labor against peeling.

The same summer: the roof moss treatment (Mossaway Roof Care, $385, zinc strips along the
ridge), the dishwasher drain pump (Appliance Doc, $248), and the second chimney sweep."""
    later = """## 2025 — small things and Dad's knee

2025 was a lighter year on the house because March went to Grandpa E.'s knee replacement and
the recovery. Erik built a temporary railing for Dad's front steps in Larkspur, which is not
our house but felt like a house project. At home: the hall bathroom fan (DIY), six deck
boards with Leif in August, the garage door opener in September (Summit Overhead Doors), and
all seven smoke detectors replaced with 10-year sealed units in November.

We started saving for the fence in earnest in the fall, after Pepper got out the second time
and was found by a neighbor three streets over.

## 2026 — the fence, the water heater, the fridge

2026 has been the most expensive year on the house since the repaint: the water heater in
May (Barlow, $1,850), the refrigerator in July after the old Frostline's compressor died
(Corvell, $1,899 from Valley Appliance), and the back fence in August (Hollis Fence Co.,
$9,830 — see [fence project](fence-project.md); the first contractor cancelled). We also
changed HVAC companies after Ridgeline's no-show in February; Fairbanks Heating & Cooling
now does the AC tune-up and the furnace service.

## What is left

- Kitchen counters (2027 at the earliest).
- The chimney crown crack found at the 2026-10-28 sweep: re-inspect in spring 2027.
- Attic fan, maybe.
- The roof: still unknown age; the moss treatment is holding.

## Notes for whoever keeps this up

- Paint touch-ups: use the labeled leftovers in the garage before buying more; the
  Northline store on Main can re-mix from the labels.
- When the furnace finally goes, ask Fairbanks about a heat pump with a gas backup;
  the PUD has had rebates for that.
- Keep receipts for anything that adds to the house's basis (the sewer lining, the
  repaint, the fence) for whenever we sell. Anna has a folder.
- The previous owners left a binder with a few warranty cards and a 2014 electrical
  permit. It is in the laundry-room binder, behind our own cards.
- Before any project that touches the yard, call the utility locate line two business
  days ahead. Hollis did this for the fence; we did not for the raised beds and got
  lucky — the cable line runs a foot from the east bed.
- Each December, add a section for the year: what we did, what it cost, what we learned.
"""
    intro = """# Projects history — the house since 2019

A long-running history of what we've done to the house and why. The maintenance log has the
rows; this note has the stories, the paint colors, and the reasons. Add a section each year.

## The house at a glance

Two stories plus a partial basement. Three bedrooms and two and a half baths. Living room
with the fireplace at the front, kitchen and family room across the back opening onto the
deck, laundry off the garage. Lot is a little under a quarter acre with the back fence on
the south and east sides and the neighbors' fence on the west. Gas furnace, gas water
heater, gas dryer, electric everything else. Public water and sewer. The sewer lateral runs
under the front lawn toward the street maple, which is the whole story of 2021.

Things a new contractor should know: the main water shutoff is in the garage behind the
bikes, not in the basement; the gas meter is on the east side by the side gate; the attic
hatch is in the hall closet; the crawlspace under the family room is reached from the
basement storage room. The electrical panel is 200 amp, upgraded by the previous owner in
2014, with a labeled directory that is mostly right (the "guest room" breaker is Leif's room).

"""
    text = intro + "\n\n".join(blocks) + "\n\n" + paint + "\n\n" + later
    w("home/projects-history.md", text, dedent=False)


def appliances():
    w("home/hvac.md", """
    # HVAC — furnace and air conditioner

    - **Furnace:** gas, 80,000 BTU, original to the house (1998). Filter **16x25x1**, change every 90 days
      (Jan / Apr / Jul / Oct). Pleated MERV 8 from Hardware Hub.
    - **AC:** 2.5-ton condenser, installed 2015 by the previous owner.
    - **Service:** Ridgeline Heating & Air — furnace every January, AC every June.
      They have our history on file.
    - Manual: [[home/furnace-manual]] (scanned PDF in the household drive).
    - Thermostat: the smart one in the hall, schedule 68°F day / 64°F night in winter.

    ## History

    - 2022-12: flame sensor replaced (Ridgeline).
    - 2024-01: tech said the igniter is original and "on borrowed time."
    - The furnace is 28 years old. Plan to replace when it fails, not before; budget $6,500–8,000.
    """)
    w("home/water-heater.md", """
    # Water heater

    - **Current:** Rheem-style 50-gallon gas tank from Barlow Plumbing, installed 2026-05-09, $1,850.
      Tank warranty 6 years (to 2032-05-09), parts 6 years, labor 1 year.
    - Old tank: 2012, leaked at the base in April 2026.
    - Flush once a year in May. Anode rod check at year 3 (2029).
    """)
    w("home/dishwasher.md", """
    # Dishwasher

    - **Kestrel KD-400**, installed 2020-09. Stainless tub, third rack.
    - 2024-09-05: drain pump replaced (Appliance Doc Repair, $248).
    - 2026-07-26: door gasket replaced (Appliance Doc Repair, $165).
    - Clean the filter monthly — it's under the bottom rack, twist counter-clockwise.
    - Quirk: the "quick wash" cycle leaves the top rack wet. Use normal.
    """)
    w("home/refrigerator.md", """
    # Refrigerator

    - **Frostline FR-2290**, French door, 25 cu ft, stainless. Bought 2019-08 at Valley Appliance when we moved in.
    - Water filter: **Frostline FL-20**, replace every 6 months (we do March and September).
      Hardware Hub carries them; the off-brand ones leak.
    - Ice maker quirk: if it stops, hold the reset button 10 seconds.
    - Coils vacuumed every January.
    - Warranty: 1 year parts and labor, 5 years sealed system (ended 2024-08).
    """)
    w("home/refrigerator-corvell.md", """
    # Refrigerator — Corvell CF-3400

    Bought 2026-07-12 at Valley Appliance after the old Frostline's compressor died on
    2026-07-10 (the ice cream gave it away). Delivered and installed 2026-07-14; haul-away of
    the old one included.

    - **Model:** Corvell CF-3400, French door, 26 cu ft, fingerprint-resistant stainless.
    - **Price:** $1,899 including delivery, install, haul-away.
    - **Water filter: Corvell CWF-9**, every 6 months (January and July). Valley Appliance
      sells them; one spare is in the pantry.
    - Warranty: 1 year parts and labor (to 2027-07-12). The booklet has the rest; registered online 2026-07-20.
    - Quirk: the door alarm beeps after 60 seconds open. It can be turned off; we didn't.
    """)
    w("home/washer-dryer.md", """
    # Washer and dryer

    - **Washer:** Corvell CW-5200 front-loader, bought 2023-10 at Valley Appliance.
      Run the cleaning cycle monthly; leave the door open.
    - **Dryer:** Dalton gas dryer, came with the house (2016?). Vent cleaned 2025-02 (DIY with a brush kit).
    - Dryer vent: clean every year in February. Lint filter after every load (Soren's job).
    """)
    w("home/garage-door.md", """
    # Garage door

    - Door: 16x7 steel, insulated, original.
    - **Opener:** belt-drive, installed 2025-09-20 by Summit Overhead Doors ($545). Two remotes plus the keypad.
    - **Springs:** both torsion springs replaced 2026-09-12 (Summit Overhead Doors, $310).
    - Lube rollers and hinges every spring.
    """)
    w("home/sprinklers.md", """
    # Sprinklers

    Six zones. Controller in the garage. Greenway Irrigation does the fall blowout (mid-October)
    and any valve repairs.

    | Zone | Area | Notes |
    | --- | --- | --- |
    | 1 | Front lawn | |
    | 2 | Front beds (drip) | |
    | 3 | Back lawn, east | valve solenoid replaced 2026-08-15 |
    | 4 | Back lawn, west | |
    | 5 | Vegetable beds (drip) | Anna's |
    | 6 | Side yard | rarely used |

    Turn on in May, off after the blowout. 2026 blowout: not yet scheduled — call Greenway.
    """)
    w("home/chimney.md", """
    # Chimney and fireplace

    Wood-burning fireplace in the living room; we burn maybe a cord a winter.

    - Sweep and inspection every fall by Top Hat Chimney.
    - 2024-11-02: sweep, crown fine.
    - 2026-10-28: sweep and inspection, $275. **Small mortar crack in the crown.** Not urgent;
      re-inspect in spring 2027 and seal then if it has grown.
    - Firewood: Larkspur Firewood, delivered in September.
    """)
    w("home/yard.md", """
    # Yard

    - The street maple: pruned 2022 by Tall Timber Tree Care. Roots are in the old sewer line (lined 2021).
    - Vegetable beds along the south side; two new raised beds for Greta built August 2026
      (boards from Ridgeway Lumber). Strawberries went in in September.
    - Lawn: overseed in September, fertilize in April and October.
    - Compost bin behind the shed.
    """)
    w("home/contractors.md", """
    # Contractors — who we call

    | Need | Who | Since | Notes |
    | --- | --- | --- | --- |
    | Plumbing | Barlow Plumbing | 2021 | sewer lining, water heater, faucets |
    | Furnace / AC | Fairbanks Heating & Cooling | 2026-06 | furnace in October, AC in June |
    | Appliance repair | Appliance Doc Repair | 2024 | dishwasher pump and gasket |
    | Garage door | Summit Overhead Doors | 2025 | |
    | Gutters | Clearflow Gutters | 2023 | every March |
    | Sprinklers | Greenway Irrigation | 2024 | blowout in October |
    | Chimney | Top Hat Chimney | 2021 | every fall |
    | Fence | Hollis Fence Co. | 2026 | built the back fence; 2-year warranty |
    | Painting | Bright Line Painting | 2024 | exterior repaint |
    | Trees | Tall Timber Tree Care | 2022 | |

    Phone numbers live in Anna's contacts, not here.
    """)


def main():
    README(); log(); projects(); fence(); history(); appliances()


if __name__ == "__main__":
    main()
