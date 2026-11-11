#!/usr/bin/env python3
"""Build branch docs without publishing; deploy only a published release's source."""
import argparse
import json
import os
import subprocess

from release_ref import ROOT, resolve


def resolve_docs(tag='', root=ROOT):
    result = resolve(tag, root=root)
    if tag:
        release = json.loads(subprocess.check_output(
            ['gh', 'api', f'repos/lawwu/holdfast/releases/tags/{tag}'], cwd=root, text=True))
        if (release.get('draft') is not False or not release.get('published_at')
                or release.get('tag_name') != tag):
            raise RuntimeError('Documentation deployment requires an already published release')
        if subprocess.run(['git', 'cat-file', '-e', f'{result["revision"]}:Website/package.json'],
                          cwd=root, capture_output=True).returncode:
            raise RuntimeError('This release predates the documentation site; use a release containing Website/')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', default='')
    args = parser.parse_args()
    values = resolve_docs(args.tag)
    result = ''.join(f'{key}={value}\n' for key, value in values.items())
    print(result, end='')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(result)
