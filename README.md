# mac-kb (POC)

A local knowledge base for **biblical counselors**: import lessons, homework sheets,
supervision recordings and past case reports, then search and ask questions of them
with citations. Everything runs on the Mac, because case material is confidential.
Nothing is sent to a cloud service.

This is the Phase 0–3 proof of concept from the Mac KB plan (kept in a
separate notes repo). One binary is the CLI, the MCP server and a SwiftUI
window: `mackb app`, or `scripts/make_app.sh` → `build/MacKB.app`.

## What it does

| Command | What happens |
| --- | --- |
| `mackb ingest <folder>` | `.docx/.doc/.rtf` via `textutil`, `.pdf` via PDFKit, scanned PDFs via Apple Vision OCR, `.md/.txt` as-is. When a lesson exists as both docx and pdf, only one copy is kept |
| `mackb ingest <audio/video>` | ffmpeg → 16 kHz → **Parakeet v3** (FluidAudio, CoreML) → a note with `[hh:mm:ss]` lines |
| `mackb ingest <YouTube URL>` | yt-dlp; uses the video's captions when there are any, otherwise transcribes the audio |
| `mackb index` | Chunks each note on headings and timestamps; SQLite FTS5 + **Qwen3-Embedding-0.6B** vectors (in-process, MLX Swift). Only changed notes are re-indexed |
| `mackb search "…"` | Retrieval pipeline below |
| `mackb ask "…"` | The top 12 passages go to **Qwen 3.8 27B** (MLX 4-bit in-process or Ollama, thinking off). The answer cites `[n]`, and each source prints as `[[note#anchor]]` |
| `mackb app` | The window: Ask (cited answers; click a source to open it), Library (browse and search), Inbox (approve or reject agent memories), and a reader that jumps to the cited section |
| `mackb eval` | Scores Q&A against a question set; see `eval/README.md` |
| `mackb mcp` | MCP server: `search`, `get_note`, `ask`, `remember`, `list_inbox` |
| `mackb drop [file…]` | Files what is in the drop folder. In a vault indexed in place, the model reads each file (PDF, Word, Markdown, images by on-device OCR, recordings by transcription) and the folder READMEs, and proposes a new note or a row for an existing log; the proposal waits in the inbox. In a managed vault the file is imported as a source. Originals move to `drop-filed/` in the app's state folder, never into the vault. The app watches the same folder (Vault › Open Drop Folder, ⇧⌘D) and has a drop zone on the Inbox page |
| `mackb inbox / approve / reject` | Memories that agents propose wait here for approval. Each one is checked for full names, emails and phone numbers first |

**Retrieval** (`Sources/mackb/Index.swift`, tuning constants in `enum Retrieval`), following
the open-source survey in the kb repo (`projects/202611_mac-kb/oss-best-practices.md`):

1. **Read the question.** "First session", "session 4", "final session", "graduation",
   or "second joint session" (from the form header) become session filters. "Across
   sessions" or "over the course of" turn on spread mode.
2. **Find candidates.** 60 passages from FTS5 BM25 and Qwen3-Embedding vectors, merged with
   reciprocal rank fusion. Each passage starts with a label (title › date › session
   kind › form question), so both searches see which session it is from.
3. **Rerank** with **Qwen3-Reranker-0.6B** (MLX, in-process). If the best score is
   below 0.08, decline without calling the LLM.
4. **Select.** Drop passages scoring under half the best. Cap each note at 2, except
   that a note holding 3 of the top 5 gets 5. Add the neighbours of the top 2 hits.
   Merge neighbouring passages. In spread mode, take the best 1–2 per session and
   send them in session order.
5. **Answer.** 8 passages go to Qwen 3.8 27B. `[n]` markers that point at no passage
   are flagged.

The vault is plain Markdown with YAML frontmatter (`$MACKB_VAULT`, default
`~/MacKB`): `sources/`, `memory/`, `inbox/`. It opens in Obsidian. The index in
`.mackb/` is a cache; delete it and run `mackb index` again.

## Household eval (synthetic)

`eval/household/` is a made-up family's knowledge base (finance, home, health,
trips, career, and counseling case reports under `ministry/`) with 40 questions
and 12 documents to file. `eval/household/run.sh` runs it across answer models
(Qwen 3.8 27B, Gemma 4 26B A4B, Gemma 4 E4B), embedders (Qwen3-Embedding,
EmbeddingGemma) and modes (plain, Research), plus Gemini when `GEMINI_API_KEY`
is set; `report.py` writes `report.md`. Pick models with `MACKB_BACKEND`,
`MACKB_MLX_REPO`, `MACKB_EMBED=embeddinggemma`, `MACKB_RERANK=0`, and fix the
date with `MACKB_TODAY=2026-11-05`.

## Build

MLX compiles Metal shaders, so build with `xcodebuild`, not `swift build`.
It needs the Metal Toolchain once (`xcodebuild -downloadComponent MetalToolchain`).

```bash
xcodebuild -scheme mac-kb -destination 'platform=macOS' -configuration Release \
  -derivedDataPath .build/xcode -skipMacroValidation -skipPackagePluginValidation build
ln -sf "$PWD/.build/xcode/Build/Products/Release/mackb" ~/.local/bin/mackb
```

The LLM is `MACKB_BACKEND=mlx` (Qwen 3.8 27B 4-bit loaded in-process from the
Hugging Face cache, `MACKB_MLX_REPO`) or `ollama` (`MACKB_LLM`). Audio and URLs also need `ffmpeg` and `yt-dlp`.

## Use from Claude Code

```bash
claude mcp add mackb -e MACKB_VAULT=$HOME/MacKB-ministry -- ~/.local/bin/mackb mcp
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
