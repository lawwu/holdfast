"""Updater configuration, feed deployment, and real Sparkle signing (when installed)."""
import base64
import json
from pathlib import Path
import plistlib
import secrets
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import configure_updates
import deploy_update_feed
import sparkle_release


def feed_xml(version='0.0.6', build='124', length=1):
    signature = base64.b64encode(b's' * 64).decode()
    return f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
      <sparkle:version>{build}</sparkle:version><sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <enclosure url="https://github.com/lawwu/holdfast/releases/download/v{version}/Holdfast-macos-arm64.dmg"
        length="{length}" sparkle:edSignature="{signature}" />
    </item></channel></rss>'''.encode()


class UpdateTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='holdfast-update-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def test_only_signed_production_app_enables_updates(self):
        contents = self.root / 'Holdfast.app/Contents'
        contents.mkdir(parents=True)
        for identity, distribution, bundle_id, expected in [
            ('-', '1', 'app.holdfast', False),
            ('Developer ID Application: Test', '0', 'app.holdfast', False),
            ('Developer ID Application: Test', '1', 'app.holdfast.demo', False),
            ('Developer ID Application: Test', '1', 'app.holdfast', True),
        ]:
            (contents / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': bundle_id}))
            configure_updates.configure(contents.parent, {'HOLDFAST_SIGNING_IDENTITY': identity,
                                                         'HOLDFAST_DISTRIBUTION': distribution})
            info = plistlib.loads((contents / 'Info.plist').read_bytes())
            self.assertEqual(info['HoldfastUpdatesEnabled'], expected)
            self.assertTrue(info['SURequireSignedFeed'])
            self.assertTrue(info['SUVerifyUpdateBeforeExtraction'])
            self.assertFalse(info['SUAllowsAutomaticUpdates'])
            self.assertFalse(info['SUEnableSystemProfiling'])
            self.assertNotIn('SUEnableAutomaticChecks', info)  # Preserve Sparkle's opt-in prompt.

    def test_deployment_uses_latest_stable_feed_and_preserves_signed_bytes(self):
        feed = feed_xml()
        release = dict(tag_name='v0.0.6', draft=False, prerelease=False, published_at='2026-11-12')
        def download(args, **kwargs):
            self.assertIn('v0.0.6', args)
            (Path(args[args.index('--dir') + 1]) / 'appcast.xml').write_bytes(feed)
        with patch('deploy_update_feed.subprocess.check_output', return_value=json.dumps(release)) as lookup, \
             patch('deploy_update_feed.subprocess.run', side_effect=download):
            deploy_update_feed.deploy(self.root)
            self.assertTrue(lookup.call_args.args[0][-1].endswith('/releases/latest'))
        self.assertEqual((self.root / 'appcast.xml').read_bytes(), feed)

    def test_invalid_or_missing_feed_never_overwrites_deployed_file(self):
        target = self.root / 'appcast.xml'
        target.write_bytes(b'previous signed feed')
        release = dict(tag_name='v0.0.6', draft=False, prerelease=False, published_at='2026-11-12')
        for changes in [dict(draft=True), dict(prerelease=True), dict(published_at=None), dict(tag_name='main')]:
            with patch('deploy_update_feed.subprocess.check_output', return_value=json.dumps({**release, **changes})):
                with self.assertRaises(RuntimeError):
                    deploy_update_feed.deploy(self.root)
        def stale_download(args, **kwargs):
            (Path(args[args.index('--dir') + 1]) / 'appcast.xml').write_bytes(feed_xml(version='0.0.5'))
        with patch('deploy_update_feed.subprocess.check_output', return_value=json.dumps(release)), \
             patch('deploy_update_feed.subprocess.run', side_effect=stale_download):
            with self.assertRaises(RuntimeError):
                deploy_update_feed.deploy(self.root)
        self.assertEqual(target.read_bytes(), b'previous signed feed')

    def test_unsigned_preview_cannot_generate_an_update(self):
        (self.root / 'release-manifest.json').write_text(json.dumps(dict(developerIDSigned=False, notarized=False)))
        with self.assertRaisesRegex(RuntimeError, 'Unsigned previews'):
            sparkle_release.generate(self.root)


@unittest.skipUnless(sys.platform == 'darwin' and (sparkle_release.TOOLS / 'generate_appcast').is_file(),
                     'Real Sparkle tools require resolved packages on macOS')
class SparkleSigningTests(unittest.TestCase):
    def test_real_signatures_verify_and_reject_tampering(self):
        # Disposable key: no production Keychain access and no secrets in subprocess arguments.
        secret = base64.b64encode(secrets.token_bytes(32)).decode()
        derive = '''import CryptoKit
import Foundation
let seed = Data(base64Encoded: readLine()!)!
print(try Curve25519.Signing.PrivateKey(rawRepresentation: seed).publicKey.rawRepresentation.base64EncodedString())
'''
        with tempfile.TemporaryDirectory(prefix='holdfast-sparkle-signing-') as temporary:
            root = Path(temporary)
            script = root / 'key.swift'
            script.write_text(derive)
            public_key = subprocess.check_output(['swift', str(script)], input=secret + '\n', text=True).strip()
            app = root / 'Holdfast.app'
            (app / 'Contents/MacOS').mkdir(parents=True)
            shutil.copyfile('/usr/bin/true', app / 'Contents/MacOS/holdfast')
            (app / 'Contents/MacOS/holdfast').chmod(0o755)
            info = dict(CFBundleIdentifier='app.holdfast.updater-test', CFBundleName='Holdfast',
                        CFBundleExecutable='holdfast', CFBundlePackageType='APPL', CFBundleVersion='124',
                        CFBundleShortVersionString='0.0.6', LSMinimumSystemVersion='15.0',
                        SUPublicEDKey=public_key, SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
                        SUFeedURL='https://example.invalid/appcast.xml')
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
            subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
            archives = root / 'archives'
            archives.mkdir()
            archive = archives / sparkle_release.DMG_NAME
            # Exercise the actual DMG format used for shipping, not a synthetic signature.
            staging = root / 'staging'
            staging.mkdir()
            shutil.move(app, staging / app.name)
            subprocess.run(['hdiutil', 'create', '-quiet', '-srcfolder', str(staging), '-format', 'UDZO',
                            str(archive)], check=True, capture_output=True)
            def sparkle(tool, *args, success=True):
                result = subprocess.run([str(sparkle_release.TOOLS / tool), '--ed-key-file', '-', *map(str, args)],
                                        input=secret + '\n', text=True, capture_output=True)
                self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
            sparkle('generate_appcast', '--download-url-prefix',
                    'https://github.com/lawwu/holdfast/releases/download/v0.0.6/', '--maximum-deltas', '0', archives)
            feed = archives / 'appcast.xml'
            signature = sparkle_release.check_feed(feed, '0.0.6', '124', archive)
            sparkle('sign_update', '--verify', archive, signature)
            sparkle('sign_update', '--verify', feed)
            feed.write_bytes(feed.read_bytes().replace(b'0.0.6', b'0.0.7'))
            sparkle('sign_update', '--verify', feed, success=False)
            with archive.open('ab') as handle:
                handle.write(b'tampered')
            sparkle('sign_update', '--verify', archive, signature, success=False)


if __name__ == '__main__':
    unittest.main()
