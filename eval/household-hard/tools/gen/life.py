"""Life domain: README, calendar, people, journal, trips, recipes, books, school, small group, pets."""
from common import table, w

JOURNAL = [
    ("2025-01-04", "Quiet Saturday. Erik printed the half-marathon plan and taped it inside the pantry door, which Anna says is 'a cry for attention.' Grandpa E. called; he's nervous about March and pretending not to be."),
    ("2025-01-28", "Took Grandpa E. to his pre-op at Cascade Ortho. Dr. Brandt is a straight shooter — Dad liked him. Surgery is set for March 11. I'm driving him; Mom doesn't like the highway in the dark."),
    ("2025-02-15", "Snow day, the real kind. Kids sledded the hill behind the school until they couldn't feel their hands. Both of Anna's clients paid late this month, again."),
    ("2025-03-11", "Up at 4:15 to get Grandpa E. to Mercy Valley by 5:30. Surgery took a little over two hours and Dr. Brandt came out smiling. Mom held it together until the doctor left. Anna had all three kids plus Soren's preschool pickup."),
    ("2025-03-13", "Dad's home. Walker, ice machine, a very grumpy patient. Small group signed up to bring meals to Larkspur for two weeks."),
    ("2025-04-02", "Paid $1,250 toward Dad's hospital deductible. He argued; we won. Mom cried on the phone."),
    ("2025-04-10", "Soren's cleaning at Bright Smile was a disaster — he screamed, bit the mirror, and they stopped halfway. Dr. Haber was kind and suggested a pediatric dentist. Anna's calling Little Oaks for all three kids. Adults stay at Bright Smile."),
    ("2025-05-10", "Harbor House banquet tonight. Greta asked why babies need a 'house.' Good conversation in the car."),
    ("2025-05-25", "Memorial Day weekend at Silver Lake with the Lindqvists. Two nights, one thunderstorm, zero sleep. Leif caught a trout and talks about nothing else."),
    ("2025-06-14", "Decided not to refinance. Rate on offer was no better than our 3.25% once the fees were in."),
    ("2025-07-22", "Anna at Ridgecrest urgent care tonight — sinus infection, antibiotics. Erik on dinner duty: pancakes."),
    ("2025-08-09", "Replaced six deck boards with Leif. He ran the impact driver and was very serious about it. Best Saturday in a while."),
    ("2025-08-14", "Leif's braces went on at Brightview. He's already asked whether popcorn is 'really' banned. It is."),
    ("2025-09-07", "First Sunday-evening small group (we moved from Wednesdays so more families can come). Twelve kids in the Lindqvists' basement. Loud. Good."),
    ("2025-09-20", "Garage door opener died with the Odyssey inside. Summit Overhead came the same afternoon."),
    ("2025-10-12", "Alder Creek Half this morning: 1:52:40. Missed 1:50 and I was grumpy all afternoon, at the kids, at Anna, at nobody. That tells me something."),
    ("2025-10-19", "Long talk with Anna about the running. It's become a scoreboard. I want to keep running and drop the racing. New goal in January: show up, not speed up."),
    ("2025-11-14", "Cascade's homeowners renewal came yesterday: $1,980. Anna is getting quotes this week."),
    ("2025-11-22", "Signed with Timberline for the house, both cars and an umbrella; starts Dec 15. Also: the Food Pantry's Thanksgiving drive was matching every gift dollar for dollar through today, so we gave $500 instead of our usual $200. Greta wanted to give her tooth-fairy money too."),
    ("2025-11-27", "Thanksgiving at Uncle Nils's in Salem. Grandpa E. walked the whole neighborhood loop after dinner, no cane."),
    ("2025-12-07", "Christmas outreach gift. The kids packed food boxes after second service."),
    ("2025-12-25", "Christmas morning. Soren got a headlamp and wore it to bed. Mormor drove down from Portland for the day."),
    ("2025-12-28", "Finished the annual review last night. The decisions are at the bottom of the review note — 401(k), giving, the emergency fund. Felt good to do it together."),
    ("2026-01-05", "New training goal starts today: 3 runs and 2 strength a week, that's it. Strength this morning in the garage. Pepper supervised."),
    ("2026-01-18", "Pepper got out again — third time — through the gap by the compost. That settles it: the fence gets replaced this year. Anna's calling for quotes."),
    ("2026-02-03", "Booked the Norway flights for Erik and Leif on Nordlys Air. Grandpa E. is booking his own seat on the same flights. June 14 out, June 24 back."),
    ("2026-02-09", "No heat. Ridgeline said 8–noon and never came. Space heaters and the kids camped in sleeping bags by the fireplace (they loved it)."),
    ("2026-02-11", "Ridgeline finally came yesterday, swapped a pressure switch and billed two hours — $289. That's it for them. The Okafors next door use Fairbanks Heating & Cooling; we'll switch."),
    ("2026-02-27", "Soren fell off the arm of the couch onto the coffee table. Chin split. Ridgecrest Urgent Care (not Ridgeview — they were closed), three stitches. He was very brave and got two stickers."),
    ("2026-03-15", "Greta's spring piano recital — she played the Clementi sonatina without stopping. Grandpa E. and Grandma Ruth came."),
    ("2026-03-22", "Picked Cedar & Sons for the fence: cheapest, and they can start May 11. Deposit Tuesday."),
    ("2026-04-04", "Anna filed our taxes. Refund goes to the car fund."),
    ("2026-04-18", "Picked up the Outback yesterday from Valley Subaru — 2022, 31,000 miles, blue. Sold the Camry this morning to the Bergstroms' nephew for $6,200. Erik is irrationally sad about the Camry."),
    ("2026-05-06", "Cedar & Sons called: the owner broke his leg and the crew has scattered to other jobs. They're cancelling and will refund the deposit. Back to the drawing board — Hollis was thorough, maybe them."),
    ("2026-05-09", "Water heater replaced by Barlow, finally. Hot showers for everyone. Harbor House banquet tonight."),
    ("2026-05-29", "Cedar & Sons deposit came back in full. Good people having a hard year."),
    ("2026-06-08", "Signed with Hollis Fence. They can't start until August 17. Pepper will have to behave all summer."),
    ("2026-06-14", "Erik, Leif and Grandpa E. flew out to Oslo this afternoon. The house is very quiet. — A."),
    ("2026-06-24", "Pepper ate one of Soren's socks yesterday. Juniper Animal Clinic made her throw it up — $318.50 for a sock. The boys land tonight. — A."),
    ("2026-06-25", "Home. Jet lag. Dad hasn't stopped talking about the farm. Leif slept 14 hours."),
    ("2026-07-10", "The fridge died. Compressor. We found out because the ice cream was soup. Coolers on the deck."),
    ("2026-07-12", "Bought a Corvell at Valley Appliance, $1,899 with install and haul-away. Delivery Tuesday."),
    ("2026-07-25", "Back from Glacier. Soren was car-sick twice on the way up; the middle row and ginger chews fixed it on the way home."),
    ("2026-08-10", "Achilles. Felt it go tight two miles into the Monday run and walked home. Ice and a lot of self-pity."),
    ("2026-08-12", "Dr. Ostrowski at Cascade Ortho: tendinopathy, no tear. No running for a month, heel lifts, calf raises, PT. Swimming is fine, which I hate."),
    ("2026-08-19", "Fence is done! Hollis was great — Dev moved a post to save the maple. Widened the side gate for $380 more. Pepper inspected every board."),
    ("2026-08-22", "Stained the fence with Leif. Our hands are brown."),
    ("2026-09-02", "First day of school. Leif 7th grade, Greta 4th (Ms. Varga), Soren kindergarten (Mr. Abbott). Soren told Mr. Abbott about the sock."),
    ("2026-09-09", "Achilles follow-up: cleared for easy runs, 30 minutes max, twice a week, through January. Plus a weekly swim. New plan is in the goals note."),
    ("2026-09-13", "Small group fall kickoff at the Lindqvists'. We're reading Gentle and Lowly this fall."),
    ("2026-09-19", "Greta and Erik built her raised beds. Strawberries in. She has named them."),
    ("2026-10-01", "Grandpa E. called the day before yesterday — Willamette Heart moved his appointment from the 6th to the 20th. I'll drive him."),
    ("2026-10-04", "Moved the Yellowstone trip: Leif's orchestra camp is June 21–26 next summer, which kills our June dates. New dates July 10–18, 2027. Trip plan updated."),
    ("2026-10-11", "Small group potluck. Anna brought her cardamom buns and came home with an empty pan and three requests for the recipe. (Recipe: [[recipes/cardamom-buns]].)"),
    ("2026-10-20", "Drove Dad to cardiology. LDL down to 91. Dr. Nadeem happy. Dad wants a medal for the jogging."),
    ("2026-10-22", "Leif fell at soccer, right wrist. Cascade Ortho squeezed him in: sprain, brace, no soccer for now."),
    ("2026-10-25", "Trunk-or-treat at church. Soren was a dinosaur, Greta a lighthouse (her own idea), Leif 'too old' but handed out candy as a referee."),
    ("2026-10-28", "Chimney sweep found a small crack in the crown. Not urgent; look again in spring."),
    ("2026-10-30", "Soren lost his first tooth at dinner — bottom front, in a piece of corn on the cob. Pure joy. Also Fairbanks did the furnace service today and replaced the igniter."),
    ("2026-11-02", "Dana extended the deadline on the regional director offer to December 4. We'll drive up to see the Salem hub together on the 14th and talk to Pastor J. before deciding."),
    ("2026-11-03", "Open enrollment opened. Northstar premium share goes up again for 2027. Counseling night — tired but grateful."),
]


