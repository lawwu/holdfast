# pi-swift-mlx

A reusable Pi provider for local inference with **Swift MLX**. It works with the
regular Pi coding-agent SDK/CLI and Pi Durable through the same `pi-ai` provider.
Tested API versions: `@earendil-works/pi-ai`, `pi-coding-agent`, and `pi-durable`
**1.5.1**. The older `@mariozechner/*` 0.x registration API is not supported.

This npm package contains:

- An npm adapter that translates Pi transcripts, complete tool schemas, streamed
  text, tool calls, token usage, and cancellation.
- A Pi CLI extension that registers the provider and starts the host lazily.
- A build wrapper and release source bundle for the optional **local-mlx-host** helper.

The maintained Swift code lives in two sibling packages:
[LocalMLX](../LocalMLX/README.md) owns embedded MLX inference and `local-mlx-host`;
[ModelProviders](../ModelProviders/README.md) owns the shared inference interface and
HTTP providers. Neither Swift package depends on this adapter or either Pi harness.

The Swift product/module is `LocalMLX`, with inference wire types under
`MLXProtocol`. The npm name, `createSwiftMLXProvider` API, `PI_MLX_*` extension
settings and version-1 JSON protocol remain unchanged by the Swift/host rename.

The provider has **no tools or approvals of its own**. A tool call is returned as
data. The calling harness/app decides which tools exist and executes them. It
accepts nested objects, arrays, numbers, booleans, nulls and JSON Schema; no vault
paths or application-specific tool names are built in.

```text
Pi CLI / SDK ─┐                            ┌─ native app's loaded MLX model
             ├─ pi-swift-mlx ─ transport ─┤
Pi Durable ──┘                            └─ local-mlx-host → local MLX model
```

## Build the standalone host

Requires Apple Silicon, macOS 15+, Xcode with Swift 6.2+, Node 22.19+, and a model
already downloaded in MLX format. No Python, inference HTTP server, model download,
or Holdfast installation is needed. From this package directory:

```sh
npm ci --ignore-scripts
bash scripts/build-host.sh
```

The host and its Metal resource bundles are copied to `build/host/`. Keep that
directory together. `PI_MLX_DERIVED_DATA` can select an Xcode build-cache directory;
`PI_MLX_SOURCE_PACKAGES` can reuse an existing Xcode package checkout cache.
In a repository checkout, the wrapper builds `../LocalMLX`. An installed npm release
uses its self-contained `native/LocalMLX` and `native/ModelProviders` source snapshot.
Its Swift dependency lockfile and source checksums travel with that release.

## Use with regular Pi

Use the current `@earendil-works/pi-coding-agent` distribution. This example uses
the pinned development CLI installed by `npm ci`, without changing a global Pi:

```sh
export PI_MLX_HOST="$PWD/build/host/local-mlx-host"
export PI_MLX_MODEL="mlx-community/Qwen3.8-27B-4bit"
export PI_MLX_MODEL_DIR="/absolute/path/to/downloaded/model"
node node_modules/@earendil-works/pi-coding-agent/dist/cli.js \
  -e "$PWD/extension.mjs" --provider swift-mlx --model "$PI_MLX_MODEL"
```

`PI_MLX_CONTEXT_WINDOW` and `PI_MLX_MAX_TOKENS` override the conservative 32768/2000
metadata defaults; set them to limits appropriate for the chosen model and Mac.
Loading the extension or listing models does not start inference. Pi's tools
remain whatever that Pi installation enables; this provider does not add an
approval system to ordinary Pi's file-editing tools.

## Use with Pi Durable (or pi-ai directly)

```js
import { createModels } from '@earendil-works/pi-ai';
import { createSwiftMLXProvider } from 'pi-swift-mlx';
import { createProcessTransport } from 'pi-swift-mlx/process';

const model = process.env.PI_MLX_MODEL;
const transport = createProcessTransport({
  executable: process.env.PI_MLX_HOST,
  model,
  modelDirectory: process.env.PI_MLX_MODEL_DIR,
});
const models = createModels();
models.setProvider(createSwiftMLXProvider({ model }, transport.generate));
// Pass `models` to Harness.open(...). Select { provider: 'swift-mlx', modelId: model }.
// Install your own tools/extensions in that harness's registry.
// On shutdown, close the harness, then await transport.close().
```

The same complete provider object can be registered with regular Pi's
`pi.registerProvider(provider)` or `ModelRuntime.registerNativeProvider(provider)`.
There is no runtime dependency on either harness; `pi-ai` is a peer dependency.

## Embed in a native app

