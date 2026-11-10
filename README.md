# Holdfast

*Your notes never leave home.* One name throughout: the app (Holdfast.app, bundle id
`net.lawrencewu.holdfast`), the `holdfast` command line, `HOLDFAST_*` settings and the data folder
(`~/Library/Application Support/Holdfast`). The About box carries 1 Thessalonians 5:21.
It was called mackb (MacKB) as a proof of concept; on first run Holdfast moves that name's
settings, data folder and a managed vault's `.mackb` folder over, still reads `MACKB_*` variables,
and keeps using a default vault at `~/MacKB` if there is one.

A local knowledge base for **biblical counselors**: import lessons, homework sheets,
supervision recordings and past case reports, then search and ask questions of them
with citations. Everything runs on the Mac, because case material is confidential.
Nothing is sent to a cloud service.

This is the Phase 0–3 proof of concept from the Holdfast plan (kept in a
separate notes repo). One binary is the CLI, the MCP server and a SwiftUI
window: `holdfast app`, or `scripts/make_app.sh` → `build/Holdfast.app`.

The **Paper & Pine** interface uses warm reading surfaces and evergreen accents in light and
dark mode. Its sidebar has Ask, Library, Inbox and Listen. Library's view picker switches between
Notes, Folders, Tables and Graph; Ask's recent questions and **All conversations** open saved
conversations. **Focus** hides the browser while reading; **Note Details** opens the outline and
linked notes. Source rows can preview the full passage, and **Answer details** reveals model and
generation statistics. The bound-page H icon is drawn from `Sources/holdfast/AppIcon.swift` for
both the app and its packaged icon.

## What it does

| Command | What happens |
| --- | --- |
| `holdfast ingest <folder>` | `.docx/.doc/.rtf` via `textutil`, `.pdf` via PDFKit, scanned PDFs via Apple Vision OCR, `.md/.txt` as-is. When a lesson exists as both docx and pdf, only one copy is kept |
| `holdfast ingest <audio/video>` | ffmpeg → 16 kHz → **Parakeet v3** (FluidAudio, CoreML) → a note with `[hh:mm:ss]` lines |
| `holdfast ingest <YouTube URL>` | yt-dlp; uses the video's captions when there are any, otherwise transcribes the audio |
| `holdfast listen -` · `--url <stream>` · `--mic` | Transcribes audio while it streams in (below). Finished `[hh:mm:ss]` lines go to stdout as they become final (`--json` for events); Ctrl-C stops, and the transcript is kept and filed like a dropped document |
| `holdfast index` | Chunks each note on headings and timestamps; SQLite FTS5 + **Qwen3-Embedding-0.6B** vectors (in-process, MLX Swift). Only changed notes are re-indexed |
| `holdfast search "…"` | Retrieval pipeline below |
| `holdfast ask "…"` | The top 8 passages go to the answer model (MLX in-process by default, a model on another Mac, or Ollama; thinking off unless Show Thinking is on). The answer cites `[n]`, and each source prints as `[[note#anchor]]` |
| `holdfast app` | The window: Ask (cited answers; click a source to open it), Library (browse and search), Inbox (approve or reject agent memories), and a reader that jumps to the cited section |
| `holdfast eval` | Scores Q&A against a question set; see `eval/README.md` |
| `holdfast mcp` | MCP server: `search`, `get_note`, `ask`, `remember`, `list_inbox` |
| `holdfast drop [file…]` | Files what is in the drop folder. In a vault indexed in place, the model reads each file (PDF, Word, Markdown, images by on-device OCR, recordings by transcription) and the folder READMEs, and proposes a new note or a row for an existing log; the proposal waits in the inbox. In a managed vault the file is imported as a source. Originals move to `drop-filed/` in the app's state folder, never into the vault. The app watches the same folder (Vault › Open Drop Folder, ⇧⌘D) and has a drop zone on the Inbox page |
| `holdfast ask "mark … done"` | A request to change a note ("mark …", "tick off …", "add … to …", "update …") runs as Research with one more tool, `propose_edit`: the model reads the note and proposes replacing the exact text. Nothing changes until the proposal is approved in the Inbox (below) |
| `holdfast inbox / approve / reject` | Memories that agents propose wait here for approval. Each one is checked for full names, emails and phone numbers first |

**Retrieval** (`Sources/holdfast/Index.swift`, tuning constants in `enum Retrieval`), following
the open-source survey in the kb repo (`projects/202611_holdfast/oss-best-practices.md`):

