# App and command-line guide

Detailed usage and development reference for [Holdfast](../README.md).
For installation and your first question, start with [Getting started](../Website/content/getting-started.md).

LocalMLX runs inside the Mac app by default. You can also choose Ollama, LM Studio, or a custom
model server. Notes covered by the private profile stay with LocalMLX on this Mac.

The app, command line, and MCP server share one binary: `holdfast app`, or
`scripts/make_app.sh` → `build/Holdfast.app`. Settings use `HOLDFAST_*` variables;
app data lives in `~/Library/Application Support/Holdfast`.

Choose the **Private notes** profile for an entire vault, or put restricted notes under a
top-level folder beginning with `private` or `confidential`. These notes use LocalMLX, are
excluded from automatic filing and cross-linking, and are left out of exports unless explicitly
included. Existing protected folders and saved settings remain supported through migration.

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
| `holdfast index` | Chunks each note on headings and timestamps; SQLite FTS5 + optional **Qwen3-Embedding-0.6B** vectors (in-process, MLX Swift). Re-indexes changed notes and fills missing embeddings |
| `holdfast search "…"` | Retrieval pipeline below |
| `holdfast ask "…"` | Pi searches and reads through Holdfast's tools, using LocalMLX by default or a selected server. Answers cite `[n]`, and each source prints as `[[note#anchor]]`; proposed edits wait in the Inbox |
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

**Settings → Search → Search by meaning** is on by default. Turning it off releases
the embedding model and keeps keyword search available; existing vectors and model
downloads are retained. Re-enabling prepares missing vectors for the current vault
and enabled reference collections, including notes indexed while it was off. The
reranker has its own setting and works with either search mode. CLI overrides
`HOLDFAST_EMBED=none` and `--no-embed` still work.

Check the preference and indexing transitions with
`python3 Tests/meaning_search_integration.py <holdfast-binary> --live` (uses the
installed embedding model and synthetic notes; omit `--live` for model-free checks).

The vault is plain Markdown with YAML frontmatter (`$HOLDFAST_VAULT`, default
`~/Holdfast`): `sources/`, `memory/`, `inbox/`. It opens in Obsidian. The index in
`.holdfast/` is a cache; delete it and run `holdfast index` again.

## Pi agent

**Regular Pi 1.5.1 is now Holdfast’s default Ask harness**, in the normal app and CLI.
It runs the tool loop and saves JSONL conversations for follow-ups. LocalMLX is the
independent default inference provider; Ollama, LM Studio and custom servers also work.
Holdfast owns tool execution, privacy, Inbox approvals, snapshots and Undo.

Three reusable packages live together in this repository:

| Package | Owns |
| --- | --- |
| [`ModelProviders`](../Packages/ModelProviders/README.md) | Shared inference types and Ollama, LM Studio, and custom HTTP providers; no external package dependencies |
| [`LocalMLX`](../Packages/LocalMLX/README.md) | Swift MLX inference and the `local-mlx-host` executable; depends on ModelProviders |
| [`pi-swift-mlx`](../Packages/pi-swift-mlx/README.md) | JavaScript adapter for regular Pi and Pi Durable; npm releases bundle Swift sources for standalone builds |

Holdfast's tools, privacy policy, Inbox approvals, snapshots, and Undo stay in the app.
Its integration uses `Runtime/pi`; Durable is no longer selected or bundled.

Build with `bash scripts/make_app.sh`, or create a separate artifact with
`bash scripts/make_pi_prototype.sh`. Node 22.19+ is required. There is no harness toggle
in Settings. `ask --conversation UUID` continues a chat; `--pi` remains an explicit alias.
See the [regular Pi bridge guide](../Runtime/pi/README.md) and
[HTML architecture guide](local-mlx-architecture.html).

Interrupted work waits for a new user request. Existing Durable SQLite records and pending
jobs are preserved under `pi-durable/` and are never replayed by the new runtime. Old app
conversations provide a short handoff; privacy and citation metadata carry forward.

## Native comparison runtime