def journal():
    for d, text in JOURNAL:
        w(f"life/journal/{d}.md", f"# {d}\n\n{text}\n", dedent=False)


def README():
    w("life/README.md", """
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
    """)


def people():
    w("life/people.md", """
    # People

    | Name | Who | Notes |
    | --- | --- | --- |
    | Erik | Erik Halvorsen, b. 1983 | |
    | Anna | Anna Halvorsen, b. 1985 | journal entries she writes are signed "— A." |
    | Leif | 12, 7th grade | braces, viola, soccer |
    | Greta | 9, 4th grade | piano, strawberries |
    | Soren | 5, kindergarten | dinosaurs |
    | **Grandpa E.** | **Erik Halvorsen Sr.**, Erik's father, b. 1954, Larkspur | right knee replaced 2025; cardiology at Willamette Heart. Records in `health/erik-sr/` |
    | Grandma Ruth | Erik's mother | |
    | Uncle Nils | Erik's brother, Salem | wife Marta, two girls |
    | Mormor | Birgit Lindgren, Anna's mother, Portland | |
    | Aunt Kristin | Anna's sister, San Diego | we stay with her at Christmas 2026 |
    | Tom and Becca Lindqvist | small-group leaders, friends | |
    | Pastor J. | Hillcrest; Erik's counseling supervisor | |
    | Pastor R. | Hillcrest; refers counselees | |
    | Dana | Erik's boss at Bluestem | |

    Two Eriks: in notes, "Erik" is always Erik (the dad of this house); his father is
    "Erik Sr." or "Grandpa E.".
    """)


