"""Generate the messy CSVs for the household-hard vault.

Writes:
  finance/data/transactions.csv  date,description,merchant,category,amount,account,notes
  finance/data/net-worth.csv     month,cash,brokerage,retirement,college_529,home_equity,debts,net_worth
  finance/data/giving.csv        date,recipient,amount,method,fund,notes
  health/data/activities.csv     date,person,type,distance_mi,minutes,notes

Deterministic (fixed seeds). Event lists (maintenance, visits, giving, large
purchases) are module-level so the note generators reuse the same numbers.
"""
import csv
import datetime as dt
import os
import random

from common import VAULT

D = dt.date.fromisoformat
START, END = D("2024-01-01"), D("2026-10-31")

# ---------------------------------------------------------------- event lists
# (date, what, who, cost, notes) -- every row also becomes a transaction unless
# merchant is None. Costs are totals paid.
MAINT = [
    ("2024-01-16", "Furnace annual service", "Ridgeline Heating & Air", 139.00, "Filter replaced. Tech said the igniter is original (1998) and 'on borrowed time'."),
    ("2024-03-09", "Gutter cleaning, front and back", "Clearflow Gutters", 210.00, ""),
    ("2024-04-20", "Roof moss treatment, north slope", "Mossaway Roof Care", 385.00, "Zinc strips added along the ridge. They did not comment on the roof's age."),
    ("2024-06-12", "AC tune-up", "Ridgeline Heating & Air", 119.00, ""),
    ("2024-07-19", "Exterior repaint, whole house", "Bright Line Painting", 7350.00, "Paid $2,000 deposit 2024-06-20 and $5,350 on completion. Colors in [projects history](projects-history.md)."),
    ("2024-09-05", "Dishwasher drain pump replaced", "Appliance Doc Repair", 248.00, "Kestrel KD-400 still fine otherwise. See [dishwasher](dishwasher.md)."),
    ("2024-10-14", "Sprinkler blowout", "Greenway Irrigation", 95.00, ""),
    ("2024-11-02", "Chimney sweep", "Top Hat Chimney", 245.00, "Crown looked fine."),
    ("2025-01-15", "Furnace annual service", "Ridgeline Heating & Air", 149.00, ""),
    ("2025-03-22", "Gutter cleaning", "Clearflow Gutters", 225.00, ""),
    ("2025-05-03", "Hall bathroom exhaust fan replaced", "DIY (Erik)", 96.40, "Fan from Hardware Hub."),
    ("2025-06-17", "AC tune-up", "Ridgeline Heating & Air", 129.00, ""),
    ("2025-08-09", "Six deck boards replaced", "DIY (Erik and Leif)", 312.55, "Boards and screws from Ridgeway Lumber."),
    ("2025-09-20", "Garage door opener replaced", "Summit Overhead Doors", 545.00, "Belt-drive opener; old chain unit died."),
    ("2025-10-13", "Sprinkler blowout", "Greenway Irrigation", 99.00, ""),
    ("2025-11-18", "All seven smoke detectors replaced", "DIY (Erik)", 214.30, "10-year sealed units from Hardware Hub."),
    ("2026-01-14", "Furnace annual service", "Ridgeline Heating & Air", 149.00, "Filter replaced, flame sensor cleaned."),
    ("2026-02-10", "No-heat call, furnace", "Ridgeline Heating & Air", 289.00, "No-show on 02-09; next day replaced a pressure switch and billed two hours. We are done with Ridgeline; see journal 2026-02-11."),
    ("2026-02-22", "Garbage disposal replaced (1/2 HP)", "DIY (Erik)", 189.00, "Parts from Hardware Hub."),
    ("2026-03-30", "Gutter cleaning, front and back", "Clearflow Gutters", 225.00, "Downspout by garage re-attached."),
    ("2026-05-09", "Water heater replaced (50-gal gas)", "Barlow Plumbing", 1850.00, "Old tank was 14 years old and leaking. See [water heater](water-heater.md)."),
    ("2026-06-18", "AC tune-up", "Fairbanks Heating & Cooling", 135.00, "First visit with Fairbanks. Condenser coil cleaned."),
    ("2026-07-14", "Old refrigerator hauled away; new one installed", "Valley Appliance", 0.00, "Haul-away and install were included in the $1,899 price; see [the new fridge](refrigerator-corvell.md)."),
    ("2026-07-26", "Dishwasher door gasket replaced", "Appliance Doc Repair", 165.00, "Was leaking onto the floor."),
    ("2026-08-15", "Sprinkler valve repair, zone 3", "Greenway Irrigation", 240.00, "Valve solenoid replaced."),
    ("2026-08-19", "Back fence built (cedar, 168 ft, two gates)", "Hollis Fence Co.", 9830.00, "$9,450 bid plus a $380 change order for the wider side gate. See [fence project](fence-project.md)."),
    ("2026-09-12", "Garage door torsion springs replaced", "Summit Overhead Doors", 310.00, "Both springs as a pair."),
    ("2026-10-03", "Kitchen faucet leak fixed", "Barlow Plumbing", 185.00, "Cartridge replaced."),
    ("2026-10-28", "Chimney sweep and inspection", "Top Hat Chimney", 275.00, "Small mortar crack on the crown; re-inspect spring 2027."),
    ("2026-10-30", "Furnace annual service + hot-surface igniter replaced", "Fairbanks Heating & Cooling", 412.00, "Igniter was the 1998 original. Parts warranty 1 year."),
]