The older Swift harness remains available for development with `HOLDFAST_AGENT_HARNESS=swift`. Its structure takes inspiration from [Pi's agent core](https://github.com/earendil-works/pi/tree/main/packages/agent)
and [Pennant's runtime](https://github.com/pennant-dev/pennant/blob/main/docs/ARCHITECTURE.md);
neither project is a dependency.

- `AgentRuntime.swift`: a model interface, explicit tool registry, full user/assistant/tool
  transcript, lifecycle events, argument validation, cancellation, and limits (8 tool rounds,
  at most 32 calls, then a final answer with tools disabled). A runtime session can accept later
  prompts with its tool history intact; overlapping runs are refused.
- `AgentModels.swift`: MLX keeps one `ChatSession` and its inference cache between steps;
  `ModelProviderSettings.swift` adapts the shared `ModelProviders` HTTP transport. Changing to the local model
  continues from completed tool results, including pending proposals, without repeating them.
- `Agent.swift`: Holdfast's six vault tools, source numbering and model-selection policy.
  Tool results can require local inference; once set, that restriction lasts for the whole
  runtime session. Private vaults start locally, and the folder overview omits private
  README excerpts. The registry exposes `propose_edit`; applying a change remains an Inbox action.
- `AgentJournal.swift`: each run has a private JSONL journal under the vault's state folder,
  `agent-runs/`. It records configuration, finalized model replies, tool intent and tool outcome
  with increasing sequence numbers. Token deltas are transient. Records include note text and
  stay on this Mac. A failed intent write prevents execution; an intent without an outcome is
  uncertain and is never automatically replayed.

This is the runtime foundation. Ask still seeds each request from its existing short history;
full transcript restoration in the UI, automatic compaction, steering, and crash-resume are not
implemented in the comparison harness. Regular Pi supplies persistent sessions and compaction;
it does not automatically replay interrupted jobs.
Both embedded and server providers stream tokens; each complete tool call is validated before execution.

Run the model-free runtime checks and, after building, the synthetic end-to-end check:

```bash
scripts/test_agent_runtime.sh
python3 Tests/agent_integration.py .build/xcode/Build/Products/Release/holdfast
```

The integration check starts a loopback model stand-in, creates a throwaway vault, tests a bad
call followed by a corrected read and an Inbox proposal, applies it, and verifies exact undo.
It removes the scratch vault and its state afterward.

The [Pi/Ollama comparison](../eval/agent-comparison/README.md) runs the same synthetic
tasks and Holdfast tools through Pi + Ollama, Swift + Ollama, and Swift + MLX, with
saved requests, proposals, approval/undo checks and timing caveats.

## Household eval (synthetic)

`eval/household/` is a made-up family's knowledge base (finance, home, health,
trips, career, and private case reports under `private/`) with 40 questions
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

The default is LocalMLX. `HOLDFAST_BACKEND=mlx|ollama|lmstudio|custom` overrides the saved
provider; `HOLDFAST_MLX_REPO` selects the embedded model. Server configuration is below.
Audio and URLs also need `ffmpeg` and `yt-dlp`.

### Adding files in the app

Use **Add Files…** on Ask, or drag files onto **Add files to your knowledge base**.
The card immediately confirms the files, then shows copying, queuing, model preparation,
and processing. **File details** keeps each filename and its current stage visible;
a running time shows how long that stage has taken. You can keep using the app.

Results stay visible until dismissed or another batch is added. Proposed changes have a
**Review in Inbox** button; files that failed or were skipped show why. In an existing
vault, proposals still wait for approval. **Pause after current file** holds the remaining
queue, and **Resume processing** starts it again. Large recordings and the first model
load can take several minutes.

### Model downloads through a mirror

In **Settings → Downloads**, enter a Hugging Face-compatible **Endpoint URL**, add an
access token if required, and click **Save**. Then download models from the Answer or
Search or Transcription tab as usual. Repository IDs such as `mlx-community/Qwen3.8-27B-4bit` stay the same.
Tokens are stored in macOS Keychain separately for each endpoint and sent as
`Authorization: Bearer <token>` on metadata and file requests. Paste the token itself,
without the `Bearer` prefix.

For JFrog Artifactory, use the `HF_ENDPOINT` value from **Set Me Up**, for example
`https://company.jfrog.io/artifactory/api/huggingfaceml/huggingface-remote`, and your
Artifactory identity token. Use the API endpoint, including its repository path, rather
than the Artifactory web UI URL or an individual model file URL. See
[JFrog's Hugging Face setup](https://docs.jfrog.com/artifactory/docs/hugging-face-repositories).

`HF_ENDPOINT` and `HF_TOKEN`, when set in the app process's environment, override saved
settings. Blank variables are ignored. A custom mirror without an explicit or saved
token uses anonymous access; it does not inherit a cached Hugging Face login.
The default `https://huggingface.co` endpoint retains the usual Hugging Face token discovery.

This setting applies to answer, embedding, reranker and transcription downloads.
The download display shows the percentage, transfer speed and estimated time remaining.
If the server does not provide a file size, Holdfast shows an indeterminate download
instead of inventing a percentage or time estimate. A final “Checking files” stage
finishes before a model is marked downloaded.

Existing downloads remain usable. Answer and search models are saved under
`~/Library/Application Support/Holdfast/models`; speech models use the FluidAudio
model folder in Application Support. In **Settings → Transcription**, choose
**Download** to prepare a model before your first recording. Parakeet v3 remains the
tested default, with v2 for English, Ultra as an additional accuracy-oriented option,
and Redux as a smaller multilingual option. Ultra and Redux have not been benchmarked
with Holdfast. Core ML is already built into macOS: only speech model files are downloaded,
and transcription runs locally after that. macOS may still take a few minutes to prepare
a newly downloaded model on first use.

Run the model-free configuration and cache checks with `scripts/test_model_downloads.sh`.
After building, run `scripts/test_model_downloads.sh --integration` to also test downloads
against a loopback mirror, including Artifactory-style paths, bearer authentication,
anonymous access, rejected tokens, missing files and empty repositories.

## Use from Claude Code

```bash
claude mcp add holdfast -e HOLDFAST_VAULT=$HOME/Notes -- ~/.local/bin/holdfast mcp
```

## Measured on an M1 Max, 64 GB (2026-11-04)

| What | Result |
| --- | --- |
| Import a document library (403 docs) | 385 notes in 3 min (OCR included); 18 docx/pdf duplicates skipped; 3 image-only docx with no text |
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
`.md` and `.txt` notes can be changed this way. Changes to private notes run on this Mac only,
like any request that touches them.

## Keeping records safe

- **Backup** (Settings → Vault → Backups, Vault › Back Up Now ⌥⌘B, `holdfast backup <folder>`):
  a dated folder `Holdfast <vault> <date time>` with the vault (without `.git` and search
  indexes), Holdfast's records for it (versions, filing log, history, kept originals,
  transcripts, rules), the app's settings, a README on restoring, and `manifest.json` with every
  file's SHA-256. Verify (`--verify <backup>`) re-reads every file; Test Restore
  (`--test-restore <backup>`) restores into a temporary folder, checks every file, opens every
  note and the history and filing log, then removes the copy. A folder inside the vault is
  refused. Back up to another drive; an encrypted one if the vault holds private notes.
- **Originals** beside their notes: approving a filing copies the document it came from into
  `originals-raw/<the note's folder>/` (the folder ignores itself in git, and `-raw` folders are
  never indexed) and links it under "## Originals"; the note's toolbar has Open Original, and
  undo removes both. `holdfast originals [--apply]` keeps and links the originals of earlier
  filings that are still in the drop-filed folder.
- **Export** (Vault › Export Notes… ⇧⌘E, `holdfast export --query … --folder … --out x.zip`):
  notes found by a question and/or a folder, ticked off in a list, with the originals they link to,
  a README and a checksum manifest; the ZIP is unpacked and checked after it's built. Private
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

## Choose an inference provider

**Settings → Answer → Provider** offers LocalMLX (default), Ollama, LM Studio and Custom server.
For a server, enter its API base, optionally add a key, discover models or enter an ID manually,
set the loaded model's context window (at least 16384), and **Save Connection**. Each provider
keeps its own settings. Credentials are stored in Keychain, bound to the endpoint, and are never
passed to the Node bridge. Editing an address clears the key field.

| Provider | Default address | Protocol |
| --- | --- | --- |
| LocalMLX | No server | Embedded Swift MLX |
| Ollama | `http://localhost:11434` | Native `/api/chat` and `/api/tags` |
| LM Studio | `http://localhost:1234/v1` | OpenAI-compatible chat completions and model discovery |
| Custom server | `http://localhost:8080/v1` | Same compatible API; supports explicit proxy prefixes |

All choices support ordinary answers and the same six Holdfast tools in both the Swift harness
and regular Pi. Use a model with tool support. Model discovery establishes connectivity, not
behavioral compatibility. The server owns model loading and scheduling. HTTP errors stay visible;
there is no automatic connection-error fallback. Private context switches to embedded LocalMLX
before the next inference request, or fails closed when no local model is available. This restriction
persists through follow-ups and Pi restarts. A loopback address alone does not prove a server runs
its selected model locally.

```sh
HOLDFAST_BACKEND=ollama HOLDFAST_PROVIDER_MODEL=qwen38-27b-q8-32k:latest holdfast ask --research "…"
HOLDFAST_BACKEND=lmstudio HOLDFAST_PROVIDER_MODEL=<model-id> holdfast ask --pi "…"
HOLDFAST_BACKEND=custom HOLDFAST_PROVIDER_URL=https://server.example/v1 \
  HOLDFAST_PROVIDER_MODEL=<model-id> holdfast ask "…"
```

Optional overrides: `HOLDFAST_PROVIDER_API_KEY`, `HOLDFAST_CONTEXT_WINDOW`.
Legacy `HOLDFAST_OLLAMA`, `HOLDFAST_LLM`, and `HOLDFAST_BACKEND=remote` with
`HOLDFAST_REMOTE_URL` / `HOLDFAST_REMOTE_MODEL` remain supported. URLs must use HTTP(S)
and contain no credentials, query or fragment. Redirects are refused.

The Foundation-only **ModelProviders** Swift package lives in
[`Packages/ModelProviders`](../Packages/ModelProviders/README.md), alongside
[`LocalMLX`](../Packages/LocalMLX/README.md). Both `MLXSession` and
`HTTPModelProvider` implement `ModelProvider` with shared `Inference.Request` / `Reply` types.
Other apps can depend on these packages without importing Holdfast, its vault or its approvals.
An HTTP-only app can use ModelProviders without resolving or building MLX.
`MLXProtocol` remains an alias for the version-1 wire types. See the
[reusable package examples](../Packages/pi-swift-mlx/README.md#use-the-same-interface-with-a-model-server).

Checks (synthetic vaults, no personal data):

```sh
python3 Tests/model_provider_transport.py
python3 Tests/provider_integration.py .build/harness-xcode/Build/Products/Release/holdfast
# Optional: actual installed Ollama 27B, scratch-vault proposal/approval/Undo
python3 Tests/provider_integration.py .build/harness-xcode/Build/Products/Release/holdfast --live-ollama
```

### Add your own LocalMLX model

In **Settings → Answer → Change model… → Add model…**, choose a Hugging Face
repository (`owner/model` or its root URL) or an existing local model folder.
Repository metadata is checked before downloading weights. The download uses
**Settings → Downloads**, including its endpoint and access token. Private or
gated repositories require an access token and any required access approval on
Hugging Face.

Custom models are saved under **Your models**, beside the unchanged recommended
list. Once available, they also appear in Ask's model menu. Local folders are used
in place; removing a choice keeps every model file. If a folder moves, add its new
location and remove the old choice.

The checkpoint needs a supported model architecture, tokenizer files, and complete
safetensors weights. A GGUF model belongs with an Ollama or LM Studio connection.
File checks do not benchmark a model or prove tool support, and memory use is higher
than the weight size shown. Load or chat-template errors can still occur on first use.
Holdfast's tools, privacy rules, Inbox approvals, and Undo apply to custom models.

## Privacy, in one place

- Everything runs on this Mac by default: the vault, its index, search, and the answer model.
- With **a server provider**, the vault, index and search stay here; the selected server receives
  each question with the passages found, the conversation so far, folder READMEs, Research's note
  reads and table results, documents dropped for filing, and note pairs when suggesting links.
  **Private notes never leave this Mac**: anything involving them is answered here instead.
  The app labels the selected server host; server inference may run here or elsewhere.
- Link import (YouTube, podcasts) fetches from the web by design. The Gemini backend exists for
  evals on synthetic data only and isn't offered in the app.
