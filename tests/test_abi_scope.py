import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from tools import check_register_map_implementation as check
from tools.source_export import identity, select_files, write_json

ROOT = Path(__file__).resolve().parents[1]
SESSION = 'tools/board_validation/stage2_board_session.py'


class AbiScopeTests(unittest.TestCase):
    def test_session_effective_addresses_masks_and_aliases(self):
        source = (ROOT / SESSION).read_text(encoding='utf-8')
        check.validate_board_session_binding(source)
        mutations = [
            source.replace('int(RegisterOffset.CTRL)', '0x04'),
            source.replace('CTRL_PWM_ENABLE | CTRL_CLEAR_FAULT', 'CTRL_PWM_ENABLE'),
            source.replace('CTRL_PWM_ENABLE | CTRL_CLEAR_FAULT', '3'),
            source.replace('RegisterOffset.CTRL', 'RegisterOffset.STATUS'),
            source + '\nCTRL_PWM_ENABLE = 1\n',
            source + '\nRegisterOffset.CTRL = 4\n',
            source.replace('self.backend.protection.write', 'mmio.write') + '\nmmio = self.backend.protection\n',
        ]
        for mutated in mutations:
            with self.subTest(mutation=mutations.index(mutated)), self.assertRaises(check.CheckError):
                check.validate_board_session_binding(mutated)

    def test_unclassified_session_is_rejected(self):
        inventory = tuple(row for row in check.CONSUMER_INVENTORY if row['path'] != SESSION)
        with self.assertRaisesRegex(check.CheckError, 'unclassified'):
            check.check_consumer_inventory(ROOT, inventory=inventory)

    def fixture(self, root):
        policy = json.loads((ROOT / 'config/self_contained_source.json').read_text())
        names = [p.relative_to(ROOT).as_posix() for p in ROOT.rglob('*') if p.is_file() and '.git' not in p.parts]
        for name in select_files(names, policy):
            if '__pycache__' in name or name.endswith('.pyc'):
                continue
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        self.seal(root)

    def seal(self, root):
        write_json(root / 'SOURCE_MANIFEST.json', {
            'schema': 'csip-source-export-v1', 'origin': {'commit': 'a' * 40, 'tree': 'b' * 40},
            'selection': {'path': 'config/self_contained_source.json', 'identity': identity(root / 'config/self_contained_source.json')},
            'files': {p.relative_to(root).as_posix(): identity(p) for p in root.rglob('*') if p.is_file() and p.name != 'SOURCE_MANIFEST.json'}})

    def test_selected_scope_and_failure_boundaries(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            self.assertFalse((root / '.git').exists())
            self.assertFalse((root / 'notebooks').exists())
            self.assertEqual(2, check.check_consumer_inventory(root)['historical_out_of_scope'])
            with self.assertRaises(check.CheckError):
                check.check_consumer_inventory(root, scope='engineering')
            file = root / SESSION
            original = file.read_bytes()
            file.unlink()
            with self.assertRaisesRegex(ValueError, 'inventory'):
                check.check_consumer_inventory(root)
            self.seal(root)
            with self.assertRaisesRegex(check.CheckError, 'required ABI'):
                check.check_consumer_inventory(root)
            file.write_bytes(original)
            extra = root / 'sw/unclassified.py'
            extra.write_text('from pynq import MMIO\nmmio = MMIO(0, 4096)\nmmio.write(4, 1)\n')
            self.seal(root)
            with self.assertRaisesRegex(check.CheckError, 'unclassified'):
                check.check_consumer_inventory(root)
            extra.unlink()
            self.seal(root)
            manifest = json.loads((root / 'SOURCE_MANIFEST.json').read_text())
            manifest['selection']['identity']['sha256'] = '0' * 64
            write_json(root / 'SOURCE_MANIFEST.json', manifest)
            with self.assertRaisesRegex(check.CheckError, 'selection identity'):
                check.check_consumer_inventory(root)

    def test_engineering_history_bytes_remain_checked(self):
        if not (ROOT / 'notebooks').exists():
            self.skipTest('Historical snapshots are explicitly outside the selected export')
        with patch.dict(check.HISTORICAL_CONSUMERS, {'notebooks/pynq_protection_mmio_demo_preboard.ipynb': '0' * 64}):
            with self.assertRaisesRegex(check.CheckError, 'historical snapshot changed'):
                check.validate_historical_exclusions(ROOT)
