import importlib.util
import json
import tempfile
import unittest
import zipfile
from pathlib import Path


test_root = Path(__file__).resolve().parents[1]
if test_root.name == 'publication':
    spec = importlib.util.spec_from_file_location(
        'publication_post_seal', test_root.parent / 'tools/verify_post_seal_release.py')
    seal = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(seal)
    validation_spec = importlib.util.spec_from_file_location(
        'publication_payload_validation', test_root.parent / 'tools/validate_release_payload.py')
    payload_validation = importlib.util.module_from_spec(validation_spec)
    validation_spec.loader.exec_module(payload_validation)
else:
    from tools import verify_post_seal_release as seal
    from tools import validate_release_payload as payload_validation


class ReleaseSealTests(unittest.TestCase):
    def test_payload_validation_uses_isolated_source_rebuild(self):
        work = Path('validation-work')
        commands = dict(payload_validation.portable_validation_commands(work))
        preflight = commands['portable_preflight']
        regression = commands['portable_regression']
        self.assertIn('tools/rebuild_delivery.py', preflight)
        self.assertIn('tools/rebuild_delivery.py', regression)
        self.assertNotIn('tools/rebuild.py', preflight)
        self.assertNotIn('tools/run_portable_regression.py', regression)
        self.assertEqual(['--target', 'portable'], preflight[-2:])
        self.assertIn('--execution-id', regression)

    def package(self, root, marker='one'):
        payload = root / 'payload'
        payload.mkdir(exist_ok=True)
        (payload / 'verify.py').write_text(
            "import json\nprint(json.dumps({'verification': 'PASS'}))\n", encoding='utf-8')
        (payload / 'VERSION.json').write_text(
            json.dumps({'release_id': seal.RELEASE_ID}) + '\n', encoding='utf-8')
        (payload / 'ACCEPTANCE.json').write_text(marker + '\n', encoding='utf-8')
        (payload / 'PAYLOAD_MANIFEST.json').write_text('{}\n', encoding='utf-8')
        archive = root / (seal.RELEASE_ID + '.zip')
        with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as zipped:
            for path in sorted(payload.iterdir()):
                zipped.write(path, path.name)
        return archive

    def test_external_mac_receipt_binds_exact_final_zip(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = self.package(root)
            facts = seal.verify_archive(archive)
            receipt = seal.build_receipt(
                facts, 'MACOS', 'CSIP-V2R3-MAC-POSTSEAL-001', '2026-09-10T12:00:00+00:00')
            self.assertIs(receipt, seal.validate_receipt(receipt, facts))

    def test_changed_final_zip_does_not_match_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = self.package(root)
            receipt = seal.build_receipt(
                seal.verify_archive(archive), 'MACOS', 'CSIP-V2R3-MAC-POSTSEAL-001',
                '2026-09-10T12:00:00+00:00')
            archive.unlink()
            (root / 'payload/ACCEPTANCE.json').write_text('changed\n', encoding='utf-8')
            with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as zipped:
                for path in sorted((root / 'payload').iterdir()):
                    zipped.write(path, path.name)
            with self.assertRaisesRegex(ValueError, 'archive'):
                seal.validate_receipt(receipt, seal.verify_archive(archive))

    def test_non_mac_receipt_cannot_satisfy_publication_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            facts = seal.verify_archive(self.package(root))
            receipt = seal.build_receipt(
                facts, 'WINDOWS', 'CSIP-V2R3-WINDOWS-POSTSEAL-001',
                '2026-09-10T12:00:00+00:00')
            with self.assertRaisesRegex(ValueError, 'platform'):
                seal.validate_receipt(receipt, facts)

    def test_publication_gate_requires_windows_and_mac(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            facts = seal.verify_archive(self.package(root))
            receipts = [seal.build_receipt(
                facts, platform, 'CSIP-V2R3-' + platform + '-POSTSEAL-001',
                '2026-09-10T12:00:00+00:00') for platform in ('WINDOWS', 'MACOS')]
            self.assertIs(receipts, seal.validate_publication_gate(receipts, facts))
            with self.assertRaisesRegex(ValueError, 'one receipt per platform'):
                seal.validate_publication_gate(receipts[:1], facts)

    def test_unsafe_zip_member_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / (seal.RELEASE_ID + '.zip')
            with zipfile.ZipFile(archive, 'w') as zipped:
                zipped.writestr('../escape', 'bad')
            with self.assertRaisesRegex(ValueError, 'Unsafe'):
                seal.verify_archive(archive)


if __name__ == '__main__':
    unittest.main()