# transactions for maintenance rows: (date, merchant alias, amount) -- some rows
# are split into deposit/final or paid elsewhere, so list explicitly.
MAINT_TX = [
    ("2024-01-16", "RIDGELINE HEATING & AIR", 139.00),
    ("2024-03-09", "CLEARFLOW GUTTERS", 210.00),
    ("2024-04-20", "MOSSAWAY ROOF CARE", 385.00),
    ("2024-06-12", "RIDGELINE HEATING & AIR", 119.00),
    ("2024-06-20", "BRIGHT LINE PAINTING", 2000.00),
    ("2024-07-19", "BRIGHT LINE PAINTING", 5350.00),
    ("2024-09-05", "APPLIANCE DOC REPAIR", 248.00),
    ("2024-10-14", "GREENWAY IRRIGATION", 95.00),
    ("2024-11-02", "TOP HAT CHIMNEY", 245.00),
    ("2025-01-15", "RIDGELINE HEATING & AIR", 149.00),
    ("2025-03-22", "CLEARFLOW GUTTERS", 225.00),
    ("2025-05-03", "HARDWARE HUB #08", 96.40),
    ("2025-06-17", "RIDGELINE HEATING & AIR", 129.00),
    ("2025-08-09", "RIDGEWAY LUMBER", 312.55),
    ("2025-09-20", "SUMMIT OVERHEAD DOORS", 545.00),
    ("2025-10-13", "GREENWAY IRRIGATION", 99.00),
    ("2025-11-18", "Hardware Hub", 214.30),
    ("2026-01-14", "RIDGELINE HEATING & AIR", 149.00),
    ("2026-02-10", "RIDGELINE HEATING & AIR", 289.00),
    ("2026-02-22", "HDWR HUB ALDER CRK", 189.00),
    ("2026-03-30", "CLEARFLOW GUTTERS", 225.00),
    ("2026-05-09", "BARLOW PLUMBING", 1850.00),
    ("2026-06-18", "FAIRBANKS HEATING & COOLING", 135.00),
    ("2026-07-26", "APPLIANCE DOC REPAIR", 165.00),
    ("2026-08-15", "GREENWAY IRRIGATION", 240.00),
    ("2026-09-12", "SUMMIT OVERHEAD DOORS", 310.00),
    ("2026-10-03", "BARLOW PLUMBING", 185.00),
    ("2026-10-28", "TOP HAT CHIMNEY", 275.00),
    ("2026-10-30", "FAIRBANKS HEATING & COOLING", 412.00),
]