def calendar():
    w("life/calendar.md", """
    # Family calendar — upcoming

    Today's view starts 2026-11-05. Past rows are pruned at the start of each month.

    ## November 2026

    | Date | Time | What | Who | Notes |
    | --- | --- | --- | --- | --- |
    | 2026-11-05 | 7:00 pm | Counseling check-in (D.M.) at church | Erik | |
    | 2026-11-08 | 12:15 pm | Hillcrest fall potluck after second service | all | Anna is bringing the [[life/recipes/swedish-meatballs|meatballs]] |
    | 2026-11-10 | 3:30 pm | Wrist follow-up, Cascade Orthopedics | Leif + Erik | |
    | 2026-11-12 | 9:00 am | Filling, Bright Smile Dental | Anna | |
    | 2026-11-12 | 7:00 pm | Counseling (R.S.) | Erik | |
    | 2026-11-14 | all day | Visit the Bluestem Salem hub | Erik + Anna | kids with Grandma Ruth |
    | 2026-11-15 | — | 401(k) investment-mix decision | Erik | [open items](../finance/open-items.md) |
    | 2026-11-17 | 4:15 pm | Parent-teacher conference, Ms. Varga | Greta, Anna + Erik | |
    | 2026-11-18 | 8:00 am | Cleaning, Bright Smile Dental | Erik | |
    | 2026-11-20 | — | Open enrollment closes | Erik + Anna | |
    | 2026-11-21 | 2:00 pm | Piano recital, Alder Creek Music Studio | Greta | arrive 1:30 |
    | 2026-11-26 | 1:00 pm | Thanksgiving — we host Nils and family | all | Nils brings pies |

    ## December 2026

    | Date | Time | What | Who | Notes |
    | --- | --- | --- | --- | --- |
    | 2026-12-04 | — | Answer on the regional director offer | Erik | |
    | 2026-12-05 | 9:00 am | Hillcrest Christmas outreach (food boxes) | all | |
    | 2026-12-08 | 7:30 am | Fasting lipid panel, Ridgeview Family Medicine | Erik | |
    | 2026-12-13 | 10:30 am | Kids' Christmas program at church | Greta, Soren | |
    | 2026-12-15 | — | Timberline policies renew | | [policies](../finance/policies.md) |
    | 2026-12-21 → 12-29 | — | San Diego Christmas trip | all | [trip plan](trips/202612_san-diego-christmas/plan.md) |

    ## January 2027

    | Date | Time | What | Who | Notes |
    | --- | --- | --- | --- | --- |
    | 2027-01-12 | — | Furnace filter change | Erik | 16x25x1 |
    | 2027-01-28 | 10:00 am | Achilles recheck, Dr. Ostrowski | Erik | decides whether to go back to 3 runs |
    """)