1. **Read the question.** "First session", "session 4", "final session", "graduation",
   or "second joint session" (from the form header) become session filters. "Across
   sessions" or "over the course of" turn on spread mode.
2. **Find candidates.** 60 passages from FTS5 BM25 and Qwen3-Embedding vectors, merged with
   reciprocal rank fusion. Each passage starts with a label (title › date › session
   kind › form question), so both searches see which session it is from.
3. **Rerank** with **Qwen3-Reranker-0.6B** (MLX, in-process). If the best score is
   below 0.08, the direct answer declines without calling the LLM; in the app the router then
   escalates to Research (search, read notes, query tables) before saying the notes don't cover it.
4. **Select.** Drop passages scoring under half the best. Cap each note at 2, except
   that a note holding 3 of the top 5 gets 5. Add the neighbours of the top 2 hits.
   Merge neighbouring passages. In spread mode, take the best 1–2 per session and
   send them in session order.
5. **Answer.** 8 passages go to Qwen 3.8 27B. `[n]` markers that point at no passage
   are flagged.

The vault is plain Markdown with YAML frontmatter (`$HOLDFAST_VAULT`, default
`~/Holdfast`): `sources/`, `memory/`, `inbox/`. It opens in Obsidian. The index in
`.holdfast/` is a cache; delete it and run `holdfast index` again.

## Household eval (synthetic)

`eval/household/` is a made-up family's knowledge base (finance, home, health,
trips, career, and counseling case reports under `ministry/`) with 40 questions
and 12 documents to file. `eval/household/run.sh` runs it across answer models
(Qwen 3.8 27B, Gemma 4 26B A4B, Gemma 4 E4B), embedders (Qwen3-Embedding,
EmbeddingGemma) and modes (plain, Research), plus Gemini when `GEMINI_API_KEY`
is set; `report.py` writes `report.md`. Pick models with `HOLDFAST_BACKEND`,
`HOLDFAST_MLX_REPO`, `HOLDFAST_EMBED=embeddinggemma`, `HOLDFAST_RERANK=0`, and fix the
date with `HOLDFAST_TODAY=2026-11-05`.

## Build

MLX compiles Metal shaders, so build with `xcodebuild`, not `swift build`.
It needs the Metal Toolchain once (`xcodebuild -downloadComponent MetalToolchain`).

```bash
xcodebuild -scheme holdfast -destination 'platform=macOS' -configuration Release \
  -derivedDataPath .build/xcode -skipMacroValidation -skipPackagePluginValidation build
ln -sf "$PWD/.build/xcode/Build/Products/Release/holdfast" ~/.local/bin/holdfast
```

The LLM is `HOLDFAST_BACKEND=mlx` (Qwen 3.8 27B 4-bit loaded in-process from the
Hugging Face cache, `HOLDFAST_MLX_REPO`) or `ollama` (`HOLDFAST_LLM`). Audio and URLs also need `ffmpeg` and `yt-dlp`.

## Use from Claude Code

```bash
claude mcp add holdfast -e HOLDFAST_VAULT=$HOME/Holdfast-ministry -- ~/.local/bin/holdfast mcp
```

## Measured on an M1 Max, 64 GB (2026-11-04)

| What | Result |
| --- | --- |
| Import a counseling lesson library (403 docs) | 385 notes in 3 min (OCR included); 18 docx/pdf duplicates skipped; 3 image-only docx with no text |
| Index 394 notes → 3,109 chunks with embeddings | 5.6 min, 1.3 GB peak memory |
| Parakeet v3 transcription | 142× real time (1 h of audio ≈ 25 s) after a one-time model download |
| Qwen 3.8 27B (Ollama, 29 GB 8-bit GGUF) | ~5 tok/s generation, 80–240 tok/s prompt; a cited answer takes ~2–2.5 min |
| Retrieval | ~3 s, mostly loading the embedding model; then milliseconds |

**Speed is the main problem.** Generation is limited by memory bandwidth: 29 GB of
weights at the M1 Max's ~400 GB/s gives about 5 tok/s. A 4-bit build (about 16 GB:
`mlx-community/Qwen3.8-27B-4bit`, or a Q4 GGUF) should roughly double that. A smaller
Qwen would be faster still.

## Not done yet

