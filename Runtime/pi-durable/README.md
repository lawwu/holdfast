> Historical prototype, retained for reference. Holdfast now uses [regular Pi](../pi/README.md).
> This runtime is not selected or bundled by current builds. Existing user databases are preserved.
> The setup and recovery behavior below describe the earlier Durable prototype.

# Pi Durable + Holdfast model providers

Pi Durable **1.5.1** owns the tool loop, full transcript, compaction, task recovery,
and SQLite history. Holdfast owns its SwiftUI app, selected inference provider, six
vault tools, citations, proposal validation, Inbox, Apply Change, and Undo.
The dependency versions and transitive packages are pinned in `package-lock.json`.

```text
Holdfast Ask / follow-ups
  └─ Swift PiAgent → private JSONL pipes → Node Pi Durable → conversation.sqlite
       ↑                                  ├─ holdfast-mlx provider
       │    one model turn per request ←──┘        │
       ├─ MLXAgentModel or ServerAgentModel ←────┘
       └─ native tools ← stable durable task ID
            ├─ search / read_note / list_folder / list_tables / query_table
            └─ propose_edit → Inbox → user Apply Change → snapshot + write
```

With LocalMLX, no inference HTTP server or second copy of the model is needed.
Ollama, LM Studio and custom servers use the reusable Swift `ModelProviders` transport.
The Node process still talks only to the Swift bridge and never receives server credentials.
The Pi provider streams native text and returns typed calls and token usage. MLX keeps
its KV cache when the model-visible transcript matches; replay or compaction
rebuilds that cache using the already-loaded model. Only the Swift bridge provider is registered. There are no Pi coding tools, shell tools, or cloud fallback.

The inference implementation is now the separate
[`pi-swift-mlx` package](../../Packages/pi-swift-mlx/README.md). This runner imports
its provider factory and injects Holdfast's pipe transport. `MLXAgentModel` adapts
the app runtime to the package's `LocalMLX` library; there is no second copy of
the inference loop here. Holdfast validates its allowed tool declarations and
string arguments at the native boundary before returning calls to the harness.
The package itself accepts general JSON schemas and knows nothing about the Inbox.
The local npm dependency is installed as a copy (`.npmrc: install-links=true`) so
its peer dependencies resolve inside this runtime on a fresh checkout. After
editing the provider package, run `npm ci --prefix Runtime/pi-durable --ignore-scripts`
to refresh that copy. The app packager always includes a fresh `npm pack` archive.

## Run

Needs macOS 15+, Xcode/Swift build dependencies, Node **22.19+**, and either a downloaded Holdfast MLX model or a configured model server. Tested development runtime: Node 26.12.1.

```sh
bash scripts/make_pi_prototype.sh
open 'build/Holdfast Pi Prototype.app'
```

This makes a separate app with Pi enabled by default. It has a separate settings
domain; choose the vault in the app. Its Inbox and records are the existing
Holdfast state for that vault. The app includes the pinned JavaScript packages;
Node itself is still an external prerequisite. The normal app can opt in with
**Settings → Answer model → Use Pi Durable for Ask (prototype)** after installing
the packages with `npm ci --prefix Runtime/pi-durable --ignore-scripts`.

```sh
HOLDFAST_VAULT=/path/to/vault .build/harness-xcode/Build/Products/Release/holdfast \
  ask --pi --no-embed --conversation 7B3298B4-C116-44F0-B0FA-FDE006102ED0 \
  "Mark the basis item in finance/checklist.md as done"
```

Reuse `--conversation UUID` for follow-ups. Retry an interrupted request with
the same conversation and question; the bridge reuses its pending request ID.
`--request-id UUID` also supports deliberate duplicate-submission tests. An
interrupted app request appears as **Resume** in Answer settings. Explicit Stop
cancels the durable run; quitting/crashing leaves unfinished work recoverable.
Model requests have a two-retry budget, including crashes during generation;
repeated failures stop the run rather than retrying indefinitely. A completed
tool result is retained when the following generation is retried.
`HOLDFAST_AGENT_HARNESS=pi|swift` overrides the preference. `HOLDFAST_NODE` can
point at a Node executable; `HOLDFAST_PI_DIR` at this directory.

