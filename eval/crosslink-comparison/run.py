#!/usr/bin/env python3
"""Serial, bounded comparison in disposable synthetic vaults. No real vault writes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
from fixtures import prepare, ROOT

BINARY = ROOT / '.build/crosslink-experiment/xcode/Build/Products/Release/holdfast'
ARMS = ['mlx-current', 'mlx-json', 'apple-typed']


def command(args):
    return subprocess.check_output(args, text=True).strip()


def state_for(vault):
    h = 1469598103934665603
    for value in str(vault).encode():
        h = ((h ^ value) * 1099511628211) & ((1 << 64)-1)
    return Path.home() / 'Library/Application Support/Holdfast/vaults' / ('vault-' + format(h, 'x')[:8])


def env_for(vault, model):
    env = {**os.environ, 'HOLDFAST_VAULT': str(vault), 'HOLDFAST_CROSSLINK_EVAL': '1',
           'HOLDFAST_PACKS': 'none', 'HOLDFAST_EMBED': 'none', 'HOLDFAST_RERANK': '0',
           'HOLDFAST_MLX_REPO': model, 'HOLDFAST_BACKEND': 'mlx', 'HOLDFAST_TODAY': '2026-11-12',
           'DYLD_FRAMEWORK_PATH': str(ROOT / '.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64')}
    for key in ['HOLDFAST_THINK', 'HOLDFAST_MLX_DIR']:
        env.pop(key, None)
    return env


def invoke(folder, fixture, model, args, timeout):
    folder.mkdir()
    with tempfile.TemporaryDirectory(prefix='holdfast-crosslink-', dir=Path.home()/'.cache') as temp:
        vault = Path(temp) / 'vault'
        if fixture:
            shutil.copytree(fixture, vault)
        else:
            (vault / 'home').mkdir(parents=True)
        (vault / '.crosslink-synthetic').write_text('synthetic crosslink experiment\n')
        state = state_for(vault)
        assert not state.exists(), 'Refusing to reuse existing state'
        env = env_for(vault, model)
        samples, stopped = [], threading.Event()
        start = time.monotonic()
        try:
            with (folder / 'stdout.jsonl').open('w') as stdout, (folder / 'stderr.log').open('w') as stderr:
                process = subprocess.Popen([str(BINARY), *args], env=env, stdout=stdout, stderr=stderr)
                def monitor():
                    while not stopped.is_set():
                        rows = []
                        result = subprocess.run(['ps', '-axo', 'pid=,rss=,comm='], capture_output=True, text=True)
                        for line in result.stdout.splitlines():
                            parts = line.strip().split(None, 2)
                            if len(parts) != 3:
                                continue
                            pid, rss, name = parts
                            if int(pid) == process.pid or any(token in name.lower() for token in ['modelmanager', 'mlhost', 'intelligence', 'inferenceservice', 'afm']):
                                rows.append({'pid': int(pid), 'rssBytes': int(rss)*1024, 'name': name})
                        samples.append({'elapsed': time.monotonic()-start, 'processes': rows})
                        stopped.wait(.5)
                observer = threading.Thread(target=monitor, daemon=True)
                observer.start()
                try:
                    code = process.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    try: process.wait(timeout=10)
                    except subprocess.TimeoutExpired: process.kill(); process.wait()
                    code = 'timeout'
                finally:
                    stopped.set(); observer.join(timeout=3)
            (folder / 'process.json').write_text(json.dumps({'exitCode': code, 'wallSeconds': time.monotonic()-start,
                'memoryNotes': 'RSS sampled every 0.5s. Apple model inference runs in shared system services; process RSS is not total Apple model memory.',
                'memorySamples': samples}, indent=2) + '\n')
            if state.exists():
                proposals = state / 'inbox'
                if proposals.exists(): shutil.copytree(proposals, folder / 'proposals')
            if code != 0:
                raise RuntimeError(f'{folder.name} failed ({code}); see stderr.log')
            return [json.loads(line) for line in (folder / 'stdout.jsonl').read_text().splitlines()]
        finally:
            # Only the computed state directory for this unique synthetic vault.
            if state.exists(): shutil.rmtree(state)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--model', default='mlx-community/Qwen3.8-27B-4bit')
    parser.add_argument('--rounds', type=int, default=2)
    parser.add_argument('--arms', nargs='+', choices=ARMS, default=ARMS)
    parser.add_argument('--smoke', action='store_true')
    opts = parser.parse_args()
    if not 1 <= opts.rounds <= 3:
        parser.error('--rounds must be between 1 and 3 for this bounded experiment')
    source_hashes = json.loads((ROOT / '.build/crosslink-experiment/source-hashes.json').read_text())
    for name, digest in source_hashes.items():
        if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest:
            raise RuntimeError(f'Source changed after the experiment build: {name}. Rebuild first.')
    out = opts.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    cases = prepare(out)
    if opts.smoke: cases = cases[:1]
    shutil.copy2(ROOT / '.build/crosslink-experiment/source-hashes.json', out / 'source-hashes.json')
    metadata = invoke(out / 'environment', out / 'fixture', opts.model, ['metadata'], 60)[0]
    metadata.update({'swVers': command(['sw_vers']), 'xcode': command(['xcodebuild', '-version']),
        'hardware': command(['sysctl', '-n', 'machdep.cpu.brand_string']), 'physicalMemoryBytes': int(command(['sysctl', '-n', 'hw.memsize'])),
        'labelStatus': 'provisional; user will review', 'rounds': opts.rounds,
        'coldDefinition': 'first request in a fresh runner process; OS filesystem/model-service caches are uncontrolled',
        'sampling': 'MLX uses production temperature override 0.2 and automatic family profile in a volatile defaults domain; no explicit RNG seed',
        'gitHead': command(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'])})
    metadata['binarySHA256'] = hashlib.sha256(BINARY.read_bytes()).hexdigest()
    metadata['runnerSourceHashes'] = {name: hashlib.sha256((Path(__file__).parent / name).read_bytes()).hexdigest()
                                    for name in ['build.py', 'fixtures.py', 'run.py']}
    model_dir = Path(metadata['modelDir'])
    metadata['weights'] = []
    if model_dir.is_dir():
        for file in sorted(model_dir.glob('*.safetensors')):
            digest = hashlib.sha256()
            with file.open('rb') as data:
                for block in iter(lambda: data.read(8*1024*1024), b''): digest.update(block)
            metadata['weights'].append({'file': file.name, 'bytes': file.stat().st_size, 'sha256': digest.hexdigest()})
    (out / 'environment.json').write_text(json.dumps(metadata, indent=2) + '\n')
    checks = invoke(out / 'invariants', None, opts.model, ['invariants'], 90)
    print(json.dumps({'invariantFailures': [row['test'] for row in checks if not row.get('pass')]}), flush=True)
    for round_index in range(opts.rounds):
        ordered = cases if round_index % 2 == 0 else list(reversed(cases))
        # Repeat the identical first prompt after the workload to observe a warm response.
        ordered = ordered + [{**ordered[0], 'id': ordered[0]['id'] + '-warm'}]
        order_path = out / f'order-{round_index+1}.json'
        order_path.write_text(json.dumps(ordered, indent=2) + '\n')
        arms = opts.arms if round_index % 2 == 0 else list(reversed(opts.arms))
        for arm in arms:
            print(f'Running round {round_index+1}: {arm} ({len(ordered)} requests)', flush=True)
            folder = out / f'round-{round_index+1}-{arm}'
            rows = invoke(folder, out / 'fixture', opts.model, [arm, str(order_path)], 2400)
            trials = [row for row in rows if row.get('kind') == 'trial']
            print(json.dumps({'arm': arm, 'round': round_index+1, 'completed': len(trials),
                'errors': sum(bool(row.get('error')) for row in trials),
                'seconds': round(sum(row['seconds'] for row in trials), 2)}), flush=True)
    print(out, flush=True)


if __name__ == '__main__':
    main()
