# Bounded cross-link comparison

This experiment compares the **actual current `CrossLink.judge` and `MLXBackend.chat`** with the same MLX weights under a JSON grammar, and Apple's system model returning a typed value. It does not change the shipped runtime or app dependencies.

Completed run: [November 12 comparison report](results/2026-11-12-three-arm/report.html) · [label review](results/2026-11-12-three-arm/label-review.html). Quality scores remain provisional; no runtime change is adopted.

Parser follow-up: [all 23 safety checks pass](results/2026-11-12-parser-fix/report.md). The production parser is now strict; MLX is unchanged. The original comparison records preserve the earlier baseline, including its two parser failures.

To check the parser and proposal safeguards without model inference:

```sh
bash scripts/test_crosslink_parser.sh eval/crosslink-comparison/results/2026-11-12-three-arm
python3 -B eval/crosslink-comparison/build.py
python3 -B eval/crosslink-comparison/safety.py --out .build/crosslink-safety-new-run
```

```sh
python3 -B eval/crosslink-comparison/build.py
python3 -B eval/crosslink-comparison/run.py \
  --out eval/crosslink-comparison/results/my-run
python3 -B eval/crosslink-comparison/report.py \
  eval/crosslink-comparison/results/my-run
```

The output directory must be new. `--smoke --rounds 1` runs one pair and a warm repeat per arm. `--arms mlx-current mlx-json apple-typed` selects arms; `--model` selects an already downloaded MLX model. No model downloads, external inference providers, or real notes are used.

The measurement harness needs Xcode 27 and macOS 27 for Apple's variant, context, and token-usage APIs, plus an already downloaded MLX checkpoint. This is an experiment requirement, not a new minimum OS for Holdfast. Each arm is capped at 40 minutes per pass and each reply at 2,000 output tokens; timeouts preserve partial records and stop the run.

## What stays fixed

- A frozen set of sixteen eligible public pairs: nine existing synthetic household pairs and seven additional synthetic pairs. Eight provisional positive and eight provisional negative labels. The user explicitly requested a provisional run and will review labels; **these are not yet human-validated ground truth**.
- The same paths, titles, first 1,500 body characters, instructions, and filing temperature for every arm. Prompt hashes are recorded. The judge is evaluated independently of retrieval: this is a fixed candidate set, not a new candidate-selection algorithm or retrieval benchmark.
- The two MLX arms use identical checkpoint files, chat templates, automatic family profile, output ceiling, penalties, and sampling distribution. The current arm calls the production backend directly. The constrained arm adds a grammar mask through `GenerationComponents` to the same generation function. Fast-forward and the library's greedy-only convenience loop are not used.
- The pinned XGrammar version cannot clone matchers. Each constrained request compiles a fresh constraint from the cached grammar tokenizer; that preparation is timed and included. The adapter handles the normal generator's one-token prefetch after EOS without asking a terminated matcher for another mask.
- The production generator has no explicit sampling seed. Both arms retain that behavior. Apple's provider controls its own sampling implementation and schema prompt; the Apple comparison changes the model and structured-output implementation together.
- `CrossLink.judge` parses all results and scrubs reasons. Positive decisions use actual `CrossLink.propose` to create Inbox proposals in disposable vaults. Source hashes must remain unchanged during inference.

## How it is isolated

`build.py` snapshots the current Swift app sources into `.build/crosslink-experiment/source`, replaces the entry point only in that copy, and adds the grammar dependency only to the copied package manifest. The `holdfast` module name remains intact. Builds use the resolved package versions. Source hashes identify the exact snapshot, including existing uncommitted changes.

The executable refuses unmarked vaults. Each process gets a new synthetic vault under `~/.cache`; only its corresponding Application Support state is created and removed. Preferences are overridden in the volatile argument domain, without changing stored app settings. Captured outputs/proposals are copied to the run directory before scratch cleanup.

## Measurements and limits

Two passes reverse both arm order and case order. Each arm gets a fresh runner process. After all cases, the first prompt is repeated to observe a warm request. Warm repeats are excluded from quality scoring.

Record OS, hardware, framework variant/context size, MLX checkpoint SHA-256 hashes, generation settings, token use, model loading, per-request latency, full process time, process peak RSS, and MLX allocator peak. The runner also samples relevant system-process RSS every half second.

“Cold” means **the first request in a new runner process**. Filesystem caches and Apple's shared model-service caches are not forcibly evicted; this is not an established cold-model measurement. Checkpoint hashing itself warms filesystem caches. The warm repeat has identical input but no retained conversation or explicit KV cache. Model-load time is reported separately. Apple's in-process RSS is **not its model memory**: inference runs in shared OS services, and MLX allocator memory is not comparable with that figure. Report unknown attribution honestly.

The corpus is small and repeated observations are not independent. Accuracy, false links, missed links, parse failures, and refusals are provisional until label review. Output validity does not establish semantic correctness. No default adoption follows from this run alone.

The decision gate is deliberately conservative: resolve safety failures and review labels before judging a runtime change. A candidate's observed reduction in time or formatting errors must be weighed against false or missing links, not used to excuse them. This experiment can nominate a candidate for a larger evaluation; sixteen pairs cannot establish production reliability.

## Guarantees tested separately

The invariant probe uses real candidate retrieval over a synthetic index, `CrossLink.run`, proposals, Apply, snapshots, and Undo. It checks private/confidential exclusion, all-private vault exclusion, injected errors, empty output, malformed positive JSON, wrong-type Booleans, and positive/negative outputs. It requires a real eligible candidate so exclusion tests cannot pass vacuously.

Failures were reported before repairing the original baseline. The parser follow-up removes its permissive fallback and expands the safety probes; `safety.py` exits unsuccessfully if any check fails. App routing and macOS 15 support remain unchanged. The probe does not claim to simulate a real unsupported OS or unavailable Apple model.

Review `label-review.html` and report label corrections by case ID. Raw model responses, error strings, and proposals remain available for auditing.
