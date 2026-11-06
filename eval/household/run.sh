#!/bin/zsh
# Runs the household fixture across models and writes results/ + report.md.
#
#   eval/household/run.sh            # everything (a few hours on an M1 Max)
#   FIXTURE=household-hard eval/household/run.sh qa   # another fixture with the same layout
#   eval/household/run.sh filing     # one stage: retrieval | filing | qa | research | candidates | small | rerankers | claude | gemini
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
#   qwen36moe    Qwen 3.6 35B A3B 4-bit · Qwen3-Embedding-0.6B · Qwen3-Reranker   (candidates, from
#   gptoss20b    gpt-oss 20B MXFP4      ·   "                  ·   "              models-to-try.md)
#   gemma31b     Gemma 4 31B 4-bit      ·   "                  ·   "
#   qwen36d27b   Qwen 3.6 27B 4-bit     ·   "                  ·   "
#   gemini       Gemini API (MACKB_GEMINI_MODEL, default gemini-flash-latest) · Qwen retrieval;
#                only if GEMINI_API_KEY is set. Synthetic data only: this sends the fixture to Google.

cd "$(dirname "$0")/../.."
B=.build/xcode/Build/Products/Release/mackb
T=eval/household                    # the scripts
H=eval/${FIXTURE:-household}        # the fixture: vault/, questions.json, filing.json, results/
export MACKB_VAULT=$PWD/$H/vault MACKB_TODAY=2026-11-05 MACKB_FIXTURE=$PWD/$H
QWEN=mlx-community/Qwen3.8-27B-4bit
G26=mlx-community/gemma-4-26b-a4b-it-4bit
GE4=mlx-community/gemma-4-e4b-it-4bit
# Candidates (stage: candidates): label=repo
CANDIDATES=(qwen36moe=mlx-community/Qwen3.6-35B-A3B-4bit gptoss20b=mlx-community/gpt-oss-20b-MXFP4-Q8
            gemma31b=mlx-community/gemma-4-31b-it-4bit qwen36d27b=mlx-community/Qwen3.6-27B-4bit)
# Research mode on the questions that need several files or numbers from CSVs.
# A fixture can list its own in research-ids.txt.
HARD=(h21 h22 h23 h24 h25 h26 h27 h28 h29 h30 h33 h34 h35 h36)
[[ -f $H/research-ids.txt ]] && HARD=($(<$H/research-ids.txt))
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
  MACKB_BACKEND=mlx MACKB_MLX_REPO=$QWEN run $B eval-filing $H/filing.json --label qwen27b --out $H/results/filing
  MACKB_BACKEND=mlx MACKB_MLX_REPO=$G26 run $B eval-filing $H/filing.json --label gemma26b --out $H/results/filing
  MACKB_BACKEND=mlx MACKB_MLX_REPO=$GE4 run $B eval-filing $H/filing.json --label gemmae4b --out $H/results/filing
  MACKB_BACKEND=mlx MACKB_MLX_REPO=$G26 MACKB_EMBED=embeddinggemma MACKB_RERANK=0 run $B eval-filing $H/filing.json --label google26b --out $H/results/filing
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

if want candidates; then
  for c in $CANDIDATES; do
    lab=${c%%=*} repo=${c#*=}
    MACKB_BACKEND=mlx MACKB_MLX_REPO=$repo run $B eval-filing $H/filing.json --label $lab --out $H/results/filing
    MACKB_BACKEND=mlx MACKB_MLX_REPO=$repo run $B eval $H/questions.json --label $lab --out $H/results/qa
    MACKB_BACKEND=mlx MACKB_MLX_REPO=$repo run $B eval $H/questions.json --research $(only) --label $lab-research --out $H/results/qa
  done
fi

# Small models for 8/16 GB Macs (stage: small): filing and plain Q&A only; Research mode's
# long tool-loop prompts are the case memory.py measures.
SMALL=(qwen35-2b=mlx-community/Qwen3.5-2B-4bit gemmae2b=mlx-community/gemma-4-e2b-it-4bit
       qwen35-4b=mlx-community/Qwen3.5-4B-4bit qwen35-9b=mlx-community/Qwen3.5-9B-4bit)
if want small; then
  for c in $SMALL; do
    lab=${c%%=*} repo=${c#*=}
    MACKB_BACKEND=mlx MACKB_MLX_REPO=$repo run $B eval-filing $H/filing.json --label $lab --out $H/results/filing
    MACKB_BACKEND=mlx MACKB_MLX_REPO=$repo run $B eval $H/questions.json --label $lab --out $H/results/qa
  done
fi

# Larger rerankers (stage: rerankers): search alone with each, on both embedders.
# The 8B (mlx-community/Qwen3-Reranker-8B-mxfp8) doesn't load: its untied lm_head isn't read by
# the Swift reranker loader (keyNotFound lm_head.weight), so search would silently run without one.
RERANKERS=(rr4b=mlx-community/Qwen3-Reranker-4B-mxfp8)
if want rerankers; then
  for c in $RERANKERS; do
    lab=${c%%=*} repo=${c#*=}
    MACKB_RERANK_REPO=$repo run $B eval $H/questions.json --retrieval-only --label search-qwen3emb-$lab --out $H/results/qa
    MACKB_EMBED=embeddinggemma MACKB_RERANK_REPO=$repo run $B eval $H/questions.json --retrieval-only --label search-embgemma-$lab --out $H/results/qa
  done
fi

# Claude Code as a cloud baseline (stage: claude): the same questions and documents,
# answered by Claude Code over a scratch copy of the vault (see claude_code.py).
# Runs under the Claude login; counts against the plan's usage.
CLAUDE_MODELS=(claude-haiku=claude-haiku-5-5 claude-sonnet=claude-sonnet-5-5 claude-opus=claude-opus-5-5 claude-fable=claude-fable-5-1)
if want claude; then
  for c in $CLAUDE_MODELS; do
    lab=${c%%=*} model=${c#*=}
    run python3 $T/claude_code.py --model $model --label $lab --filing
    run python3 $T/claude_code.py --model $model --label $lab
  done
fi

if want gemini && [[ -n $GEMINI_API_KEY ]]; then
  MACKB_BACKEND=gemini run $B eval-filing $H/filing.json --label gemini --out $H/results/filing
  MACKB_BACKEND=gemini run $B eval $H/questions.json --label gemini --out $H/results/qa
fi

python3 $T/report.py > /dev/null && echo "\nwrote $H/report.md" >&2