def trips():
    w("life/trips/README.md", """
    # Trips

    | Folder | Trip | Dates | Who |
    | --- | --- | --- | --- |
    | [202505_silver-lake](202505_silver-lake/plan.md) | Silver Lake camping with the Lindqvists | 2025-05-24 → 05-26 | all |
    | [202606_norway-heritage](202606_norway-heritage/plan.md) | Norway — the family farm | 2026-06-14 → 06-24 | Erik, Leif, Grandpa E. |
    | [202607_glacier-camping](202607_glacier-camping/plan.md) | Glacier National Park camping | 2026-07-18 → 07-25 | all |
    | [202612_san-diego-christmas](202612_san-diego-christmas/plan.md) | Christmas with Aunt Kristin | 2026-12-21 → 12-29 | all |
    | [202706_yellowstone](202706_yellowstone/plan.md) | Yellowstone by car | 2027-07-10 → 07-18 | all |

    Folder names keep the month the trip was first planned for.
    """)
    w("life/trips/202505_silver-lake/plan.md", """
    # Silver Lake camping — Memorial Day 2025

    With the Lindqvists. Sites 14 and 15 at the state park, two nights (2025-05-24 → 05-26).

    - Bring: the big tent, the kids' tent, both stoves, rain fly (we needed it).
    - Food plan: tacos Saturday, Lindqvists' chili Sunday, pancakes both mornings.
    - Leif caught a 12-inch trout off the dock Sunday morning.
    - Next time: earth plugs. The thunderstorm at 2 am woke everyone.
    """)
    w("life/trips/202607_glacier-camping/plan.md", """
    # Glacier camping — July 2026

    2026-07-18 → 07-25. Drive: two days each way, overnight in Missoula.

    ## Bookings
    - Apgar campground, 5 nights, $168 (booked 2026-07-03 when a cancellation opened).
    - Missoula motel both ways.

    ## Plan
    - Day hikes: Trail of the Cedars, Avalanche Lake, Hidden Lake if the snow is gone.
    - Going-to-the-Sun Road needs a vehicle reservation — got one for 07-21.

    ## After
    Soren was car-sick twice on the drive up. On the way back he sat in the **middle row**
    with **ginger chews** and was fine. Do that from the start next time.
    Avalanche Lake was the favorite. Greta wants to go back "when she's twelve."
    """)
    w("life/trips/202612_san-diego-christmas/plan.md", """
    # San Diego Christmas — 2026

    2026-12-21 → 12-29, staying with Aunt Kristin in Escondido.

    ## Bookings
    - Flights: not booked yet. Target under $1,900 for five. Watch Pacific Coast fares.
    - Car: borrow Kristin's van.

    ## Plan
    - Christmas Eve service at Kristin's church.
    - Beach day at La Jolla Shores (wetsuits for the kids?).
    - Zoo day with Mormor if she flies down.
    """)
    w("life/trips/202706_yellowstone/plan.md", """
    # Yellowstone — summer 2027

    ## Overview

    **Dates: June 19–27, 2027.** Driving (the Outback plus a roof box), two days each way.
    All five of us. Grandpa E. and Grandma Ruth may join for the middle three days.

    ## Route

    Alder Creek → Boise (night 1) → West Yellowstone. Home through Jackson and Twin Falls.

    ## Bookings

    - Firehole Cabins, West Yellowstone: deposit $450 paid 2026-10-06. Two-bedroom cabin.
    - Inside-the-park nights: try again when the lottery opens.

    ## Things to see

    - Old Faithful and the Upper Geyser Basin boardwalks (stroller-friendly for nobody; Soren walks).
    - Grand Prismatic overlook trail.
    - Lamar Valley at dawn for wolves — Leif's request.
    - Junior Ranger program for Greta and Soren.

    ## Packing

    Bear spray (buy there), layers, the kids' headlamps, ginger chews for Soren, the car-sick
    seat order (Soren in the middle row).

    ## Budget

    About $3,800: lodging $2,100, gas $450, food $900, park pass and extras $350.

    ## Changes

    - 2026-10-04: **moved to July 10–18, 2027** because Leif's orchestra camp is June 21–26.
      Firehole Cabins moved the deposit to the new dates. Boise night is now July 10.
    """)
    norway()


