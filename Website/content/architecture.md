---
title: How Holdfast fits together
description: The app, Pi agent loop, reusable Swift providers, and local or server-based models.
editUrl: false
---

Holdfast separates the interface and file approvals from the agent loop and the model that generates answers. The same provider packages can be used by other apps.

## From a question to an answer

1. **Holdfast** owns the window, vault, search, privacy rules, and Inbox.
2. **Regular Pi** runs the conversation and tool loop and saves conversations for follow-ups.
3. **pi-swift-mlx** connects Pi to the model interface supplied by the app.
4. **LocalMLX** runs the model inside the Swift app. **ModelProviders** also supplies HTTP connections for Ollama, LM Studio, and compatible servers.
5. The selected **model** generates text and tool requests. Holdfast validates and executes its own tools.

An edit proposal travels back to Holdfast’s Inbox. Pi does not receive unrestricted file or shell tools in the app, and a model reply cannot approve its own proposal.

[Open the interactive architecture explorer →](/holdfast-docs/explore/)

The explorer compares embedded inference, a standalone helper, and model servers, and walks through the approval path.

## The reusable packages

| Package | Responsibility |
| --- | --- |
| [ModelProviders](../../Packages/ModelProviders/README.md) | Shared inference types and HTTP providers. Foundation only; it can be used without MLX or Pi. |
| [LocalMLX](../../Packages/LocalMLX/README.md) | Embedded Swift MLX inference and the standalone `local-mlx-host` helper. |
| [pi-swift-mlx](../../Packages/pi-swift-mlx/README.md) | The JavaScript adapter for Pi, supporting an embedded app bridge or a standalone host. |

Sharing a library shares code. It does not automatically share one loaded model between app processes. A common model server can serve multiple apps, with each app retaining its own conversation and data rules.

## Which parts stay in the app?

Holdfast owns tools, local-only data rules, Inbox approval, snapshots, and Undo. Those policies do not move into the reusable inference packages.

Holdfast uses **regular Pi**. The reusable adapter also supports Pi Durable, but Durable is not selected or bundled in Holdfast. Interrupted work waits for a new request rather than automatically replaying uncertain actions.

Read the [Pi bridge guide](../../Runtime/pi/README.md) for the integration details, and the [release guide](../../docs/releases.md) for packaging and verification.