- Keep Word headings and tables on import (Docling or a Swift OOXML reader) instead of the "?"-line heuristic; sqlite-vec
- Per-session summaries and a per-case timeline written at import, for questions across sessions
- Claim-level faithfulness and citation-precision scores in the eval; a bigger question set
- Faster prompt reading on MLX (prompt caching, MTP)
- Batched embeddings (currently one passage at a time); a background job queue
- Case-report templates (ACBC structure: data gathering, problem, hope, plan, homework)
  so questions can filter by section

## Live transcription (`holdfast listen`)

Transcribes audio as it arrives, on this Mac, with the same Parakeet model as recordings
(FluidAudio's sliding-window manager: 15 s windows, 2 s before, an 11 s chunk, 2 s after).
A line is printed once its words can no longer change, about 10–25 s after they were spoken.

```bash
holdfast listen --app zoom --mic --title "Elders meeting"     # both sides of a call
holdfast listen --system                                      # everything the Mac plays
holdfast listen --url https://example.org/live/stream.m3u8 --title "Sunday livestream"
ffmpeg -i <anything> -f s16le -ar 16000 -ac 1 - | holdfast listen - --json
```

- **In:**
  - `--app <name>` taps one app's audio (Zoom, Teams, Chrome, FaceTime…; helper processes included),
    `--system` everything the Mac plays. Add `--mic` to mix in the default microphone, which a call
    needs for your side. Core Audio process taps (macOS 14.2+) in a private aggregate device
    (`SystemAudio.swift`); no screen recording. `--apps` lists apps that have opened audio. `--mute`
    keeps the tapped audio off the speakers while it is transcribed.
  - `--url` takes anything ffmpeg opens (HLS, RTMP, Icecast, a file; `--realtime` plays a file at speed).
  - `-` reads raw 16 kHz mono s16le from stdin, so any program that makes audio can feed it.
  - `--mic` alone uses the default input through AVAudioEngine.
- **In the app:** the Listen page (sidebar, or Vault › Listen…, ⇧⌘R) picks the same sources, shows
  lines as they become final with words still settling in grey, and a red "Listening" badge stays
  in the sidebar on other pages. Stop keeps everything heard; the transcript is listed under Recent
  transcripts and handed to the drop folder, so the Inbox shows the model's filing proposal (or why
  it skipped it). Choices are remembered.
- **Permissions:** Holdfast's Info.plist says why it records audio (`NSAudioCaptureUsageDescription`,
  `NSMicrophoneUsageDescription`), so macOS asks Holdfast once. macOS won't ask on behalf of a
  terminal that doesn't declare this, and a tap without permission gives silence, so from the command
  line `--app`/`--system` runs the capture inside Holdfast.app (`open -n -g -W`, output passed back
  through FIFOs, Ctrl-C forwarded) unless the terminal already has System Audio Recording. The check
  and request use the private TCC calls AudioCap uses. Ad-hoc signing means each rebuild asks again.
- **Calls:** a transcript records everyone on the call; ask them first (California needs everyone's
  consent to record a confidential conversation). Headphones keep the other side out of your microphone.
- **Out:** finished lines on stdout; with `--json`, `line`, `partial` (words that may still change)
  and `done` events, one per line. Progress goes to stderr.
- **When it ends** (end of stream, `--seconds N`, or Ctrl-C): the whole transcript is kept in the
  state folder's `listening/` (and `--out file.md`), then filed like a dropped document: a proposal in
  the Inbox in a vault indexed in place, a source note in a managed vault. `--no-file` skips filing.

Measured 2026-11-07 on a 54 s synthetic speech (macOS `say`): every line arrived with the right
timestamp, and the words matched the script except punctuation at two window seams; piped in at full
speed it finished in 30 s including model load; over HLS served by HTTP and with Ctrl-C mid-stream it
kept everything heard; 20 s of silence saved nothing. App and system audio (2026-11-07, speech
played by ffmpeg into a virtual output device so nothing reached the speakers): `--app ffmpeg` and
`--system`, each run inside Holdfast.app after its permission prompt, transcribed all of it with
timestamps; a tap also catches audio sent to a non-default device. The Listen page did the same
live, with the sidebar badge, Stop, and filing (the model skipped it as already recorded, and said
why in the Inbox). Not tested: `--mic` and the microphone mixed into a call (not run, to avoid
recording the room), `--mute`, and a real Zoom or Teams call.

## Changing notes from Ask

