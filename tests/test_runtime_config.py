import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools import runtime_config as config


class RuntimeConfigTests(unittest.TestCase):
    def test_config_relative_paths_and_precedence(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {}, clear=True):
            root = Path(temp)
            file = root / 'local.json'
            file.write_text(json.dumps({'build_root': './output', 'iverilog': 'configured'}))
            os.environ['CSIP_CONFIG'] = str(file)
            self.assertEqual(root / 'output', config.resolve_directory(root, 'build_root'))
            os.environ['CSIP_IVERILOG'] = 'environment'
            self.assertEqual('environment', config.configured(root, 'iverilog'))
            self.assertEqual('command-line', config.configured(root, 'iverilog', 'command-line'))

    def test_invalid_explicit_tool_does_not_fall_back(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(ValueError):
                config.resolve_tool(Path(temp), 'python', 'absent-csip-tool-1234')

    def test_malformed_config_is_an_error(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {}, clear=True):
            file = Path(temp) / 'invalid.json'
            file.write_text('{')
            os.environ['CSIP_CONFIG'] = str(file)
            with self.assertRaises(ValueError):
                config.load_config(Path(temp))

    def test_export_never_inherits_parent_repository_identity(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(config.subprocess, 'run') as run:
            self.assertIsNone(config.optional_git_identity(Path(temp)))
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
