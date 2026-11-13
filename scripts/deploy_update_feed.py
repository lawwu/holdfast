#!/usr/bin/env python3
"""Copy the latest published stable release's feed into the Pages artifact, unchanged."""
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from release_ref import VERSION_PATTERN
from sparkle_release import REPOSITORY, check_feed


def deploy(destination):
    release = json.loads(subprocess.check_output(
        ['gh', 'api', f'repos/{REPOSITORY}/releases/latest'], text=True))
    tag = release.get('tag_name', '')
    if (release.get('draft') is not False or release.get('prerelease') is not False
            or not release.get('published_at') or not re.fullmatch('v' + VERSION_PATTERN, tag)):
        raise RuntimeError('The update feed requires a published stable release')
    # A missing feed is an error: never deploy a site that silently removes app updates.
    with tempfile.TemporaryDirectory(prefix='holdfast-feed-') as temporary:
        subprocess.run(['gh', 'release', 'download', tag, '--repo', REPOSITORY,
                        '--pattern', 'appcast.xml', '--dir', temporary], check=True)
        feed = Path(temporary) / 'appcast.xml'
        check_feed(feed, tag[1:])
        (destination / 'appcast.xml').write_bytes(feed.read_bytes())


if __name__ == '__main__':
    deploy(Path(sys.argv[1]))
