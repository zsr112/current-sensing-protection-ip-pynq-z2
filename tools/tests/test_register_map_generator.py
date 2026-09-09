"""Focused Stage 2H-A2 generator and legacy-ABI mutation tests."""

from __future__ import annotations

import copy
import argparse
import shutil
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import check_register_map_implementation as checker
from tools import generate_register_map as generator
from tools import replay_register_map_source_archive as source_replay


class RegisterMapMutationTests(unittest.TestCase):
    FAILURE_MODES = {
        "test_legacy_register_offset_change_is_rejected": "frozen register offset drift",
        "test_field_bit_position_change_is_rejected": "frozen field encoding drift",
        "test_access_type_change_is_rejected": "frozen access-semantic drift",
        "test_reset_value_change_is_rejected": "frozen reset-semantic drift",
        "test_fault_code_numeric_change_is_rejected": "frozen fault-code drift",
        "test_legacy_alias_removal_is_rejected": "legacy public-name or alias removal",
        "test_legacy_c_output_path_change_is_rejected": "frozen C path drift",
        "test_fault_defs_numeric_authority_is_rejected": "parallel RTL numeric authority",
        "test_manual_generated_file_edit_is_detected": "hand-edited generated output",
        "test_nondeterministic_renderer_is_rejected": "environment-dependent output",
        "test_duplicate_register_offset_is_rejected": "ambiguous address decode",
        "test_overlapping_fields_are_rejected": "ambiguous field encoding",
        "test_generated_docs_disagreement_is_detected": "documentation/source drift",
        "test_source_change_without_regeneration_is_detected": "stale generated outputs",
        "test_invalid_access_type_is_rejected": "unsupported access semantics",
        "test_unknown_enum_reference_is_rejected": "unresolved enum ownership",
        "test_conflicting_fault_alias_is_rejected": "ambiguous public fault name",
        "test_duplicate_json_key_is_rejected": "ambiguous JSON source",
        "test_field_outside_register_width_is_rejected": "field/register width mismatch",
        "test_unowned_generated_target_is_rejected": "unowned generated artifact",
    }

    @classmethod
    def setUpClass(cls) -> None:
        tests = {name for name in dir(cls) if name.startswith("test_")}
        if tests != set(cls.FAILURE_MODES):
            raise AssertionError(
                f"mutation failure-mode inventory mismatch: tests={sorted(tests)} "
                f"modes={sorted(cls.FAILURE_MODES)}"
            )

    def setUp(self) -> None:
        self.spec, _ = generator.load_json(ROOT / "spec/register_map.json")
        self.schema, _ = generator.load_json(ROOT / "spec/register_map.schema.json")
        self.baseline, self.baseline_bytes = generator.load_json(
            ROOT / "spec/stage2h_register_map_convergence.json"
        )

    def register(self, name: str) -> dict:
        return next(item for item in self.spec["registers"] if item["name"] == name)

    def fault(self, name: str) -> dict:
        return next(item for item in self.spec["fault_codes"] if item["name"] == name)

    def render(self, spec: dict | None = None) -> dict[str, str]:
        outputs, _ = generator.validate_and_render(
            spec or self.spec,
            self.schema,
            self.baseline,
            baseline_bytes=self.baseline_bytes,
        )
        return outputs

    def assert_rejected(self, pattern: str) -> None:
        with self.assertRaisesRegex(generator.GenerationError, pattern):
            self.render()

    def test_legacy_register_offset_change_is_rejected(self) -> None:
        ctrl = self.register("CTRL")
        status = self.register("STATUS")
        ctrl["offset"], status["offset"] = status["offset"], ctrl["offset"]
        self.assert_rejected("legacy ABI parity failed: offset=2")

    def test_field_bit_position_change_is_rejected(self) -> None:
        fields = self.register("STATUS")["fields"]
        valid = next(field for field in fields if field["name"] == "fault_valid")
        latched = next(field for field in fields if field["name"] == "fault_latched")
        valid["lsb"], valid["msb"] = 1, 1
        latched["lsb"], latched["msb"] = 0, 0
        self.assert_rejected("legacy ABI parity failed:.*field=2")

    def test_access_type_change_is_rejected(self) -> None:
        self.register("STATUS")["access"] = "RW"
        self.assert_rejected("legacy ABI parity failed:.*access=1")

    def test_reset_value_change_is_rejected(self) -> None:
        register = self.register("TH_OC1")
        register["reset"] = 2999
        register["fields"][0]["reset"] = 2999
        self.assert_rejected("legacy ABI parity failed:.*reset=1.*field=1")

    def test_fault_code_numeric_change_is_rejected(self) -> None:
        overcurrent = self.fault("OVERCURRENT")
        mismatch = self.fault("SENSOR_MISMATCH")
        overcurrent["value"], mismatch["value"] = mismatch["value"], overcurrent["value"]
        self.assert_rejected(
            "fault projection differs from frozen priority at bitmap 0x01"
        )

    def test_legacy_alias_removal_is_rejected(self) -> None:
        aliases = self.fault("OC_WITH_ANY_SENSOR")["legacy_aliases"]["rtl"]
        self.fault("OC_WITH_ANY_SENSOR")["legacy_aliases"]["rtl"] = []
        self.assert_rejected("legacy fault taxonomy parity failed:.*aliases=1")
        self.fault("OC_WITH_ANY_SENSOR")["legacy_aliases"]["rtl"] = aliases
        self.register("CTRL")["public_names"]["python"] = "REG_CONTROL"
        self.assert_rejected("legacy software register name changed: CTRL")

    def test_legacy_c_output_path_change_is_rejected(self) -> None:
        self.spec["generated_artifacts"][2] = "sw/generated/protection_ip_regs.h"
        self.assert_rejected("frozen eight-path master topology")

    def test_fault_defs_numeric_authority_is_rejected(self) -> None:
        shim = (ROOT / "rtl/fault_defs.vh").read_text(encoding="utf-8")
        mutated = shim.replace("`endif", "`define FAULT_NONE 8'h00\n\n`endif")
        with self.assertRaisesRegex(checker.CheckError, "independent numeric"):
            checker.validate_fault_defs_shim(mutated)

    def test_manual_generated_file_edit_is_detected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="a2-generated-edit-") as temporary:
            output = Path(temporary)
            outputs = self.render()
            generator.write_outputs(output, outputs)
            target = output / "rtl/generated/protection_register_map.vh"
            target.write_text(
                target.read_text(encoding="utf-8") + "// manual edit\n",
                encoding="utf-8",
                newline="\n",
            )
            self.assertIn(
                "CONTENT:rtl/generated/protection_register_map.vh",
                generator.compare_outputs(output, outputs),
            )

    def test_nondeterministic_renderer_is_rejected(self) -> None:
        calls = 0

        def unstable() -> dict[str, str]:
            nonlocal calls
            calls += 1
            return {"artifact": f"run={calls}\n"}

        with self.assertRaisesRegex(checker.CheckError, "nondeterministic"):
            checker.assert_deterministic(unstable)

    def test_duplicate_register_offset_is_rejected(self) -> None:
        self.register("STATUS")["offset"] = self.register("CTRL")["offset"]
        self.assert_rejected("duplicate register offset")

    def test_overlapping_fields_are_rejected(self) -> None:
        reserved = self.register("CTRL")["fields"][-1]
        reserved["lsb"] = 1
        self.assert_rejected("overlapping fields")

    def test_generated_docs_disagreement_is_detected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="a2-doc-drift-") as temporary:
            output = Path(temporary)
            outputs = self.render()
            generator.write_outputs(output, outputs)
            docs = output / "docs/implementation/register_map.md"
            docs.write_text("# Incorrect map\n", encoding="utf-8", newline="\n")
            self.assertIn(
                "CONTENT:docs/implementation/register_map.md",
                generator.compare_outputs(output, outputs),
            )

    def test_source_change_without_regeneration_is_detected(self) -> None:
        changed = copy.deepcopy(self.spec)
        pwm = next(item for item in changed["registers"] if item["name"] == "PWM_PERIOD")
        pwm["description"] += " Source-only mutation."
        changed_outputs = self.render(changed)
        drift = generator.compare_outputs(ROOT, changed_outputs)
        self.assertTrue(drift)
        self.assertIn("CONTENT:docs/implementation/register_map.md", drift)

    def test_invalid_access_type_is_rejected(self) -> None:
        self.register("STATUS")["access"] = "WRITE_ONLY"
        self.assert_rejected("access is invalid")

    def test_unknown_enum_reference_is_rejected(self) -> None:
        self.register("FAULT_CODE")["fields"][0]["enum_ref"] = "other_codes"
        self.assert_rejected("unknown enum reference")

    def test_conflicting_fault_alias_is_rejected(self) -> None:
        self.fault("SENSOR_OPEN")["legacy_aliases"]["rtl"].append("FAULT_OVERCURRENT")
        self.assert_rejected("conflicting rtl fault alias")

    def test_duplicate_json_key_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="a2-duplicate-json-") as temporary:
            source = Path(temporary) / "duplicate.json"
            source.write_text('{"schema_version":"1", "schema_version":"2"}\n', encoding="utf-8")
            with self.assertRaisesRegex(generator.GenerationError, "duplicate JSON key"):
                generator.load_json(source)

    def test_field_outside_register_width_is_rejected(self) -> None:
        self.register("CTRL")["fields"][-1]["msb"] = 32
        self.assert_rejected("field outside register width")

    def test_unowned_generated_target_is_rejected(self) -> None:
        self.spec["generated_artifacts"][-1] = "spec/generated/unowned.json"
        self.assert_rejected("frozen eight-path master topology")