Provider selection is shared with the native harness (Settings → Answer, or
`HOLDFAST_BACKEND=mlx|ollama|lmstudio|custom`). The historical `holdfast-mlx` provider ID
is retained for durable conversation compatibility; it now routes to the selected Swift adapter.
Counseling results latch a native local-only flag before acknowledgement. Future model requests,
including after restart, switch to embedded LocalMLX or fail closed. Inbox approval is unchanged.

## Approval and recovery boundary

Only `propose_edit` changes app state, by writing a proposal in the Inbox. Pi
cannot approve it. Existing stale-file, generated-file, extension, and path
checks remain in Swift. Multiple edits to a note coalesce. Approved edits save
an unthrottled, byte-exact snapshot before writing, including UTF-8 BOM handling.

Each native tool result and its numbered sources are atomically saved before
the response is acknowledged to Pi. A retried task ID returns that receipt.
Proposal metadata also records the operation ID in the proposal's atomic write,
covering a crash between creating the proposal and saving the receipt. Approved
proposal metadata stays in the filing log. The same ID cannot be reused for
different arguments within a conversation's native receipt store.

State lives under the vault's existing Holdfast state directory, in
`pi-durable/<conversation UUID>/`: `conversation.sqlite`, `native.json`, and a
temporary `pending.json`. These include note content and are local to this Mac;
the directories/files are private (0700/0600). One process holds a conversation
lock; tools run sequentially. Treat SQLite and native state as one unit when
backing up or removing a conversation. They are retained until removed manually.

## Checks

```sh
npm test --prefix Runtime/pi-durable
npm ci --prefix Packages/pi-swift-mlx --ignore-scripts
npm test --prefix Packages/pi-swift-mlx
python3 Tests/pi_integration.py .build/harness-xcode/Build/Products/Release/holdfast
bash scripts/test_agent_runtime.sh
```

The runner suite uses real Pi Durable and SQLite with a fake native peer, including
a forced kill after a tool side effect, replay, duplicate submissions, and follow-ups.
The extracted package tests both Pi harnesses, streaming, typed tool schemas,
malformed/truncated calls, transport framing and cancellation. The Swift suite
uses a marked synthetic vault and scripted local inference through the real pipe
bridge, native tools, approval/Undo, citation restoration, and file guards.

The [real 27B smoke test](../../eval/agent-comparison/results/2026-11-10-pi-durable/summary.json)
completed a checkbox edit in 66.6 seconds and a follow-up insertion after restarting
the process in 59.3 seconds. Both proposals left the note unchanged until approval;
both approvals and byte-exact Undos passed through the production CLI. The Swift
suite also kills its native host after a proposal and resumes the unfinished Pi
request without creating another proposal. GUI clicks were not automated on this
Mac (Accessibility access is unavailable).

The [extracted provider checks](../../eval/agent-comparison/results/2026-11-10-provider-package/checks.json)
also exercise the ordinary Pi SDK and Pi Durable with the standalone Swift host
and the real local 27B model. Both preserve nested JSON arguments, including
booleans and nulls. A separate Holdfast run through the extracted library passed
proposal, approval and byte-exact Undo. These are functional checks, not a speed
comparison between harnesses.

## Prototype limits

- Pi Durable is an experimental upstream API. Upgrades require rerunning recovery
  tests; the archived `pi-mlx-models` launcher is not a dependency.
- Text only, one local model, sequential tools, eight tool rounds per input and a
  32-call native limit per invocation. No Pi extensions, subagents, or code mode.
- Context metadata is conservatively set to 32K, with foreground compaction
  enabled; background compaction is disabled to serialize use of the local GPU.
  Long-context compaction has not yet been tested with the real MLX model.
- A resumed generation reruns inference; token-level continuation is not saved.
  Existing Swift-only conversations enter Pi as a short textual handoff.
- The native process owns approvals and file policy. This is an application
  boundary, not an OS sandbox for Node or a guarantee against malicious packages.
- Packaging is local/ad-hoc. Node distribution, notarization, transcript retention
  controls and a richer conversation inspector remain future work.
