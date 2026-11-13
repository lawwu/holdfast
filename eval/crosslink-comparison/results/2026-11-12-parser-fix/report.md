# Cross-link parser fix — safety recheck

November 12, 2026. All 23 integration safety checks pass after tightening the production parser. The MLX runtime, model settings, prompts, candidate selection, and package dependencies remain unchanged.

The parser now requires one complete JSON object containing exactly a Boolean `link` and a string `reason`, after existing thought-channel normalization. It rejects truncated output, string/numeric Booleans, missing or extra fields, duplicate keys, trailing commas, nested objects, and surrounding prose or code fences. Invalid replies return an error and a negative verdict, producing no Inbox proposal.

Additional validation: 43 standalone parser cases passed. Replaying all 102 saved model replies from the original comparison preserved their Boolean decisions; no new model inference was needed. The app snapshot built successfully.

Private notes remain excluded, detected sensitive text is removed from reasons, valid proposals still await explicit Apply, and Undo restores the source bytes.

| Safety check | Result |
| --- | --- |
| private and confidential excluded from candidates | PASS |
| private vault excludes all notes | PASS |
| backend error | PASS |
| backend error after positive output | PASS |
| empty response | PASS |
| refusal prose | PASS |
| malformed positive JSON | PASS |
| string Boolean | PASS |
| numeric Boolean | PASS |
| missing reason | PASS |
| wrong reason type | PASS |
| extra field | PASS |
| duplicate link key | PASS |
| trailing comma | PASS |
| trailing prose | PASS |
| refusal with positive example | PASS |
| fenced JSON | PASS |
| multiple JSON objects | PASS |
| nested positive object | PASS |
| valid negative | PASS |
| valid positive with sensitive reason | PASS |
| valid positive | PASS |
| explicit Apply changes note; Undo restores bytes | PASS |

[Raw checks](summary.json) · [Source snapshot hashes](source-hashes.json) · [Original comparison](../2026-11-12-three-arm/report.html)

Rerun from the repository root:

```sh
bash scripts/test_crosslink_parser.sh eval/crosslink-comparison/results/2026-11-12-three-arm
python3 -B eval/crosslink-comparison/build.py
python3 -B eval/crosslink-comparison/safety.py --out .build/crosslink-safety-new-run
```

Choose a new output directory for each safety run. The original benchmark and its labels remain provisional; these checks validate parser and proposal behavior, not model quality.
