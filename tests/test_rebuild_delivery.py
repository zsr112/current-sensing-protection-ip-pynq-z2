import os
import tempfile
import unittest
from pathlib import Path

from tools.rebuild_delivery import prepare
from tools.source_export import identity, write_json


class DeliveryRebuildTests(unittest.TestCase):
    def test_isolation_copies_only_verified_build_inputs(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name) / 'delivery'
            root.mkdir()
            (root / 'rtl').mkdir()
            (root / 'rtl/top.v').write_text('module top; endmodule\n')
            write_json(root / 'SOURCE_MANIFEST.json', {
                'schema': 'csip-source-export-v1', 'origin': {'commit': 'a' * 40, 'tree': 'b' * 40},
                'files': {'rtl/top.v': identity(root / 'rtl/top.v')}})
            (root / 'README.md').write_text('Release metadata, not a hardware input\n')
            isolated = prepare(root, Path(name) / 'external build')
            self.assertEqual({'rtl', 'SOURCE_MANIFEST.json'}, {p.name for p in isolated.iterdir()})
            (root / 'rtl/top.v').write_text('modified\n')
            with self.assertRaisesRegex(ValueError, 'Delivered source changed'):
                prepare(root, Path(name) / 'changed build')
            with self.assertRaisesRegex(ValueError, 'disjoint'):
                prepare(root, root / 'bad-output')

    @unittest.skipUnless(hasattr(os, 'symlink'), 'symbolic link support')
    def test_selected_root_alias_is_allowed_but_internal_link_is_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            base = Path(name)
            real = base / 'real delivery'
            real.mkdir()
            (real / 'rtl').mkdir()
            (real / 'rtl/top.v').write_text('module top; endmodule\n')
            write_json(real / 'SOURCE_MANIFEST.json', {
                'schema': 'csip-source-export-v1', 'origin': {'commit': 'a' * 40, 'tree': 'b' * 40},
                'files': {'rtl/top.v': identity(real / 'rtl/top.v')}})
            alias = base / 'delivery alias'
            try:
                alias.symlink_to(real, target_is_directory=True)
            except OSError as error:
                self.skipTest('symbolic links unavailable: ' + str(error))
            isolated = prepare(alias, base / 'valid output')
            self.assertEqual('module top; endmodule\n', (isolated / 'rtl/top.v').read_text())
            (real / 'rtl/link.v').symlink_to(real / 'rtl/top.v')
            write_json(real / 'SOURCE_MANIFEST.json', {
                'schema': 'csip-source-export-v1', 'origin': {'commit': 'a' * 40, 'tree': 'b' * 40},
                'files': {'rtl/link.v': identity(real / 'rtl/link.v')}})
            with self.assertRaisesRegex(ValueError, 'Link or reparse point'):
                prepare(alias, base / 'rejected output')


if __name__ == '__main__':
    unittest.main()
