# Pi's file tools versus Holdfast's proposed edits

This compares Pi's actual installed `read`, `edit` and `write` implementations with
Holdfast's `read_note`, `propose_edit`, Apply and Undo. The earlier harness comparison
gave both loops the same Holdfast tools; it could not establish differences between
the editors themselves.

There are 14 direct scenarios on both editors (28 observations), plus model-driven
trials using the same local Ollama model. Every file is synthetic. No editor code was
changed during the comparison; discovered defects remain in the tested baseline.

Both editors produced correct results on all three model-driven tasks. Pi was faster
in this small sample, but the prompts, tool descriptions and output lengths differ.
The stronger reason to borrow from Pi is its batch edit API and CRLF handling. The
test does not establish an accuracy reason to replace the Swift harness. Keep the
approval workflow, fix its snapshot defects, and avoid Pi's broad fuzzy normalization.

## Model-driven results

| Request | Pi + Ollama | Swift + Ollama | Correctness |
|---|---:|---:|---|
| Tick only the Work occurrence of a repeated item | 37.9 s | 54.6 s | Both exact |
| Insert an item at the end of Work, before Later | 55.5 s | 69.8 s | Both correct section; existing text preserved |
| Tick a curly-quote item and rename a separate item | 51.1 s | 97.6 s | Both exact |

All **6/6 model trials passed**. Existing metadata, Unicode punctuation, Markdown
hard-break spaces and the unrelated file survived. All three Holdfast trials left one
pending proposal, explained approval, applied correctly and restored the original
fixture exactly with Undo. Each trial used a fresh vault, so the successive-approval
defect appears in the separate direct probe, not these single-approval trials.

Pi used one read and one edit call per task. Its two-edit request used one `edits[]`
batch. Holdfast used one read and two proposal calls for that request, coalescing them
into one Inbox item. **Both still used three model requests**: Holdfast returned both
tool calls in the same model turn. Pi generated 132–152 output tokens per task versus
Holdfast's 179–286, with shorter prompts as well. Batching did not save a model round
in these runs, and the timings cannot be attributed solely to the harness or editor.

## Direct editor behavior

These are controlled tool calls, including intentionally invalid or stale inputs.
They establish behavior and policy differences, not a model success rate.

| Scenario | Pi's stock file tools | Holdfast's proposal tool |
|---|---|---|
| Exact targeted edit with Unicode and Markdown hard break elsewhere | Correct; preserves unrelated bytes | Correct after approval; Undo exact |
| Old text occurs twice | Refuses; file unchanged | Refuses; no proposal |
| ASCII quotes supplied for curly-quote text | Fuzzy match succeeds, but changes unrelated text too | Refuses; file unchanged |
| UTF-8 BOM + Windows CRLF, single-line edit | Preserves BOM and CRLF | Keeps CRLF but drops BOM; Undo also lacks BOM |
| LF multiline old text against a CRLF file | Matches and preserves CRLF | Refuses the mismatch |
| Two separate replacements | One batch call; correct result | Two calls coalesce into one proposal; correct result; Undo exact |
| Batch contains one good and one missing match | Refuses the whole batch; writes nothing | First call leaves a partial proposal; second refuses; writes nothing until approval |
| Generated report | Tool permits the edit | Tool refuses |
| CSV row | Tool permits the edit | Tool refuses: only `.md` / `.txt` |
| Create a Markdown file | `write` creates it | `propose_edit` refuses; creation uses other app workflows |
| Unrelated change after model read / proposal | `edit` rereads and preserves the change while applying its replacement | Apply refuses the stale proposal |
| Target text changed after model read / proposal | `edit` refuses because old text is gone | Apply refuses the stale proposal |
| Whole-file write from a stale read | `write` overwrites the intervening addition | Apply refuses the stale proposal |
| Two independently approved changes in quick succession | Both edits succeed; no checkpoint/Undo feature in these tools | Both apply, but the second Undo fails because its snapshot was skipped |

All Holdfast proposals left the note untouched before approval. The unrelated sentinel
file remained byte-identical in all 28 observations. A partial proposal was inspected
but deliberately not applied. Stock Pi's direct tool calls enforce neither Holdfast's
generated-file rule nor its file-type policy; that is a policy difference, not a claim
that the model would always choose to violate an instruction.

## Defects found

