import tempfile
import unittest
import shutil
import subprocess
from pathlib import Path
from tools.source_export import identity, select_files, verify, write_json


class SourceExportTests(unittest.TestCase):
    def test_selection_rejects_missing_required_inputs(self):
        selection = {'schema': 'csip-source-selection-v1', 'include': ['rtl/*'],
                     'exclude': {}, 'required': ['rtl/top.v']}
        self.assertEqual({'rtl/top.v'}, select_files(['rtl/top.v', 'private.log'], selection))
        with self.assertRaisesRegex(ValueError, 'Required delivery inputs'):
            select_files(['private.log'], selection)
        selection['exclude'] = {'rtl/*': 'Historical inputs'}
        with self.assertRaisesRegex(ValueError, 'Required delivery inputs'):
            select_files(['rtl/top.v'], selection)

    def fixture(self, root):
        (root / 'rtl').mkdir()
        (root / 'rtl/top.v').write_text('module top; endmodule\n')
        write_json(root / 'SOURCE_MANIFEST.json', {
            'schema': 'csip-source-export-v1', 'origin': {'commit': 'a' * 40, 'tree': 'b' * 40},
            'files': {'rtl/top.v': identity(root / 'rtl/top.v')}})

    def test_changed_and_extra_files_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            verify(root)
            (root / 'extra.v').write_text('')
            with self.assertRaisesRegex(ValueError, 'inventory'):
                verify(root)
            (root / 'extra.v').unlink()
            (root / 'rtl/top.v').write_text('module changed; endmodule\n')
            with self.assertRaisesRegex(ValueError, 'changed'):
                verify(root)

    @unittest.skipUnless(shutil.which('pwsh'), 'PowerShell export validation requires pwsh')
    def test_powershell_validates_and_rejects_tampering(self):
        with tempfile.TemporaryDirectory(prefix='source export ') as temp:
            root = Path(temp)
            self.fixture(root)
            digest = identity(root / 'SOURCE_MANIFEST.json')['sha256']
            script = Path(__file__).with_name('source_export_fixture.ps1')
            def check(mode, manifest_hash=digest):
                result = subprocess.run(['pwsh', '-NoProfile', '-File', str(script),
                    '-RepositoryRoot', str(root), '-ManifestHash', manifest_hash, '-Mode', mode],
                    capture_output=True, text=True)
                self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            check('valid')
            check('bad_hash', 'c' * 64)
            (root / 'rtl/top.v').write_text('module changed; endmodule\n')
            check('changed')


if __name__ == '__main__':
    unittest.main()
