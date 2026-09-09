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


if __name__ == '__main__':
    unittest.main()
