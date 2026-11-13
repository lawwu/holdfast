import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from verified_release import INSTALLER_CHECKS, verify_installer


class VerifiedReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.payload = self.folder / 'app.pkg'
        self.payload.write_bytes(b'installer')
        self.digest = hashlib.sha256(b'installer').hexdigest()
        self.manifest = dict(version='1.2.3', sourceDirty=False, sourceRevision='revision',
                             installer='app.pkg', sha256=self.digest, developerIDSigned=False, notarized=False)
        self.report = dict(version='1.2.3', installerSHA256=self.digest, **dict.fromkeys(INSTALLER_CHECKS, True))
        (self.folder / 'SHA256SUMS').write_text(f'{self.digest}  app.pkg\n')
        self.save()

    def save(self):
        (self.folder / 'release-manifest.json').write_text(json.dumps(self.manifest))
        (self.folder / 'verification.json').write_text(json.dumps(self.report))

    def test_fresh_bytes_are_checked_on_every_invocation(self):
        result = verify_installer(self.folder, version='1.2.3', revision='revision')
        self.assertEqual(result.installer, self.payload.resolve())
        self.assertFalse(result.signed)
        self.payload.write_bytes(b'changed')
        with self.assertRaisesRegex(RuntimeError, 'checksum mismatch'):
            verify_installer(self.folder)

    def test_every_required_check_must_be_boolean_true(self):
        for key in INSTALLER_CHECKS:
            for value in [False, None, 1, 'true']:
                with self.subTest(key=key, value=value):
                    self.report[key] = value
                    self.save()
                    with self.assertRaisesRegex(RuntimeError, 'exact installer'):
                        verify_installer(self.folder)
            self.report[key] = True

    def test_signed_state_is_consistent_and_strict(self):
        for signed, notarized in [(True, False), (False, True), ('true', True), (1, True)]:
            self.manifest.update(developerIDSigned=signed, notarized=notarized)
            self.save()
            with self.assertRaisesRegex(RuntimeError, 'either signed'):
                verify_installer(self.folder)
        self.manifest.update(developerIDSigned=True, notarized=True)
        self.save()
        self.assertTrue(verify_installer(self.folder).signed)

    def test_evidence_identity_and_source_must_match(self):
        for key, value in [('version', '9.9.9'), ('installerSHA256', 'old')]:
            original = self.report[key]
            self.report[key] = value
            self.save()
            with self.assertRaises(RuntimeError):
                verify_installer(self.folder)
            self.report[key] = original
        self.save()
        for args in [dict(version='9.9.9'), dict(revision='other')]:
            with self.assertRaises(RuntimeError):
                verify_installer(self.folder, **args)
        self.manifest['sourceDirty'] = True
        self.save()
        with self.assertRaises(RuntimeError):
            verify_installer(self.folder)

    def test_installer_cannot_escape_release_directory(self):
        self.manifest['installer'] = '../app.pkg'
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'file in the release directory'):
            verify_installer(self.folder)

if __name__ == '__main__':
    unittest.main()
