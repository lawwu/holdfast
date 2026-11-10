#!/usr/bin/env python3
"""Resolve an existing release tag without creating tags or changing the checkout."""
import argparse
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
VERSION_PATTERN = r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)'


def git(*args, root=ROOT):
    return subprocess.check_output(['git', *args], cwd=root, text=True).strip()


def resolve(tag='', root=ROOT):
    if tag and not re.fullmatch('v' + VERSION_PATTERN, tag):
        raise RuntimeError('Release tags must have the form vX.Y.Z')
    revision = git('rev-parse', '--verify', f'refs/tags/{tag}^{{commit}}' if tag else 'HEAD', root=root)
    version = git('show', f'{revision}:VERSION', root=root)
    if not re.fullmatch(VERSION_PATTERN, version):
        raise RuntimeError('VERSION must contain a three-part numeric version')
    if tag:
        if tag != 'v' + version:
            raise RuntimeError('The tag must match VERSION at that commit')
        if subprocess.run(['git', 'merge-base', '--is-ancestor', revision, 'origin/main'],
                          cwd=root, capture_output=True).returncode:
            raise RuntimeError('Release tags must point to a commit on origin/main')
        notes = git('show', f'{revision}:docs/releases/{tag}.md', root=root)
        if not notes:
            raise RuntimeError('Release notes must be committed with the tagged source')
    return {'revision': revision, 'version': version, 'tag': tag, 'publish': 'true' if tag else 'false'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', default='')
    args = parser.parse_args()
    values = resolve(args.tag)
    result = ''.join(f'{key}={value}\n' for key, value in values.items())
    print(result, end='')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(result)