**Pi fuzzy matching can modify unrelated content, and the returned diff misses it.**
When the old text used straight quotes and the file used curly quotes, Pi normalized
the entire file before replacing the requested line. In an unrelated paragraph,
`“Café”—½` became `"Café"-1⁄2`. It also removed the two trailing spaces that express a
Markdown hard break. Its diff treated those normalized lines as unchanged context.
Exact matches did not cause this damage. See the
[actual bytes and tool diff](fuzzy-quotes-pi-native/result.json).

**Holdfast loses a UTF-8 byte-order mark on Apply and Undo.** The CRLF line endings,
Unicode text and hard break survived; the initial `EF BB BF` bytes did not. Undo
returned success but was not byte-exact. The snapshot path reads and writes `String`
instead of preserving the original bytes. See
[before, after and after Undo](bom-crlf-holdfast/result.json).

**Holdfast can skip the snapshot needed to undo a second approved edit.**
`Edits.apply` requests a snapshot with reason `edit`; `Versions.snapshot` throttles
that reason to one copy per ten minutes. Two successive approved edits therefore
left the second filing without a snapshot. Undo refused with a misleading message
that the file had changed after filing, although no external writer intervened.
See the [two approvals and failed Undo](successive-approvals-holdfast/result.json).

## Interpretation

Pi supplies useful editing capabilities: several replacements in one validated batch,
line-ending normalization, general text-file edits and file creation. The stock tools
write immediately. Pi's extension system supports permission hooks and Git checkpoint
examples, but those were not installed in this test; approval and undo are not
impossible in Pi.

Holdfast has the more appropriate default workflow for reviewing changes to personal
notes: proposals, stale-file refusal, generated-file checks and an Inbox. Its Undo
implementation needs the fixes above before it can promise exact restoration for all
supported files and successive approvals.

The next useful native changes are atomic batches of replacements, CRLF-aware matching
that preserves the original bytes, and a mandatory byte-preserving snapshot for every
approved edit. Copying Pi's whole-file fuzzy normalization would import the collateral
edit problem found here. These capabilities can be added without changing harnesses.

## Method and limits

- Installed Pi 0.67.2; Ollama 0.40.15; existing local
  `qwen38-27b-q8-32k:latest`; 64 GB M1 Max. This follow-up uses Ollama for both model
  arms to hold inference constant; it does not rerun MLX.
- Holdfast uses the same frozen release binary as the preceding harness comparison.
  Its SHA-256 is in [metadata](metadata.json). The repository remains based on
  `e088130` with the native harness and evaluation changes uncommitted. Installed
  editor [source hashes](source-hashes.json) are recorded too.
- Pi uses its SDK with the installed built-in file implementations, a short knowledge
  base editing prompt, and no shell, extensions, project discovery or cloud provider.
  A supplied filesystem adapter restricts operations to the scratch vault; it does
  not change Pi's matching or writing algorithms. This boundary is evaluation
  infrastructure, not a built-in Pi safeguard.
- Holdfast uses its actual tools and system prompt. Tool schemas and prompts differ
  because these are different editing workflows; this is not the earlier controlled
  harness-only comparison. Both receive identical user requests and fixture bytes.
- Sampling, seed and Ollama weights match through the same loopback proxy. Each model
  trial starts fresh, warms on an unrelated one-token prompt, and unloads afterwards.
  Three tasks alternate the order of the two arms. No timing is a stable performance
  ranking: prompts, tool schemas, output lengths and the desktop workload differ.
- Holdfast generation ends with a pending proposal. The evaluator then applies it via
  the real CLI and verifies Undo; Pi writes during generation. Agent timings exclude
  the scripted approval, model loading and process startup.
- Repeated-item and two-edit model tasks require exact resulting bytes. Insertion
  allows blank-line placement around the new item, but requires every original
  nonblank line—including trailing hard-break spaces—to survive exactly. Other files
  must be unchanged. Frontmatter preservation is checked too.
- Concurrent-change cases insert a change before tool execution or before approval.
  They do not establish safety against an external writer racing the actual write.
  GUI clicks, counseling locality, long files, non-UTF-8 encodings, crash recovery and
  multi-file transactions are outside this comparison.

Raw direct evidence: [all 28 observations](direct-results.json). Model transcripts,
requests, proposed content, resulting files and checks are in
[model results](../2026-11-09-file-models/model-results.json).