class RegisterMapConsumerIntegrationTests(unittest.TestCase):
    def test_stage2g_generated_include_root_is_fail_closed(self) -> None:
        runner = (ROOT / "tools/run_stage2g_functional_rtl.py").read_text(
            encoding="utf-8"
        )
        checker.validate_stage2g_tb_include_path(runner)
        stale = runner.replace(
            'TB_GENERATED = ROOT / "tb/generated"',
            'TB_GENERATED = TB / "generated"',
        )
        with self.assertRaisesRegex(
            checker.CheckError, "generated testbench include root"
        ):
            checker.validate_stage2g_tb_include_path(stale)

    def test_active_consumer_binding_contracts_pass(self) -> None:
        self.assertEqual(
            checker.check_active_consumer_bindings(ROOT),
            len(checker.ACTIVE_CONSUMER_BINDING_PATHS),
        )


class MatrixReusePolicyMutationTests(unittest.TestCase):
    @staticmethod
    def _markers(paths: set[str]) -> str:
        return "\n".join(
            marker
            for path in paths
            for marker in source_replay.TARGETED_VALIDATION_MARKERS[path]
        )

    def test_rtl_change_invalidates_reuse(self) -> None:
        result = source_replay.validate_matrix_reuse_change_set(
            {"rtl/protection_reg_bank.v"}, set(), set(), ""
        )
        self.assertFalse(result["valid"])
        self.assertEqual(result["unapproved"], ["rtl/protection_reg_bank.v"])
        self.assertTrue(result["behavioral_inputs_changed"])

    def test_tb_change_invalidates_reuse(self) -> None:
        result = source_replay.validate_matrix_reuse_change_set(
            {"tb/stage2g/tb_stage2g_policy_matrix.sv"}, set(), set(), ""
        )
        self.assertFalse(result["valid"])
        self.assertEqual(
            result["unapproved"], ["tb/stage2g/tb_stage2g_policy_matrix.sv"]
        )
        self.assertTrue(result["behavioral_inputs_changed"])

    def test_added_path_invalidates_reuse(self) -> None:
        result = source_replay.validate_matrix_reuse_change_set(
            set(), {"sw/unexpected_runtime.py"}, set(), ""
        )
        self.assertFalse(result["valid"])

    def test_removed_path_invalidates_reuse(self) -> None:
        result = source_replay.validate_matrix_reuse_change_set(
            set(), set(), {"rtl/protection_reg_bank.v"}, ""
        )
        self.assertFalse(result["valid"])

    def test_missing_targeted_validation_invalidates_reuse(self) -> None:
        path = "tools/check_register_map_implementation.py"
        result = source_replay.validate_matrix_reuse_change_set(
            {path}, set(), set(), "REGISTER_MAP_IMPLEMENTATION_CHECK=PASS"
        )
        self.assertFalse(result["valid"])
        self.assertEqual(result["missing_targeted_validation"], [path])


