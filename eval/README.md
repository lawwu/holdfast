# Eval: synthetic case reports

A repeatable test of `mackb ask` on the first use case: a counselor asking questions
of past case reports. **All data here is synthetic.** "D.M." and his family are
fictional, and no real counselee material is used.

| File | What it is |
| --- | --- |
| `cases/dm-session-01..08.md` | Eight session reports for one fictional counselee, a man struggling with anger in his marriage. Each follows the ACBC Phase 3 Case Report Form (its 16 questions), with facts kept consistent across sessions: one relapse, two joint sessions, a safety plan, memory verses, and the counselor's "could have done better" notes |
| `make_docx.py` | Renders `cases/*.md` to `docx/*.docx` with macOS `textutil`, so the eval goes through the same Word import as real reports |
| `questions.json` | 16 questions: 10 single-session facts, 5 that need several sessions, and 1 the reports cannot answer (medication). Each lists the regex patterns a correct answer must contain and the sessions that hold the answer |
| `compare.py` | Side-by-side table of every run in `results/` |
| `results/<label>.json` | One file per run: every answer, its score, sources and timing |

## Run it

```bash
python3 eval/make_docx.py
export MACKB_VAULT=~/MacKB-eval
mackb ingest eval/docx --tag case-report && mackb index
MACKB_BACKEND=mlx    mackb eval eval/questions.json --label qwen38-27b-4bit-mlx
MACKB_BACKEND=ollama mackb eval eval/questions.json --label qwen38-27b-8bit-ollama
python3 eval/compare.py
```

## Scoring

- **Facts found:** the share of a question's required patterns that appear in the
  answer. Crude (it can't tell a wrong statement that happens to contain a keyword)
  but cheap and repeatable. Read the answers for anything that matters.
- **Retrieval recall:** the share of the expected sessions that were among the
  passages given to the model. This is the same for every model, so a low fact
  score with full recall is the model's fault.
- **Cited:** whether the answer cites at least one passage as `[n]`.
- The unanswerable question passes if the answer says the reports don't say.
