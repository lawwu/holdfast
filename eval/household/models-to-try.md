# Models to try next (researched 2026-11-05)

All of these have mlx-community builds whose architecture the app's MLX
library already loads (`qwen3_5`, `qwen3_5_moe`, `gpt_oss`, `gemma4`), so each
is a download plus a line in `run.sh`. Sizes are the 4-bit (or MXFP4) download
on Hugging Face; all fit comfortably in 64 GB next to the embedder and reranker.

## Answer and filing models

| Try | Repo | Size | Why |
| --- | --- | --- | --- |
| 1 | `mlx-community/Qwen3.6-35B-A3B-4bit` | 20.4 GB | Mixture-of-experts with ~3B active: should run at Gemma 26B speed. The question is whether it keeps Qwen 3.8 27B's filing accuracy (100% place, 96% facts) at ~12 s/file instead of 63 s. The most likely new default. |
| 2 | `mlx-community/gpt-oss-20b-MXFP4-Q8` | 12.1 GB | OpenAI's open model; strong at tool calls, which is what Research mode is. A reasoning model: needs its reasoning effort set low, or answers slow down. |
| 3 | `mlx-community/gemma-4-31b-it-4bit` | 18.4 GB | Google's dense Gemma 4. Tests whether the 26B MoE's misses (79% in Research, the bank-statement filing) are from its 4B active parameters. |
| 4 | `mlx-community/Qwen3.6-27B-4bit` | 16.1 GB | The previous dense Qwen, for a same-size check on 3.8. Low priority. |

Skipped: Mistral Small 4 (119B MoE; too big for 64 GB at useful quality),
Mistral Small 3.2 24B (older than the rest), DeepSeek V4 (hundreds of GB),
Qwen3-Coder-Next (a coding model, ~52 GB).

## Search

| Try | Repo | Size | Why |
| --- | --- | --- | --- |
| 1 | `mlx-community/Qwen3-Embedding-8B-4bit-DWQ` | 4.3 GB | The most-cited open embedder (only a stub of the full model is in the HF cache). Search-only runs take minutes, so this is the cheapest test: `MACKB_EMBED_DIR=<snapshot> run.sh retrieval`. |
| 2 | `mlx-community/Qwen3-Embedding-4B-4bit-DWQ` | 2.3 GB | Middle size if 8B is slow to index. |
| 3 | `mlx-community/Qwen3-Reranker-4B-mxfp8` | 4.2 GB | The reranker did more for search than the embedder did (+6 to +12 points); a bigger one may help again. |

Not runnable yet: `bge-m3` (XLM-RoBERTa, not in the Swift embedders library)
and `bge-reranker-v2-m3`. Google publishes no open reranker, so an all-Google
stack stays without one.

## Speech

The fixture has no recordings, so transcription isn't scored. Parakeet v3
stays; adding a few synthetic voice memos to `drops/` would let
`whisper-large-v3-turbo` (already downloaded) be compared.

## Cloud baseline

Gemini (`MACKB_BACKEND=gemini`, needs `GEMINI_API_KEY`) is wired up for the
synthetic fixture only. Worth one run as a ceiling for the local models.

## Sources

- https://insiderllm.com/guides/best-local-llms-mac-2026/
- https://llmcheck.net/
- https://dev.to/brunocerberus/running-local-llms-on-apple-silicon-2ecm
- https://openclawdc.com/blog/mlx-model-coverage-apple-silicon/
- https://supermemory.ai/blog/best-open-source-embedding-models-benchmarked-and-ranked/
- https://builderai.tools/blog/best-open-source-embedding-models-2026
- Hugging Face model pages and configs for every repo above (checked 2026-11-05)