def norway():
    head = """# Norway — the family farm (June 2026)

Three generations: **Erik, Leif and Grandpa E.** Anna stayed home with Greta and Soren
(Soren is too young for the flights, and someone had to keep the fence quotes moving).
2026-06-14 → 2026-06-24.

## Why

Grandpa E.'s grandfather, Johan, left a farm in the hills above Lake Mjøsa in 1903 and
came to Minnesota, then Oregon. Dad has talked about seeing it for as long as Erik can
remember. After the knee replacement he said, "If I can walk it, I want to go." He turned
72 this spring. Leif is the age Johan's youngest brother was when the family left.

## Bookings

- **Flights:** Nordlys Air, Portland → Oslo via Reykjavik, out 2026-06-14, back 2026-06-24.
  Erik and Leif: $2,960 for the two of us (booked 2026-02-03). Grandpa E. booked and paid
  his own seat on the same flights. Bag fee on the way home: $85.
- **Oslo:** 2 nights at a small hotel near the station (Dad's treat).
- **Gjøvik area:** 4 nights at Fjordgard Guesthouse, deposit $640 paid 2026-03-10.
- **Bergen:** 2 nights; the Bergen line train from Oslo.
- **Oslo again:** last night near the airport train.
- Leif's school excused the last week (letter from the principal in his school file).

## Budget

| Item | Planned | Notes |
| --- | --- | --- |
| Flights (Erik + Leif) | $2,960 | paid |
| Lodging (our share) | $1,400 | Dad covering Oslo |
| Trains | $420 | Norway rail passes are not worth it for this trip |
| Food | $900 | Norway is expensive; picnic lunches |
| Gifts for the cousins | $150 | Oregon hazelnuts, a Hillcrest mug, Leif's drawings |

## Itinerary

| Date | Plan |
| --- | --- |
| 06-14 | Fly out of PDX in the afternoon |
| 06-15 | Arrive Oslo mid-day. Walk, early dinner, sleep |
| 06-16 | Oslo: the Viking ship exhibits, the fortress, Vigeland park for Leif |
| 06-17 | Train north to Gjøvik; check in at Fjordgard |
| 06-18 | The lake, the old town, Dad rests in the afternoon |
| 06-19 | The farm |
| 06-20 | The church in Biri where Johan was baptized; the cemetery |
| 06-21 | Train to Oslo, then the Bergen line |
| 06-22 | Bergen: the fish market, Fløyen on the funicular |
| 06-23 | Bergen: fjord boat to Mostraumen |
| 06-24 | Train to Oslo airport and home |

## The family tree, as far as we know it

- **Johan** (1881–1958), born on the farm, baptized at Biri. Left in 1903 at 22 with his
  younger brother Peder (who went back to Norway in 1911). Farmed in Minnesota, then moved
  to the Willamette Valley in 1926. Changed the spelling of the surname at Ellis Island
  (the clerk wrote "Halvorsen"; he kept it).
- **Johan's son Erik** (1912–1989) — the first Erik. Dairy, then the mill in Larkspur.
- **His son Erik** (b. 1954) — Grandpa E., our Dad.
- **Erik** (b. 1983), and **Leif** (b. 2014).
- The farm stayed with Peder's line after he went back. The current owners descend from Peder.

Dad has a shoebox of letters from Peder to Johan, in Norwegian, from 1911 to the 1930s. A
retired teacher at church translated six of them in 2024. One describes the new barn
built in 1912 "on the old stones."

## Preparing (February – June)

- **February:** flights booked (02-03). Passports: Leif's renewed (it expired in 2025);
  Dad's was fine; Erik's expires 2027.
- **March:** Fjordgard deposit (03-10). Dad started walking 3 miles at a time to be ready.
  Asked Dr. Brandt's office whether flying is fine a year after the knee — yes, with
  compression socks and getting up every hour.
- **April:** emailed back and forth with the cousins about a date for the farm visit.
  Leif's principal approved the absence for 06-15 to 06-19 with a "travel journal" assignment.
- **May:** bought rain jackets, a power bank, a phrasebook Leif ignored. Printed the family
  tree on 11x17 for the cousins.
- **June:** cash for the first day (kroner from the credit union, ordered a week ahead).
  Mom packed Dad's bag twice.

## Practical notes

- Phones: an eSIM for Erik's phone; Dad's carrier has an international day pass.
- Money: cards work everywhere; nobody wanted cash except the church donation box in Biri.
- Trains: book the Bergen line seats ahead — it sells out in summer. Oslo–Gjøvik doesn't need it.
- Dad's knee: aisle seat on the plane, an hour of walking max before a sit-down, the
  folding cane in his backpack. He used it about a third of the time.
- Food: Leif ate waffles with brown cheese at every opportunity. Picnic lunches from the
  grocery store saved a lot.
- Time zone: nine hours ahead of Oregon. Calls home at 7 am our time / 4 pm theirs.

## Packing

Rain jackets for everyone. Dad's knee brace and the folding cane, even if he says no.
Leif's sketchbook. Power adapters. A printed family tree for the cousins.
"""
    daily = """## The trip, day by day

### 06-14 — leaving

Anna drove us to PDX. Soren cried at the curb and then, Anna says, cheered up completely at
the drive-through on the way home. Dad was at the gate an hour early. The Reykjavik
connection was tight but the plane waited for a wheelchair passenger and we made it.

### 06-15 — Oslo

Landed around noon. Dad slept on the train into the city. We walked along the harbor in
the evening; it was light until almost eleven, which Leif found deeply suspicious. Dinner
was fish soup that Leif said was "actually good."

### 06-16 — Oslo

The Viking ships were the highlight for Leif; he sketched the Oseberg prow for an hour.
Vigeland park in the afternoon. Dad walked about four miles with breaks and was proud of it.
He called Mom twice. We bought a small Norwegian Bible for the cousins' church as a gift.

### 06-17 — north to Gjøvik

Two-hour train up the lake. Fjordgard Guesthouse is a converted farmhouse with a view of
Mjøsa. The owner recognized our family name from the old parish records. Dad went quiet when she said it.

### 06-18 — the lake

Rest day. Leif and Erik rented a canoe. Dad sat on the dock with coffee and wrote in the
little notebook he brought "for the farm." We went over the family tree again at dinner.
In the evening we walked into Gjøvik to the glass factory museum, which Leif liked more
than he expected — he watched a glassblower for forty minutes. Dad called Mom from the
guesthouse porch and told her about the view three times in one call.

Leif asked good questions about why someone would leave a farm for a place he'd never seen;
Dad said, "The same reason anybody does anything hard. They thought God was in it."

### 06-20 — Biri

The white wooden church where Johan was baptized in 1881. The sexton let us in and showed
us the baptismal font. Dad read Psalm 90 aloud in the pew — "Lord, you have been our
dwelling place in all generations." Nobody said anything for a while. In the cemetery we
found two stones from the 1890s with the family name on them.

### 06-21 to 06-23 — Bergen

The train over the mountains is the most beautiful thing Leif has ever seen (his words).
Bergen rained the whole time. The funicular, the fish market, the fjord boat. Dad's knee
held up; he used the cane on the cobblestones only.

We stayed in a guesthouse up the hill from the harbor with a steep street that Dad named
"the knee test." He passed. On the 22nd we ate fish cakes at the market and walked the old
wharf with its leaning wooden buildings; Leif wanted to know why they lean (they were
rebuilt on the old foundations after fires, and the ground settled). On the 23rd the fjord
boat to Mostraumen took about three hours there and back, with a waterfall close enough to
feel. We spent the evening packing the cousins' gifts for the trip home and talking about
the farm, which by then Dad called "home" without noticing.

### 06-24 — home

Long day. Bag fee for the extra suitcase of cousin gifts going the other way ($85). Anna
picked us up at 10 pm with all three kids in pajamas.
"""
    farm = """
## From Leif's travel journal (typed up with permission)

> **June 15.** The sun does not go down here. I am not joking. At 10:30 it was like 6 pm at
> home. Grandpa says in the winter it is the opposite and that is why everyone here has
> candles. Dad says I have to write something about history and not just the sun.
>
> **June 16.** The Viking ships are actual ships that were buried with people in them. The
> Oseberg one has a snake carved on the front that goes in a spiral. I drew it four times.
> Grandpa walked the whole day and only sat down six times. I counted.
>
> **June 18.** We canoed on the lake. It is so big you can't see the end. Grandpa wrote in
> his notebook for a long time and wouldn't let me read it. He said I can type it later.
>
> **June 22.** The train to Bergen goes through snow in JUNE. There was a waterfall right
> next to the tracks and the train stopped so people could take pictures. Bergen rains
> 240 days a year (the guide said). It rained all of them while we were there.
>
> **June 23.** Fjord boat. Grandpa fell asleep. A seal looked at me.

## Notes from the road (Erik)

- The Reykjavik connection both ways was under an hour; fine with carry-ons, risky with
  checked bags. Ours made it, barely, on the way home.
- Fjordgard's owner, Sigrid, drove us to the farm and back on the 19th and refused payment.
  We sent her a card and a jar of Oregon honey afterward.
- Dad's best day physically was the 16th in Oslo; his hardest was the 22nd (stairs at
  the Bergen station). He did not complain once, which for Dad is a miracle.
- Leif was a good travel companion. He carried Dad's bag without being asked on the
  Bergen stairs. Tell him that again.

## The farm — 06-19

This is the part we will want to remember, so it gets its own section.

The farm is **Nordre Halvorsrud**, about twenty minutes up the hill from Gjøvik, on the
road toward Biri. It is still a working farm (sheep and hay now; it was dairy when Johan
left). The family that owns it now are Halvorsruds too: **Ingrid Halvorsrud**, the
daughter of Grandpa E.'s second cousin, runs it with her husband Arne and their three
teenagers.

**Ingrid hosted us for dinner at the farm on the evening of 2026-06-19.** She had found us
through a genealogy forum two years ago and has been writing to Dad since. She served
rømmegrøt (sour-cream porridge) with cinnamon and butter, cured meats, flatbread, and
strawberries from the garden. Arne showed Leif the sheep and let him drive the small
tractor in the yard. Dad walked the edge of the hay field with Ingrid and stood a long
time at the stone foundation of the old barn, the one Johan would have known. He cried,
which none of us have seen often.

Ingrid gave Dad a photograph of the farmhouse from about 1900 — the only picture of it
from before the family left. It is framed in Larkspur now. We gave her the Oregon
hazelnuts, the family tree, and Leif's drawing of the Oseberg ship.

We prayed together before dinner — Arne asked Dad to, in English, and Ingrid translated
for the teenagers. Dad thanked God for "the ones who left and the ones who stayed."

Ingrid and Arne might visit Oregon in 2027. If they do, they stay with us.

On the way out Ingrid showed us the farm's guest book, which goes back to 1952. Dad wrote
in it: "Johan's great-grandson and great-great-grandson came home for an evening." Leif
added a drawing of the sheep.

## Afterward

Dad's notebook is going to be typed up by Leif for a school project. Leif's travel journal
for school got an A and a note from his teacher asking whether the family would share the
farm photo with the class.

Things we would do differently: two nights in Bergen was one too few for the rain; the
Oslo hotel near the station was loud; we should have brought a gift for Arne, not just for
Ingrid and the kids. Things we would do exactly the same: going with Dad while he can walk
it, and leaving the whole of 06-19 free for the farm.

Total cost to us: about $5,300, close to the plan.

For next time (if there is one): Greta and Soren want to go. Anna wants to go. Dad says
"next time" as if it is booked. If Ingrid and Arne come to Oregon first, we will show them
Larkspur, the mill where the first Erik worked, and the coast. The photo of the
farmhouse is the best souvenir any of us have ever brought home from anywhere.
"""
    text = head + "\n" + daily + "\n" + farm
    w("life/trips/202606_norway-heritage/plan.md", text, dedent=False)


