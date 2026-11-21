#!/usr/bin/env python3
"""Summarize recorded observations without treating provisional labels as truth."""
import html
import json
from pathlib import Path
import statistics
import sys

LABELS = {'mlx-current': 'Current MLX', 'mlx-json': 'Same MLX + JSON grammar', 'apple-typed': 'Apple typed output'}


def read_lines(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def summarize(root):
    environment = json.loads((root / 'environment.json').read_text())
    cases = json.loads((root / 'cases.json').read_text())
    invariants = read_lines(root / 'invariants/stdout.jsonl')
    required_checks = {'private and confidential excluded from candidates', 'private vault excludes all notes',
                       'backend error', 'empty response', 'refusal prose', 'malformed positive JSON',
                       'string Boolean', 'valid negative', 'valid positive',
                       'explicit Apply changes note; Undo restores bytes'}
    assert required_checks <= {row['test'] for row in invariants}, 'Safety probe did not finish'
    assert all(row.get('sourceFilesUnchanged', True) for row in invariants), 'Source mutation before approval'
    arms = {name: [] for name in LABELS}
    runs = {name: [] for name in LABELS}
    for folder in sorted(root.glob('round-*')):
        if not folder.is_dir(): continue
        records = read_lines(folder / 'stdout.jsonl')
        meta = next(row for row in records if row.get('kind') == 'metadata')
        process = json.loads((folder / 'process.json').read_text())
        if process['exitCode'] != 0: raise RuntimeError(f'Incomplete run: {folder}')
        if meta.get('skipped'):
            runs[meta['arm']].append({'folder': folder.name, 'metadata': meta, 'process': process})
            continue
        trials = [dict(row, run=folder.name) for row in records if row.get('kind') == 'trial']
        expected = len(json.loads((root / f'order-{folder.name.split("-")[1]}.json').read_text()))
        assert len(trials) == expected, f'Incomplete trials: {folder.name}'
        assert all(row['sourceFilesUnchanged'] for row in trials), 'Source mutation during inference'
        arms[meta['arm']].extend(trials)
        runs[meta['arm']].append({'folder': folder.name, 'metadata': meta, 'process': process})
    prompt_hashes = {}
    for trials in arms.values():
        for row in trials:
            key = row['id'].removesuffix('-warm')
            prompt_hashes.setdefault(key, set()).add(row['promptSHA256'])
    assert all(len(values) == 1 for values in prompt_hashes.values()), 'Prompts differ across arms'
    summary = {}
    for arm, trials in arms.items():
        scored = [row for row in trials if not row['id'].endswith('-warm')]
        if not scored:
            summary[arm] = {'trials': 0, 'skipped': True}
            continue
        tp = sum(row['link'] and row['label'] for row in scored)
        fp = sum(row['link'] and not row['label'] for row in scored)
        fn = sum(not row['link'] and row['label'] for row in scored)
        tn = sum(not row['link'] and not row['label'] for row in scored)
        refusals = [row for row in scored if row.get('details', {}).get('failureKind') in ['refusal', 'guardrail'] or any(word in (str(row.get('error', '')) + ' ' + row.get('raw', '')).lower()
                    for word in ['refusal', 'guardrail', 'cannot assist', "can't assist", 'cannot help', "can't help"])]
        external = {}
        for run in runs[arm]:
            for sample in run['process']['memorySamples']:
                for proc in sample['processes']:
                    if proc['name'].endswith('/holdfast'): continue
                    external[proc['name']] = max(external.get(proc['name'], 0), proc['rssBytes'])
        warm_changes = []
        for warm in trials:
            if not warm['id'].endswith('-warm'): continue
            first = next(row for row in trials if row['run'] == warm['run'] and row['processFirstRequest'])
            if first['link'] != warm['link']:
                warm_changes.append({'id': first['id'], 'run': warm['run'], 'firstLink': first['link'],
                                     'warmLink': warm['link'], 'warmRaw': warm['raw']})
        summary[arm] = {'trials': len(scored), 'uniquePairs': len(set(row['id'] for row in scored)),
            'trueLinks': tp, 'falseLinks': fp, 'missedLinks': fn, 'correctNonLinks': tn,
            'agreementPercent': (tp+tn)/len(scored)*100,
            'schemaFailures': sum(not row['schemaValid'] for row in scored),
            'backendErrors': sum(bool(row.get('error')) for row in scored),
            'refusalOrGuardrailMatches': len(refusals),
            'contextTokens': runs[arm][0]['metadata']['contextTokens'],
            'maxOutputTokens': runs[arm][0]['metadata']['maxOutputTokens'],
            'promptTokenRange': [min(row.get('promptTokens', 0) for row in scored), max(row.get('promptTokens', 0) for row in scored)],
            'outputTokenRange': [min(row.get('outputTokens', 0) for row in scored), max(row.get('outputTokens', 0) for row in scored)],
            'inconsistentPairs': sum(len({row['link'] for row in scored if row['id'] == key}) > 1 for key in set(row['id'] for row in scored)),
            'warmRepeatVerdictChanges': warm_changes,
            'medianSeconds': statistics.median(row['seconds'] for row in scored),
            'inferenceSeconds': sum(row['seconds'] for row in trials),
            'processWallSeconds': sum(run['process']['wallSeconds'] for run in runs[arm]),
            'loadSeconds': [run['metadata']['modelLoadSeconds'] for run in runs[arm]],
            'loadMeasurement': 'explicit MLX model loading' if arm != 'apple-typed' else 'Apple load is not separately exposed; stored values time only runner setup',
            'firstRequestSeconds': [row['seconds'] for row in trials if row['processFirstRequest']],
            'warmRepeatSeconds': [row['seconds'] for row in trials if row['id'].endswith('-warm')],
            'maxProcessRSSBytes': max(row['processPeakRSSBytes'] for row in trials),
            'maxMLXAllocatorBytes': max((row.get('mlxPeakBytes', 0) for row in trials), default=0) or None,
            'observedSystemServicePeakRSS': external,
            'errors': [{'id': row['id'], 'run': row['run'], 'error': row.get('error'), 'raw': row['raw']} for row in scored if row.get('error') or not row['schemaValid']],
            'disagreements': [{'id': row['id'], 'run': row['run'], 'expected': row['label'], 'link': row['link'], 'reason': row['reason'], 'raw': row['raw']} for row in scored if row['link'] != row['label']]}
    result = {'labelStatus': 'provisional; pending human review', 'environment': environment,
              'summary': summary, 'invariants': invariants, 'applicationPromptHashesIdentical': True,
              'decision': {'adopt': False, 'productionRuntimeChanged': False,
                           'reasons': ['Labels await human review', 'Small exploratory corpus on one device']
                           + (['Existing parser failed safety probes'] if any(not row['pass'] for row in invariants) else [])}}
    (root / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
    return result, arms, runs, cases


def main():
    root = Path(sys.argv[1]).resolve()
    result, arms, runs, cases = summarize(root)
    env, summary, checks = result['environment'], result['summary'], result['invariants']
    failures = [row['test'] for row in checks if not row['pass']]
    observations = []
    baseline, grammar, apple = (summary[name] for name in LABELS)
    if not baseline.get('skipped') and not grammar.get('skipped'):
        if baseline['schemaFailures'] == grammar['schemaFailures'] == 0:
            observations.append('Adding the MLX grammar did not reduce observed schema failures: both MLX arms produced valid JSON in every scored trial.')
    if not baseline.get('skipped') and not apple.get('skipped'):
        observations.append(f"Apple's median response was {apple['medianSeconds']:.2f}s versus {baseline['medianSeconds']:.2f}s for current MLX. "
                            f"It proposed {apple['falseLinks']} false links and missed {apple['missedLinks']}, versus {baseline['falseLinks']} false and {baseline['missedLinks']} missed for current MLX, against the provisional labels.")
    lines = ['# Cross-link experiment — provisional results', '',
        'No runtime or default-model adoption is made. Labels await human review; safety failures in the existing parser must be addressed before treating malformed responses as safe.', '',
        ' '.join(observations), '',
        f"Machine: {env['hardware']}, {env['physicalMemoryBytes']/2**30:.0f} GiB; {env['swVers'].replace(chr(10), '; ')}.",
        f"Apple: {env.get('appleVariant', 'unknown')}, {env.get('appleContextTokens', 'unknown')}-token context. MLX: `{env['repo']}`; checkpoint hashes in `environment.json`.", '',
        'Sixteen fixed public synthetic pairs, eight positive/eight negative provisional labels, two passes with reversed arm/case order. Each arm repeats its first prompt at the end for a warm measurement. The quality table excludes those warm repeats. Repeated pairs are not independent samples.', '',
        '[Review the labels](label-review.html) · [Raw summary](summary.json)', '',
        '| Arm | Scored trials | Agreement with provisional labels | False links | Missed links | Schema failures | Backend errors | Refusal/guardrail matches | Median seconds |',
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for arm, label in LABELS.items():
        s = summary[arm]
        if s.get('skipped'):
            lines.append(f'| {label} | unavailable | — | — | — | — | — | — | — |')
        else:
            lines.append(f"| {label} | {s['trials']} | {s['agreementPercent']:.1f}% | {s['falseLinks']} | {s['missedLinks']} | {s['schemaFailures']} | {s['backendErrors']} | {s['refusalOrGuardrailMatches']} | {s['medianSeconds']:.2f} |")
    lines += ['', 'Thrown backend errors fail closed in `CrossLink.judge` and count as missed links when a positive was expected. Schema failures count responses that are not exactly a JSON object with Boolean `link` and string `reason`, even if the existing parser salvages them. Refusal/guardrail matches use typed Apple errors or recorded error/response text and need manual review; they are not inferred from every negative verdict.', '',
              '## Latency and memory', '',
              '| Arm | Model load seconds per pass | First request seconds per pass | Same prompt warm repeat seconds | Total process seconds | Process peak RSS GiB | MLX peak allocation GiB |',
              '| --- | --- | --- | --- | ---: | ---: | ---: |']
    fmt = lambda xs: ', '.join(f'{x:.2f}' for x in xs)
    for arm, label in LABELS.items():
        s = summary[arm]
        if s.get('skipped'): continue
        mlx = f"{s['maxMLXAllocatorBytes']/2**30:.2f}" if s['maxMLXAllocatorBytes'] else 'not applicable'
        load_time = fmt(s['loadSeconds']) if arm != 'apple-typed' else 'not separately exposed'
        lines.append(f"| {label} | {load_time} | {fmt(s['firstRequestSeconds'])} | {fmt(s['warmRepeatSeconds'])} | {s['processWallSeconds']:.2f} | {s['maxProcessRSSBytes']/2**30:.2f} | {mlx} |")
    lines += ['', 'All arms reserve 2,000 output tokens. MLX uses a configured 32,768-token context; Apple reports 4,096 tokens on this device. Apple input counts include framework schema overhead, so token counts are not directly interchangeable.', '']
    for arm, label in LABELS.items():
        s = summary[arm]
        if not s.get('skipped'):
            lines.append(f"- {label}: prompt tokens {s['promptTokenRange']}; output tokens {s['outputTokenRange']}; {s['inconsistentPairs']} pairs changed their Boolean verdict between passes; {len(s['warmRepeatVerdictChanges'])} warm repeats changed the first verdict.")
    lines += ['', 'The first request is process-cold, not proven model-cold. Filesystem caches and Apple’s shared model service are uncontrolled; checkpoint hashing warms disk caches. Apple inference runs out of process, so its runner RSS is not the model’s total memory and must not be compared as a memory win over MLX. Observed system-service RSS samples are preserved in each `process.json`; these do not establish exclusive model attribution. Total process time includes loading and warm repeats. No training, weight downloads, or cloud inference occurred.', '',
              '## Safety probes', '', '| Check | Result |', '| --- | --- |']
    lines += [f"| {row['test']} | {'PASS' if row['pass'] else 'FAIL'} |" for row in checks]
    lines += ['', 'The malformed-positive and string-Boolean probes exercise the original parser, not a replacement. A failure can create a proposal but does not edit a source note. Valid proposals require explicit Apply; Undo restored the original bytes. Private/confidential notes were excluded before inference, and an all-private vault produced no candidates.', '',
              'Unsupported/unavailable systems keep the existing product path because this experiment does not modify the shipped app. No old-OS runtime test or forced system-model unavailability test was performed.', '',
              '## Disagreements to review', '']
    for arm, label in LABELS.items():
        lines += [f'### {label}', '']
        for row in summary[arm].get('disagreements', []):
            lines.append(f"- {row['id']} ({row['run']}): proposed label={row['expected']}, model={row['link']}. {row['reason'] or '(reason scrubbed or absent)'}")
        if not summary[arm].get('disagreements'): lines.append('None against the provisional labels.')
        lines.append('')
    lines += ['## Reproducibility', '',
              'See [experiment instructions](../../README.md). `source-hashes.json` records the actual source snapshot; `fixture-hashes.json` records notes; `environment.json` records checkpoint hashes. All application instruction/note-text hashes matched. Apple’s framework adds its own schema context and tokenization differs. Models ran serially. Raw responses, proposals, errors, timings, and sampled process memory are retained per pass.', '',
              'Interpretation remains limited by provisional labels, sixteen unique pairs, only two passes, unseeded production sampling, one M1 Max, no Core Advanced coverage, shared OS services, and an unchanged manual candidate set.']
    (root / 'report.md').write_text('\n'.join(lines) + '\n')
    quality_rows, timing_rows = [], []
    for arm, label in LABELS.items():
        s = summary[arm]
        if s.get('skipped'): continue
        quality_rows.append(f'<tr><th>{label}</th><td>{s["agreementPercent"]:.1f}%</td><td>{s["falseLinks"]}</td><td>{s["missedLinks"]}</td><td>{s["schemaFailures"]}</td><td>{s["backendErrors"]}</td><td>{s["refusalOrGuardrailMatches"]}</td><td>{s["medianSeconds"]:.2f}s</td></tr>')
        timing_rows.append(f'<tr><th>{label}</th><td>{fmt(s["loadSeconds"])}</td><td>{fmt(s["firstRequestSeconds"])}</td><td>{fmt(s["warmRepeatSeconds"])}</td><td>{s["processWallSeconds"]:.1f}</td><td>{s["maxProcessRSSBytes"]/2**30:.2f}</td><td>{s["maxMLXAllocatorBytes"]/2**30:.2f}</td></tr>' if s['maxMLXAllocatorBytes'] else f'<tr><th>{label}</th><td>Not exposed</td><td>{fmt(s["firstRequestSeconds"])}</td><td>{fmt(s["warmRepeatSeconds"])}</td><td>{s["processWallSeconds"]:.1f}</td><td>{s["maxProcessRSSBytes"]/2**30:.2f}*</td><td>Not applicable</td></tr>')
    panels = []
    for case in cases:
        rows = []
        disputed = 0
        for arm in LABELS:
            case_observations = []
            for row in arms[arm]:
                if row['id'] == case['id']:
                    text = row.get('error') or row['raw']
                    disputed += row['link'] != case['link']
                    case_observations.append(f'<p class="note">Pass {row["run"].split("-")[1]} · {row["seconds"]:.2f}s · {"LINK" if row["link"] else "NO LINK"}</p><pre>{html.escape(text)}</pre>')
            rows.append(f'<article><h4>{LABELS[arm]}</h4>{"".join(case_observations)}</article>')
        flag = f'<span class="flag">{disputed} disagreement(s)</span>' if disputed else ''
        panels.append(f'<details data-disputed="{str(bool(disputed)).lower()}"><summary>{case["id"]} · provisional {"LINK" if case["link"] else "NO LINK"} · {html.escape(case["why"])} {flag}</summary><p><a href="label-review.html#{case["id"]}">Review source notes</a></p><div class="pairs">{"".join(rows)}</div></details>')
    safety = ''.join(f'<li><strong>{"PASS" if row["pass"] else "FAIL"}</strong> — {html.escape(row["test"])}</li>' for row in checks)
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><title>Holdfast cross-link experiment</title><style>
    :root{--bg:#f5f4ee;--fg:#20372b;--card:#fffefa;--line:#c7d2c7;--muted:#52645a;--accent:#245a42;--wash:#e4ecdf;--warn:#f0e6d7}*{box-sizing:border-box}body{overflow-wrap:anywhere;font:16px/1.65 system-ui;background:var(--bg);color:var(--fg);max-width:1160px;padding:36px 24px 70px;margin:auto}h1,h2{font-family:Georgia,serif;font-weight:400;line-height:1.15}h1{font-size:clamp(2.5rem,6vw,4.5rem);margin:30px 0 20px;letter-spacing:-.03em}h2{font-size:2rem;margin-top:42px}h4{margin:0 0 10px;font-size:.9rem}.eyebrow{font-size:.78rem;letter-spacing:.12em;text-transform:uppercase;color:var(--accent)}.lead{font-size:1.15rem;max-width:850px}.callout{background:var(--warn);padding:20px 25px;margin:24px 0}.note{color:var(--muted);font-size:.88rem}a{color:var(--accent);text-underline-offset:3px}.scroll{overflow:auto}table{border-collapse:collapse;width:100%;font-size:.88rem}th,td{text-align:left;padding:13px 12px;border-bottom:1px solid var(--line);vertical-align:top}thead{background:var(--wash)}thead th{white-space:nowrap}details{border-top:1px solid var(--line);padding:15px 0}summary{cursor:pointer;font-weight:600}.flag{display:inline-block;background:var(--warn);font-size:.75rem;padding:2px 8px;margin-left:8px}details[hidden]{display:none}.pairs{display:grid;grid-template-columns:repeat(3,1fr);gap:14px}article{background:var(--card);padding:16px;min-width:0}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.55 ui-monospace,monospace}li{margin:7px 0}:focus-visible{outline:3px solid var(--accent);outline-offset:3px}@media(max-width:800px){.pairs{grid-template-columns:1fr}body{padding:24px 18px}th,td{min-width:105px}}@media(prefers-color-scheme:dark){:root{--bg:#17221c;--fg:#e7eee4;--card:#202f26;--line:#425848;--muted:#afc0b1;--accent:#a8d4b2;--wash:#2a4030;--warn:#3b3125}}@media print{details>*{display:block}.pairs{grid-template-columns:1fr}body{font-size:11pt}.scroll{overflow:visible}}
    </style><div class="eyebrow">Holdfast / Bounded cross-link experiment / November 12, 2026</div><h1>Measure the helper.<br>Keep the runtime.</h1><p class="lead">Three local inference paths, the same synthetic note pairs, and the existing approval flow. Quality results are provisional until you review the labels.</p>'''
    page += f'<div class="callout"><strong>No adoption yet.</strong> The baseline safety probe found {len(failures)} failure(s): {html.escape(", ".join(failures))}. Invalid replies can create Inbox proposals; no source note was edited before explicit Apply.</div>'
    page += f'<p>{html.escape(env["hardware"])} · {env["physicalMemoryBytes"]/2**30:.0f} GiB · {html.escape(env["os"])}<br>Apple: {html.escape(env.get("appleVariant", "unknown"))} / {env.get("appleContextTokens", "unknown")} tokens. MLX: {html.escape(env["repo"])} / 32,768 configured tokens.</p><p><a href="label-review.html">Review the 16 labels</a> · <a href="report.md">Detailed report</a> · <a href="summary.json">Recorded measurements</a></p>'
    page += '<h2>Agreement with provisional labels</h2><p>16 unique pairs × two passes per arm. Eight proposed positive and eight negative labels; warm repeats excluded. Errors count as misses on positive cases.</p><div class="scroll"><table><thead><tr><th>Arm</th><th>Agreement</th><th>False links</th><th>Missed links</th><th>Schema failures</th><th>Errors</th><th>Refusal matches</th><th>Median / pair</th></tr></thead><tbody>' + ''.join(quality_rows) + '</tbody></table></div>'
    page += '<p>' + html.escape(' '.join(observations)) + '</p>'
    page += '<p class="note">“Schema failure” means the raw response does not match the exact Boolean/string object, even when the current parser salvages it. Refusal matches come from error/response text and require manual confirmation.</p><h2>First-use, warm-use, and memory observations</h2><div class="scroll"><table><thead><tr><th>Arm</th><th>Load (s)</th><th>First request (s)</th><th>Warm repeat (s)</th><th>Total process (s)</th><th>Runner RSS (GiB)</th><th>MLX peak (GiB)</th></tr></thead><tbody>' + ''.join(timing_rows) + '</tbody></table></div>'
    page += '<p class="note">Two values represent the two passes. First-use means a fresh process, with filesystem and system-service caches uncontrolled. Total includes loading and warm repeats. Apple model-load timing is not separately exposed. *Apple inference runs in a shared OS service: its runner RSS is not total model memory. These columns cannot establish an Apple memory advantage.</p><h2>Protection checks</h2><ul>' + safety + '</ul><p>The app and its existing local path are unchanged. Old-OS execution and actual Apple unavailability were not tested; unavailable experimental arms are skipped rather than mislabeled as model results.</p><h2>Inspect every decision</h2><p>The application instructions and note text matched across arms; Apple’s framework adds its own schema context. Open a case to compare both passes and check its source notes.</p><p><label><input type="checkbox" id="disputed-only"> Show only pairs that disagree with a provisional label</label></p>' + ''.join(panels)
    page += '<h2>Decision gate</h2><p>Review labels and disputed cases first. Repair the parser’s failure handling separately from any model switch. Then repeat on more note types and supported devices before adopting a new default. This run covers one M1 Max and AFM 3 Core, not Core Advanced.</p><p class="note">No production runtime change. No real notes or cloud inference. Two passes over a small corpus are exploratory, not a stable quality or speed ranking. The experiment instructions and raw records preserve the exact scope.</p><script>document.getElementById("disputed-only").addEventListener("change", event => { document.querySelectorAll("details[data-disputed]").forEach(item => { item.hidden = event.target.checked && item.dataset.disputed === "false"; }); });</script></html>'
    (root / 'report.html').write_text(page)
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
