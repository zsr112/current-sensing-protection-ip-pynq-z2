from __future__ import annotations
import json
import os
import tempfile
import unittest
import subprocess
from unittest.mock import patch
from pathlib import Path

from tools import build_windows_board_release as builder
from tools import verify_windows_board_release as verifier
from tools.board_validation.stage2_board_session import identity
from tools.run_stage2_board_plan_rtl import vectors
from tools import runtime_config, run_stage2g_functional_rtl as regression


class WindowsEvidenceTests(unittest.TestCase):
    @unittest.skipUnless(os.name == "nt", "Windows Tcl environment")
    def test_tcl_child_uses_native_powershell_modules_and_canonical_environment(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "xtclsh.bat").touch()
            modules = root / "System32/WindowsPowerShell/v1.0/Modules"
            modules.mkdir(parents=True)
            supplied = {"SYSTEMROOT": str(root), "PSMODULEPATH": "custom-modules", "KEEP_ME": "yes"}
            with patch.dict(regression.os.environ, supplied, clear=True), \
                 patch.object(regression, "run_logged", return_value=(0, "PASS")) as runner:
                regression.run_tcl(root, "fixture", root / "fixture.tcl", root)
                environment = runner.call_args.kwargs["env"]
                self.assertEqual(str(root), environment["SystemRoot"])
                self.assertNotIn("SYSTEMROOT", environment)
                self.assertNotIn("PSMODULEPATH", environment)
                self.assertEqual(str(modules) + os.pathsep + "custom-modules", environment["PSModulePath"])
                self.assertEqual("yes", environment["KEEP_ME"])
                self.assertEqual(supplied, dict(regression.os.environ))

    @unittest.skipUnless(os.name == "nt", "Windows Tcl environment")
    def test_tcl_child_does_not_invent_missing_system_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "xtclsh.bat").touch()
            with patch.dict(regression.os.environ, {"PSMODULEPATH": "custom-modules"}, clear=True), \
                 patch.object(regression, "run_logged", return_value=(0, "PASS")) as runner:
                regression.run_tcl(root, "fixture", root / "fixture.tcl", root)
                environment = runner.call_args.kwargs["env"]
                self.assertNotIn("SystemRoot", environment)
                self.assertEqual("custom-modules", environment["PSModulePath"])

    def test_missing_git_history_refs_do_not_block_current_checkout(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(regression, "optional_git_identity", return_value={"branch": "work", "commit": "a" * 40}), \
                 patch.object(regression.subprocess, "run", return_value=subprocess.CompletedProcess([], 128, "")), \
                 patch.object(regression.subprocess, "check_output", return_value=""):
                regression.git_identity(Path(temporary), require_clean=True)
            self.assertIn("REMOTE_MAIN=UNAVAILABLE", (Path(temporary) / "git_identity.txt").read_text())

    def test_vivado_path_fallback(self):
        executable = Path("toolchain/bin/vivado.bat")
        with patch.object(runtime_config, "resolve_directory", return_value=None), \
             patch.object(runtime_config, "resolve_tool", return_value=executable):
            self.assertEqual(executable.parent, runtime_config.resolve_vivado_bin(Path(".")))

    def test_http_urls_are_not_drive_paths(self):
        url = "http://www.xilinx.com/path"
        self.assertIsNone(verifier.PRIVATE_PATH.search(url.encode()))
        self.assertEqual(url, builder.portable_text(url, {}))

    def test_path_derivatives_preserve_structured_values(self):
        value = {"file": "D:" + r"\example\a.json", "count": 456, "status": "PASS"}
        converted = builder.portable_json(value, {})
        self.assertEqual(456, converted["count"])
        self.assertEqual("PASS", converted["status"])
        self.assertNotEqual(value["file"], converted["file"])
        self.assertIsNone(verifier.PRIVATE_PATH.search(json.dumps(converted).encode()))
        self.assertEqual("D:" + r"\example\a.json", value["file"])

    def test_parent_absolute_and_drive_paths_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            for relative in ("../escape", "/absolute", "D:" + "/private", "a\\b"):
                with self.subTest(relative=relative), self.assertRaises(ValueError):
                    verifier.safe_file(Path(temporary), relative)

    def test_changed_missing_and_extra_evidence_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "capture.csv"
            path.write_bytes(b"original raw capture")
            records = {"capture.csv": identity(path)}
            verifier.verify_files(root, records)
            path.write_bytes(b"changed raw capture")
            with self.assertRaises(ValueError):
                verifier.verify_files(root, records)
            path.unlink()
            with self.assertRaises(ValueError):
                verifier.verify_files(root, records)
            path.write_bytes(b"original raw capture")
            (root / "extra.txt").write_text("unexpected")
            with self.assertRaises(ValueError):
                verifier.verify_files(root, records)

    def test_duplicate_json_key_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "receipt.json"
            path.write_text('{"status":"FAIL","status":"PASS"}')
            with self.assertRaises(ValueError):
                verifier.load(path)

    def test_failed_campaign_cannot_be_released(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "board_verification_receipt.json").write_text(
                '{"status":"BLOCKED","evidence_state":"NOT_FORMALLY_ACCEPTED"}')
            with self.assertRaisesRegex(ValueError, "did not pass"):
                verifier.verify_board(root)

    def test_plan_contains_exact_stuck_transition_boundary(self):
        commands = vectors()
        pattern = [(0, 1024, 1024, 2, 0), (2, 0, 0, 0, 0),
                   (0, 1024, 1024, 1, 0), (2, 32, 32, 5, 1)]
        self.assertTrue(any(commands[i:i + 4] == pattern for i in range(len(commands))))


if __name__ == "__main__":
    unittest.main()
