#!/bin/zsh
# Runs the household fixture across models and writes results/ + report.md.
#
#   eval/household/run.sh            # everything (a few hours on an M1 Max)
#   eval/household/run.sh filing     # one stage: retrieval | filing | qa | research | gemini
#
# Each run is one JSON file in results/{qa,filing}/ named after its setup;
# report.py turns them into report.md. A stage that fails is logged and skipped.
#
# Setups (LLM · embedder · reranker):
#   qwen27b      Qwen 3.8 27B 4-bit   · Qwen3-Embedding-0.6B · Qwen3-Reranker   (the app's default)
#   gemma26b     Gemma 4 26B A4B 4-bit · Qwen3-Embedding-0.6B · Qwen3-Reranker   (swap the answer model only)
#   gemmae4b     Gemma 4 E4B 4-bit     · Qwen3-Embedding-0.6B · Qwen3-Reranker
#   google26b    Gemma 4 26B A4B 4-bit · EmbeddingGemma-300m  · none            (Google models only;
#                Google has no open reranker, and transcription isn't exercised by this fixture)
#   gemini       Gemini API (MACKB_GEMINI_MODEL, default gemini-flash-latest) · Qwen retrieval;
#                only if GEMINI_API_KEY is set. Synthetic data only: this sends the fixture to Google.

cd "$(dirname "$0")/../.."
B=.build/xcode/Build/Products/Release/mackb
H=eval/household
export MACKB_VAULT=$PWD/$H/vault MACKB_TODAY=2026-11-05
QWEN=mlx-community/Qwen3.8-27B-4bit
G26=mlx-community/gemma-4-26b-a4b-it-4bit
GE4=mlx-community/gemma-4-e4b-it-4bit
# Research mode on the questions that need several files or numbers from CSVs.
HARD=(h21 h22 h23 h24 h25 h26 h27 h28 h29 h30 h33 h34 h35 h36)
STAGE=${1:-all}

run() { echo "\n=== $*" >&2; "$@" || echo "!!! failed: $*" >&2; }
want() { [[ $STAGE == all || $STAGE == $1 ]]; }
only() { local o=(); for q in $HARD; do o+=(--only $q); done; echo $o; }

run $B index
MACKB_EMBED=embeddinggemma run $B index

if want retrieval; then
  run $B eval $H/questions.json --retrieval-only --label search-qwen3emb-rerank --out $H/results/qa
  MACKB_RERANK=0 run $B eval $H/questions.json --retrieval-only --label search-qwen3emb-norerank --out $H/results/qa
  MACKB_EMBED=embeddinggemma run $B eval $H/questions.json --retrieval-only --label search-embgemma-rerank --out $H/results/qa
  MACKB_EMBED=embeddinggemma MACKB_RERANK=0 run $B eval $H/questions.json --retrieval-only --label search-embgemma-norerank --out $H/results/qa
fi

if want filing; then
  MACKB_BACKEND=mlx MACKB_MLX_REPO=$QWEN run $B eval-filing $H/filing.json --label qwen27b
  MACKB_BACKEND=mlx MACKB_MLX_REPO=$G26 run $B eval-filing $H/filing.json --label gemma26b
  MACKB_BACKEND=mlx MACKB_MLX_REPO=$GE4 run $B eval-filing $H/filing.json --label gemmae4b
  MACKB_BACKEND=mlx MACKB_MLX_REPO=$G26 MACKB_EMBED=embeddinggemma MACKB_RERANK=0 run $B eval-filing $H/filing.json --label google26b
fi

if want qa; then
  MACKB_BACKEND=mlx MACKB_MLX_REPO=$QWEN run $B eval $H/questions.json --label qwen27b --out $H/results/qa
  MACKB_BACKEND=mlx MACKB_MLX_REPO=$G26 run $B eval $H/questions.json --label gemma26b --out $H/results/qa
  MACKB_BACKEND=mlx MACKB_MLX_REPO=$GE4 run $B eval $H/questions.json --label gemmae4b --out $H/results/qa
  MACKB_BACKEND=mlx MACKB_MLX_REPO=$G26 MACKB_EMBED=embeddinggemma MACKB_RERANK=0 run $B eval $H/questions.json --label google26b --out $H/results/qa
fi

if want research; then
  MACKB_BACKEND=mlx MACKB_MLX_REPO=$G26 run $B eval $H/questions.json --research $(only) --label gemma26b-research --out $H/results/qa
  MACKB_BACKEND=mlx MACKB_MLX_REPO=$QWEN run $B eval $H/questions.json --research $(only) --label qwen27b-research --out $H/results/qa
fi

if want gemini && [[ -n $GEMINI_API_KEY ]]; then
  MACKB_BACKEND=gemini run $B eval-filing $H/filing.json --label gemini
  MACKB_BACKEND=gemini run $B eval $H/questions.json --label gemini --out $H/results/qa
fi

python3 $H/report.py > /dev/null && echo "\nwrote $H/report.md" >&2
