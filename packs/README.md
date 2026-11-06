# Knowledge packs

Read-only reference collections that Holdfast searches beside your own notes:
a Bible, a wiki, a manual. Each pack lives in
`~/Library/Application Support/MacKB/packs/<id>/`, shared by every vault:

```
packs/<id>/
  pack.json            id, name, cite (short label), version, license, attribution, source, description
  notes/…/*.md         the text, as Markdown notes
  index.sqlite         its own search index (index-embeddinggemma.sqlite for that embedder)
enabled.json           which packs Search and Ask use
```

- Switch packs on and off in Library → Knowledge Packs, or `mackb pack on|off <id>`.
  `MACKB_PACKS=bsb,…` (or `none`) overrides for one command (evals, scripts).
- Search ranks the vault and each pack on its own, then merges the lists; the
  reranker sorts the merged passages. Passages from a pack are cited as
  `pack:<id>/…`, and their titles carry the pack's label ("John 3 — BSB").
- Packs are never edited, filed into, or used as "related notes" when filing.
- Only build packs from text whose license allows keeping a copy, and keep
  the attribution the license asks for in `pack.json`.

## Packs

| Pack | Build | Source and license |
| --- | --- | --- |
| `bsb` Berean Standard Bible | `python3 packs/bsb/build.py` (reads `~/github/lawrencewu-net/data/bsb.txt` and the reader's `headings.json`; nothing is downloaded) | BereanBible.com; public domain since 2023-04-30 |

Then: `mackb pack install <folder>` (the BSB builder writes straight into place),
`mackb pack index <id>`, `mackb pack on <id>`.

## A pack from files you have

Any folder of saved web pages (`.webarchive`, `.html`), PDFs, Word files or
Markdown becomes a pack, converted the way Bulk Import's "Bring in as-is" works:

```
mackb pack create <id> --name "…" --cite "…" --license "…" --attribution "…" --source <url> <files or folders…>
mackb pack index <id>
mackb pack on <id>
```

### Bogleheads wiki

Not built automatically. The wiki sits behind a Cloudflare bot check, and its
robots.txt reserves AI training (`ai-train=no`) and blocks AI crawlers, so
Holdfast does not crawl it. Its content license wasn't confirmed from the site
itself (a third-party catalog lists CC BY-SA 4.0); check the wiki's footer
before sharing a pack with anyone. For a personal pack, save the pages you
use from Safari (File → Save As → Web Archive) into a folder, then:

```
mackb pack create bogleheads --name "Bogleheads wiki (saved pages)" --cite Bogleheads \
  --license "as stated on bogleheads.org" --attribution "Bogleheads® wiki contributors" \
  --source https://www.bogleheads.org/wiki <folder>
```