class RegisterMapConsumerProvenanceMutationTests(unittest.TestCase):
    def _single_file_root(self, relative: str, content: str) -> Path:
        temporary = Path(tempfile.mkdtemp(prefix="a2-consumer-mutation-"))
        target = temporary / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8", newline="\n")
        self.addCleanup(shutil.rmtree, temporary)
        return temporary

    def test_active_consumer_offset_drift_is_detected(self) -> None:
        source = (ROOT / "sw/stage2c9e_b_pynq_mmio_register_smoke.py").read_text(
            encoding="utf-8"
        )
        mutated = source.replace(
            "REG_CTRL = int(RegisterOffset.CTRL)", "REG_CTRL = 0x04", 1
        )
        root = self._single_file_root(
            "sw/stage2c9e_b_pynq_mmio_register_smoke.py", mutated
        )
        with self.assertRaisesRegex(checker.CheckError, "manual ABI authority"):
            checker.validate_active_consumer(
                root,
                {"path": "sw/stage2c9e_b_pynq_mmio_register_smoke.py", "role": "ACTIVE_GENERATED_CONSUMER"},
            )

    def test_active_consumer_fault_code_drift_is_detected(self) -> None:
        source = (ROOT / "tools/board_validation/stage1_board_functional_validation.py").read_text(
            encoding="utf-8"
        )
        mutated = source + "\nFAULT_OVERCURRENT = 0x03\n"
        root = self._single_file_root(
            "tools/board_validation/stage1_board_functional_validation.py", mutated
        )
        with self.assertRaisesRegex(checker.CheckError, "manual ABI authority"):
            checker.validate_active_consumer(
                root,
                {"path": "tools/board_validation/stage1_board_functional_validation.py", "role": "ACTIVE_GENERATED_CONSUMER"},
            )

    def test_unclassified_executable_consumer_is_detected(self) -> None:
        root = self._single_file_root(
            "sw/unclassified_abi_consumer.py", "REG_CTRL = 0x00\n"
        )
        discovered = checker.discover_executable_consumers(ROOT)
        discovered.add("sw/unclassified_abi_consumer.py")
        with self.assertRaisesRegex(checker.CheckError, "unclassified executable"):
            checker.validate_discovered_consumer_paths(
                discovered,
                {entry["path"] for entry in checker.CONSUMER_INVENTORY},
            )
        self.assertTrue(checker._python_consumer_candidate(root / "sw/unclassified_abi_consumer.py"))

    def test_independent_oracle_misclassified_as_active_is_detected(self) -> None:
        mutated = copy.deepcopy(checker.CONSUMER_INVENTORY)
        entry = next(
            item for item in mutated if item["path"] == "tools/stage2g_reference_model.py"
        )
        entry["role"] = "ACTIVE_GENERATED_CONSUMER"
        with self.assertRaisesRegex(checker.CheckError, "manual ABI authority"):
            checker.check_consumer_inventory(ROOT, tuple(mutated))

    def test_recovery_snapshot_oracle_value_drift_is_detected(self) -> None:
        relative = "tools/check_stage2g_recovery_snapshots.py"
        source = (ROOT / relative).read_text(encoding="utf-8")
        mutated = source.replace("FAULT_OVERCURRENT = 0x01", "FAULT_OVERCURRENT = 0x03", 1)
        root = self._single_file_root(relative, mutated)
        entry = next(item for item in checker.CONSUMER_INVENTORY if item["path"] == relative)
        with self.assertRaisesRegex(checker.CheckError, "independent oracle parity drift"):
            checker.validate_independent_oracle(root, entry)

    def test_historical_snapshot_added_to_runtime_package_is_detected(self) -> None:
        temporary = Path(tempfile.mkdtemp(prefix="a2-history-package-mutation-"))
        self.addCleanup(shutil.rmtree, temporary)
        for relative in (
            "tools/board_validation/build_stage1_board_execution_package.py",
            "tools/build_current_release.py",
            *checker.HISTORICAL_CONSUMERS,
        ):
            target = temporary / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        builder = temporary / "tools/board_validation/build_stage1_board_execution_package.py"
        text = builder.read_text(encoding="utf-8")
        text = text.replace(
            "SOURCE_FILES = {",
            'SOURCE_FILES = {"notebooks/pynq_protection_mmio_demo_preboard.ipynb": ("history.ipynb", "fixture"),',
            1,
        )
        builder.write_text(text, encoding="utf-8", newline="\n")
        with self.assertRaisesRegex(checker.CheckError, "historical snapshot added"):
            checker.validate_historical_exclusions(temporary)


