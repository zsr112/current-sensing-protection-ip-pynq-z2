from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

from tools import check_register_map_implementation as register_checker
from tools import run_stage2g_functional_rtl as stage2g_runner


ROOT = Path(__file__).resolve().parents[2]
RUNNER_PATH = ROOT / "tools/run_stage2g_functional_rtl.py"
CORE_FIXTURE_PATH = ROOT / "tb/stage2g/tb_stage2g_core_directed.sv"
LIVE_PACKAGE_PATH = (
    ROOT
    / "fpga/vivado/build/runtime/runner/"
    "stage1e_production_vivado_runner_v2.tcl"
)
COMPATIBILITY_PACKAGE_PATH = (
    ROOT / "fpga/vivado/package_protection_ip_stage2_axi_lite.tcl"
)


class CurrentStage2GOrchestrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.runner = RUNNER_PATH.read_text(encoding="utf-8")
        self.core_fixture = CORE_FIXTURE_PATH.read_text(encoding="utf-8")

    def validate(self, runner: str | None = None, core: str | None = None) -> None:
        stage2g_runner.validate_current_orchestration_source(
            runner if runner is not None else self.runner,
            core if core is not None else self.core_fixture,
        )

    def test_current_sources_pass(self) -> None:
        self.validate()

    def test_frozen_git_gate_is_rejected(self) -> None:
        mutant = self.runner + (
            "\nFROZEN_GATE = "
            '"codex/stage2g-reset-wait-first-fault-policy-implementation"\n'
        )
        with self.assertRaisesRegex(stage2g_runner.RunnerError, "frozen Stage 2G"):
            self.validate(runner=mutant)

    def test_removed_sequence_matrix_reference_is_rejected(self) -> None:
        mutant = self.runner + '\nOBSOLETE = "tb_stage2g_sequence_integrity_matrix.sv"\n'
        with self.assertRaisesRegex(stage2g_runner.RunnerError, "removed sequence"):
            self.validate(runner=mutant)

    def test_historical_replay_in_current_default_is_rejected(self) -> None:
        anchor = "    git_identity(output, require_clean)\n"
        mutant = self.runner.replace(
            anchor,
            anchor + '    forbidden = "replay_stage2g_source_archive.py"\n',
            1,
        )
        with self.assertRaisesRegex(stage2g_runner.RunnerError, "historical oracle"):
            self.validate(runner=mutant)

    def test_undriven_destination_integrity_is_rejected(self) -> None:
        mutant = self.core_fixture.replace(
            "        .sample_destination_integrity_clean(\n"
            "            sample_destination_integrity_clean),\n",
            "",
            1,
        )
        with self.assertRaisesRegex(
            stage2g_runner.RunnerError, "destination_integrity_clean"
        ):
            self.validate(core=mutant)


class LivePackageBindingTests(unittest.TestCase):
    def check_mutant(self, live_text: str) -> None:
        with tempfile.TemporaryDirectory(prefix="stage2h-c2-package-") as temporary:
            root = Path(temporary)
            live = root / LIVE_PACKAGE_PATH.relative_to(ROOT)
            compatibility = root / COMPATIBILITY_PACKAGE_PATH.relative_to(ROOT)
            live.parent.mkdir(parents=True)
            compatibility.parent.mkdir(parents=True, exist_ok=True)
            live.write_text(live_text, encoding="utf-8")
            shutil.copy2(COMPATIBILITY_PACKAGE_PATH, compatibility)
            register_checker.check_live_package_ipxact_binding(root)

    def test_generated_ipxact_omission_is_rejected(self) -> None:
        mutant = LIVE_PACKAGE_PATH.read_text(encoding="utf-8").replace(
            "    source $register_map_ipxact\n", "", 1
        )
        with self.assertRaisesRegex(
            register_checker.CheckError, "source.*exactly once"
        ):
            self.check_mutant(mutant)

    def test_generated_ipxact_double_apply_is_rejected(self) -> None:
        live = LIVE_PACKAGE_PATH.read_text(encoding="utf-8")
        token = "protection_register_map_apply_ipxact $block"
        mutant = live.replace(token, f"{token}\n    {token}", 1)
        with self.assertRaisesRegex(
            register_checker.CheckError, "apply_ipxact.*exactly once"
        ):
            self.check_mutant(mutant)


if __name__ == "__main__":
    unittest.main()