RECIPES = {
    "kardemummabullar": """
    # Kardemummabullar (cardamom buns)

    Mormor's recipe, the way Anna makes it for potlucks. Makes 20.

    ## Dough
    - 1 cup whole milk, warmed to 105°F
    - 2¼ tsp instant yeast
    - ⅓ cup sugar
    - 1 tsp freshly ground cardamom
    - ½ tsp salt
    - 6 tbsp butter, soft
    - 3½ cups flour

    ## Filling
    - ½ cup butter, soft; ⅓ cup sugar; 2 tsp ground cardamom

    ## Method
    1. Mix, knead 8 minutes, rise 1 hour.
    2. Roll to a 12x18 rectangle, spread filling, fold in thirds, cut strips, twist and knot.
    3. Rise 30 minutes. Brush with egg, sprinkle pearl sugar.
    4. **Bake at 400°F for 11–13 minutes**, until deep golden.

    The small group likes them warm. Double the batch for potlucks.
    """,
    "swedish-meatballs": """
    # Swedish meatballs

    Anna's, from Mormor. Serves 6–8.

    - 1 lb ground beef, ½ lb ground pork, 1 small onion grated, ½ cup breadcrumbs soaked in ½ cup cream,
      1 egg, allspice, nutmeg, salt and white pepper.
    - Roll small (1 inch). Brown in butter in batches.
    - Gravy: 3 tbsp butter, 3 tbsp flour, 2 cups beef stock, ½ cup cream, a spoon of lingonberry jam.
    - Or bake the meatballs at 425°F for 15 minutes when it's for a crowd.

    Serve with mashed potatoes and lingonberries.
    """,
    "sheet-pan-chicken-fajitas": """
    # Sheet-pan chicken fajitas

    Weeknight standby.

    - 1½ lb chicken breast in strips, 3 peppers, 1 onion, 2 tbsp oil, fajita seasoning.
    - **425°F for 22 minutes**, stirring once.
    - Tortillas warmed in foil the last 5 minutes.
    """,
    "banana-bread": """
    # Banana bread

    Greta's favorite to make. Uses 3 very ripe bananas.

    - ⅓ cup melted butter, ¾ cup sugar, 1 egg, 1 tsp vanilla, 1 tsp baking soda, pinch of salt, 1½ cups flour.
    - **350°F for 60 minutes** in a 9x5 loaf pan. Tent with foil at 40 minutes.
    - Cardamom instead of cinnamon is good too.
    """,
    "small-group-chili": """
    # Small-group chili (Tom's)

    Tom Lindqvist's chili for 20, the one from the fall kickoffs.

    - 4 lb ground beef, 3 onions, 6 cloves garlic, 4 cans kidney beans, 4 cans crushed tomatoes,
      chili powder, cumin, a square of dark chocolate.
    - Simmer 2 hours. Cornbread on the side (400°F, 20 minutes).
    """,
    "risgrynsgrot": """
    # Risgrynsgröt (Christmas rice porridge)

    Christmas Eve breakfast. Whoever finds the almond does the dishes (it's a family rule, not a Swedish one).

    - 1 cup short-grain rice, 1 cup water, 4 cups milk, cinnamon stick, pinch of salt, 1 tbsp butter.
    - Simmer the rice in water, add milk, cook low 45 minutes stirring often.
    - Serve with cinnamon, sugar and cold milk. One blanched almond hidden in the pot.
    """,
    "apple-crisp": """
    # Apple crisp

    For the fall potluck when the Larkspur apples come in.

    - 8 apples sliced, lemon, ¼ cup sugar, cinnamon.
    - Topping: 1 cup oats, ¾ cup flour, ¾ cup brown sugar, ½ cup cold butter.
    - **375°F for 45 minutes.**
    """,
}