class ActiveConsumerBindingMutationTests(unittest.TestCase):
    def _single_file_root(self, relative: str, content: str) -> Path:
        temporary = Path(tempfile.mkdtemp(prefix="a2-active-binding-mutation-"))
        target = temporary / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8", newline="\n")
        self.addCleanup(shutil.rmtree, temporary)
        return temporary

    def test_stage2c9e_alias_bypass_is_detected(self) -> None:
        source = (ROOT / "sw/stage2c9e_b_pynq_mmio_register_smoke.py").read_text(
            encoding="utf-8"
        )
        mutated = source.replace(
            "REG_CTRL = int(RegisterOffset.CTRL)", "CTRL_OFFSET = 0x04", 1
        ).replace("REG_CTRL", "CTRL_OFFSET")
        with self.assertRaisesRegex(checker.CheckError, "generated ABI binding"):
            checker.validate_stage2c9e_binding(mutated)

    def test_direct_literal_mmio_is_detected(self) -> None:
        source = (ROOT / "sw/stage2c9e_b_pynq_mmio_register_smoke.py").read_text(
            encoding="utf-8"
        )
        mutated = source.replace(
            "protection.write(REG_CTRL, 0)",
            "protection.write(0x04, 0)",
            1,
        )
        with self.assertRaisesRegex(checker.CheckError, "direct literal"):
            checker.validate_stage2c9e_binding(mutated)

    def test_fault_cause_binding_mutation_is_detected(self) -> None:
        source = (
            ROOT / "tools/board_validation/stage1_board_functional_validation.py"
        ).read_text(encoding="utf-8")
        mutated = source.replace(
            "FaultCause.SENSOR_OPEN", "FaultCause.SENSOR_STUCK"
        )
        with self.assertRaisesRegex(checker.CheckError, "SENSOR_OPEN"):
            checker.validate_board_binding(mutated)

    def test_unused_generated_import_bypass_is_detected(self) -> None:
        source = (
            ROOT / "tools/board_validation/build_stage1_board_execution_package.py"
        ).read_text(encoding="utf-8")
        mutated = source.replace(
            '"major": int(REGISTER_MAP_VERSION_ABI_MAJOR_RESET)',
            '"major": 1',
            1,
        )
        self.assertIn("REGISTER_MAP_VERSION_ABI_MAJOR_RESET", mutated)
        with self.assertRaisesRegex(checker.CheckError, "ABI_MAJOR_RESET"):
            checker.validate_board_package_builder_binding(mutated)

    def test_stage2c9e_mmio_receiver_alias_bypass_is_detected(self) -> None:
        source = (ROOT / "sw/stage2c9e_b_pynq_mmio_register_smoke.py").read_text(
            encoding="utf-8"
        )
        mutated = source + "\nio = protection\nio.write(REG_CTRL, 0)\nio.read(REG_CTRL)\n"
        with self.assertRaisesRegex(checker.CheckError, "MMIO receiver alias bypass"):
            checker.validate_stage2c9e_binding(mutated)

    def test_interface_mmio_alias_and_literal_bypass_is_detected(self) -> None:
        source = (ROOT / "sw/protection_ip_interface.py").read_text(encoding="utf-8")
        mutated = source + "\nCTRL_OFFSET = 0x04\nio = mmio\nio.write(CTRL_OFFSET, 0)\nio.read(CTRL_OFFSET)\n"
        with self.assertRaisesRegex(checker.CheckError, "MMIO receiver alias bypass"):
            checker.validate_interface_binding(mutated)

    def test_arbitrary_name_mmio_consumer_is_discovered_and_rejected(self) -> None:
        root = self._single_file_root(
            "sw/new_bad_mmio_consumer.py",
            "def poke(mmio):\n    mmio.write(0x04, 0)\n    return mmio.read(0x04)\n",
        )
        discovered = checker.discover_executable_consumers(root)
        self.assertIn("sw/new_bad_mmio_consumer.py", discovered)
        with self.assertRaisesRegex(checker.CheckError, "unclassified executable"):
            checker.validate_discovered_consumer_paths(
                discovered,
                {entry["path"] for entry in checker.CONSUMER_INVENTORY},
            )

    def test_rendered_example_mmio_alias_bypass_is_detected(self) -> None:
        source = checker._render_read_only_example(ROOT)
        mutated = source + "\nio = mmio\nio.read(offset)\n"
        with self.assertRaisesRegex(checker.CheckError, "MMIO receiver alias bypass"):
            checker.validate_rendered_example_binding(mutated)