Ask a change instead of a question ("mark 'Protect pretax 401(k) basis' as done", "add the 11/3
dentist visit to the dental log"). The model reads the note and calls `propose_edit` with the exact
text to replace and its replacement; nothing in the vault changes then. The change waits in the
Inbox showing the removed and added lines; **Apply Change** writes the note after keeping a copy,
and undo (`holdfast undo`, the filing log) puts that copy back. A note changed after the proposal
is refused rather than overwritten, a second change to the same note in a conversation joins the
first proposal, files with a `> GENERATED` banner are refused (change the script instead), and only
`.md` and `.txt` notes can be changed this way. Changes to counseling notes run on this Mac only,
like any request that touches them.

## Keeping records safe

- **Backup** (Settings → Vault → Backups, Vault › Back Up Now ⌥⌘B, `holdfast backup <folder>`):
  a dated folder `Holdfast <vault> <date time>` with the vault (without `.git` and search
  indexes), Holdfast's records for it (versions, filing log, history, kept originals,
  transcripts, rules), the app's settings, a README on restoring, and `manifest.json` with every
  file's SHA-256. Verify (`--verify <backup>`) re-reads every file; Test Restore
  (`--test-restore <backup>`) restores into a temporary folder, checks every file, opens every
  note and the history and filing log, then removes the copy. A folder inside the vault is
  refused. Back up to another drive; an encrypted one if the vault holds counseling notes.
- **Originals** beside their notes: approving a filing copies the document it came from into
  `originals-raw/<the note's folder>/` (the folder ignores itself in git, and `-raw` folders are
  never indexed) and links it under "## Originals"; the note's toolbar has Open Original, and
  undo removes both. `holdfast originals [--apply]` keeps and links the originals of earlier
  filings that are still in the drop-filed folder.
- **Export** (Vault › Export Notes… ⇧⌘E, `holdfast export --query … --folder … --out x.zip`):
  notes found by a question and/or a folder, ticked off in a list, with the originals they link to,
  a README and a checksum manifest; the ZIP is unpacked and checked after it's built. Counseling
  notes are left out unless included on purpose.
- **Pins**: Pin on an answer keeps its question on the Ask home page, one click to ask again
  (right-click to unpin).

## Which model (`holdfast models`)

Holdfast recommends an answer model from its own household eval: answers, hard questions with
Research, filing (right place, facts kept, privacy slips), peak memory and speed, measured on an
M1 Max. The pick is the best-scoring model that fits the Mac's memory (the eval's rule: the GPU
gets about 2/3 of RAM, 4 GB stays for macOS), with a faster one beside it when it's at least 2×
faster and within 15 points. It shows on the first-run card and at the top of Settings → Answer
model (with Download / Use), and `holdfast models [--ram GB] [--json]` prints the whole table, e.g.
`--ram 256` for a Mac Studio. The list in Settings is the same catalog, best first. The numbers
live in `Sources/holdfast/ModelCatalog.swift`, generated by `eval/household/catalog.py` from the
saved results: run more evals, then the script. Weights and thresholds are constants at the top of
`Recommend.swift`.

## A model on another Mac

Holdfast can send its questions to a model served by another Mac (say a Mac Studio)
while the vault, the index and search stay on this one. On the other Mac run LM Studio
(port 1234), `mlx_lm.server` (8080) or Ollama (11434) with its server on; in Holdfast,
model menu → Another Mac → Set Up…, enter its address (its Tailscale name keeps the
traffic encrypted), Connect, pick the model. Research's tools still run here; only the
model's decisions come over the network. If that Mac doesn't answer, this Mac's model
answers instead and the steps say so. CLI: `HOLDFAST_BACKEND=remote HOLDFAST_REMOTE_URL=http://studio:1234 HOLDFAST_REMOTE_MODEL=<id>`.

## Privacy, in one place

- Everything runs on this Mac by default: the vault, its index, search, and the answer model.
- With **a model on another Mac**, the vault, index and search stay here; the other Mac receives
  each question with the passages found, the conversation so far, folder READMEs, Research's note
  reads and table results, documents dropped for filing, and note pairs when suggesting links.
  **Counseling notes never leave this Mac**: anything involving them is answered here instead.
  The app's labels switch from "nothing leaves this Mac" to "sent to <host>" while it's in use.
- Link import (YouTube, podcasts) fetches from the web by design. The Gemini backend exists for
  evals on synthetic data only and isn't offered in the app.
