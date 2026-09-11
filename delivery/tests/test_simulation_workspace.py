from __future__ import annotations

import json
import os
import shutil
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

from tools.simulation_workspace import ascii_simulation_workspace


class SimulationWorkspaceTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('iverilog') and shutil.which('vvp'), 'Icarus required for real failure evidence')
    def test_real_vvp_failure_preserves_log_and_exit_code(self):
        from tools.run_stage2g_functional_rtl import iverilog_case, RunnerError
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / 'failure.sv'
            source.write_text('module failure; initial $fatal(1, "intentional simulation failure"); endmodule\n')
            with patch.dict(os.environ, {'CSIP_SIM_SCRATCH_ROOT': str(root / 'scratch')}):
                with self.assertRaises(RunnerError):
                    iverilog_case(root / 'result', 'failure', 'failure', [source], 'MUST_NOT_PASS')
            evidence = root / 'result/icarus/failure'
            self.assertIn('intentional simulation failure', (evidence / 'run.log').read_text())
            self.assertNotEqual(0, json.loads((evidence / 'run.log.command.json').read_text())['exit_code'])
            self.assertEqual('FAIL', json.loads((evidence / 'workspace_receipt.json').read_text())['status'])

    def test_unavailable_scratch_and_output_overlap_fail(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            blocked = root / 'file'
            blocked.write_text('not a directory')
            with patch.dict(os.environ, {'CSIP_SIM_SCRATCH_ROOT': str(blocked)}):
                with self.assertRaises(OSError):
                    with ascii_simulation_workspace(root / 'source', root / 'result', 'failure'):
                        self.fail('Must not run')
            with self.assertRaisesRegex(ValueError, 'disjoint'):
                with ascii_simulation_workspace(root, root / 'inside', 'failure'):
                    self.fail('Must not run')

    def test_copy_failure_keeps_original_diagnostics(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with patch.dict(os.environ, {'CSIP_SIM_SCRATCH_ROOT': str(root / 'scratch')}), \
                 patch('tools.simulation_workspace.shutil.copytree', side_effect=OSError('copy failed')):
                with self.assertRaisesRegex(OSError, 'copy failed'):
                    with ascii_simulation_workspace(root / 'source', root / 'result', 'copy') as work:
                        (work / 'run.log').write_text('diagnostic')
            self.assertEqual('diagnostic', (work / 'run.log').read_text())

    def test_unicode_requested_output_receives_ascii_workspace_evidence(self):
        with tempfile.TemporaryDirectory(prefix='csip-scratch-') as scratch_name, \
             tempfile.TemporaryDirectory(prefix='csip-output-') as output_name, \
             patch.dict(os.environ, {'CSIP_SIM_SCRATCH_ROOT': scratch_name}, clear=True):
            evidence = Path(output_name) / '中文 结果'
            seen = []
            with ascii_simulation_workspace(Path(output_name) / 'source', evidence, 'fixture') as work:
                seen.append(work)
                self.assertTrue(str(work).isascii())
                (work / 'run.log').write_text('PASS\n')
            self.assertFalse(seen[0].exists())
            self.assertEqual('PASS\n', (evidence / 'run.log').read_text())
            receipt = json.loads((evidence / 'workspace_receipt.json').read_text())
            self.assertEqual('PASS', receipt['status'])
            self.assertEqual(str(seen[0]), receipt['scratch_path'])
            self.assertEqual(str(evidence.resolve()), receipt['caller_output'])

    def test_failure_is_copied_and_marked_failed(self):
        with tempfile.TemporaryDirectory(prefix='csip-scratch-') as scratch_name, \
             tempfile.TemporaryDirectory(prefix='csip-output-') as output_name, \
             patch.dict(os.environ, {'CSIP_SIM_SCRATCH_ROOT': scratch_name}, clear=True):
            evidence = Path(output_name) / 'failure'
            with self.assertRaisesRegex(RuntimeError, 'intentional'):
                with ascii_simulation_workspace(Path(output_name) / 'source', evidence, 'fixture') as work:
                    (work / 'run.log').write_text('failure detail\n')
                    raise RuntimeError('intentional')
            self.assertEqual('failure detail\n', (evidence / 'run.log').read_text())
            receipt = json.loads((evidence / 'workspace_receipt.json').read_text())
            self.assertEqual('FAIL', receipt['status'])

    def test_non_ascii_explicit_scratch_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix='csip-output-') as output_name, \
             patch.dict(os.environ, {'CSIP_SIM_SCRATCH_ROOT': str(Path(output_name) / '中文')}, clear=True):
            with self.assertRaisesRegex(ValueError, 'must be ASCII'):
                with ascii_simulation_workspace(Path(output_name) / 'source', Path(output_name) / 'evidence', 'fixture'):
                    pass

    def test_concurrent_workspaces_do_not_share_files(self):
        with tempfile.TemporaryDirectory(prefix='csip-scratch-') as scratch_name, \
             tempfile.TemporaryDirectory(prefix='csip-output-') as output_name, \
             patch.dict(os.environ, {'CSIP_SIM_SCRATCH_ROOT': scratch_name}, clear=True):
            root = Path(output_name)

            def run(label):
                with ascii_simulation_workspace(root / 'source', root / ('结果 ' + label), label) as work:
                    (work / 'owner.txt').write_text(label)
                    return work

            with ThreadPoolExecutor(max_workers=2) as executor:
                workspaces = list(executor.map(run, ('one', 'two')))
            self.assertNotEqual(workspaces[0], workspaces[1])
            self.assertEqual('one', (root / '结果 one/owner.txt').read_text())
            self.assertEqual('two', (root / '结果 two/owner.txt').read_text())


if __name__ == '__main__':
    unittest.main()
