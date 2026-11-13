"""Exercise release selection and publication gates with real Git and a fake GitHub CLI."""
import base64
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
        for name in ['verified_release.py', 'release_ref.py', 'publish_release.py', 'docs_release.py', 'sparkle_release.py', 'deploy_update_feed.py']:
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
        self.manifest = dict(version='0.0.2', buildNumber='123', sourceRevision=self.revision, sourceDirty=False,
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

    def publish(self, success=True, include_dmg=False):
        return self.command('publish_release.py', '--tag', 'v0.0.2', '--publish',
                            '--allow-unsigned-preview', *(['--include-dmg'] if include_dmg else []), success=success)

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
        self.assertEqual(Path(upload[-1]).name, self.installer)
        self.assertNotIn('SHA256SUMS', [Path(p).name for p in upload])
        self.assertNotIn('Automated checks', (self.folder / 'release-notes.md').read_text())

    def test_published_release_and_api_failure_never_write(self):
        for mode in ['published', 'denied']:
            self.env['TEST_GH_MODE'] = mode
            self.log.unlink(missing_ok=True)
            self.publish(success=False)
            self.assertTrue(all(c[0] == 'api' for c in self.calls()))

    def add_dmg(self):
        name = 'Holdfast-0.0.2-macos-arm64-unsigned.dmg'
        payload = b'synthetic disk image for publication guard tests'
        digest = hashlib.sha256(payload).hexdigest()
        (self.folder / name).write_bytes(payload)
        (self.folder / (name + '.sha256')).write_text(f'{digest}  {name}\n')
        report = dict(version='0.0.2', sourceRevision=self.revision, installerSHA256=self.digest,
                      diskImage=name, diskImageSHA256=digest, passed=True, mountedReadOnly=True,
                      appMatchesInstaller=True, signatureIntegrityValidated=True, bundledRuntimeValidated=True)
        self.save('dmg-verification.json', report)
        return name, report

    def test_verified_preview_uploads_only_the_installers(self):
        name, _ = self.add_dmg()
        self.publish(include_dmg=True)
        upload = next(c for c in self.calls() if c[:2] == ['release', 'upload'])
        self.assertEqual([Path(p).name for p in upload[-2:]], [self.installer, name])

    def test_missing_or_changed_dmg_never_reaches_github(self):
        self.publish(success=False, include_dmg=True)
        self.assertEqual(self.calls(), [])
        name, _ = self.add_dmg()
        (self.folder / name).write_bytes(b'changed image')
        self.assertIn('DMG checksum mismatch', self.publish(success=False, include_dmg=True))
        self.assertEqual(self.calls(), [])

    def test_dmg_from_wrong_installer_or_failed_mount_never_reaches_github(self):
        _, report = self.add_dmg()
        for field, value in [('sourceRevision', 'old'), ('installerSHA256', 'old'),
                             ('appMatchesInstaller', False), ('mountedReadOnly', False)]:
            self.save('dmg-verification.json', {**report, field: value})
            self.publish(success=False, include_dmg=True)
            self.assertEqual(self.calls(), [])

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

    # Signed releases: Apple's tools are faked; the gates and GitHub calls are real.
    def make_signed(self, dmg_signed=True):
        bin_dir = Path(self.env['PATH'].split(os.pathsep)[0])
        for tool in ['pkgutil', 'xcrun', 'spctl']:
            fake = bin_dir / tool
            fake.write_text('#!/bin/sh\nexit 0\n')
            fake.chmod(0o755)
        self.installer = 'Holdfast-0.0.2-macos-arm64.pkg'
        (self.folder / 'Holdfast-0.0.2-macos-arm64-unsigned.pkg').rename(self.folder / self.installer)
        (self.folder / 'SHA256SUMS').write_text(f'{self.digest}  {self.installer}\n')
        self.manifest.update(installer=self.installer, developerIDSigned=True, notarized=True)
        self.save('release-manifest.json', self.manifest)
        name = 'Holdfast-0.0.2-macos-arm64' + ('' if dmg_signed else '-unsigned') + '.dmg'
        payload = b'synthetic signed disk image'
        digest = hashlib.sha256(payload).hexdigest()
        (self.folder / name).write_bytes(payload)
        (self.folder / (name + '.sha256')).write_text(f'{digest}  {name}\n')
        self.save('dmg-verification.json', dict(
            version='0.0.2', sourceRevision=self.revision, installerSHA256=self.digest, diskImage=name,
            diskImageSHA256=digest, passed=True, mountedReadOnly=True, appMatchesInstaller=True,
            signatureIntegrityValidated=True, bundledRuntimeValidated=True,
            developerIDSigned=dmg_signed, notarized=dmg_signed))
        signature = base64.b64encode(b's' * 64).decode()
        feed = self.folder / 'appcast.xml'
        feed.write_text(f"""<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
          <sparkle:version>123</sparkle:version><sparkle:shortVersionString>0.0.2</sparkle:shortVersionString>
          <enclosure url="https://github.com/lawwu/holdfast/releases/download/v0.0.2/Holdfast-macos-arm64.dmg"
            length="{len(payload)}" sparkle:edSignature="{signature}" />
        </item></channel></rss>""")
        self.save('sparkle-verification.json', dict(passed=True, sourceRevision=self.revision,
            diskImageSHA256=digest, appcastSHA256=hashlib.sha256(feed.read_bytes()).hexdigest()))
        return name

    def publish_signed(self, success=True):
        return self.command('publish_release.py', '--tag', 'v0.0.2', '--publish', '--include-dmg', success=success)

    def test_signed_release_publishes_as_latest_not_prerelease(self):
        name = self.make_signed()
        self.publish_signed()
        calls = self.calls()
        create = next(c for c in calls if c[:2] == ['release', 'create'])
        self.assertIn('--prerelease=false', create)
        self.assertNotIn('--prerelease', create)
        final = next(c for c in calls if '--draft=false' in c)
        self.assertIn('--latest', final)
        self.assertNotIn('--latest=false', final)
        upload = next(c for c in calls if c[:2] == ['release', 'upload'])
        self.assertEqual([Path(p).name for p in upload[-3:]],
                         ['Holdfast-macos-arm64.dmg', 'Holdfast-macos-arm64.pkg', 'appcast.xml'])
        self.assertEqual((self.folder / 'Holdfast-macos-arm64.dmg').read_bytes(), (self.folder / name).read_bytes())
        self.assertEqual((self.folder / 'Holdfast-macos-arm64.pkg').read_bytes(), (self.folder / self.installer).read_bytes())
        notes = (self.folder / 'release-notes.md').read_text()
        self.assertIn('**[Download for Mac]', notes)
        self.assertIn('Signed and notarized', notes)
        self.assertNotIn('Automated checks', notes)

    def test_signed_installer_never_ships_with_an_unsigned_disk_image(self):
        self.make_signed(dmg_signed=False)
        self.assertIn('signed and notarized exactly when', self.publish_signed(success=False))
        self.assertTrue(all(c[0] == 'api' for c in self.calls()))

    def test_unsigned_installer_never_publishes_without_the_preview_flag(self):
        self.assertIn('--allow-unsigned-preview', self.command('publish_release.py', '--tag', 'v0.0.2', '--publish', success=False))
        self.assertEqual(self.calls(), [])

    def test_missing_or_changed_feed_never_reaches_github(self):
        self.make_signed()
        feed = self.folder / 'appcast.xml'
        feed.write_text(feed.read_text().replace('123', '124'))
        self.assertIn('exact signed release', self.publish_signed(success=False))
        self.assertEqual(self.calls(), [])
        feed.unlink()
        self.publish_signed(success=False)
        self.assertEqual(self.calls(), [])

    def test_stale_feed_build_or_download_url_is_rejected_even_with_matching_checksum(self):
        self.make_signed()
        feed = self.folder / 'appcast.xml'
        original = feed.read_text()
        for old, new in [('123', '122'), ('v0.0.2/', 'latest/'), ('0.0.2</sparkle:short', '0.0.3</sparkle:short')]:
            feed.write_text(original.replace(old, new))
            report = json.loads((self.folder / 'sparkle-verification.json').read_text())
            report['appcastSHA256'] = hashlib.sha256(feed.read_bytes()).hexdigest()
            self.save('sparkle-verification.json', report)
            self.assertIn('does not match', self.publish_signed(success=False))
        self.assertEqual(self.calls(), [])


if __name__ == '__main__':
    unittest.main()
