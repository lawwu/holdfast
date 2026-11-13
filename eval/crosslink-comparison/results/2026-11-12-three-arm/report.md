# Cross-link experiment — provisional results

**Follow-up:** the parser has been fixed and all 23 safety checks pass. [See the recheck](../2026-11-12-parser-fix/report.md). The findings below preserve the original baseline.

No runtime or default-model adoption is made. Labels await human review; safety failures in the existing parser must be addressed before treating malformed responses as safe.

Adding the MLX grammar did not reduce observed schema failures: both MLX arms produced valid JSON in every scored trial. Apple's median response was 1.57s versus 13.94s for current MLX. It proposed 6 false links and missed 0, versus 0 false and 2 missed for current MLX, against the provisional labels.

Machine: Apple M1 Max, 64 GiB; ProductName:		macOS; ProductVersion:		27.2; BuildVersion:		26B123.
Apple: AFM 3 Core, 4096-token context. MLX: `mlx-community/Qwen3.8-27B-4bit`; checkpoint hashes in `environment.json`.

Sixteen fixed public synthetic pairs, eight positive/eight negative provisional labels, two passes with reversed arm/case order. Each arm repeats its first prompt at the end for a warm measurement. The quality table excludes those warm repeats. Repeated pairs are not independent samples.

[Review the labels](label-review.html) · [Raw summary](summary.json)

| Arm | Scored trials | Agreement with provisional labels | False links | Missed links | Schema failures | Backend errors | Refusal/guardrail matches | Median seconds |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Current MLX | 32 | 93.8% | 0 | 2 | 0 | 0 | 0 | 13.94 |
| Same MLX + JSON grammar | 32 | 93.8% | 0 | 2 | 0 | 0 | 0 | 12.63 |
| Apple typed output | 32 | 81.2% | 6 | 0 | 0 | 0 | 0 | 1.57 |

Thrown backend errors fail closed in `CrossLink.judge` and count as missed links when a positive was expected. Schema failures count responses that are not exactly a JSON object with Boolean `link` and string `reason`, even if the existing parser salvages them. Refusal/guardrail matches use typed Apple errors or recorded error/response text and need manual review; they are not inferred from every negative verdict.

## Latency and memory

| Arm | Model load seconds per pass | First request seconds per pass | Same prompt warm repeat seconds | Total process seconds | Process peak RSS GiB | MLX peak allocation GiB |
| --- | --- | --- | --- | ---: | ---: | ---: |
| Current MLX | 4.34, 5.85 | 16.90, 7.03 | 22.08, 12.43 | 549.63 | 11.80 | 16.22 |
| Same MLX + JSON grammar | 4.30, 5.12 | 20.21, 8.08 | 19.02, 10.89 | 489.47 | 13.62 | 16.22 |
| Apple typed output | not separately exposed | 3.71, 1.23 | 2.18, 1.34 | 67.15 | 0.04 | not applicable |

All arms reserve 2,000 output tokens. MLX uses a configured 32,768-token context; Apple reports 4,096 tokens on this device. Apple input counts include framework schema overhead, so token counts are not directly interchangeable.

- Current MLX: prompt tokens [283, 1272]; output tokens [25, 59]; 0 pairs changed their Boolean verdict between passes; 1 warm repeats changed the first verdict.
- Same MLX + JSON grammar: prompt tokens [283, 1272]; output tokens [24, 49]; 0 pairs changed their Boolean verdict between passes; 0 warm repeats changed the first verdict.
- Apple typed output: prompt tokens [379, 1365]; output tokens [17, 37]; 0 pairs changed their Boolean verdict between passes; 0 warm repeats changed the first verdict.

The first request is process-cold, not proven model-cold. Filesystem caches and Apple’s shared model service are uncontrolled; checkpoint hashing warms disk caches. Apple inference runs out of process, so its runner RSS is not the model’s total memory and must not be compared as a memory win over MLX. Observed system-service RSS samples are preserved in each `process.json`; these do not establish exclusive model attribution. Total process time includes loading and warm repeats. No training, weight downloads, or cloud inference occurred.

## Safety probes

| Check | Result |
| --- | --- |
| private and confidential excluded from candidates | PASS |
| private vault excludes all notes | PASS |
| backend error | PASS |
| empty response | PASS |
| refusal prose | PASS |
| malformed positive JSON | FAIL |
| string Boolean | FAIL |
| valid negative | PASS |
| valid positive | PASS |
| explicit Apply changes note; Undo restores bytes | PASS |

The malformed-positive and string-Boolean probes exercise the original parser, not a replacement. A failure can create a proposal but does not edit a source note. Valid proposals require explicit Apply; Undo restored the original bytes. Private/confidential notes were excluded before inference, and an all-private vault produced no candidates.

Unsupported/unavailable systems keep the existing product path because this experiment does not modify the shipped app. No old-OS runtime test or forced system-model unavailability test was performed.

## Disagreements to review

### Current MLX

- c09 (round-1-mlx-current): proposed label=True, model=False. Note B is a general calendar entry that merely lists the appointment date already detailed in Note A, rather than providing new information about the specific dental visit.
- c09 (round-2-mlx-current): proposed label=True, model=False. Note B is a general calendar entry that merely lists the appointment date already detailed in Note A, rather than providing new information about the specific dental visit.

### Same MLX + JSON grammar

- c09 (round-1-mlx-json): proposed label=True, model=False. Note B is a general calendar entry that merely lists the appointment date already detailed in Note A, so it does not provide new information or context about the specific dental visit.
- c09 (round-2-mlx-json): proposed label=True, model=False. Note B is a general calendar entry that merely lists the appointment date already detailed in Note A, rather than providing new information about the specific dental visit.

### Apple typed output

- c03 (round-1-apple-typed): proposed label=False, model=True. (reason scrubbed or absent)
- c06 (round-1-apple-typed): proposed label=False, model=True. same person's ongoing situation
- c07 (round-1-apple-typed): proposed label=False, model=True. same person's ongoing situation
- c07 (round-2-apple-typed): proposed label=False, model=True. same person's ongoing situation
- c06 (round-2-apple-typed): proposed label=False, model=True. same person's ongoing situation
- c03 (round-2-apple-typed): proposed label=False, model=True. (reason scrubbed or absent)

## Reproducibility

See [experiment instructions](../../README.md). `source-hashes.json` records the actual source snapshot; `fixture-hashes.json` records notes; `environment.json` records checkpoint hashes. All application instruction/note-text hashes matched. Apple’s framework adds its own schema context and tokenization differs. Models ran serially. Raw responses, proposals, errors, timings, and sampled process memory are retained per pass.

Interpretation remains limited by provisional labels, sixteen unique pairs, only two passes, unseeded production sampling, one M1 Max, no Core Advanced coverage, shared OS services, and an unchanged manual candidate set.
