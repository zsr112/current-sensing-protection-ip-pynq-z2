import json
import io
from contextlib import redirect_stdout
import os
import subprocess
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path
from unittest.mock import patch
from tools import target_preflight as preflight
from tools import run_portable_regression as portable
from tools import rebuild
from tools.runtime_config import resolve_directory, resolve_vivado_bin


class TargetPreflightTests(unittest.TestCase):
    def test_full_digital_child_failure_propagates(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            root, output = base / 'source', base / 'output'
            root.mkdir()
            self.fixture(root)
            source = {'origin': {'commit': 'a' * 40, 'tree': 'b' * 40}, 'files': {}}
            tools = {name: Path(name) for name in ('iverilog', 'vvp', 'pwsh')}
            args = Namespace(config=None, phase='digital', execution_id='TEST-DIGITAL', build_root=output, target='all')
            with patch.object(rebuild, 'ROOT', root), \
                 patch.object(preflight, 'inventory', return_value={'target_ready': True}), \
                 patch.object(rebuild, 'verify', return_value=source), \
                 patch.object(rebuild, 'tool_environment', return_value=(tools, base, None)), \
                 patch.object(rebuild, 'version', return_value='Vivado 2024.1 5076996'), \
                 patch.object(rebuild, 'resolve_directory', return_value=output), \
                 patch.object(rebuild.subprocess, 'run') as run:
                run.side_effect = [subprocess.CompletedProcess([], code) for code in (1, 0, 0, 0, 0)]
                with redirect_stdout(io.StringIO()):
                    self.assertEqual(1, rebuild.run(args))
            receipt = json.loads((output / 'rebuild_receipt.json').read_text())
            self.assertEqual('FAIL', receipt['status'])
            self.assertEqual('PASS', receipt['checks']['board_plan']['status'])

    def fixture(self, root):
        (root / 'SOURCE_MANIFEST.json').write_text(json.dumps({'schema': 'csip-source-export-v1', 'files': {}}))

    def test_portable_only_environment_and_vendor_block(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            with patch.object(preflight, 'resolve_tool', side_effect=lambda r, n, a: Path(n) if n in ('iverilog', 'vvp') else None), \
                 patch.object(preflight, 'resolve_vivado_bin', return_value=None), \
                 patch.object(preflight, 'probe', return_value=(0, 'Icarus Verilog version 13.0')):
                result = preflight.inventory(root, 'portable')
                self.assertTrue(result['target_ready'], result)
                for target in ('digital', 'vivado', 'all'):
                    result = preflight.inventory(root, target)
                    self.assertFalse(result['target_ready'])
                    self.assertIn('vivado', result['missing'])
                    self.assertEqual('NOT_RUN', result['license'])
                    self.assertEqual('NOT_RUN', result['board_verified'])

    def test_wrong_version_invalid_configuration_and_source_are_retained(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            with patch.object(preflight, 'resolve_tool', return_value=Path('fake')), \
                 patch.object(preflight, 'resolve_vivado_bin', side_effect=ValueError('explicit bad path')), \
                 patch.object(preflight, 'probe', return_value=(0, 'Icarus Verilog version 11.0')):
                (root / 'unexpected').write_text('extra')
                result = preflight.inventory(root, 'portable')
                self.assertFalse(result['target_ready'])
                self.assertEqual('FAIL', result['source_integrity'])
                self.assertIn('iverilog', result['unsupported'])
                self.assertTrue(any('explicit bad path' in e for e in result['errors']))

    def test_bare_relative_directory_uses_config_parent(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {}, clear=True):
            root = Path(temp)
            config = root / 'config.json'
            config.write_text(json.dumps({'sim_scratch_root': 'scratch', 'vivado_bin': 'missing'}))
            os.environ['CSIP_CONFIG'] = str(config)
            self.assertEqual((root / 'scratch').resolve(), resolve_directory(root, 'sim_scratch_root'))
            with self.assertRaisesRegex(ValueError, 'no Vivado'):
                resolve_vivado_bin(root)

    def test_failure_does_not_get_overwritten_by_later_passes(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(portable.subprocess, 'run') as run:
            run.side_effect = [subprocess.CompletedProcess([], c) for c in (1, 0, 0, 0)]
            with self.assertRaisesRegex(RuntimeError, 'failed'), redirect_stdout(io.StringIO()):
                portable.run_checks(Path(temp), Path(temp), rtl_only=True)
            result = json.loads((Path(temp) / 'portable_result.json').read_text())
            self.assertEqual('FAIL', result['status'])
            self.assertEqual('FAIL', result['checks']['basic_rtl']['status'])
            self.assertEqual('PASS', result['checks']['board_plan']['status'])
