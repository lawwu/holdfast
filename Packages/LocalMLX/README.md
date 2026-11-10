# LocalMLX

Reusable Swift MLX inference for native macOS apps, plus the inference-only
`local-mlx-host` executable for callers in another process. Requires Apple Silicon,
macOS 15+, and Xcode with Swift 6.2+.

LocalMLX depends on the sibling [ModelProviders](../ModelProviders/README.md) package
for its shared inference interface and types, and on MLX Swift for generation.
Neither Swift package depends on Pi or Holdfast. Keep both sibling directories
together when using this repository as a local dependency.

## Embed in another app

```swift
.package(path: "../holdfast/Packages/LocalMLX")
// In the app target's dependencies:
.product(name: "LocalMLX", package: "localmlx")
```

```swift
import LocalMLX

let engine = MLXSession(container: alreadyLoadedModelContainer)
let request = MLXProtocol.Request(
    model: modelID, sessionID: conversationID,
    system: "Help the user reflect on their journal.",
    messages: [.init(role: "user", text: "Help me reflect on today.")], tools: []
)
let reply = try await engine.respond(to: request) { textDelta in /* update the app */ }
```

`MLXProtocol` is a compatibility alias for `ModelProviders.Inference`. `MLXSession`
implements `ModelProvider` and manages streaming, cancellation, tool-call parsing,
and conversation caching. The app loads its model and owns scheduling, prompts,
data, tools, credentials, and approvals. No Pi, Node, or host process is needed
for direct use. Sharing this library across apps does not share loaded model memory.

## Build the standalone host

```sh
bash Packages/LocalMLX/scripts/build-host.sh
```

The executable and Metal bundles are placed together in `Packages/LocalMLX/build/host/`.
`LOCAL_MLX_DERIVED_DATA`, `LOCAL_MLX_SOURCE_PACKAGES`, and `LOCAL_MLX_OUTPUT_DIR`
can select the Xcode cache, dependency checkout cache, and output directory.
Builds do not download model weights; the caller supplies an existing model directory.

The helper accepts `--model MODEL_ID --model-dir /absolute/path/to/model`, then
serves version-1 JSONL generation, streaming, and cancellation over stdin/stdout.
It has one client and one active generation. It never executes tools or writes notes.
The [pi-swift-mlx adapter](../pi-swift-mlx/README.md) can use this helper or an app's
embedded engine through an injected transport.

Holdfast supplies its native tools, privacy rules, Inbox approvals, snapshots,
and Undo from the app. Those features are not part of this inference package.
