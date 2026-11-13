#!/usr/bin/env python3
"""Run only safety probes against a freshly built app snapshot; never load a model."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from run import invoke, ROOT


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    opts = parser.parse_args()
    hashes_path = ROOT / '.build/crosslink-experiment/source-hashes.json'
    for name, digest in json.loads(hashes_path.read_text()).items():
        if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest:
            raise RuntimeError(f'Source changed after build: {name}. Rebuild first.')
    out = opts.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    shutil.copy2(hashes_path, out / 'source-hashes.json')
    rows = invoke(out / 'invariants', None, 'mlx-community/Qwen3.8-27B-4bit', ['invariants'], 90)
    failures = [row['test'] for row in rows if not row['pass']]
    summary = {'passed': len(rows) - len(failures), 'failed': failures, 'checks': rows,
               'scope': 'Scripted responses through actual candidate retrieval, judge, Inbox proposals, Apply and Undo; no model inference or runtime change.'}
    (out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    for row in rows:
        print(('PASS' if row['pass'] else 'FAIL') + ': ' + row['test'])
    if not rows or rows[-1]['test'] != 'explicit Apply changes note; Undo restores bytes':
        raise RuntimeError('Safety probes did not finish')
    if failures:
        raise RuntimeError(f'{len(failures)} safety checks failed')
    print(f'All {len(rows)} safety checks passed; {out}')


if __name__ == '__main__':
    main()
