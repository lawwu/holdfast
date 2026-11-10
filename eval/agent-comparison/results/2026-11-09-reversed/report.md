# Pi / Ollama / Swift comparison

Synthetic notes only. One fresh conversation and vault per case; no default Pi tools or cloud providers.

| Setup | Passed | Mean agent seconds | Median agent seconds |
|---|---:|---:|---:|
| pi-ollama | 2/2 | 94.6 | 94.6 |
| swift-ollama | 2/2 | 98.0 | 98.0 |

Timings describe completed runs only; a single pass per case is exploratory, not a stable speed ranking.

| Task | Run | Setup | Pass | Agent seconds | Tool calls | Output tokens |
|---|---:|---|---|---:|---:|---:|
| checkbox | 1 | swift-ollama | yes | 87.9 | 2 | 201 |
| checkbox | 1 | pi-ollama | yes | 82.9 | 2 | 201 |
| combined | 1 | swift-ollama | yes | 108.2 | 3 | 298 |
| combined | 1 | pi-ollama | yes | 106.3 | 3 | 298 |

Agent seconds exclude model loading and process startup. Ollama is unloaded then warmed on an unrelated one-token prompt before each trial, so the second harness does not inherit the first harness's task cache.

The two Ollama arms use identical weights, sampling, seed, system prompt and tool implementations. Streaming differs: Pi streams; Swift's HTTP adapter receives complete turns. The proxy records their actual requests and normalizes only provider settings/schema order.

MLX uses the app's 4-bit Qwen3.8-27B; Ollama uses the existing 31.5 GB imported GGUF. Its Q8 tag and Q4_K_M metadata disagree; the attached gguf-types.json, when present, records actual tensor types (Q8_0 plus BF16/F32 in this run). Cross-engine results therefore compare the installed stacks, not equal quantization. No model download or global configuration change is made.

Compaction, long conversations, crash recovery, steering, private locality and concurrent workloads are outside this short-task evaluation. Peak physical/GPU memory is not measured; model sizes are not runtime memory measurements.

Initial-request audit: 2/2 Ollama pairs match after normalizing string versus text-block content and excluding streaming flags. Full wire requests are retained.

These repeats reverse the initial arm order: Swift first, then Pi. Both repeated tasks passed with identical answers and tool arguments between harnesses.

Timing limitation: another Xcode compilation and simulator activity were observed during these repeats. The same Swift checkbox task varied from 57.0 seconds in the initial pass to 87.9 seconds here. Small Pi-versus-Swift gaps cannot be treated as a stable harness speed advantage. See environment-observation.json.

The initial five-task pass and these two repeated cases total 19 successful operational trials. All seven matched Ollama pairs produced identical final answers and tool arguments. Compaction, session restoration and production app integration were not evaluated.
