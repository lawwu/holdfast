"""Drops (documents to file) and filing.json for household-hard. Numbers here are fake."""
import json
import os

from common import ROOT, d

CASES = []


def case(cid, fname, convert, action, path, facts, forbid, text):
    d(fname, text)
    CASES.append({"id": cid, "file": f"drops/{fname}", "convert": convert, "expect_action": action,
                  "expect_path": path, "expect_facts": facts, "forbid": forbid})


def warranty_booklet():
    sections = []
    boiler = [
        ("IMPORTANT SAFETY INSTRUCTIONS", "Read all instructions before using this appliance. This refrigerator must be properly installed and located in accordance with these instructions before it is used. Do not allow children to climb, stand or hang on the doors or shelves. Never clean refrigerator parts with flammable fluids. Keep fingers out of pinch-point areas; clearances between the doors and cabinet are necessarily small. Unplug the refrigerator before cleaning or making repairs. If the power cord is damaged, it must be replaced by the manufacturer, its service agent or a similarly qualified person. Do not use an extension cord. Child entrapment and suffocation are not problems of the past: junked or abandoned refrigerators are still dangerous. Before you throw away your old refrigerator, take off the doors and leave the shelves in place."),
        ("INSTALLATION", "Allow 1/2 inch of clearance on each side and at the top, and 1 inch behind the unit, for air circulation. Do not install where the temperature will fall below 55°F or rise above 110°F. The floor must be strong enough to support a fully loaded refrigerator, about 700 pounds. Level the refrigerator side to side and front to back by turning the leveling legs. The front should be slightly higher than the back so the doors close easily. Connect the water line using 1/4-inch copper or the supplied PEX tubing; do not use plastic tubing without a reinforced braid. Flush the water system by dispensing 3 gallons before first use. Discard the first three batches of ice."),
        ("USING THE CONTROLS", "The control panel is inside the fresh-food compartment at the top. Recommended settings are 37°F for the fresh-food compartment and 0°F for the freezer. Allow 24 hours for temperatures to stabilize after any change. Turbo Cool lowers the fresh-food temperature quickly after a large grocery load and turns off automatically after 6 hours. Vacation Mode raises the fresh-food setting to 55°F to save energy; do not store perishable food while it is on. The Door Alarm sounds after the door has been open 60 seconds; press and hold Alarm for 3 seconds to silence it permanently."),
        ("THE ICE MAKER AND DISPENSER", "The ice maker produces about 3.5 pounds of ice per day. It will not produce ice until the freezer reaches 10°F. If the ice maker does not run, check that the feeler arm is in the down position and that the water supply valve is open. Do not use the dispenser to crush ice cream or frozen food. Hollow or small cubes usually mean low water pressure or a clogged filter; replace the filter first. To reset the ice maker, press and hold the test button for 3 seconds. Empty the ice bucket before long absences."),
        ("STORAGE TIPS", "Store meat and fish in the lower crisper set to Meat. Store vegetables in the upper crisper set to Produce. Butter keeps best in the covered dairy bin. Do not overload door bins; they are rated for 15 pounds each. Allow air to circulate around food. Hot food may be placed in the refrigerator after it has cooled for 30 minutes. Freezer: wrap food in moisture-proof material to avoid freezer burn. Do not refreeze thawed food."),
        ("CLEANING", "Clean the interior every few months with a solution of 2 tablespoons baking soda in 1 quart warm water. Do not use abrasive cleaners, bleach or cleaners containing ammonia on the fingerprint-resistant stainless finish; use a soft cloth and mild dish soap. Vacuum the condenser coils behind the toe grille once a year, more often with pets. The door gaskets can be cleaned with mild soap and warm water; dry thoroughly. Shelves are tempered glass; let them reach room temperature before washing in warm water."),
        ("NORMAL SOUNDS", "Your new refrigerator may make sounds your old one did not. A high-pitched whine or pulsating sound is the variable-speed compressor adjusting to cool efficiently. Clicking is the defrost timer or the water valve. Gurgling is refrigerant flowing. Popping is contraction and expansion of the inside walls. A buzzing sound may be heard when the water valve opens to fill the ice maker. Water dripping on the defrost heater can cause a sizzling sound. None of these sounds indicate a problem."),
        ("TROUBLESHOOTING", "Refrigerator does not operate: check the plug, the household fuse or breaker, and whether the unit is in Showroom Mode (press Freezer and Fresh Food together for 5 seconds to exit). Temperature too warm: the doors may be opened too often, the door gaskets may not seal, or the coils may be dirty. Frost or ice crystals on frozen food: the door may have been left ajar. Water on the floor: the drain pan may be cracked or the water line connection loose. Water has poor taste: replace the filter. Dispenser slow: low household water pressure (below 40 psi) or a clogged filter. If the problem persists, call Corvell Service before scheduling any outside repair; unauthorized repairs may void the warranty."),
    ]
    for i, (h, t) in enumerate(boiler, 1):
        sections.append(f"--- page {i} ---\n\n{h}\n\n{t}\n\n{t.split('. ')[0]}. (See also the Quick Start card included in the literature pack.)")
    end = """--- page 9 ---

WATER FILTER

Use only genuine Corvell CWF-9 filters. Replace the filter every 6 months, or sooner if
the filter indicator turns red or water flow decreases. To replace: turn the old filter a
quarter turn counter-clockwise, pull out, insert the new filter and turn clockwise until it
locks. Dispense 2 gallons to flush. Reset the indicator by holding Filter for 3 seconds.

--- page 10 ---

CORVELL LIMITED WARRANTY — MODEL CF-3400

Keep your sales receipt; proof of the original purchase date is needed for warranty service.

FIRST YEAR — From the date of original purchase, Corvell will repair or replace any part
of the refrigerator that fails because of a defect in materials or workmanship, and pay
all labor and in-home service.

SECOND THROUGH FIFTH YEAR — SEALED SYSTEM. For five (5) years from the date of original
purchase, Corvell will repair or replace, parts AND labor, any part of the sealed
refrigerating system (the compressor, evaporator, condenser, dryer and connecting tubing)
that fails because of a defect in materials or workmanship.

SIXTH THROUGH TENTH YEAR — LINEAR INVERTER COMPRESSOR. For ten (10) years from the date of
original purchase, Corvell will provide a replacement compressor (PART ONLY) if the
compressor fails because of a defect. In years 6 through 10 the owner pays labor and
in-home service.

NOT COVERED: water filters; light bulbs; service calls to teach you how to use the
product; damage from improper installation, accident, fire, flood or acts of God; food
loss; commercial use.

Registration (detach and mail, or register online within 60 days of purchase):

  Model: CF-3400        Serial: CV34-26-0712-8841
  Purchased: 2026-07-12 at Valley Appliance, Alder Creek OR
  Owner: Anna Halvorsen   Phone: 541-555-0123   Email: anna.halvorsen.test@example.com
"""
    return "CORVELL FRENCH-DOOR REFRIGERATOR — USE & CARE GUIDE AND WARRANTY\nModels CF-3400 / CF-3400S\n\n" + "\n\n".join(sections) + "\n\n" + end