# The fence: what fence-project.md says counts toward the project total.
FENCE_TX = [
    ("2026-03-24", "Cedar & Sons Fencing - deposit", "CEDAR & SONS FENCING", 1000.00, ""),
    ("2026-05-29", "REFUND Cedar & Sons Fencing deposit", "CEDAR & SONS FENCING", -1000.00, "deposit returned"),
    ("2026-06-10", "HOLLIS FENCE CO deposit", "HOLLIS FENCE CO", 2000.00, ""),
    ("2026-08-19", "Hollis Fence Company progress pmt", "Hollis Fence Company", 4000.00, ""),
    ("2026-08-22", "RIDGEWAY LUMBER fence stain + brushes", "RIDGEWAY LUMBER", 186.40, ""),
    ("2026-08-29", "RIDGEWAY LUMBER fence stain 2nd coat", "RIDGEWAY LUMBER", 92.37, ""),
    ("2026-09-02", "HOLLIS FENCE CO PMT final", "HOLLIS FENCE CO", 3830.00, ""),
]
# Ridgeway purchases that are NOT fence (trap rows)
RIDGEWAY_OTHER = [("2026-08-25", 58.12, "garden bed boards"), ("2026-09-19", 41.80, "deck screws")]

LARGE = [  # date, item, vendor, amount, where noted
    ("2024-07-19", "Exterior repaint (whole house)", "Bright Line Painting", 7350.00),
    ("2025-04-02", "Grandpa E.'s hospital bill (our gift toward his deductible)", "Mercy Valley Hospital", 1250.00),
    ("2025-08-14", "Leif's braces (24-month contract, $600 down + $200/month)", "Brightview Orthodontics", 5400.00),
    ("2025-09-20", "Garage door opener", "Summit Overhead Doors", 545.00),
    ("2025-12-02", "Laptop for Anna's bookkeeping", "Tech Depot", 1240.00),
    ("2026-02-03", "Norway flights (Erik + Leif)", "Nordlys Air", 2960.00),
    ("2026-04-17", "2022 Subaru Outback (used)", "Valley Subaru", 27400.00),
    ("2026-05-09", "Water heater", "Barlow Plumbing", 1850.00),
    ("2026-07-12", "Refrigerator, Corvell CF-3400", "Valley Appliance", 1899.00),
    ("2026-08-19", "Back fence", "Hollis Fence Co.", 9830.00),
]

# health visits that cost us something (copay), for transactions
COPAYS = [
    ("2024-10-03", "ALDER CREEK PEDIATRICS", 25.00),
    ("2025-02-19", "BRIGHT SMILE DENTAL", 45.00),
    ("2025-07-22", "RIDGECREST URGENT CARE", 75.00),
    ("2026-02-27", "RIDGECREST URGENT CARE", 75.00),
    ("2026-04-21", "LITTLE OAKS PEDIATRIC DENT", 68.00),
    ("2026-08-12", "CASCADE ORTHOPEDICS", 50.00),
    ("2026-08-21", "ALDER CREEK PEDIATRICS", 25.00),
    ("2026-10-22", "CASCADE ORTHOPEDICS", 50.00),
]

PET_VET = [  # date, alias, amount, note
    ("2024-03-15", "JUNIPER ANIMAL CLINIC", 186.00, ""),
    ("2025-03-20", "Juniper Animal Clinic PC", 198.00, ""),
    ("2026-03-17", "JUNIPER ANIMAL CLINIC", 205.00, ""),
    ("2026-06-23", "JUNIPER ANIMAL CLINIC", 318.50, ""),
    ("2026-07-01", "Juniper Animal Clinic PC", 42.00, ""),
]

# giving.csv rows: date, recipient, amount, method, fund, notes
def giving_rows():
    rows = []
    for y, amt in ((2024, 1300), (2025, 1350), (2026, 1400)):
        for m in range(1, 13):
            if y == 2026 and m > 10:
                break
            rows.append((f"{y}-{m:02d}-05", "Hillcrest Bible Church", amt, "ACH", "General (tithe)", ""))
    for y, amt in ((2024, 250), (2025, 300), (2026, 300)):
        for m in (3, 6, 9, 12):
            if y == 2026 and m == 12:
                continue
            rows.append((f"{y}-{m:02d}-20", "Hillcrest Bible Church", amt, "Online", "Missions Fund", ""))
    rows += [
        ("2024-05-11", "Harbor House Pregnancy Center", 150, "Check", "", "spring banquet"),
        ("2024-12-08", "Hillcrest Bible Church", 400, "Online", "Christmas outreach", ""),
        ("2024-12-14", "Alder Creek Food Pantry", 250, "Card", "", ""),
        ("2025-05-10", "Harbor House Pregnancy Center", 150, "Check", "", "spring banquet"),
        ("2025-06-07", "Alder Creek Food Pantry", 200, "Card", "", ""),
        ("2025-11-22", "Alder Creek Food Pantry", 500, "Card", "", "Thanksgiving matching drive"),
        ("2025-12-07", "Hillcrest Bible Church", 500, "Online", "Christmas outreach", ""),
        ("2026-03-28", "Alder Creek Food Pantry", 300, "Card", "", ""),
        ("2026-04-12", "Hillcrest Bible Church", 150, "Online", "Youth camp scholarships", ""),
        ("2026-05-09", "Harbor House Pregnancy Center", 200, "Check", "", "spring banquet"),
        ("2026-09-12", "Alder Creek Food Pantry", 200, "Card", "", ""),
    ]
    rows.sort()
    return rows