BOOKS = {
    "gentle-and-lowly": """
    # Gentle and Lowly — Dane Ortlund

    The small group's fall 2026 book. Two chapters a week, Sunday evenings.

    - Ch. 1: Matthew 11:29 — the only place Jesus describes his own heart.
    - Ch. 4: "his heart goes out" — compassion as his first response, not his last.
    - Anna's favorite line so far is from chapter 6; she underlined half the page.
    - Discussion question that worked: where do you assume Jesus is disappointed in you?
    """,
    "when-people-are-big": """
    # When People Are Big and God Is Small — Ed Welch

    Erik's reading for the counseling training (and assigned to counselees sometimes).

    - Fear of man: being exposed, being rejected, being hurt.
    - The fix isn't to need people less but to love them more and need them less — to fear God.
    - Chapters 1–4 diagnose; 5–8 move toward the fear of the Lord; 9–12 apply it.
    - Pairs well with Proverbs 29:25 and Isaiah 51:12-13.
    """,
    "the-hobbit-read-aloud": """
    # The Hobbit — family read-aloud

    Started 2026-09-20 at bedtime. Erik does the voices; Soren requests Gollum nightly.
    At chapter 8 (spiders) as of 2026-11-01. Greta is reading ahead and won't tell.
    """,
    "good-and-angry": """
    # Good and Angry — David Powlison

    Read in 2026 for the counseling training. Good on anger as a moral judgment ("I'm
    against that") that can be godly or ungodly; the work is to learn to be good and angry
    rather than to stop being angry. Chapter 6 on the "anger at God" question was the best.
    """,
    "reading-list-2026": """
    # Reading list 2026

    | Who | Book | Status |
    | --- | --- | --- |
    | Erik | Good and Angry (Powlison) | done |
    | Erik | When People Are Big and God Is Small (Welch) | re-reading |
    | Anna | Gentle and Lowly (Ortlund) | with small group |
    | Anna | The Hiding Place (ten Boom) | done |
    | Leif | Hatchet | done, wants the sequels |
    | Family | The Hobbit | reading aloud |
    """,
}

SCHOOL = {
    "README": """
    # School — logistics

    | Child | School | Grade 2026–27 | Teacher | Start / end |
    | --- | --- | --- | --- | --- |
    | Leif | Alder Creek Middle School | 7th | homeroom Mr. Dunn | 7:55 – 2:40 |
    | Greta | Alder Creek Elementary | 4th | Ms. Varga | 8:30 – 3:05 |
    | Soren | Alder Creek Elementary | Kindergarten | Mr. Abbott | 8:30 – 3:05 (Wed early out 1:45) |

    - Drop-off: Anna Mon/Wed/Fri, Erik Tue/Thu on his way to work.
    - Early-out Wednesdays: Grandma Ruth picks up Soren twice a month.
    - Lunch accounts are topped up through the district site.
    - Report cards and progress reports go in each kid's file; dated flyers go on the calendar.
    """,
    "leif": """
    # Leif — school

    - 2025–26 (6th): straight A's except a B+ in PE ("the mile").
    - 2026–27 (7th): orchestra (viola), soccer in the fall (paused for the wrist).
    - Orchestra camp June 21–26, 2027 at Willamette Music Camp — the reason Yellowstone moved.
    - Missed 06-15 to 06-19, 2026 for the Norway trip; excused.
    """,
    "greta": """
    # Greta — school

    - 2025–26 (3rd): a hard spring (her teacher was on leave); fine by June.
    - 2026–27 (4th): Ms. Varga. Reading group "Cedars." Wants to do the science fair.
    - Conference 2026-11-17.
    - Vision recheck next spring (right eye 20/25 at the well-child).
    """,
    "soren": """
    # Soren — school

    - Kindergarten, Mr. Abbott, 2026–27. Loves recess and the class guinea pig.
    - Reading: knows all letter sounds, starting CVC words.
    - Lost his first tooth 2026-10-30 (at home, at dinner).
    """,
}

