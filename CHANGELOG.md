# Changelog

## Next (after 0.1.0)

- **`mackb listen`: live transcription.** Audio from a stream URL (via ffmpeg), the microphone, or raw
  audio on stdin is transcribed as it arrives; finished lines print as they become final (JSON events
  with `--json`), and the transcript is kept and filed like a dropped document when it ends. CLI only
  for now; `--mic` is untested.
- **Meetings and other apps' audio:** `--app <name>` (one app) or `--system` (everything the Mac
  plays) through Core Audio process taps, with `--mic` mixed in for your side of a call; `--apps`
  lists audio apps; `--mute` keeps the tapped audio off the speakers. From a terminal the capture runs
  inside Holdfast.app so macOS asks Holdfast for System Audio Recording.
- **Listen page in the app** (sidebar, ⇧⌘R): a call or app, all Mac audio, the microphone or a stream;
  live lines, a sidebar badge while listening, Stop, recent transcripts, and filing through the Inbox.
- Not yet tested: the microphone (alone or mixed into a call), `--mute`, a real call app. Each
  rebuild asks for the audio permission again (ad-hoc signing).

## 0.1.0 (unreleased)

The first version with a name: **Holdfast**, a private second brain for a family's notes.
Everything runs on this Mac by default.

### What's in it
- **Ask, in one box.** A router decides how to handle each request: a direct answer from the
  closest passages, Research (search, read notes, query CSV tables in steps) for totals,
  lists and comparisons, or a job such as suggesting links, which asks before it starts.
  A direct answer that finds nothing looks deeper on its own.
- **Conversations.** Every question is a conversation you can follow up in and reopen from
  History. Steps show live and open to show the exact call and what came back; Stop (⌘.)
  keeps what was written. Optional Show Thinking.
- **Filing.** Drop documents, mail, spreadsheets, scans, recordings, zip archives, mailboxes,
  Evernote and Day One exports; the model proposes where each belongs and you approve in the
  Inbox, in groups. Bulk import can file each one or bring a folder in as-is.
- **Keeping it safe to trust.** Every filing can be undone; notes keep earlier copies (History);
  learned filing rules (optionally automatic, never for counseling or anything with names,
  emails or numbers); properties and a Tables view; Upcoming follow-ups; Related notes;
  cross-link suggestions.
- **Knowledge packs.** Read-only references searched beside your notes, starting with the
  Berean Standard Bible (public domain).
- **A model on another Mac** (LM Studio, mlx_lm.server, Ollama) with the vault, index and
  search staying here, and counseling notes never sent.
- **Quick Look** previews for Markdown in Finder, a larger type scale, an app icon.

### Fixed before release (from four independent reviews and a second full review)
- Undo: undoing a cross-link no longer trashes the note; undo removes only the exact lines
  it added (and its follow-ups), refuses when they were edited or the note was moved, and
  never claims success when nothing changed. Restoring the oldest copy can't prune it first.
- Writes stay in the vault: a model's text can no longer add frontmatter keys (newlines in
  values are flattened, the first key wins), every write re-checks its target, bulk-import
  folders must be inside the vault, pack ids are validated, nothing is created inside a pack.
- Filings are serialized across the app, CLI and MCP server with a file lock (eight
  simultaneous approvals all land, with eight undo records).
- Privacy: rules match whole words, are never learned or applied for counseling, and never
  auto-file entries with names, emails or long numbers; cross-links leave counseling out and
  drop reasons that carry personal details; the remote model never receives counseling
  material, can't be redirected elsewhere, and the app's labels say when a remote model is in
  use; switching vaults clears the conversation and its context.
- Answering: Stop with a remote model stops instead of falling back; reasoning never becomes
  answer text; short follow-ups are searched with the previous question only when they lean
  on it; Research citations no longer merge different passages; Bible passages can't outrank
  your notes when the reranker is off; other jobs no longer clear "busy" mid-answer.
- Files: no crashes on malformed spreadsheets; sheet names follow the workbook; archives are
  unpacked with UTF-8 names and size/count limits; mail is decoded per charset (Latin-1,
  Windows-1252, GB2312, split encoded words); plain text in UTF-16 or Windows-1252 reads;
  vCard quoted-printable; streaming mailbox split; capped OCR memory; Evernote exports recover
  from stray control characters; staging folders are removed; a rejected or undone document
  can be dropped again.
- Release: search models can be downloaded in Settings, Rebuild Index re-embeds, first-run
  guidance, clear errors for missing ffmpeg / yt-dlp / Ollama, MLX as the CLI default, ⌘W and
  ⇧⌘G / ⇧⌘\ conflicts resolved, closing the window doesn't quit mid-answer.
- First run: on a Mac with no model downloaded the whole window was blank (the first-run card's
  text asked for a fixed height outside a scroll view); the job confirmation card had the same text
  and was fixed with it.
- Evals: the router score counts all 36 answerable questions (94% vs 74% always-direct with
  Qwen 3.8 27B; 22 questions without a Research run assume it equals the direct answer);
  evals run with knowledge packs off.

### Known limitations
- Not clicked through after the fixes: the job confirmation card, search-model downloads, ⌘W
  behaviour, the reader sheet, Stop mid-answer in the app. (The first-run card was checked on screen.)
- Ad-hoc signed for this Mac: another Mac's Gatekeeper will block it until it is signed and
  notarized. Permission prompts reset with each build.
- Quick Look: Obsidian's preview may win for .md; non-UTF-8 notes preview blank; no size cap.
- Follow-ups proposed for a CSV filing aren't saved anywhere; lines under "## See also" or
  "## Follow-ups" can attach to an indented item that follows the list.
- Times are America/Los_Angeles throughout; transcripts always record "parakeet-v3".
- The cross-link score (Qwen 3.5 4B and Qwen 3.8 27B 100%) is on 46 pairs, 38 of them
  counseling reports, which the app no longer cross-links; it measures the yes/no judge only.
- Built in Swift 5 language mode; Swift 6 strict concurrency hasn't been checked.