GIVING = giving_rows()


# ---------------------------------------------------------------- transactions
def months():
    y, m = 2024, 1
    while (y, m) <= (2026, 10):
        yield y, m
        m += 1
        if m == 13:
            y, m = y + 1, 1


def day(y, m, d_):
    import calendar
    last = calendar.monthrange(y, m)[1]
    return dt.date(y, m, min(d_, last))


def build_transactions():
    r = random.Random(20261105)
    T = []

    def add(date, desc, merchant, cat, amt, acct, notes=""):
        if isinstance(date, dt.date):
            date = date.isoformat()
        T.append([date, desc, merchant, cat, round(amt, 2), acct, notes])

    def grocery_cat():
        x = r.random()
        return "Groceries" if x < 0.84 else ("groceries" if x < 0.92 else "Grocery")

    FB = ["FRESH BASKET #212", "Fresh Basket Market", "FRESHBASKET ONLINE"]
    HH = ["HARDWARE HUB #08", "Hardware Hub", "HDWR HUB ALDER CRK"]
    DINING = ["Pinecone Pizza", "TAQUERIA SOL", "Ridge Burger", "Fresh Bake Co.", "Golden Lotus Noodle"]
    GAS = ["ALDER FUEL", "RIDGE FUEL STOP"]
    SHOP = ["Northgate Books", "River Outfitters", "Tech Depot", "Kidsville Toys", "Thread & Needle"]

    for y, m in months():
        # fixed bills
        mort = 2264.00 if (y, m) >= (2026, 4) else 2180.00
        add(day(y, m, 1), "Columbia Home Lending - mortgage", "COLUMBIA HOME LENDING", "Mortgage", mort, "Summit Checking")
        winter = m in (11, 12, 1, 2, 3)
        add(day(y, m, 15), "ALDER CREEK PUD electric", "ALDER CREEK PUD", "Utilities",
            r.uniform(150, 215) if winter else r.uniform(88, 130), "Summit Checking")
        add(day(y, m, 18), "Cascadia Natural Gas", "CASCADIA NATURAL GAS", "Utilities",
            r.uniform(110, 165) if winter else r.uniform(34, 58), "Summit Checking")
        if m % 2 == 1:
            add(day(y, m, 22), "City of Alder Creek water/sewer", "CITY OF ALDER CREEK", "Utilities", r.uniform(128, 166), "Summit Checking")
        add(day(y, m, 9), "Ridgewire Internet", "RIDGEWIRE INTERNET", "Utilities", 75.00 if y == 2024 else 80.00, "Summit Visa")
        add(day(y, m, 12), "Pinewave Mobile", "PINEWAVE MOBILE", "Utilities", 118.00 if y == 2024 else 124.00, "Summit Visa")
        # auto insurance
        if (y, m) <= (2025, 11):
            add(day(y, m, 5), "Cascade Mutual auto", "CASCADE MUTUAL INS", "Insurance", 148.00 if y == 2024 else 155.00, "Summit Checking")
        else:
            add(day(y, m, 5), "Timberline Mutual auto", "TIMBERLINE MUTUAL", "Insurance", 145.00, "Summit Checking")
        # kids
        if (y, m) >= (2024, 9):
            add(day(y, m, 3), "Alder Creek Music Studio - piano (Greta)", "ALDER CREEK MUSIC STUDIO", "Kids",
                130.00 if (y, m) < (2025, 9) else 140.00, "Summit Visa")
        if (y, m) >= (2025, 9):
            add(day(y, m, 15), "Brightview Orthodontics monthly", "BRIGHTVIEW ORTHO", "Medical", 200.00, "Summit Checking")
        add(day(y, m, 7), "STREAMFLIX", "STREAMFLIX", "Subscriptions", 15.49 if y < 2026 else 17.99, "Summit Visa")
        add(day(y, m, 21), "Hearthsong Music", "HEARTHSONG", "Subscriptions", 10.99, "Summit Visa")
        if m in (3, 6, 9, 12):
            add(day(y, m, 2), "Juniper Lane HOA dues", "JUNIPER LANE HOA", "Home", 90.00, "Summit Checking")
        add(day(y, m, 6), "Paws & Co dog food", "PAWS & CO", "Pets", r.choice([58.99, 62.49, 64.99, 71.25]), "Summit Visa")

        # groceries: Fresh Basket ~weekly on Saturdays
        first = day(y, m, 1)
        sat = first + dt.timedelta(days=(5 - first.weekday()) % 7)
        while sat.month == m:
            alias = r.choices(FB, weights=[6, 3, 1])[0]
            acct = "Summit Visa" if (y, m) < (2025, 6) or r.random() < 0.5 else "Evergreen Card"
            add(sat, f"POS {alias} ALDER CREEK OR" if alias.isupper() else alias, alias, grocery_cat(),
                r.uniform(138, 262), acct)
            sat += dt.timedelta(days=7)
        # Lakeside Warehouse twice a month, often split
        for dd in (r.randint(2, 13), r.randint(16, 27)):
            total = r.uniform(170, 330)
            date = day(y, m, dd)
            if r.random() < 0.55:
                g = round(total * r.uniform(0.6, 0.75), 2)
                add(date, "LAKESIDE WHSE #44", "Lakeside Warehouse", grocery_cat(), g, "Summit Visa", "split receipt 1/2")
                add(date, "LAKESIDE WHSE #44", "Lakeside Warehouse", "Household", round(total - g, 2), "Summit Visa", "split receipt 2/2")
            else:
                add(date, "LAKESIDE WHSE #44", "Lakeside Warehouse", grocery_cat(), total, "Summit Visa")
        for _ in range(r.randint(1, 3)):
            alias = r.choices(FB, weights=[6, 3, 1])[0]
            add(day(y, m, r.randint(1, 28)), alias, alias, grocery_cat(), r.uniform(18, 64), "Summit Visa")
        add(day(y, m, r.randint(8, 26)), "Valley Co-op", "VALLEY CO-OP", grocery_cat(), r.uniform(38, 92), "Summit Visa")
        if r.random() < 0.35:
            alias = r.choice(FB)
            add(day(y, m, r.randint(2, 27)), f"REFUND {alias}", alias, grocery_cat(), -r.uniform(4.5, 31), "Summit Visa", "return")

        # dining
        for _ in range(r.randint(5, 8)):
            name = r.choice(DINING)
            cat = "Restaurants" if y == 2024 else "Dining"
            amt = r.uniform(9, 24) if name == "Fresh Bake Co." else r.uniform(18, 88)
            add(day(y, m, r.randint(1, 28)), name, name, cat, amt, "Summit Visa")
        # gas
        for _ in range(r.randint(3, 5)):
            g = r.choice(GAS)
            add(day(y, m, r.randint(1, 28)), g, g, "Gas", r.uniform(36, 72), "Summit Visa")
        # shopping
        for _ in range(r.randint(3, 5)):
            s = r.choice(SHOP)
            add(day(y, m, r.randint(1, 28)), s, s, "Shopping", r.uniform(14, 140), "Summit Visa")
        # hardware hub incidental
        for _ in range(r.randint(0, 2)):
            h = r.choice(HH)
            add(day(y, m, r.randint(1, 28)), h, h, "Home", r.uniform(9, 88), "Summit Visa")
        if r.random() < 0.18:
            h = r.choice(HH)
            add(day(y, m, r.randint(1, 28)), f"RETURN {h}", h, "Home", -r.uniform(8, 46), "Summit Visa", "return")

    # one-off events
    for date, alias, amt in MAINT_TX:
        add(date, alias, alias if alias != "Hardware Hub" else "Hardware Hub", "Home", amt, "Summit Visa" if amt < 1000 else "Summit Checking")
    for date, desc, merch, amt, note in FENCE_TX:
        add(date, desc, merch, "Home", amt, "Summit Checking", note)
    for date, amt, note in RIDGEWAY_OTHER:
        add(date, f"RIDGEWAY LUMBER {note}", "RIDGEWAY LUMBER", "Home", amt, "Summit Visa")
    for date, alias, amt in COPAYS:
        add(date, alias, alias, "Medical", amt, "Summit Visa")
    for date, alias, amt, note in PET_VET:
        add(date, alias, alias, "Pets", amt, "Summit Visa", note)
    for date, rec, amt, method, fund, note in GIVING:
        acct = "Summit Checking" if method in ("ACH", "Check", "Online") else "Summit Visa"
        add(date, f"{rec}{' - ' + fund if fund else ''}", rec.upper(), "Giving", amt, acct)
    # insurance annual premiums
    add("2024-12-12", "Cascade Mutual homeowners renewal", "CASCADE MUTUAL INS", "Insurance", 1420.00, "Summit Checking")
    add("2025-12-08", "Timberline Mutual homeowners", "TIMBERLINE MUTUAL", "Insurance", 1612.00, "Summit Checking")
    add("2025-12-08", "Timberline Mutual umbrella", "TIMBERLINE MUTUAL", "Insurance", 285.00, "Summit Checking")
    for y in (2024, 2025, 2026):
        add(f"{y}-03-02", "Pinewood Life - Erik term", "PINEWOOD LIFE", "Insurance", 690.00, "Summit Checking")
        add(f"{y}-03-02", "Pinewood Life - Anna term", "PINEWOOD LIFE", "Insurance", 310.00, "Summit Checking")
    # large purchases and specials
    add("2025-04-02", "MERCY VALLEY HOSPITAL pmt (Dad)", "MERCY VALLEY HOSPITAL", "Medical", 1250.00, "Summit Checking", "gift toward Grandpa E.'s deductible")
    add("2025-08-14", "Brightview Orthodontics down pmt", "BRIGHTVIEW ORTHO", "Medical", 600.00, "Summit Checking")
    add("2025-12-02", "Tech Depot laptop", "Tech Depot", "Shopping", 1240.00, "Summit Visa")
    add("2026-02-03", "NORDLYS AIR 2 tickets PDX-OSL", "NORDLYS AIR", "Travel", 2960.00, "Summit Visa")
    add("2026-03-10", "Fjordgard Guesthouse deposit", "FJORDGARD GUESTHOUSE", "Travel", 640.00, "Summit Visa")
    add("2026-06-25", "NORDLYS AIR bag fee", "NORDLYS AIR", "Travel", 85.00, "Summit Visa")
    add("2026-04-17", "VALLEY SUBARU 2022 Outback", "VALLEY SUBARU", "Auto", 21200.00, "Summit Checking", "plus $6,200 from the Camry sale")
    add("2026-07-12", "VALLEY APPLIANCE refrigerator", "VALLEY APPLIANCE", "Home", 1899.00, "Summit Visa")
    add("2026-07-03", "Glacier NP campground", "RECREATION RESERVATIONS", "Travel", 168.00, "Summit Visa")
    add("2026-10-06", "Firehole Cabins deposit", "FIREHOLE CABINS", "Travel", 450.00, "Summit Visa", "Yellowstone")
    add("2026-09-14", "Alder Creek MS orchestra fee (Leif)", "ALDER CREEK SCHOOL DIST", "Kids", 85.00, "Summit Visa")
    add("2025-09-15", "Alder Creek MS orchestra fee (Leif)", "ALDER CREEK SCHOOL DIST", "Kids", 80.00, "Summit Visa")
    add("2026-09-10", "Cascade Aquatic Center 10-swim pass", "CASCADE AQUATIC CTR", "Health", 65.00, "Summit Visa")
    add("2026-10-19", "Cascade Aquatic Center 10-swim pass", "CASCADE AQUATIC CTR", "Health", 65.00, "Summit Visa")
    add("2026-08-18", "Summit Peak CU overdraft fee", "SUMMIT PEAK CU", "Fees", 35.00, "Summit Checking", "dispute - see open items")

    T.sort(key=lambda x: (x[0], x[2], x[4]))
    # duplicates: copy some rows, flag most of them
    pool = [t for t in T if t[3] in ("Groceries", "groceries", "Grocery", "Dining", "Restaurants", "Home", "Gas", "Shopping")
            and t[4] > 0 and "split" not in t[6] and t[2] not in ("HOLLIS FENCE CO", "Hollis Fence Company", "CEDAR & SONS FENCING")]
    dups = r.sample(pool, 22)
    flags = ["duplicate import", "DUP - ignore", "dup of row above", "duplicate (bank re-sent)"]
    for t in dups:
        c = list(t)
        c[6] = r.choice(flags)
        T.append(c)
    T.sort(key=lambda x: (x[0], x[2], x[4], x[6]))
    return T