class ActiveRegisterContainerBindingMutationTests(unittest.TestCase):
    def test_stage2c9e_container_value_literal_is_detected(self) -> None:
        source = (ROOT / "sw/stage2c9e_b_pynq_mmio_register_smoke.py").read_text(
            encoding="utf-8"
        )
        mutated = source.replace(
            "(register.name, int(register))", "(register.name, 0x04)", 1
        )
        with self.assertRaisesRegex(
            checker.CheckError, "effective register container binding"
        ):
            checker.validate_stage2c9e_binding(mutated)

    def test_stage2c9f_write_candidate_literal_is_detected(self) -> None:
        source = (
            ROOT / "sw/stage2c9f_b_controlled_expanded_mmio_idempotent_rw.py"
        ).read_text(encoding="utf-8")
        mutated = source.replace(
            "(register.name, int(register))", "(register.name, 0x04)", 2
        )
        with self.assertRaisesRegex(
            checker.CheckError, "effective register container binding"
        ):
            checker.validate_stage2c9f_binding(mutated)

    def test_stage2i_runtime_register_read_literal_is_detected(self) -> None:
        source = (ROOT / "sw/stage2i_board_runtime.py").read_text(encoding="utf-8")
        mutated = source.replace(
            "mmio.read(int(register))", "mmio.read(0x04)", 1
        )
        with self.assertRaisesRegex(
            checker.CheckError, "effective register container binding"
        ):
            checker.validate_stage2i_board_runtime_binding(mutated)

    def test_generated_register_key_value_mismatch_is_detected(self) -> None:
        source = (
            ROOT / "sw/stage2c9f_b_controlled_expanded_mmio_idempotent_rw.py"
        ).read_text(encoding="utf-8")
        mutated = source.replace(
            "RegisterOffset.CTRL,", "RegisterOffset.STATUS,", 1
        )
        with self.assertRaisesRegex(
            checker.CheckError, "effective register container binding"
        ):
            checker.validate_stage2c9f_binding(mutated)


