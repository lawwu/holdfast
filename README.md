# Holdfast

A local knowledge base for your Mac. Search your notes, ask questions with sources,
and review proposed edits before they’re saved.

**[Download](https://github.com/lawwu/holdfast/releases)** ·
[Documentation](https://lawwu.github.io/holdfast/) ·
[Watch the tour](https://lawwu.github.io/holdfast/tour/) ·
[Changelog](CHANGELOG.md)

**Current preview: [v0.0.3](https://github.com/lawwu/holdfast/releases/tag/v0.0.3)** —
[Download the macOS installer](https://github.com/lawwu/holdfast/releases/download/v0.0.3/Holdfast-0.0.3-macos-arm64-unsigned.pkg)
(Apple Silicon, macOS 15+, unsigned).

## What you can do

- **Find what you need.** Search documents and notes by keyword or meaning.
- **Ask your notes.** Get answers with citations you can open and check.
- **Review changes.** Ask for an edit, approve it in the Inbox, and undo it if needed.
- **Bring your sources together.** Import documents, transcribe recordings, and keep
  notes as ordinary Markdown files.

## Get started

Requires an **Apple Silicon Mac running macOS 15 or later**.

1. Download the `.pkg` from [Releases](https://github.com/lawwu/holdfast/releases).
2. Install Holdfast, open it from Applications, and choose your notes folder.
3. Download a model in the app, or connect an existing model server.

Try asking “What did I decide about the kitchen repair?” or
“Mark ‘Book the inspection’ as done.” Proposed edits wait in your Inbox.

Holdfast is an early preview. Installers are **unsigned and not notarized by Apple**;
see the [installation guide](https://lawwu.github.io/holdfast/getting-started/) if
macOS blocks them. The installer includes the core runtime; models download separately.

## Models and privacy

**LocalMLX** runs the answer model inside the app by default. You can also use
**Ollama**, **LM Studio**, or a compatible custom server.
Choose a recommended model, or use **Add model…** to bring an MLX-compatible
Hugging Face repository or local folder.

With a server provider, the server receives the question and relevant context.
Notes covered by the **Private notes** profile or protected-folder rules stay
with LocalMLX on this Mac. See [model and privacy settings](docs/guide.md#choose-an-inference-provider).

## Build and extend

Holdfast uses Swift for the app and regular Pi for the agent loop. Building requires
Xcode 27.2 with the Metal Toolchain and Node.js 22.19 or later.

```sh
bash scripts/make_app.sh
open build/Holdfast.app
```

Three reusable packages live in this repository:

- [LocalMLX](Packages/LocalMLX/README.md) — Swift MLX inference and `local-mlx-host`.
- [ModelProviders](Packages/ModelProviders/README.md) — shared inference types and HTTP providers.
- [pi-swift-mlx](Packages/pi-swift-mlx/README.md) — the Pi adapter.

Holdfast keeps its tools, privacy rules, Inbox approvals, and Undo in the app.

[App and CLI reference](docs/guide.md) ·
[Architecture](https://lawwu.github.io/holdfast/architecture/) ·
[Builds and releases](docs/releases.md)
