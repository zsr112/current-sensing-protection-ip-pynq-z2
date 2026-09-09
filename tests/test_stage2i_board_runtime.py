from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from sw import stage2i_board_runtime as board_runtime
from tests import stage2i_release_test_support as support
from tools import stage2i_physical_authority as physical_authority
from tools.board_validation import build_stage1_board_execution_package as builder


REPO_ROOT = Path(__file__).resolve().parents[1]


class Stage2IBoardPackageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def build_tree(self, profile: str) -> Path:
        fixture = support.write_artifact_manifest_fixture(
            self.root / f"physical-{profile}", profile
        )
        manifest = physical_authority.load_artifact_manifest(
            fixture["manifest_path"], expected_profile=profile
        )
        package_root = self.root / f"package-{profile}"
        package_root.mkdir()
        builder.write_package_tree(
            package_root,
            REPO_ROOT,
            manifest,
            "codex/stage2i-fixture",
            support.SOURCE_COMMIT,
            support.SOURCE_TREE,
        )
        return package_root

    def test_safe_inert_package_validates_offline(self) -> None:
        package_root = self.build_tree(board_runtime.SAFE_INERT)
        result = builder.validate_package_tree(package_root)
        offline = board_runtime.validate_package(
            package_root, expected_profile=board_runtime.SAFE_INERT
        )
        self.assertEqual("PASS", result["status"])
        self.assertEqual({"destination"}, set(offline["ltx"]))
        self.assertEqual(12, offline["ltx"]["destination"]["probe_count"])
        self.assertNotIn(
            "stage2i_b2_ready_aware_stimulus_0", offline["hwh"]["modules"]
        )

    def test_ready_aware_package_validates_both_ila_cores(self) -> None:
        package_root = self.build_tree(board_runtime.READY_AWARE)
        result = builder.validate_package_tree(package_root)
        offline = board_runtime.validate_package(
            package_root, expected_profile=board_runtime.READY_AWARE
        )
        self.assertEqual(board_runtime.READY_AWARE, result["implementation_profile"])
        self.assertEqual({"destination", "source"}, set(offline["ltx"]))
        self.assertIn(
            "stage2i_b2_ready_aware_stimulus_0", offline["hwh"]["modules"]
        )
        self.assertEqual(8, offline["ltx"]["destination"]["probe_count"])
        self.assertEqual(8, offline["ltx"]["source"]["probe_count"])
        destination_signals = {
            record["signal"]
            for record in board_runtime.debug_core_contract(board_runtime.READY_AWARE)[
                "destination"
            ]["probes"].values()
        }
        self.assertTrue(
            destination_signals.isdisjoint(
                {
                    "adc_sample_valid",
                    "adc_sample_ready",
                    "adc_sample_ch1",
                    "adc_sample_ch2",
                }
            )
        )

    def test_profile_mismatch_and_safe_inert_topology_leak_fail_closed(self) -> None:
        package_root = self.build_tree(board_runtime.SAFE_INERT)
        with self.assertRaisesRegex(
            board_runtime.Stage2IBoardError, "differs from caller"
        ):
            board_runtime.validate_package(
                package_root, expected_profile=board_runtime.READY_AWARE
            )

        profile = board_runtime.load_profile(package_root)
        hwh_path = package_root / "artifacts/protection_system.hwh"
        hwh = hwh_path.read_text(encoding="utf-8").replace(
            "</SYSTEM>",
            '  <MODULE INSTANCE="stage2i_b2_ready_aware_stimulus_0"/>\n</SYSTEM>',
        )
        hwh_path.write_text(hwh, encoding="utf-8")
        with self.assertRaisesRegex(
            board_runtime.Stage2IBoardError, "leaked into SAFE_INERT"
        ):
            board_runtime.validate_hwh(hwh_path, profile)

    def test_ltx_missing_source_core_fails_closed(self) -> None:
        package_root = self.build_tree(board_runtime.READY_AWARE)
        profile = board_runtime.load_profile(package_root)
        ltx_path = package_root / "artifacts/protection_system.ltx"
        payload = json.loads(ltx_path.read_text(encoding="utf-8"))
        cores = payload["ltx_root"]["ltx_data"][0]["debug_cores"]
        payload["ltx_root"]["ltx_data"][0]["debug_cores"] = cores[:1]
        ltx_path.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaisesRegex(
            board_runtime.Stage2IBoardError, "ILA core count differs"
        ):
            board_runtime.validate_ltx(ltx_path, profile)

    def test_ltx_native_probe_width_drift_fails_closed(self) -> None:
        package_root = self.build_tree(board_runtime.READY_AWARE)
        profile = board_runtime.load_profile(package_root)
        ltx_path = package_root / "artifacts/protection_system.ltx"
        payload = json.loads(ltx_path.read_text(encoding="utf-8"))
        destination = payload["ltx_root"]["ltx_data"][0]["debug_cores"][0]
        destination["native_ports"][5]["port_maps"][0]["physical_pin"][
            "width"
        ] = 7
        ltx_path.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaisesRegex(
            board_runtime.Stage2IBoardError, "native pin cross-check differs"
        ):
            board_runtime.validate_ltx(ltx_path, profile)

    def test_ltx_explicit_non_probe_protocol_fails_closed(self) -> None:
        package_root = self.build_tree(board_runtime.READY_AWARE)
        profile = board_runtime.load_profile(package_root)
        ltx_path = package_root / "artifacts/protection_system.ltx"
        payload = json.loads(ltx_path.read_text(encoding="utf-8"))
        destination = payload["ltx_root"]["ltx_data"][0]["debug_cores"][0]
        destination["native_ports"][0]["protocol"] = "AXI4LITE"
        ltx_path.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaisesRegex(
            board_runtime.Stage2IBoardError, "native port is not a probe"
        ):
            board_runtime.validate_ltx(ltx_path, profile)

    def test_package_entry_drift_is_rejected(self) -> None:
        package_root = self.build_tree(board_runtime.SAFE_INERT)
        (package_root / "unexpected.txt").write_text("unexpected\n", encoding="utf-8")
        with self.assertRaisesRegex(builder.PackageBuildError, "entry set differs"):
            builder.validate_package_tree(package_root)

    def test_deterministic_zip_round_trip(self) -> None:
        package_root = self.build_tree(board_runtime.READY_AWARE)
        zip_a = self.root / "package-a.zip"
        zip_b = self.root / "package-b.zip"
        builder.write_deterministic_zip(package_root, zip_a)
        builder.write_deterministic_zip(package_root, zip_b)
        self.assertEqual(zip_a.read_bytes(), zip_b.read_bytes())
        result = builder.validate_package_zip(zip_a)
        self.assertEqual("PASS", result["status"])
        self.assertEqual("PASS", result["zip_crc"])

    def test_direct_builder_help_works_from_repository(self) -> None:
        script = REPO_ROOT / "tools/board_validation/build_stage1_board_execution_package.py"
        result = subprocess.run(
            [sys.executable, str(script), "--help"],
            cwd=REPO_ROOT,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("--artifact-manifest", result.stdout)


class Stage2IB2ControlTests(unittest.TestCase):
    def test_command_encoding_and_status_decoding(self) -> None:
        word = board_runtime.encode_b2_command(0x123, 0xABC, 127, 1)
        self.assertEqual(0x123, word & 0xFFF)
        self.assertEqual(0xABC, (word >> 12) & 0xFFF)
        self.assertEqual(127, (word >> 24) & 0x7F)
        self.assertEqual(1, (word >> 31) & 1)

        raw_status = (
            (board_runtime.B2_STATUS_MARKER << 24)
            | (37 << 11)
            | (12 << 4)
            | (1 << 2)
            | (1 << 1)
            | 1
        )
        status = board_runtime.decode_b2_status(raw_status)
        self.assertEqual(37, status["accepted_count"])
        self.assertEqual(12, status["remaining"])
        self.assertTrue(status["request_pending"])
        self.assertTrue(status["active"])
        self.assertEqual(1, status["ack_epoch"])

    def test_invalid_command_fields_are_rejected(self) -> None:
        for values in ((-1, 0, 1, 0), (0, 0x1000, 1, 0), (0, 0, 128, 0), (0, 0, 1, 2)):
            with self.subTest(values=values):
                with self.assertRaises(board_runtime.Stage2IBoardError):
                    board_runtime.encode_b2_command(*values)


if __name__ == "__main__":
    unittest.main()
