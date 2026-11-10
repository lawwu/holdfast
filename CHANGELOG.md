# Changelog

## Next (after 0.1.0)

- **Regular Pi is now the default agent.** The normal app and CLI use Pi 1.5.1 with
  saved JSONL conversations and Holdfast-only tools. LocalMLX and server providers,
  Inbox approvals, byte-exact Undo and counseling restrictions are preserved.
  Durable records remain untouched; interrupted jobs are not automatically replayed.
  The normal app packager now includes the regular Pi runtime.

- **Choose an answer provider.** LocalMLX is the default, with Ollama, LM Studio and
  custom compatible servers in Answer settings. Model discovery, manual IDs, context
  limits and endpoint-bound Keychain keys work with regular Pi and the Swift comparison harness.
  The Foundation-only `ModelProviders` Swift product shares an inference interface with
  LocalMLX and is reusable by other apps. Tools, proposals, approval, snapshots and Undo
  remain in Holdfast. Counseling restrictions survive follow-ups and Pi restarts;
  server failures are visible and redirects are refused.

- **Reusable Swift MLX provider.** `Packages/pi-swift-mlx` contains an npm provider
  for Pi and Pi Durable, the **LocalMLX** Swift inference library and the
  **local-mlx-host** standalone helper. Full tool schemas and JSON arguments cross the provider boundary. Holdfast
  retains its tools, validation, privacy policy, Inbox approvals and Undo.
- **Archived Pi Durable prototype.** The earlier bridge remains under `Runtime/pi-durable`
  for reference. Holdfast now uses regular Pi; `scripts/make_pi_prototype.sh` builds a
  separate regular-Pi app. The reusable adapter continues to support both harnesses.
- **Undo for successive approvals.** Each approved edit now keeps an unthrottled,
  byte-exact snapshot; UTF-8 BOMs survive Apply Change and Undo.
- **Native agent harness.** Local MLX and network Research now share one runtime with a
  tool registry, validated arguments, conversation transcripts, lifecycle events, cancellation
  and bounded execution. Local model handoff continues from tool results instead of replaying
  earlier proposals. Private local journals record tool intent before execution and the outcome
  afterward. The structure is informed by Pi and Pennant; no new runtime dependencies.
- **Changes from Ask.** "Mark … done", "add … to …": the model reads the note and proposes the exact
  change, which waits in the Inbox with removed and added lines until approved; undo restores the
  copy kept first. A note changed since the proposal is refused, generated files are refused.
- **Double-click a note to edit it**, and **answers can be selected** (citation links still open: the
  app registers its link schemes so macOS hands those clicks back).

- **`holdfast listen`: live transcription.** Audio from a stream URL (via ffmpeg), the microphone, or raw
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
- **New layout.** The sidebar is grouped (Ask and Listen; Notes; Activity) and shows when Holdfast is
  listening or writing an answer. Every page has a title header and sits in a readable column when
  no note is open beside it, instead of stretching across the window. Ask opens on a home page: a
  greeting, the question box in the middle, suggestions, proposals waiting for approval, upcoming
  follow-ups and recent conversations. In a conversation the question is a bubble on the right, the
  answer's Copy button sits in its footer, sources lay out in two columns, and a new question
  scrolls into view. Library rows show each note's folder in its folder's colour; the Files list
  blends into the page. Listen keeps the transcript on the page after Stop, with Copy and a Follow
  toggle for reading back. Checked on screen in light mode; dark mode not yet checked.

- **Model recommendations.** `holdfast models`, the first-run card and Settings recommend the
  answer model that scores best on the household eval and fits this Mac's memory, with a faster
  alternative; Settings lists every measured model with its scores. Before a model is chosen, the
  default is this Mac's pick. On 64 GB: Qwen 3.8 27B (Gemma 4 26B A4B as the 4× faster choice);
  32 GB: Qwen 3.5 9B; 16 GB: Qwen 3.5 4B.
- **Backup, originals, export, pins.** Checked backups with Verify and Test Restore; the document a
  filing came from kept beside its note with Open Original; checked ZIP exports with counseling
  left out by default; questions pinned to the Ask home page. Tested on the scratch vault: a
  tampered file is caught, undo removes a kept original, a backup inside the vault is refused.
- **Renamed to Holdfast everywhere** (command, bundle id, settings, data folder); the old name's
  settings and data move over on first run.

### Fixed after a review of the above
- Privacy: a follow-up in a conversation that used counseling notes stays on this Mac (earlier
  answers go along as context); remote Research keeps folder listings, tables and properties from
  counseling folders here too. Tested against a stand-in server: nothing counseling reached it, and
  an ordinary question still did.
- Listen from a terminal: kill and Ctrl-C reach the capture inside Holdfast.app (it found the wrong
  process before and could keep recording), the terminal waits for the transcript and gets the real
  exit status, and progress lines arrive as they happen.
- `--app` and the Listen page take exactly the app chosen ("Music" no longer catches YouTube Music;
  an ambiguous name is refused with the matches listed), follow an app's new audio processes within a
  second, and can start before the app plays anything. An output device with a microphone of its own
  (a USB headset) is no longer recorded unless the microphone is asked for. A device change (AirPods
  connecting) rebuilds the capture; the microphone alone restarts on its new input.
- Stop pressed while the model loads leaves nothing running; a stream ffmpeg can't open says why
  instead of "heard no speech"; piped audio is paced, not held in memory; live lines are built from
  the open line only, so long sessions don't slow down.
- Transcripts: the model sees the beginning and end of a long one (40,000 characters, not the first
  12,000), and the whole transcript is offered in the Inbox as its own note beside the summary.
  Switching vaults while listening is refused; a transcript saved in a managed vault is indexed at
  once. When this Mac answers instead of the other one, the answer names this Mac's model.
- Speed: opening a citation no longer re-reads the whole vault, Research reads it once per run, and
  the Ask page no longer checks the disk for the model on every streamed word.
- Not tested: the headset-microphone fix and device-change rebuilds (no headset or device switch
  here), switching vaults while listening, and a managed vault's transcript.

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