# ---------------------------------------------------------------- activities
def build_activities():
    r = random.Random(4417)
    A = []

    def add(date, person, typ, dist, mins, notes=""):
        A.append([date.isoformat(), person, typ, "" if dist is None else f"{dist:.1f}", mins, notes])

    d0 = D("2024-06-03")  # Monday
    while d0 <= END:
        wk = [d0 + dt.timedelta(days=i) for i in range(7)]
        def ok(x):
            return x <= END
        if d0 < D("2025-01-01"):
            # building back up: 3 runs, 1 strength, Sunday walk
            for i, lo, hi in ((1, 3.0, 4.2), (3, 3.0, 4.5), (5, 5.0, 7.0)):
                if ok(wk[i]) and r.random() < 0.9:
                    dist = r.uniform(lo, hi); add(wk[i], "Erik", "run", dist, int(dist * r.uniform(9.0, 9.8)))
            if r.random() < 0.6:
                add(wk[0], "Erik", "strength", None, r.randint(30, 40))
        elif d0 < D("2025-10-13"):
            # half-marathon year: 4 runs, 1 strength
            for i, lo, hi in ((1, 4.0, 5.5), (2, 3.5, 5.0), (3, 4.0, 6.0), (5, 7.0, 11.5)):
                if ok(wk[i]) and r.random() < 0.88:
                    dist = r.uniform(lo, hi); add(wk[i], "Erik", "run", dist, int(dist * r.uniform(8.4, 9.2)))
            if r.random() < 0.7:
                add(wk[4], "Erik", "strength", None, r.randint(30, 40))
        elif d0 < D("2026-01-05"):
            # post-race drift: 2 runs
            for i in (2, 5):
                if r.random() < 0.8:
                    dist = r.uniform(3, 5); add(wk[i], "Erik", "run", dist, int(dist * r.uniform(9.0, 9.8)))
        elif d0 < D("2026-08-10"):
            # 3 runs + 2 strength
            for i, lo, hi in ((1, 3.0, 4.5), (3, 3.0, 4.5), (5, 5.5, 7.5)):
                if r.random() < 0.9:
                    dist = r.uniform(lo, hi); add(wk[i], "Erik", "run", dist, int(dist * r.uniform(9.1, 9.9)))
            for i in (0, 4):
                if r.random() < 0.85:
                    add(wk[i], "Erik", "strength", None, r.randint(35, 45))
        elif d0 < D("2026-09-14"):
            if d0 == D("2026-08-10"):
                add(wk[0], "Erik", "run", 2.1, 21, "left Achilles sore, stopped early")
            for i in (0, 4):
                if wk[i] != D("2026-08-10") and ok(wk[i]):
                    add(wk[i], "Erik", "strength", None, r.randint(30, 40), "upper body only" if d0 < D("2026-08-24") else "")
        else:
            # revised goal from 2026-09-08: 2 runs (<=30 min) + 2 strength + 1 swim
            for i in (1, 5):
                if ok(wk[i]) and r.random() < 0.9:
                    mins = r.randint(24, 30); add(wk[i], "Erik", "run", mins / r.uniform(9.6, 10.4), mins)
            for i in (0, 4):
                if ok(wk[i]) and r.random() < 0.9:
                    add(wk[i], "Erik", "strength", None, r.randint(35, 45))
            if ok(wk[3]) and r.random() < 0.9:
                add(wk[3], "Erik", "swim", None, r.randint(25, 35))
        # Sunday family walk
        if ok(wk[6]) and r.random() < 0.55:
            dist = r.uniform(1.5, 3.0); add(wk[6], "Erik", "walk", dist, int(dist * 20))

        # Erik Sr.: from 2025-05 after knee rehab
        if d0 >= D("2025-05-05"):
            for i in (0, 2, 4, 5):
                if ok(wk[i]) and r.random() < 0.62:
                    who = "Grandpa E." if r.random() < 0.12 else "Erik Sr."
                    dist = r.uniform(1.2, 2.4) if d0 < D("2025-09-01") else r.uniform(1.8, 3.2)
                    add(wk[i], who, "walk", dist, int(dist * r.uniform(21, 25)))
            if d0 >= D("2025-09-01") and ok(wk[3]) and r.random() < 0.7:
                dist = r.uniform(5, 9); add(wk[3], "Erik Sr.", "bike", dist, int(dist * 5.5))
            if d0 >= D("2026-08-17") and ok(wk[1]) and r.random() < 0.85:
                dist = r.uniform(1.4, 2.0); add(wk[1], "Erik Sr.", "run", dist, int(dist * 15), "jog/walk intervals")
        d0 += dt.timedelta(days=7)

    # the half marathon itself (Sunday)
    add(D("2025-10-12"), "Erik", "run", 13.1, 113, "Alder Creek Half - 1:52:40")
    # Erik copied a batch of Dad's September 2026 walks from his watch by hand
    for row in A:
        if row[1] == "Erik Sr." and row[2] == "walk" and row[0].startswith("2026-09") and int(row[0][-2:]) % 2 == 0:
            row[1] = "Grandpa E."
    A.sort(key=lambda x: (x[0], x[1], x[2]))
    return A


