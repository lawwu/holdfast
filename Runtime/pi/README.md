# Regular Pi in Holdfast

Holdfast Ask uses the **regular Pi coding-agent SDK 1.5.1** by default in both
the normal app and CLI. LocalMLX remains the default inference provider, with
Ollama, LM Studio and custom compatible servers available in Answer settings.

```text
Holdfast Ask
  → private JSONL pipes → regular Pi AgentSession → saved JSONL conversation
                           ↓ pi-swift-mlx provider
                       Swift model adapter
                           ├─ LocalMLX (default)
                           └─ ModelProviders → Ollama / LM Studio / custom server

Pi tool requests → Holdfast validation and native tools
                   └─ propose_edit → Inbox → user approval → snapshot + write → Undo
```

Only Holdfast's six tools are enabled: search, read_note, list_folder, list_tables,
query_table and propose_edit. Pi's built-in read/write/edit/bash tools, MCP,
extensions, skills, context-file discovery and model-network discovery are disabled.
Credentials stay in Swift. Local-only private restrictions are checked before
each model request, including after reopening a conversation. The reusable packages
live under `Packages/ModelProviders`, `Packages/LocalMLX` (including `local-mlx-host`),
and `Packages/pi-swift-mlx`. The adapter supports regular Pi and Pi Durable; both
Swift packages also work without a Pi harness. This runtime and its tool integration
remain part of Holdfast.

## Run and package

Development builds require Node **22.19+**, macOS 15+ and the existing Swift
build dependencies. Installer releases bundle a pinned Node runtime. JavaScript dependency
versions are pinned in `package-lock.json`.

```sh
npm ci --prefix Runtime/pi --ignore-scripts
bash scripts/make_app.sh
# Separate artifact, same normal app and regular Pi runtime:
bash scripts/make_pi_prototype.sh
```

The normal app packager includes this runtime; there is no Durable toggle or
Durable dependency in the shipped runtime. `scripts/make_pi_prototype.sh` is now
a compatibility entry point that produces `build/Holdfast Pi.app`, with a separate
settings domain so it can be opened alongside older builds. Choose the vault in the app.

```sh
holdfast ask --no-embed "Mark the basis item in finance/checklist.md done"
holdfast ask --conversation UUID "What did you read?"
```

`--pi` is still accepted but unnecessary. `HOLDFAST_AGENT_HARNESS=swift` selects
the older loop for development/comparison tests only. `HOLDFAST_NODE` and
`HOLDFAST_PI_DIR` override the Node executable and this runtime's location.

## Sessions, interruption and compatibility

New conversations live in the vault's private state directory under `pi/<UUID>/`:

- `sessions/*.jsonl`: ordinary Pi history, tool results, compaction and small
  Holdfast request markers. Completed request IDs return their saved answer.
- `native.json`: native citation numbering, private restriction and tool receipts.
- `pending.json`: the current request; retained after a crash so Settings can open
  a follow-up draft. Opening it does not submit anything.

Regular Pi continues saved conversations on a new user request. It **does not
restart an interrupted job automatically**. Reusing an unfinished request ID is
refused; a new request can continue the conversation. Unmatched historical tool
calls are marked interrupted with an unknown outcome, without executing them.
Check existing Inbox proposals before asking for the same change again. Stop
cancels the active turn and inference. A partial generation is not resumed token
by token. Compaction is enabled; background cache warming is disabled.

The previous `pi-durable/<UUID>/` files and pending jobs are left untouched. They
are not executed or converted to regular Pi sessions. Continuing an old app chat
provides the existing short conversation handoff. Native privacy/source metadata
is copied into the new sidecar when needed, so old private results cannot be sent
to a server. The existing Inbox and approved-file history stay in place.

Native tools remain sequential, with at most 32 tool calls per invocation and
12 model requests per submitted turn (including any compaction). All files in
the session can contain note text; they stay in Holdfast's local state directory.

## Checks

```sh
npm test --prefix Runtime/pi
npm test --prefix Packages/pi-swift-mlx
python3 Tests/pi_integration.py .build/harness-xcode/Build/Products/Release/holdfast
python3 Tests/provider_integration.py .build/harness-xcode/Build/Products/Release/holdfast
# Opt-in checks with installed real 27B models and a synthetic vault:
python3 Tests/provider_integration.py .build/harness-xcode/Build/Products/Release/holdfast --live-mlx
python3 Tests/provider_integration.py .build/harness-xcode/Build/Products/Release/holdfast --live-ollama
```