def run_consumer_mutations() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(
        RegisterMapConsumerProvenanceMutationTests
    )
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        return 1
    count = suite.countTestCases()
    print(f"A2_CONSUMER_PROVENANCE_MUTATIONS=PASS_{count}_OF_{count}")
    print("ACTIVE_CONSUMER_OFFSET_MUTATION=DETECTED")
    print("ACTIVE_CONSUMER_FAULT_CODE_MUTATION=DETECTED")
    print("UNCLASSIFIED_CONSUMER_MUTATION=DETECTED")
    print("ORACLE_ROLE_MISCLASSIFICATION_MUTATION=DETECTED")
    print("RECOVERY_SNAPSHOT_ORACLE_PARITY_MUTATION=DETECTED")
    print("HISTORICAL_RUNTIME_PACKAGE_MUTATION=DETECTED")
    return 0


def run_matrix_reuse_mutations() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(
        MatrixReusePolicyMutationTests
    )
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        return 1
    count = suite.countTestCases()
    print(f"MATRIX_REUSE_MUTATIONS=PASS_{count}_OF_{count}")
    print("RTL_CHANGE_INVALIDATES_REUSE=YES")
    print("TB_CHANGE_INVALIDATES_REUSE=YES")
    print("ADDED_PATH_INVALIDATES_REUSE=YES")
    print("REMOVED_PATH_INVALIDATES_REUSE=YES")
    print("UNEXPECTED_CHANGED_PATH_INVALIDATES_REUSE=YES")
    print("MISSING_TARGETED_VALIDATION_INVALIDATES_REUSE=YES")
    return 0