def main():
    case("f01", "fairbanks-corrected-invoice-2026-10-30.txt", "pdf", "append", "^home/maintenance-log\\.md$",
         ["2026-10-30", "Fairbanks", "\\$?386(\\.00)?", "correct"], ["4417", "FHC-?20931", "1418"], """
        FAIRBANKS HEATING & COOLING
        Alder Creek, Oregon

        *** CORRECTED INVOICE ***   Invoice FHC-20931-C
        This invoice replaces invoice FHC-20931 dated 2026-10-30.

        Customer: Erik Halvorsen, 1418 Juniper Lane, Alder Creek OR
        Service date: 2026-10-30   Technician: R. Molina

        Furnace annual service (clean, inspect, filter)          $129.00
        Hot-surface igniter, replaced (part)                      $214.00
        Labor, igniter replacement (0.5 hr)                        $69.00
        Original total                                            $412.00
        Returning-customer discount (omitted in error)            -$26.00
        CORRECTED TOTAL                                           $386.00

        Paid 2026-10-30: $412.00, Visa ending 4417.
        Refund of $26.00 issued to the same card on 2026-11-03.
        Parts warranty on the igniter: 1 year.
        """)
    case("f02", "timberline-homeowners-renewal-2026.txt", "pdf", "append", "^finance/policies\\.md$",
         ["Timberline", "\\$?1,?688", "2027-12-15|Dec(ember)?\\.? 15,? 2027"], ["5520", "918-?44", "HO-?TM"], """
        TIMBERLINE MUTUAL INSURANCE
        Homeowners Policy Renewal Declaration

        Named insured: Erik and Anna Halvorsen
        Policy number: HO-TM-5520-918-44
        Policy period: 2026-12-15 to 2027-12-15

        Coverage A — Dwelling            $575,000 (was $560,000; inflation guard)
        Coverage E — Liability           $300,000
        Deductible                       $2,500
        Water backup endorsement         included

        Renewal premium                  $1,688.00 (prior term $1,612.00)
        Payment due 2026-12-15. Your umbrella and auto policies renew separately.
        """)
    case("f03", "cascade-mutual-we-miss-you.txt", "none", "skip", ".*", [], ["77310", "CM-?HO"], """
        CASCADE MUTUAL — We miss you, Erik!

        It's been almost a year since you left us. Come back and save: bundle home and auto
        for as little as $2,140 a year*. Your former policy CM-HO-77310 can be reinstated with
        your loyalty history intact. Call your Alder Creek agent today.

        *Rates vary. Offer ends 2026-12-31.
        """)
    case("f04", "little-oaks-receipt-2026-11-02.txt", "png", "new", "^health/visits/2026-11-02_(greta|soren)_[a-z0-9-]+\\.md$",
         ["2026-11-02", "Little Oaks"], ["88231457", "4417", "NHP"], """
        LITTLE OAKS PEDIATRIC DENTISTRY — Receipt
        Date of service: 2026-11-02     Guarantor: Anna Halvorsen
        Insurance: Northstar Dental, subscriber ID NHP-88231457

        Patient: Greta Halvorsen (9)
          Periodic exam, cleaning, fluoride varnish ........ covered
          Notes: no new cavities; last spring's filling looks good.
        Patient: Soren Halvorsen (5)
          Periodic exam, cleaning, fluoride varnish ........ covered
          Sealant, lower left first molar (the "watch" spot) $85.00
          Notes: sealant placed rather than waiting; recheck in 6 months.

        Patient portion paid: $85.00, Visa ending 4417
        Next visits: both children, May 2027
        """)
    case("f05", "jp-case-report-session-5.txt", "docx", "new", "^ministry/counseling/jp/jp-session-0?5\\.md$",
         ["2026-11-03", "money meeting", "J\\.P\\."], ["Jared", "Pellham", "Corinne", "Hannah"], """
        Case Report — Jared Pellham — Session 5

        Date: 2026-11-03 · Session: 5 · Length of Session: 60 minutes

        What was gained by performing the homework from last session? What change?
        Jared and Corinne held their first weekly money meeting on Sunday, 2026-11-01, at the
        kitchen table. Jared led it with the written agenda. They opened and closed in prayer.
        Corinne said it was "the first money conversation in years that didn't end in a fight."
        The receipts envelope worked. Anger log: two entries, both mild. Ephesians 4:29 memorized.
        Their daughter Hannah (14) asked why they were "having a meeting about money" and they
        told her the truth, briefly.

        What homework was given?
        1. Second weekly money meeting; add a short look at the debt-repayment chart.
        2. Begin Proverbs 21:5 study: diligent plans vs. haste.
        3. Anger log continues.
        4. Plan one inexpensive date with Corinne this month.

        Goal for next session: the root of hiding — fear of being seen as a poor provider.
        """)
    case("f06", "text-soren-tooth.txt", "png", "skip", "^life/journal/2026-10-30\\.md$", [], [], """
        Messages — Anna
        Fri, Oct 30, 6:42 PM

        Anna: SOREN LOST HIS TOOTH
        Anna: in the corn on the cob!!!
        Erik: no way. bottom front?
        Anna: yes. he is vibrating. tooth fairy tonight
        Erik: on my way home, 10 min
        """)
    case("f07", "alder-creek-elementary-winter-flyer.txt", "png", "append", "^life/calendar\\.md$",
         ["2026-11-19|Nov(ember)?\\.? 19", "2026-12-10|Dec(ember)?\\.? 10"], [], """
        ALDER CREEK ELEMENTARY — Coming Up!

        PICTURE RETAKE DAY — Thursday, November 19, 2026
        Bring your proof envelope if you want retakes. Morning only.

        WINTER CONCERT, Grades K–5 — Thursday, December 10, 2026, 6:30 pm, school gym
        Kindergarten sings first! Students arrive by 6:00 in dark pants and a bright top.

        Questions? Call the front office.
        """)
    case("f08", "becca-wild-rice-soup.txt", "none", "new", "^life/recipes/[a-z0-9-]*wild-rice[a-z0-9-]*\\.md$",
         ["wild rice", "Becca"], ["555-0199", "becca\\.lindqvist"], """
        From: Becca Lindqvist <becca.lindqvist.test@example.com>
        Subject: the soup!

        Anna — here's the wild rice soup from Sunday. Call me if anything's unclear (541-555-0199).

        Chicken & Wild Rice Soup (serves 8)
        - 1 cup wild rice, rinsed
        - 2 tbsp butter, 1 onion, 2 carrots, 2 celery stalks, diced
        - 3 cloves garlic
        - 6 cups chicken stock
        - 2 cups shredded cooked chicken
        - 1 cup half-and-half, 3 tbsp flour
        - thyme, salt, pepper

        Simmer the wild rice in the stock 45 minutes. Meanwhile soften the vegetables in butter,
        add garlic. Stir the flour into the half-and-half, add everything to the pot with the
        chicken and simmer 10 more minutes until thick. Better the next day.
        — Becca
        """)
    case("f09", "summit-peak-statement-oct-2026.txt", "pdf", "append", "^finance/(statements/2026\\.md|open-items\\.md)$",
         ["9,?412", "\\$?35", "revers|refund|credit"], ["0049221077315", "221077315", "323075880", "7315"], """
        SUMMIT PEAK CREDIT UNION — Checking Statement
        Member: Erik and Anna Halvorsen
        Account number: 0049221077315     Routing: 323075880
        Statement period: 2026-10-01 to 2026-10-31

        Beginning balance                     $8,604.55
        Deposits and credits                 $14,880.40
        Withdrawals and debits              -$14,072.77
        Ending balance                        $9,412.18

        Notable items:
        2026-10-01  Columbia Home Lending          -$2,264.00
        2026-10-05  Hillcrest Bible Church ACH     -$1,400.00
        2026-10-29  COURTESY REVERSAL - OD FEE 08/18   +$35.00
        """)
    case("f10", "cascade-orthopedics-statement-leif.txt", "pdf", "append",
         "^(finance/open-items\\.md|health/visits/2026-10-22_leif_cascade-orthopedics\\.md)$",
         ["\\$?145", "2026-11-30|Nov(ember)?\\.? 30"], ["88231460", "5571923", "NHP"], """
        CASCADE ORTHOPEDICS — Patient Statement
        Patient: Leif Halvorsen     Guarantor: Erik Halvorsen
        Account: CO-5571923        Insurance: Northstar Health Plan, member ID NHP-88231460

        Date of service 2026-10-22 — office visit, wrist X-ray (3 views), wrist brace
        Charges                    $410.00
        Insurance paid            -$215.00
        Copay paid at visit        -$50.00
        BALANCE DUE                $145.00   Please pay by 2026-11-30.
        """)
    case("f11", "corvell-cf3400-use-care-warranty.txt", "pdf", "append", "^home/refrigerator-corvell\\.md$",
         ["5[- ]year|five", "10[- ]year|ten", "compressor"], ["555-0123", "anna\\.halvorsen\\.test@example\\.com"],
         warranty_booklet())
    case("f12", "texts-soren-bike.txt", "png", "new|append", "^life/journal/2026-11-04\\.md$",
         ["Soren", "training wheels|bike"], [], """
        Messages — Anna
        Wed, Nov 4, 4:18 PM

        Anna: SOREN. NO TRAINING WHEELS.
        Anna: down the whole block and back
        Erik: no way!!! video??
        Anna: sending. he crashed into the okafors hedge at the end but got right back on
        Erik: thats my boy. pizza tonight?
        Anna: obviously
        """)
    case("f13", "alder-creek-strings-viola-buyout.txt", "png", "append", "^finance/large-purchases\\.md$",
         ["\\$?640", "viola"], ["9902"], """
        ALDER CREEK STRINGS — Sales Receipt
        2026-11-01

        Rent-to-own buyout: 15.5" viola outfit (Leif Halvorsen account)
          Rental credit applied: 14 months
          Buyout price                    $640.00
        Paid: Summit Visa ending 9902

        Includes case, bow and rosin. Bow rehair free within 12 months.
        """)
    case("f14", "juniper-animal-clinic-2026-11-03.txt", "png", "append", "^life/pets/pepper\\.md$",
         ["2026-11-03", "\\$?164(\\.20)?", "ear"], ["4417", "JAC-?40021"], """
        JUNIPER ANIMAL CLINIC — Invoice
        Client: Anna Halvorsen (client ID JAC-40021)   Patient: Pepper (canine, lab mix)
        Date: 2026-11-03   Doctor: Dr. Lund

        Exam — head shaking, scratching right ear            $68.00
        Ear cytology                                          $46.00
        Otic ointment, 10-day course                          $50.20
        TOTAL                                                $164.20   Paid Visa ending 4417

        Diagnosis: right ear yeast infection. Recheck in 2 weeks if not resolved.
        Reminder: annual exam and DHPP due March 2027.
        """)
    case("f15", "willamette-heart-holter-results.txt", "pdf", "new",
         "^health/erik-sr/visits/2026-1[01]-\\d\\d_erik-sr_[a-z0-9-]+\\.md$",
         ["Holter", "PVC|premature"], ["00731188", "731188", "1954-03-08"], """
        WILLAMETTE HEART ASSOCIATES
        Results letter — 2026-11-02

        Patient: Erik Halvorsen Sr.     DOB: 1954-03-08     MRN: 00731188
        Physician: Farah Nadeem, MD

        Dear Mr. Halvorsen,

        The 48-hour Holter monitor you wore from 2026-10-27 to 2026-10-29 (ordered at your
        October 20 visit) showed normal sinus rhythm with occasional premature ventricular
        contractions (PVCs), under 1% of beats. There was no atrial fibrillation and no pauses.
        These findings are benign and do not change your plan: continue atorvastatin 40 mg
        and lisinopril. Please call if you notice fainting or a racing heartbeat.

        We will see you in April 2027 as planned.
        """)
    case("f16", "firehole-cabins-confirmation.txt", "pdf", "append", "^life/trips/202706_yellowstone/plan\\.md$",
         ["2027-07-11|July 11", "\\$?1,?650", "2027-06-11|June 11"], ["FC-?88412", "4417"], """
        FIREHOLE CABINS — West Yellowstone, Montana
        Reservation updated

        Guest: Erik Halvorsen     Confirmation: FC-88412
        Two-bedroom cabin, sleeps 6
        Arrive: Sunday, July 11, 2027 (check-in 4 pm)
        Depart: Friday, July 16, 2027 (check-out 10 am)   5 nights

        Total             $2,100.00
        Deposit paid        -$450.00 (Visa ending 4417, 2026-10-06; moved from your June dates)
        Balance due       $1,650.00 on 2027-06-11
        """)
    case("f17", "harbor-401k-q3-2026.txt", "pdf", "append", "^finance/statements/2026\\.md$",
         ["251,?380", "10 ?%"], ["4410-?2231-?90", "223190"], """
        HARBOR RETIREMENT SERVICES — Quarterly Statement
        Bluestem Logistics 401(k) Plan
        Participant: Erik Halvorsen      Account: 4410-2231-90
        Period: 2026-07-01 to 2026-09-30

        Beginning balance              $236,912.40
        Your contributions (10%)         $3,500.01
        Employer match (4%)              $1,400.00
        Investment gain                  $9,567.81
        Ending balance                 $251,380.22

        Investment: Target Date 2045 Fund (100%)
        """)
    case("f18", "leif-q1-progress-report.txt", "docx", "append", "^life/school/leif\\.md$",
         ["Q1|first quarter|quarter 1", "A-|B\\+"], ["118842"], """
        ALDER CREEK MIDDLE SCHOOL — Quarter 1 Progress Report, 2026–27
        Student: Leif Halvorsen   Grade 7   Student ID 2024-118842   Issued 2026-11-02

        Language Arts      A-   "Thoughtful writer; the Norway travel essay was outstanding."
        Math 7 Advanced    B+   "Careless errors on tests; strong on homework."
        Science            A
        Social Studies     A-
        Orchestra (viola)  A    "Section leader material."
        PE                 B+   (excused from soccer unit — wrist)

        Attendance: 0 absences, 1 tardy.
        """)
    case("f19", "hollis-fence-warranty-certificate.txt", "pdf", "append", "^home/fence-project\\.md$",
         ["2028-08-19", "2036|10[- ]year"], ["HF-?2026-?0817"], """
        HOLLIS FENCE CO. — Certificate of Warranty
        Job HF-2026-0817     Property: Halvorsen residence, Alder Creek
        Completion date: 2026-08-19

        WORKMANSHIP: Hollis Fence Co. warrants the installation against defects in workmanship
        for two (2) years from completion, through 2028-08-19, including gate sag and
        hardware adjustment.

        POSTS: Cedar posts set in concrete with gravel drainage are warranted against rot at
        the ground line for ten (10) years, through 2036-08-19 (materials and labor to replace
        any failed post).

        Not covered: damage from animals, vehicles, storms, or staining products not
        approved for cedar.
        """)
    case("f20", "food-pantry-receipt-2026-11-02.txt", "none", "append", "^finance/(giving\\.md|data/giving\\.csv)$",
         ["2026-11-02", "\\$?250", "Food Pantry"], ["4417"], """
        ALDER CREEK FOOD PANTRY — Thank you!

        Received from: The Halvorsen family
        Date: 2026-11-02
        Amount: $250.00 — Thanksgiving Drive
        Paid by Visa ending 4417

        No goods or services were provided in exchange for this gift.
        """)
    with open(os.path.join(ROOT, "filing.json"), "w") as f:
        json.dump(CASES, f, indent=1, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    main()
