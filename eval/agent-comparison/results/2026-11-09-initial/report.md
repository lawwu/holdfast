# Pi / Ollama / Swift comparison

Synthetic notes only. One fresh conversation and vault per case; no default Pi tools or cloud providers.

| Setup | Passed | Mean agent seconds | Median agent seconds |
|---|---:|---:|---:|
| pi-ollama | 5/5 | 88.8 | 88.9 |
| swift-ollama | 5/5 | 93.2 | 93.9 |
| swift-mlx | 5/5 | 103.3 | 85.3 |

Timings describe completed runs only; a single pass per case is exploratory, not a stable speed ranking.

| Task | Run | Setup | Pass | Agent seconds | Tool calls | Output tokens |
|---|---:|---|---|---:|---:|---:|
| checkbox | 1 | pi-ollama | yes | 55.5 | 2 | 201 |
| checkbox | 1 | swift-ollama | yes | 57.0 | 2 | 201 |
| checkbox | 1 | swift-mlx | yes | 72.1 | 2 | 195 |
| insert | 1 | pi-ollama | yes | 52.1 | 2 | 190 |
| insert | 1 | swift-ollama | yes | 59.9 | 2 | 190 |
| insert | 1 | swift-mlx | yes | 77.3 | 2 | 224 |
| combined | 1 | pi-ollama | yes | 88.9 | 3 | 298 |
| combined | 1 | swift-ollama | yes | 100.4 | 3 | 298 |
| combined | 1 | swift-mlx | yes | 123.5 | 3 | 314 |
| table | 1 | pi-ollama | yes | 89.9 | 4 | 259 |
| table | 1 | swift-ollama | yes | 93.9 | 4 | 259 |
| table | 1 | swift-mlx | yes | 85.3 | 4 | 279 |
| generated | 1 | pi-ollama | yes | 157.5 | 6 | 472 |
| generated | 1 | swift-ollama | yes | 154.5 | 6 | 472 |
| generated | 1 | swift-mlx | yes | 158.4 | 6 | 708 |

Agent seconds exclude model loading and process startup. Ollama is unloaded then warmed on an unrelated one-token prompt before each trial, so the second harness does not inherit the first harness's task cache.

The two Ollama arms use identical weights, sampling, seed, system prompt and tool implementations. Streaming differs: Pi streams; Swift's HTTP adapter receives complete turns. The proxy records their actual requests and normalizes only provider settings/schema order.

MLX uses the app's 4-bit Qwen3.8-27B; Ollama uses the existing 31.5 GB imported GGUF. Its Q8 tag and Q4_K_M metadata disagree; the attached gguf-types.json, when present, records actual tensor types (Q8_0 plus BF16/F32 in this run). Cross-engine results therefore compare the installed stacks, not equal quantization. No model download or global configuration change is made.

Compaction, long conversations, crash recovery, steering, private locality and concurrent workloads are outside this short-task evaluation. Peak physical/GPU memory is not measured; model sizes are not runtime memory measurements.

Initial-request audit: 5/5 Ollama pairs match after normalizing string versus text-block content and excluding streaming flags. Full wire requests are retained.

Manual review: all five Ollama task pairs produced identical tool names/arguments and identical final answers. The CSV task recovered from a wrong category filter by inspecting rows and retrying. Native MLX also recovered and answered correctly.

Response-quality limitation: all three setups correctly refused the generated-note edit, but then offered a CSV edit that propose_edit cannot perform (it supports .md and .txt only). The operational pass does not mean the responses were flawless. No CSV edit was attempted or applied.

All nine edit trials passed the pending-proposal, exact-content, stale-note refusal, Apply and exact Undo checks. Generated-note refusal was observed in model behavior; these cases did not force a prohibited propose_edit call.

On the checkbox case, the MLX journal reports 1,594 prompt tokens processed on the final turn after 64 on the preceding turn. Ollama reported 1,480 cached tokens out of 1,553 on its final turn. This is evidence to investigate cache reuse in the native adapter/library, not a general claim that one engine is faster.

Order-reversal checks are in ../2026-11-09-reversed/report.md. All four repeats passed, with identical answers and arguments between harnesses. The same Swift checkbox task varied from 57.0 to 87.9 seconds; concurrent Xcode/simulator activity was observed during the repeat, so these are not clean performance measurements.
