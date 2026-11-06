"""Builds the Berean Standard Bible knowledge pack: one Markdown note per chapter.

  python3 packs/bsb/build.py [--bsb data/bsb.txt] [--headings headings.json] [--out DIR]
  then: mackb pack install DIR && mackb pack index bsb && mackb pack on bsb

Reads (from Lawrence's website repo by default; nothing is downloaded):
- BSB: bsb.txt, the official tab-separated text from BereanBible.com
  ("Genesis 1:1<TAB>In the beginning…"). Public domain since 2023-04-30
  (https://berean.bible/licensing.htm).
- HEADINGS: headings.json, the BSB section headings by chapter
  ({"John.3": [[verse, "Heading", level], …]}), keyed by OSIS id in canonical
  order, which is also the order books appear in bsb.txt.

Writes OUT/pack.json and OUT/notes/NN Book/Book C.md. Each chapter note has a
frontmatter title like "John 3 — BSB", the section headings as "## …", and
verses as "**16** For God so loved…", so a search passage carries its chapter
and section and an answer can cite chapter and verse. Stdlib only.
"""
import argparse, json, pathlib, re

LWN = pathlib.Path.home() / "github/lawrencewu-net"
BSB = LWN / "data/bsb.txt"
HEADINGS = LWN / "apps/web/bible/data/headings.json"
OUT = pathlib.Path.home() / "Library/Application Support/MacKB/packs/bsb"

MANIFEST = {
    "id": "bsb",
    "name": "Berean Standard Bible",
    "cite": "BSB",
    "version": "BSB text from BereanBible.com (bsb.txt)",
    "license": "Public domain (dedicated 2023-04-30)",
    "attribution": "The Holy Bible, Berean Standard Bible, BSB. Produced in cooperation with Bible Hub, Discovery Bible, "
                   "unfoldingWord, Bible Aquifer, OpenBible.com, and the Berean Bible Translation Committee.",
    "source": "https://berean.bible",
    "description": "The whole Bible, one note per chapter, with section headings and verse numbers.",
}

REF = re.compile(r"^(.+?) (\d+):(\d+)$")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bsb", type=pathlib.Path, default=BSB)
    ap.add_argument("--headings", type=pathlib.Path, default=HEADINGS)
    ap.add_argument("--out", type=pathlib.Path, default=OUT)
    a = ap.parse_args()

    chapters = {}   # (book, chapter) -> [(verse, text)]
    books = []      # book names in order
    for line in a.bsb.read_text(encoding="utf-8-sig").splitlines():
        if "\t" not in line:
            continue
        ref, text = line.split("\t", 1)
        m = REF.match(ref.strip())
        if not m:
            continue
        book, c, v = m.group(1), int(m.group(2)), int(m.group(3))
        if book not in books:
            books.append(book)
        chapters.setdefault((book, c), []).append((v, text.strip()))

    heads = json.loads(a.headings.read_text())
    osis = []
    for k in heads:
        b = k.rsplit(".", 1)[0]
        if b not in osis:
            osis.append(b)
    if len(osis) != len(books):
        raise SystemExit(f"{len(books)} books in the BSB text but {len(osis)} in the headings; can't line them up")
    to_osis = dict(zip(books, osis))

    notes = a.out / "notes"
    notes.mkdir(parents=True, exist_ok=True)
    n = 0
    for (book, c), verses in chapters.items():
        bi = books.index(book) + 1
        hs = {h[0]: (h[1], h[2]) for h in heads.get(f"{to_osis[book]}.{c}", [])}  # a 4th item (Song of Songs speakers) is ignored
        lines = ["---", f'title: "{book} {c} — BSB"', f'book: "{book}"', f'chapter: "{c}"', 'pack: "bsb"', "---",
                 f"# {book} {c}", ""]
        para = []
        for v, text in sorted(verses):
            if v in hs:
                if para:
                    lines += [" ".join(para), ""]
                    para = []
                t, lvl = hs[v]
                lines += [("## " if lvl <= 1 else "### ") + t, ""]
            para.append(f"**{v}** {text}")
        if para:
            lines += [" ".join(para), ""]
        d = notes / f"{bi:02d} {book}"
        d.mkdir(exist_ok=True)
        (d / f"{book} {c}.md").write_text("\n".join(lines), encoding="utf-8")
        n += 1
    (a.out / "pack.json").write_text(json.dumps(MANIFEST, indent=2, sort_keys=True) + "\n")
    print(f"wrote {n} chapters of {len(books)} books to {a.out}")


if __name__ == "__main__":
    main()
