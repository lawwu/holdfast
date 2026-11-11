# ModelProviders

A standalone Swift package for inference types and HTTP model providers. It uses
Foundation and has **no external package dependencies**, including MLX, Pi, or Holdfast.
Requires Swift 6.2+ and macOS 15+.

Add this directory to another app's Swift package dependencies:

```swift
.package(path: "../holdfast/Packages/ModelProviders")
// In the app target's dependencies:
.product(name: "ModelProviders", package: "modelproviders")
```

```swift
import ModelProviders

let configuration = ServerConfiguration(kind: .ollama, model: "your-installed-model")
let provider: any ModelProvider = try HTTPModelProvider(configuration: configuration)
let reply = try await provider.respond(to: Inference.Request(
    model: configuration.model,
    system: "Help the user reflect.",
    messages: [.init(role: "user", text: "Help me reflect on today.")],
    tools: []
)) { textDelta in /* update the app */ }
```

Ollama uses native NDJSON; `.lmStudio` and `.custom` use compatible chat-completion
SSE streams. The package supports model discovery, typed tool-call arguments,
streaming, cancellation, errors, and redirect refusal. The caller supplies the
endpoint, model ID, and optional API key. Discovery does not establish tool support.

`Inference` holds the version-1 request/reply types and `ModelProvider` defines the
shared interface. [LocalMLX](../LocalMLX/README.md) implements the same interface for
embedded inference and depends on this package. HTTP-only apps can depend on
ModelProviders without resolving or building MLX.

Applications own credentials, data policy, tool execution, persistence, and
approvals. This package does not execute tool calls or choose fallback providers.

From the repository root:

```sh
swift build --package-path Packages/ModelProviders
python3 Tests/model_provider_transport.py
```

`ModelProfile` provides portable per-model generation settings, conservative family defaults,
validation, and template options. Applications persist profiles under their own model and
endpoint identities. `ModelIdentity` groups precision variants without merging model sizes.

`ResumableDownload` is a Foundation-only streaming downloader. The caller supplies a stable
revision identity and expected byte count. It retains partial bytes across cancellation and
relaunch, uses HTTP ranges when supported, restarts when a revision changes or the server
ignores ranges, and strips credentials on redirects to another origin. Callers serialize
writes per destination and decide where files can be stored or deleted.
