"""Keep vendor dispatch and portable entrypoint arguments independent."""
import ast
import inspect
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from tools import run_stage2g_functional_rtl as runner


class RegressionDispatchTests(unittest.TestCase):
    def test_all_xsim_calls_match_the_real_helper_signature(self):
        tree = ast.parse(Path(runner.__file__).read_text(encoding='utf-8'))
        signature = inspect.signature(runner.xsim_case)
        calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)
                 and isinstance(node.func, ast.Name) and node.func.id == 'xsim_case']
        self.assertTrue(calls)
        for node in calls:
            with self.subTest(line=node.lineno):
                signature.bind(*[None for _ in node.args], **{kw.arg: None for kw in node.keywords})

    def test_portable_cli_preserves_portable_dispatch(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(runner, 'run_current') as run, \
             patch.object(runner, 'resolve_vivado_bin') as vendor:
            self.assertEqual(0, runner.main(['--portable', '--output', str(Path(temp) / 'out')]))
            vendor.assert_not_called()
            self.assertTrue(run.call_args.kwargs['portable'])
            self.assertIsNone(run.call_args.kwargs['vivado_bin'])

    def test_full_digital_cli_keeps_vendor_dispatch(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(runner, 'run_current') as run, \
             patch.object(runner, 'resolve_vivado_bin', return_value=Path(temp)):
            self.assertEqual(0, runner.main(['--full-regression', '--xsim', '--output', str(Path(temp) / 'out')]))
            self.assertFalse(run.call_args.kwargs['portable'])
            self.assertTrue(run.call_args.kwargs['full'])
            self.assertTrue(run.call_args.kwargs['include_xsim'])