SMALL_GROUP = {
    "README": """
    # Small group

    Hillcrest Bible Church, the "Juniper" group. Leaders: Tom and Becca Lindqvist.
    **Sunday evenings, 6:00–8:00**, rotating homes (we host the first Sunday of the month).
    Moved from Wednesday nights in September 2025.

    About seven families, fourteen kids. Dinner together, kids downstairs with a rotating
    adult, then study and prayer.

    | Term | Study | Notes |
    | --- | --- | --- |
    | Fall 2025 | The Gospel of Mark (chapters 1–8) | [2025-fall](2025-fall.md) |
    | Spring 2026 | Philippians | [2026-spring](2026-spring.md) |
    | Fall 2026 | Gentle and Lowly (Ortlund) | [2026-fall](2026-fall.md) |
    """,
    "2025-fall": """
    # Small group — fall 2025

    Mark 1–8, one passage a week. First Sunday-evening term.

    - 09-07 kickoff at the Lindqvists'; Tom's chili.
    - 10-05 we hosted. Mark 4, the sower. Soren knocked over the lemonade.
    - 11-02 Thanksgiving potluck; the Food Pantry drive was announced.
    - 12-14 Christmas party, white-elephant gifts, Greta won a lava lamp.

    Prayer: Grandpa E.'s recovery (praise — walking without a cane), the Bergstroms' job search.
    """,
    "2026-spring": """
    # Small group — spring 2026

    Philippians, a chapter every two weeks.

    - 01-11 we hosted. Philippians 1:6 — "he who began a good work."
    - 02-08 snowed out.
    - 03-08 Philippians 4:6-7 on anxiety; Becca shared about her mother.
    - 05-31 end-of-term picnic at Riverside Park.

    Prayer: Erik and Leif and Grandpa E.'s trip to Norway; the fence saga (yes, we prayed about the fence).
    """,
    "2026-fall": """
    # Small group — fall 2026

    Gentle and Lowly (Dane Ortlund), two chapters a week. See the [book notes](../books/gentle-and-lowly.md).

    - 09-13 kickoff at the Lindqvists'. Tom's chili again.
    - 10-04 we hosted. Chapters 3–4.
    - **10-11 potluck at the Bergstroms'.** Anna brought her cardamom buns ([recipe](../recipes/cardamom-buns.md)) —
      gone in ten minutes; three people asked for the recipe.
    - 10-25 no group (trunk-or-treat).
    - 11-01 we hosted. Chapters 9–10.

    Prayer: Erik's job decision; Leif's wrist; Grandpa E.'s cardiology (praise — LDL down).
    """,
}


def pets():
    w("life/pets/pepper.md", """
    # Pepper

    Black lab mix, about 6. Adopted 2022-04 from the Alder Creek Animal Shelter. Microchipped
    (registered to Anna). Vet: **Juniper Animal Clinic**, Dr. Lund. Food: Paws & Co salmon kibble,
    2 cups a day.

    ## Vaccines

    | Vaccine | Last given | Next due |
    | --- | --- | --- |
    | Rabies (3-year) | 2024-03-15 | **2027-03** |
    | DHPP | 2026-03-17 | **2027-03** |
    | Leptospirosis | 2026-03-17 | 2027-03 |
    | Bordetella | 2026-03-17 | 2027-03 (only if boarding) |

    ## Visits

    | Date | Why | Cost | Notes |
    | --- | --- | --- | --- |
    | 2024-03-15 | Annual exam, rabies (3-yr), DHPP | $186 | |
    | 2025-03-20 | Annual exam | $198 | slightly overweight; less kibble |
    | 2026-03-17 | Annual exam, DHPP, lepto, bordetella | $205 | |
    | 2026-06-23 | Ate a sock (Soren's) | $318.50 | induced vomiting; sock recovered |
    | 2026-07-01 | Recheck after the sock | $42 | fine |

    ## Incidents

    - Got out through the old back fence three times (2025 twice, 2026-01-18). Not since the new fence.
    - The sock. Socks now live in the hamper with a lid.
    """)


def main():
    README(); people(); calendar(); journal(); trips(); pets()
    for k, v in RECIPES.items():
        w(f"life/recipes/{k}.md", v)
    for k, v in BOOKS.items():
        w(f"life/books/{k}.md", v)
    for k, v in SCHOOL.items():
        w(f"life/school/{k}.md", v)
    for k, v in SMALL_GROUP.items():
        w(f"life/small-group/{k}.md", v)


if __name__ == "__main__":
    main()
