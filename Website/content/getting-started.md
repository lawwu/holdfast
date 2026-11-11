---
title: Getting started
description: Install Holdfast and try your first question, source check, and approved edit with sample notes.
editUrl: false
---

In a few steps, you'll have a folder of notes you can browse, search, and ask questions about. Your notes stay ordinary files you can open in other apps.

**Prefer to watch?** [Take the narrated tour](/holdfast/tour/), then follow along with the same sample notes.

## 1. Install Holdfast

You need an **Apple Silicon Mac running macOS 15 or later**.

1. Download the `.pkg` from [Holdfast Releases](https://github.com/lawwu/holdfast/releases).
2. Open the installer and follow its instructions. It places **Holdfast** in **Applications**.
3. Open Holdfast from Applications.

:::caution[This is an unsigned preview]
The installer is not signed with Developer ID or notarized by Apple. macOS may block it. If you trust the download, follow [Apple's instructions for opening a trusted app](https://support.apple.com/en-us/102445), including **System Settings → Privacy & Security → Open Anyway** when available. Do not disable macOS security protections globally.
:::

The installer includes the app's runtime. You do not need developer tools for the core app. Models download separately and need additional disk space.

## 2. Choose a folder of notes

For your first try, [download the sample notes](/holdfast/demo/holdfast-sample-notes.zip) and unzip them. Choose the **Holdfast Sample Notes** folder as your vault (Holdfast's name for your notes folder). You can change the folder in **Settings → Vault**.

Open **Library** and select **Kitchen repair plan**. You should see the decisions and the $1,800 budget shown below. All notes in these screenshots are fictional.

[![The Library showing the Kitchen repair plan, with repair decisions, a budget, and next steps.](/holdfast/screenshots/library.webp)](/holdfast/screenshots/library.webp)

*Select any screenshot to open it at full size.*

## 3. Choose an answer model

Open **Settings → Answer**. Start with **LocalMLX**, the default, and download a model that fits your Mac's available memory. The app runs it locally. The first download and first model load can take a while.

[![Answer settings with LocalMLX selected and tabs for Ollama, LM Studio, and a custom server.](/holdfast/screenshots/settings.webp)](/holdfast/screenshots/settings.webp)

Already use **Ollama** or **LM Studio**? Start its server, load a model, and choose that provider in Holdfast. **Custom** supports compatible chat-completions servers. Use a model with tool support for edits and other agent actions. A successful connection test only confirms that the server is reachable.

A server receives your question and the relevant note context. Notes covered by the **Private notes** profile or protected-folder rules must use LocalMLX on this Mac; Holdfast refuses the private request if a suitable local model is unavailable. See [model and privacy settings](../../docs/guide.md#choose-an-inference-provider).

## 4. Ask your first question

Open **Ask** and enter:

> What did I decide about the kitchen repair?

Wait for the answer. Local models can take a minute or more, depending on the model, your Mac, and the request. You should get a summary with numbered citations.

[![Ask summarizing the kitchen decisions and linking to the original notes.](/holdfast/screenshots/ask.webp)](/holdfast/screenshots/ask.webp)

Open a citation to check the source passage. If an answer seems wrong, check the source before relying on it. If the notes don't contain an answer, add the missing source or ask a more specific question.

[![The kitchen repair source open beside the answer for checking its details.](/holdfast/screenshots/source.webp)](/holdfast/screenshots/source.webp)

**Search by meaning** is on by default in **Settings → Search**. Turn it off if you prefer keyword search. The reranker is a separate setting; it reorders retrieved results.

## 5. Review an edit before saving it

Start a new question and enter:

> Mark “Book the inspection” as done in my home checklist.

Start edit requests with an action such as **mark**, **add**, or **update**. The model reads the note and prepares a proposal. **Your file has not changed yet.**

Open **Inbox**. Red shows the text being removed; green shows its replacement.

[![An Inbox proposal showing the unchecked inspection item in red and the checked replacement in green, with Apply Change and Edit controls.](/holdfast/screenshots/inbox.webp)](/holdfast/screenshots/inbox.webp)

Review the exact change. Use **Edit** to adjust the proposal if needed, then choose **Apply Change**. Holdfast saves a copy before writing. Open **Home checklist** to see the checked item.

If the note changed after the proposal, Holdfast refuses to overwrite it. This edit path accepts `.md` and `.txt` notes and protects generated files.

## 6. Undo if you change your mind

In **Inbox → Recently filed**, choose **Undo** for that change. Holdfast restores the saved copy of the note.

[![Recently filed in the Inbox showing the approved checklist change and its Undo button.](/holdfast/screenshots/undo.webp)](/holdfast/screenshots/undo.webp)

## When you're ready for your own notes

Choose your notes folder in **Settings → Vault**, then try a specific question about something you've written. Browse in Library, check citations, and review every proposed edit in Inbox.

For more tasks, see the [full app guide](../../docs/guide.md). Recording and stream imports need the optional `ffmpeg` tool; video-link imports also need `yt-dlp`.
