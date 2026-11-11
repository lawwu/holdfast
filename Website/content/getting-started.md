---
title: Getting started
description: Install Holdfast, choose a notes folder, and try your first question and approved edit.
editUrl: false
---

Holdfast brings search, answers, and proposed edits to a folder of notes. Your files remain ordinary files that you can open in other apps.

## Install the preview

You need an **Apple Silicon Mac running macOS 15 or later**.

1. Download the `.pkg` from [Holdfast Releases](https://github.com/lawwu/holdfast/releases).
2. Open the installer and follow its instructions. It places **Holdfast** in **Applications**.
3. Open Holdfast and choose your notes folder.

:::caution[Unsigned preview]
The current installer is not signed with Developer ID or notarized by Apple. macOS may block it. If you trust the download, follow [Apple’s instructions for opening a trusted app](https://support.apple.com/en-us/102445), including **System Settings → Privacy & Security → Open Anyway** when available.
:::

Node and Pi are included in the installer. You do not need developer tools to use the core app. Model weights are downloaded separately and need additional disk space.

Recording-file and stream imports need the optional `ffmpeg` tool. Video-link imports also need `yt-dlp`; the installer does not install these tools.

## Choose a model

In Settings, choose an answer provider:

| Provider | What you need |
| --- | --- |
| **LocalMLX** — the default | Download a supported model in the app. Inference runs inside Holdfast on your Mac. |
| **Ollama** | A running Ollama server and an installed model. |
| **LM Studio** | A running LM Studio server with a model loaded. |
| **Custom server** | A compatible chat-completions endpoint and, if required, an API key. |

For agent actions, use a model with tool support. A server connection test confirms the connection, not the model’s ability to follow every tool request.

When you select a server, it receives the context needed to answer your question. Notes covered by the **Private notes** profile, including protected folders, continue to use LocalMLX on this Mac. If a suitable local model is unavailable, the private request is refused.

Read the [provider guide](../../README.md#choose-an-inference-provider) for addresses and command-line options.

## Ask your first question

Choose a question your notes can answer, such as:

> What did I decide about the kitchen repair?

Holdfast finds relevant passages and includes citations in its answer. Open a citation to check the underlying note. If the notes do not cover the question, add the source material or try a more specific question.

**Settings → Search → Search by meaning** is on by default. You can turn it off and keep keyword search. The reranker has its own setting.

## Propose an edit

Try a direct request that starts with an action:

> Mark “Book the inspection” as done.

Or:

> Add an open item to my home checklist: replace the porch light.

The agent reads the note and proposes a change. **The note is not changed yet.**

1. Open the **Inbox** and review the removed and added text.
2. Use **Edit** to adjust the proposal if needed.
3. Choose **Apply Change**. Holdfast saves a copy before writing.
4. Use **Undo** if you want the original file back.

If the note changed after the proposal, Holdfast refuses to overwrite it. Generated files are protected, and this editing path accepts `.md` and `.txt` notes.

## Go further

- [App and command-line guide](../../README.md)
- [How the architecture fits together](architecture.md)
- [Reference collections](../../packs/README.md)
- [Release notes](../../docs/releases/v0.0.1.md)
