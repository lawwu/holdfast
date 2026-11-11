"""Exercise release selection and publication gates with real Git and a fake GitHub CLI."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='holdfast-release-test-')
        self.addCleanup(self.temporary.cleanup)
        self.scratch = Path(self.temporary.name)
        self.repo = self.scratch / 'repo'
        self.repo.mkdir()
        self.git('init', '-b', 'main')
        self.git('config', 'user.name', 'Release Tests')
        self.git('config', 'user.email', 'release-tests@example.invalid')
        (self.repo / '.gitignore').write_text('build/\n__pycache__/\n')
        (self.repo / 'VERSION').write_text('0.0.2\n')
        notes = self.repo / 'docs/releases'
        notes.mkdir(parents=True)
        (notes / 'v0.0.2.md').write_text('Preview release notes.\n')
        scripts = self.repo / 'scripts'
        scripts.mkdir()
        for name in ['release_ref.py', 'publish_release.py', 'docs_release.py']:
            shutil.copyfile(ROOT / 'scripts' / name, scripts / name)
        website = self.repo / 'Website'
        website.mkdir()
        (website / 'package.json').write_text('{"private":true}\n')
        self.git('add', '.')
        self.git('commit', '-m', 'Release fixture')
        self.revision = self.git('rev-parse', 'HEAD')
        self.git('update-ref', 'refs/remotes/origin/main', self.revision)
        self.git('tag', 'v0.0.2')
        self.folder = self.repo / 'build/releases/0.0.2'
        self.folder.mkdir(parents=True)
        self.installer = 'Holdfast-0.0.2-macos-arm64-unsigned.pkg'
        payload = b'synthetic installer for publication guard tests'
        (self.folder / self.installer).write_bytes(payload)
        self.digest = hashlib.sha256(payload).hexdigest()
        self.manifest = dict(version='0.0.2', sourceRevision=self.revision, sourceDirty=False,
                             installer=self.installer, sha256=self.digest, developerIDSigned=False, notarized=False)
        self.save('release-manifest.json', self.manifest)
        (self.folder / 'SHA256SUMS').write_text(f'{self.digest}  {self.installer}\n')
        self.verification = dict(passed=True, version='0.0.2', installerSHA256=self.digest,
            payloadAndBundleValidated=True, bundledRuntimeValidated=True, approvalUndoStaleEditValidated=True,
            developerFallbacksDisabled=True, realEmbeddedMLXTested=False)
        self.save('verification.json', self.verification)
        bin_dir = self.scratch / 'bin'
        bin_dir.mkdir()
        self.log = self.scratch / 'gh-calls.jsonl'
        gh = bin_dir / 'gh'
        gh.write_text('#!' + sys.executable + '\n' + '''import json, os, sys
with open(os.environ['TEST_GH_LOG'], 'a') as log: log.write(json.dumps(sys.argv[1:]) + '\\n')
if sys.argv[1] == 'api':
    mode = os.environ.get('TEST_GH_MODE', 'missing')
    if mode == 'published': print('{"draft":false,"tag_name":"v0.0.2","published_at":"2026-11-10T00:00:00Z","prerelease":true}'); sys.exit(0)
    if mode == 'wrong-tag': print('{"draft":false,"tag_name":"v0.0.3","published_at":"2026-11-10T00:00:00Z"}'); sys.exit(0)
    if mode == 'unpublished': print('{"draft":false,"tag_name":"v0.0.2","published_at":null}'); sys.exit(0)
    if mode == 'draft': print('{"draft":true}'); sys.exit(0)
    print('HTTP 403' if mode == 'denied' else 'HTTP 404', file=sys.stderr); sys.exit(1)
if sys.argv[1:3] == ['release', 'view']: print('https://example.invalid/release')
''')
        gh.chmod(0o755)
        self.env = {**os.environ, 'PATH': str(bin_dir) + os.pathsep + os.environ['PATH'],
                    'TEST_GH_LOG': str(self.log)}
        self.env.pop('GITHUB_OUTPUT', None)

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.repo, text=True, stderr=subprocess.DEVNULL).strip()

    def save(self, name, data):
        (self.folder / name).write_text(json.dumps(data))

    def command(self, script, *args, success=True):
        result = subprocess.run([sys.executable, self.repo / 'scripts' / script, *args], cwd=self.repo,
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def publish(self, success=True):
        return self.command('publish_release.py', '--tag', 'v0.0.2', '--publish',
                            '--allow-unsigned-preview', success=success)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_branch_build_never_requests_publication(self):
        self.assertIn('publish=false', self.command('release_ref.py'))

    def test_docs_branch_checks_never_query_github_or_publish(self):
        self.assertIn('publish=false', self.command('docs_release.py'))
        self.assertEqual(self.calls(), [])

    def test_docs_use_published_prerelease_revision_instead_of_main(self):
        self.env['TEST_GH_MODE'] = 'published'
        self.git('commit', '--allow-empty', '-m', 'Development after release')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')
        result = self.command('docs_release.py', '--tag', 'v0.0.2')
        self.assertIn('revision=' + self.revision, result)
        self.assertIn('publish=true', result)
        self.assertTrue(all(c[0] == 'api' for c in self.calls()))

    def test_docs_refuse_unpublished_or_unverifiable_releases(self):
        for mode in ['missing', 'draft', 'denied', 'wrong-tag', 'unpublished']:
            with self.subTest(mode=mode):
                self.env['TEST_GH_MODE'] = mode
                result = self.command('docs_release.py', '--tag', 'v0.0.2', success=False)
                self.assertNotIn('publish=true', result)

    def test_docs_refuse_old_tags_without_site_sources(self):
        self.env['TEST_GH_MODE'] = 'published'
        self.git('rm', 'Website/package.json')
        self.git('commit', '-m', 'Remove site from fixture')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')
        self.git('tag', '-f', 'v0.0.2')
        result = self.command('docs_release.py', '--tag', 'v0.0.2', success=False)
        self.assertIn('predates the documentation site', result)

    def test_rejects_invalid_tags_and_version_mismatch(self):
        for tag in ['--help', 'main', 'v0.0.2;echo nope', 'v0.0.2\ninjected=true', 'v01.0.2']:
            self.command('release_ref.py', '--tag=' + tag, success=False)
        self.git('tag', 'v0.0.3')
        self.assertIn('match VERSION', self.command('release_ref.py', '--tag', 'v0.0.3', success=False))

    def test_rejects_tag_outside_main(self):
        self.git('checkout', '-b', 'unmerged')
        (self.repo / 'VERSION').write_text('0.0.3\n')
        self.git('commit', '-am', 'Unmerged version')
        self.git('tag', 'v0.0.3')
        self.assertIn('origin/main', self.command('release_ref.py', '--tag', 'v0.0.3', success=False))

    def test_rejects_missing_committed_notes(self):
        self.git('rm', 'docs/releases/v0.0.2.md')
        self.git('commit', '-m', 'Remove notes')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')
        self.git('tag', '-f', 'v0.0.2')
        self.command('release_ref.py', '--tag', 'v0.0.2', success=False)

    def test_detached_tag_publishes_only_tested_assets_as_prerelease(self):
        self.git('checkout', '--detach', 'v0.0.2')
        refs = self.git('show-ref')
        self.publish()
        self.assertEqual(self.git('show-ref'), refs)
        calls = self.calls()
        self.assertTrue(any(c[:2] == ['release', 'create'] and '--draft' in c and '--prerelease' in c for c in calls))
        self.assertTrue(any(c[:2] == ['release', 'edit'] and '--draft=false' in c and '--latest=false' in c for c in calls))
        upload = next(c for c in calls if c[:2] == ['release', 'upload'])
        self.assertEqual([Path(p).name for p in upload[-4:]],
                         [self.installer, 'SHA256SUMS', 'release-manifest.json', 'verification.json'])
        self.assertIn('Real MLX inference was not run', (self.folder / 'release-notes.md').read_text())

    def test_published_release_and_api_failure_never_write(self):
        for mode in ['published', 'denied']:
            self.env['TEST_GH_MODE'] = mode
            self.log.unlink(missing_ok=True)
            self.publish(success=False)
            self.assertTrue(all(c[0] == 'api' for c in self.calls()))

    def test_rejects_changed_payload_checksum_or_failed_checks(self):
        (self.folder / self.installer).write_bytes(b'changed')
        self.assertIn('checksum mismatch', self.publish(success=False))
        self.assertEqual(self.calls(), [])

    def test_rejects_checksum_file_mismatch(self):
        (self.folder / 'SHA256SUMS').write_text('wrong\n')
        self.assertIn('SHA256SUMS', self.publish(success=False))

    def test_rejects_stale_verification_and_missing_approval_check(self):
        for field, value in [('installerSHA256', 'old digest'), ('approvalUndoStaleEditValidated', False)]:
            self.save('verification.json', {**self.verification, field: value})
            self.assertIn('exact installer', self.publish(success=False))
        self.assertEqual(self.calls(), [])

    def test_rejects_dirty_source_and_wrong_checked_out_commit(self):
        self.save('release-manifest.json', {**self.manifest, 'sourceDirty': True})
        self.assertIn('committed source', self.publish(success=False))
        self.save('release-manifest.json', self.manifest)
        self.git('commit', '--allow-empty', '-m', 'Newer commit')
        self.assertIn('Check out the release tag', self.publish(success=False))


if __name__ == '__main__':
    unittest.main()