# ---------------------------------------------------------------- net worth
def build_networth():
    r = random.Random(77)
    rows = []
    cash, brok, ret, c529, eq, debt = 52000, 182000, 268000, 38000, 268000, 21800
    for y, m in months():
        cash += r.uniform(-900, 2100)
        if (y, m) == (2024, 7):
            cash -= 7350
        if (y, m) == (2026, 4):
            cash -= 21200
        if (y, m) == (2026, 8):
            cash -= 6000
        if (y, m) == (2026, 9):
            cash -= 3830
        brok *= 1 + r.uniform(-0.025, 0.03); brok += 500
        ret *= 1 + r.uniform(-0.022, 0.028); ret += 1400 if y < 2026 else 1750
        c529 *= 1 + r.uniform(-0.02, 0.025); c529 += 450
        eq += r.uniform(600, 1500)
        debt = max(0, debt - 410) if (y, m) != (2026, 4) else debt
        nw = cash + brok + ret + c529 + eq - debt
        rows.append([f"{y}-{m:02d}", round(cash), round(brok), round(ret), round(c529), round(eq), round(debt)])
    for row in rows:
        row.append(sum(row[1:6]) - row[6])
    return rows


def write_csv(rel, header, rows):
    path = os.path.join(VAULT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        wr = csv.writer(f)
        wr.writerow(header)
        for row in rows:
            wr.writerow([f"{c:.2f}" if isinstance(c, float) else c for c in row])


def main():
    T = build_transactions()
    write_csv("finance/data/transactions.csv", ["date", "description", "merchant", "category", "amount", "account", "notes"], T)
    write_csv("finance/data/giving.csv", ["date", "recipient", "amount", "method", "fund", "notes"],
              [[a, b, f"{c:.2f}", d_, e, f] for a, b, c, d_, e, f in GIVING])
    write_csv("finance/data/net-worth.csv", ["month", "cash", "brokerage", "retirement", "college_529", "home_equity", "debts", "net_worth"], build_networth())
    write_csv("health/data/activities.csv", ["date", "person", "type", "distance_mi", "minutes", "notes"], build_activities())
    return T


if __name__ == "__main__":
    T = main()
    print(len(T), "transactions")