Add `Packages/LocalMLX` from a checkout as a Swift package dependency and depend on
the `LocalMLX` product. Keep its sibling `Packages/ModelProviders` available too.
See [LocalMLX's guide](../LocalMLX/README.md) for the manifest declaration.

```swift
import LocalMLX

let engine = MLXSession(container: alreadyLoadedModelContainer)
let request = MLXProtocol.Request(
    model: modelID,
    sessionID: conversationID,
    system: "Help the user reflect on their prayer journal.",
    messages: [.init(role: "user", text: "Help me reflect on today.")],
    tools: []
)
let reply = try await engine.respond(to: request) { token in
    // Forward the text delta to the caller.
}
```

This Swift API also works **without Pi, Node, or the subprocess host**. Another
native Mac app can use it directly for chat or generation. The app loads its model
container and supplies its own conversation, prompts, data and optional tools;
the library manages generation, streaming, cancellation and conversation caching.
A prayer app and Holdfast can share this implementation while keeping their data
and behavior separate. Reusing the library does not share a loaded model across
processes: each app normally has its own model memory. Sharing one loaded model
would require a separate local service and scheduling, outside this package.

## Use the same interface with a model server

**ModelProviders** is a separate Foundation-only Swift package with no external package,
SwiftUI, Holdfast, tool execution or persistence dependency. `LocalMLX` depends on it;
`MLXSession` conforms to the same `ModelProvider` protocol as `HTTPModelProvider`.
Depend on `Packages/ModelProviders` if your app only needs server inference. It does
not resolve, download, or link MLX. See [its guide](../ModelProviders/README.md).

```swift
import ModelProviders

let config = ServerConfiguration(kind: .ollama, model: "your-installed-model")
let provider: any ModelProvider = try HTTPModelProvider(configuration: config)
// .lmStudio and .custom use OpenAI-compatible /v1/chat/completions.
// Supply baseURL for another host or an explicit proxy API prefix.
let reply = try await provider.respond(to: Inference.Request(
    model: config.model, system: "Help the user reflect.",
    messages: [.init(role: "user", text: "Help me reflect on today.")], tools: []
)) { textDelta in /* update your UI */ }
```

`models()` discovers IDs; manual IDs also work. The app supplies an optional `apiKey`, stores
credentials itself, and decides which data may reach a server. HTTP streams, typed JSON tool
calls, cancellation, errors and refused redirects are handled here. The API doesn't execute
tools or make model-capability claims from discovery. Applications must choose tool-capable
models and validate their own tool arguments. Truncated/malformed calls are refused.
`MLXProtocol` remains a compatibility alias for `Inference`; JSON fields and protocol version
are unchanged. The package owns no automatic network or local fallback.

Ollama uses native NDJSON and `think`; LM Studio/custom use SSE and portable chat-completions
fields. Configure model-specific reasoning controls on those servers. A localhost server may
proxy a cloud model, so an app's private-data policy should not rely on the hostname alone.

On the JavaScript side, inject a transport instead of spawning the standalone host:

```js
const provider = createSwiftMLXProvider({ model, providerID: 'my-app-mlx' },
  (request, options) => appBridge.generate(request, options));
```

The transport implements `(NativeRequest, { signal, onDelta }) => Promise<NativeReply>`;
the exported types in `index.d.ts` match `MLXProtocol.Request`/`Reply` in Swift. The app
owns transport framing, lifecycle and authorization. Holdfast uses this mode: its
existing model stays loaded inside the app, and its tools, local-content policy,
citations, proposal receipts, Inbox approvals and Undo stay in Holdfast.

## Protocol and boundaries

The standalone host uses UTF-8 JSONL over stdin/stdout, split strictly on LF.

- Request: `{ "type": "generate", "id": "1", "request": { "version": 1, ... } }`.
- Stream: `{ "type": "delta", "id": "1", "text": "..." }`.
- Completion: `{ "type": "response", "id": "1", "result": { ... } }`, or `error`.
- Cancellation: `{ "type": "cancel", "id": "1" }`.

`request` includes model/session IDs, one system prompt, messages, full tool
declarations, and generation controls. Transcript updates are folded before
rendering the model's own chat template. The Swift library normalizes JSON nulls
and boxed booleans/numbers for the template, without changing their meaning.

The engine retains a KV cache when the session, prompt, tools, parameters and
message prefix match. A model/session switch, changed prefix or compaction
rebuilds the cache with the loaded weights. Cancellation/rejection drops partial
cache state. Each engine/transport allows one active generation; the caller owns
scheduling across conversations. The host never executes tool calls or writes
notes, and rejects model/protocol mismatches.

This first version supports text models, `toolChoice: auto|none`, temperature,
max tokens, and configured top-p/top-k/presence penalty. It does not support
images, forced named tools, reasoning-budget controls, or dynamic model discovery.
No speed or model-quality improvement is implied by packaging the same engine.

## Tests and packaging

```sh
npm test
# Opt-in 27B test using the environment above; runs both real harnesses:
node test/live.mjs
npm pack
```

Tests run both actual harnesses with typed tool arguments, test transcript
translation, streaming/usage, malformed and truncated calls, and exercise a
subprocess peer's Unicode framing, cancellation, crash, restart and shutdown.
The opt-in live test uses the actual Swift host and installed MLX model.

`npm pack` runs `scripts/stage-native.mjs` to copy the two maintained Swift packages
into ignored `native/` staging files, with a checksum manifest and the host's dependency
lockfile. Edit the sibling packages, never these generated copies. If lifecycle scripts
are disabled, run `node scripts/stage-native.mjs` explicitly before packing.

The archive includes the adapter, declarations, extension, standalone Swift sources
and build scripts. It excludes models, build outputs, test fixtures and development
dependencies. The package is local and unpublished; publication/license decisions
can be made separately.