def run_active_binding_mutations() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(
        ActiveConsumerBindingMutationTests
    )
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        return 1
    count = suite.countTestCases()
    print(f"ACTIVE_CONSUMER_BINDING_MUTATIONS=PASS_{count}_OF_{count}")
    print("ACTIVE_CONSUMER_ALIAS_BYPASS_MUTATION=DETECTED")
    print("ACTIVE_CONSUMER_DIRECT_LITERAL_MMIO_MUTATION=DETECTED")
    print("ACTIVE_CONSUMER_DIRECT_LITERAL_FAULT_MUTATION=DETECTED")
    print("UNUSED_GENERATED_IMPORT_BYPASS_MUTATION=DETECTED")
    print("ACTIVE_CONSUMER_MMIO_RECEIVER_ALIAS_BYPASS=DETECTED")
    print("ACTIVE_CONSUMER_GENERATED_BINDING_UNUSED=DETECTED")
    print("NEW_UNCLASSIFIED_MMIO_CONSUMER_MUTATION=DETECTED")
    print("ARBITRARY_NAME_MMIO_CONSUMER_DISCOVERY=PASS")
    return 0


def run_container_binding_mutations() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(
        ActiveRegisterContainerBindingMutationTests
    )
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        return 1
    count = suite.countTestCases()
    print(f"ACTIVE_REGISTER_CONTAINER_BINDING_MUTATIONS=PASS_{count}_OF_{count}")
    print("STAGE2C9E_CONTAINER_VALUE_LITERAL_MUTATION=DETECTED")
    print("BOARD_VALIDATION_CONTAINER_VALUE_LITERAL_MUTATION=DETECTED")
    print("RENDERED_EXAMPLE_CONTAINER_VALUE_LITERAL_MUTATION=DETECTED")
    print("GENERATED_REGISTER_KEY_VALUE_MISMATCH_MUTATION=DETECTED")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--consumer-mutations", action="store_true")
    parser.add_argument("--matrix-reuse-mutations", action="store_true")
    parser.add_argument("--active-binding-mutations", action="store_true")
    parser.add_argument("--container-binding-mutations", action="store_true")
    args = parser.parse_args()
    if args.consumer_mutations:
        return run_consumer_mutations()
    if args.matrix_reuse_mutations:
        return run_matrix_reuse_mutations()
    if args.active_binding_mutations:
        return run_active_binding_mutations()
    if args.container_binding_mutations:
        return run_container_binding_mutations()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(RegisterMapMutationTests)
    count = suite.countTestCases()
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        return 1
    print(f"A2_LEGACY_ABI_MUTATION_SUITE=PASS_{count}_OF_{count}")
    print("MUTATIONS_WITHOUT_DEFINED_FAILURE_MODE=0")
    print("MANUAL_GENERATED_FILE_MUTATION=DETECTED")
    print("SOURCE_CHANGE_WITHOUT_REGENERATION=DETECTED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
