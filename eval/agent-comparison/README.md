# Compare the agent harnesses

Three arms use the same synthetic notes, questions, system prompt and six Holdfast
tools: Pi + Ollama, Swift + Ollama, and Swift + in-process MLX. This separates the
harness comparison (same Ollama weights) from the installed-stack comparison.
All arms enter agent mode directly; Ask's intent routing is not part of the test.

## Results on this Mac

On the 64 GB M1 Max, all **19 operational trials passed**: five tasks on all three
setups, then two tasks repeated with the Ollama arm order reversed. All seven paired
Pi/Swift Ollama trials produced identical answers and tool arguments. Time outside
the model requests stayed below 0.6 seconds per trial.

The [initial report](results/2026-11-09-initial/report.md) contains per-task timing,
proposal checks and manual review. The [reversed-order report](results/2026-11-09-reversed/report.md)
records the four repeats. Timings were noisy: the same Swift checkbox task varied
from 57 to 88 seconds, and concurrent Xcode/simulator activity was observed during
the repeats. This establishes compatibility on these tasks, not a stable speed ranking.

One response issue appeared on all three setups: after correctly refusing a generated
note edit, the model offered a follow-up CSV edit that `propose_edit` cannot perform.
No CSV was changed. The operational pass should not be read as flawless answer quality.

## Compare the editors themselves

The [file-edit comparison](results/2026-11-09-file-editors/report.md) uses Pi's installed
`read`/`edit`/`write` implementations instead of sharing Holdfast's tools. It covers 14
direct scenarios per editor and three model-driven requests per editor, including
repeated checklist items, insertion under a heading and two separated replacements.
All six model-driven trials passed. Direct probes found collateral normalization in
Pi's fuzzy matching and two Holdfast Undo defects:
lost UTF-8 BOM bytes and skipped snapshots for successive approvals.

Run the direct probes without loading a model, then the matched Ollama trials:

```bash
python3 -B eval/agent-comparison/file_edits.py --mode direct \
  --out eval/agent-comparison/results/my-file-tools
python3 -B eval/agent-comparison/file_edits.py --mode models \
  --out eval/agent-comparison/results/my-file-models
```

Both output directories must be new. The direct probes record behavior, including
intentional refusals and unsupported operations; they are not a single pass/fail score.
Model results include correctness checks. Pi uses a scratch-boundary adapter around
its actual file tools; no approval or checkpoint extension is installed. Model prompts
and schemas differ by workflow, so this follow-up measures editors and integration,
not just the harness loop. It uses the same Ollama weights for both arms.

## Reproduce

Build Holdfast, then run with the installed Pi SDK and a local Ollama model:

```bash
python3 eval/agent-comparison/run.py \
  --binary .build/harness-xcode/Build/Products/Release/holdfast \
  --arms pi-ollama swift-ollama swift-mlx \
  --out eval/agent-comparison/results/my-run
```

Use `--only checkbox table`, `--repeats 2`, `--model NAME` or `--mlx-model REPO` to
change the trial. The output directory must be new. Pi is resolved from the installed
`pi` command; no global packages, models or settings are changed. The initial result
uses Pi 0.67.2 and Ollama server 0.40.15. Its Ollama model is the existing imported
Qwen3.8-27B (mostly Q8_0 tensors), while MLX is Qwen3.8-27B 4-bit. They are not equal
quantizations, so an engine speed or quality claim cannot be isolated from these runs.

The runner creates a fresh vault under `~/.cache` for each trial, then removes it and
its Application Support state after saving synthetic evidence. Ollama must have no
loaded models at the start. Each Ollama trial loads the model with an unrelated one-token
prompt, then unloads it at the end. Agent timing excludes model load and process startup;
both are recorded separately. Tests run sequentially to avoid competing for the GPU.

`pi.mjs` uses Pi's real SDK and provider implementation with custom tools. It disables
built-in tools, resource discovery, compaction and retries for this bounded short-task
comparison. Tools run through the `_agent-eval` JSONL bridge into the app's `ToolContext`
and `Edits`; tool intent/outcome records are written before/after execution. The bridge
requires an environment opt-in, a marked synthetic vault and disabled knowledge packs.
It is not a public tool server or a production Pi integration.

A loopback proxy supplies identical temperature, top-p, presence penalty, seed, output
limit and disabled-thinking setting to both Ollama clients. Top-k and context size come
from the installed model's settings, recorded in metadata. The proxy sorts tool schema
keys and strips unsupported provider fields, while preserving real streamed responses
for Pi and complete responses for Swift. Pi's provider context uses exactly Holdfast's
system prompt, without Pi's extra date/cwd suffix. Full requests and responses are kept.

Pass/fail checks inspect the proposed file content, unchanged vault, approval wording,
stale-note refusal, Apply and byte-exact Undo. The CSV task checks the total, a citation
and an actual query call; the generated-note task requires refusal and an explanation.
Answers still need manual review. These fixtures give explicit paths; retrieval quality
is not evaluated (no embedding/reranker or prebuilt search index).

This does not evaluate long conversations, compaction, crash recovery, steering,
counseling locality, concurrency, or peak physical/GPU memory. A single pass per case
is exploratory, not a statistically stable speed ranking. Repeat the cases and alternate
arm order before making a performance decision. The runner reverses arm order on even
repetitions.

References: [Pi SDK](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/sdk.md),
[Ollama compatibility API](https://docs.ollama.com/api/openai-compatibility).
