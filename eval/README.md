# Eval: synthetic case reports

Names, terminology, and fixture paths in these datasets and saved results have been normalized
for the public repository. Historical scores and timings are unchanged; saved answers are
sanitized records, not byte-for-byte model transcripts or new runs against the current prompts.

A repeatable test of `holdfast ask` on the first use case: a reviewer asking questions
of past case reports. **All data here is synthetic.** "D.M." and his family are
fictional, and no real participant material is used.

| File | What it is |
| --- | --- |
| `cases/dm-session-01..08.md` | Eight session reports for one fictional participant, a man struggling with anger in his marriage. Each follows the ACBC Phase 3 Case Report Form (its 16 questions), with facts kept consistent across sessions: one relapse, two joint sessions, a safety plan, memory verses, and the reviewer's "could have done better" notes |
| `make_docx.py` | Renders `cases/*.md` to `docx/*.docx` with macOS `textutil`, so the eval goes through the same Word import as real reports |
| `questions.json` | 16 questions: 10 single-session facts, 5 that need several sessions, and 1 the reports cannot answer (medication). Each lists the regex patterns a correct answer must contain and the sessions that hold the answer |
| `compare.py` | Side-by-side table of every run in `results/` |
| `results/<label>.json` | One file per run: every answer, its score, sources and timing |

## Run it

```bash
python3 eval/make_docx.py
export HOLDFAST_VAULT=~/Holdfast-eval
holdfast ingest eval/docx --tag case-report && holdfast index
HOLDFAST_BACKEND=mlx    holdfast eval eval/questions.json --label qwen38-27b-4bit-mlx
HOLDFAST_BACKEND=ollama holdfast eval eval/questions.json --label qwen38-27b-8bit-ollama
python3 eval/compare.py
```

## Scoring

- **Facts found:** the share of a question's required patterns that appear in the
  answer. Crude (it can't tell a wrong statement that happens to contain a keyword)
  but cheap and repeatable. Read the answers for anything that matters.
- **Context recall:** the share of the expected facts that appear in the passages
  given to the model. It's the same for every model, so a low fact score with
  full context recall is the model's fault, and a low context recall is
  retrieval's. (Before 2026-11-05 the eval only checked whether the right
  *session* was retrieved; that reported 98% while the passage holding the
  answer was missing.)
- **Cited:** whether the answer cites at least one passage as `[n]`.
- The unanswerable question passes if the answer says the reports don't say.
