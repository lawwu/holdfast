# mac-kb (POC)

A local knowledge base for **biblical counselors**: import lessons, homework sheets,
supervision recordings and past case reports, then search and ask questions of them
with citations. Everything runs on the Mac, because case material is confidential.
Nothing is sent to a cloud service.

This is the Phase 0–3 proof of concept from the Mac KB plan (`a notes repo`,
`projects/202611_mac-kb/`). It's a command-line tool. A SwiftUI app comes later.

## What it does

| Command | What happens |
| --- | --- |
| `mackb ingest <folder>` | `.docx/.doc/.rtf` via `textutil`, `.pdf` via PDFKit, scanned PDFs via Apple Vision OCR, `.md/.txt` as-is. When a lesson exists as both docx and pdf, only one copy is kept |
| `mackb ingest <audio/video>` | ffmpeg → 16 kHz → **Parakeet v3** (FluidAudio, CoreML) → a note with `[hh:mm:ss]` lines |
| `mackb ingest <YouTube URL>` | yt-dlp; uses the video's captions when there are any, otherwise transcribes the audio |
| `mackb index` | Chunks each note on headings and timestamps; SQLite FTS5 + **Qwen3-Embedding-0.6B** vectors (in-process, MLX Swift). Only changed notes are re-indexed |
| `mackb search "…"` | Keyword (BM25) and vector results merged with reciprocal rank fusion |
| `mackb ask "…"` | The top 8 passages go to **Qwen 3.8 27B** (Ollama, thinking off). The answer cites `[n]`, and each source prints as `[[note#anchor]]` |
| `mackb mcp` | MCP server: `search`, `get_note`, `ask`, `remember`, `list_inbox` |
| `mackb inbox / approve / reject` | Memories that agents propose wait here for approval. Each one is checked for full names, emails and phone numbers first |

The vault is plain Markdown with YAML frontmatter (`$MACKB_VAULT`, default
`~/MacKB`): `sources/`, `memory/`, `inbox/`. It opens in Obsidian. The index in
`.mackb/` is a cache; delete it and run `mackb index` again.

## Build

MLX compiles Metal shaders, so build with `xcodebuild`, not `swift build`.
It needs the Metal Toolchain once (`xcodebuild -downloadComponent MetalToolchain`).

```bash
xcodebuild -scheme mac-kb -destination 'platform=macOS' -configuration Release \
  -derivedDataPath .build/xcode -skipMacroValidation -skipPackagePluginValidation build
ln -sf "$PWD/.build/xcode/Build/Products/Release/mackb" ~/.local/bin/mackb
```

It also needs Ollama with a Qwen model (`MACKB_LLM`), plus `ffmpeg` and `yt-dlp`
for audio and URLs.

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

- SwiftUI app (three panes, audio player synced to the transcript, clickable citations)
- An in-process Qwen 27B through MLX (`LLMBackend` is ready for it); a reranker; sqlite-vec
- Batched embeddings (currently one passage at a time); a background job queue
- Case-report templates (ACBC structure: data gathering, problem, hope, plan, homework)
  so questions can filter by section
