from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path

from tools.stage2g_reset_wait_first_fault_policy_audit import (
    BEHAVIOR_PATH,
    CONTRACT_PATH,
    FIXTURE_DIR,
    SCHEMA_PATH,
    SOURCE_MAP_PATH,
    AuditError,
    cross_artifact_errors,
    load_json,
    validate_behavior_matrix,
    validate_contract,
    validate_cross_fixtures,
    validate_evidence_citation,
    validate_fixtures,
    validate_source_map,
)


ROOT = Path(__file__).resolve().parents[2]


class Stage2gPolicyAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contract = load_json(ROOT / CONTRACT_PATH)
        cls.schema = load_json(ROOT / SCHEMA_PATH)

    def test_frozen_contract_and_schema_pass(self) -> None:
        self.assertEqual([], validate_contract(self.contract, self.schema))

    def test_source_map_and_current_behavior_matrix_pass(self) -> None:
        self.assertEqual([], validate_source_map(ROOT, load_json(ROOT / SOURCE_MAP_PATH)))
        self.assertEqual([], validate_behavior_matrix(ROOT, load_json(ROOT / BEHAVIOR_PATH)))

    def test_source_map_rejects_missing_test_evidence(self) -> None:
        source_map = copy.deepcopy(load_json(ROOT / SOURCE_MAP_PATH))
        source_map["baseline_entries"][0]["current_tests"].append(
            "tb/missing_stage2g_evidence.sv"
        )
        errors = validate_source_map(ROOT, source_map)
        self.assertTrue(any("missing test" in error for error in errors))

    def test_generated_fault_citation_preserves_frozen_authority(self) -> None:
        generated = "\n".join(
            (
                "`define FAULT_NONE 8'h00",
                "`define FAULT_OVERCURRENT 8'h01",
                "`define FAULT_SENSOR_MISMATCH 8'h02",
                "`define FAULT_SENSOR_OPEN 8'h03",
                "`define FAULT_SENSOR_SATURATION 8'h04",
                "`define FAULT_SENSOR_STUCK 8'h05",
                "`define FAULT_OC_WITH_ANY_SENSOR 8'h06",
                "`define FAULT_OC_WITH_SENSOR `FAULT_OC_WITH_ANY_SENSOR",
            )
        )
        shim = (
            "`ifndef FAULT_DEFS_VH\n"
            "`define FAULT_DEFS_VH\n\n"
            "// Value-free compatibility shim.\n"
            "`include \"generated/protection_register_map.vh\"\n\n"
            "`endif\n"
        )
        citation = "rtl/fault_defs.vh:5-11"
        with tempfile.TemporaryDirectory(prefix="stage2g_fault_citation_") as directory:
            root = Path(directory)
            (root / "rtl/generated").mkdir(parents=True)
            fault_defs = root / "rtl/fault_defs.vh"
            generated_defs = root / "rtl/generated/protection_register_map.vh"
            fault_defs.write_text(shim, encoding="utf-8")
            generated_defs.write_text(generated, encoding="utf-8")
            self.assertIsNone(validate_evidence_citation(root, citation))

            fault_defs.write_text(
                shim.replace(
                    '`include "generated/protection_register_map.vh"',
                    "`define FAULT_NONE 8'h00",
                ),
                encoding="utf-8",
            )
            self.assertIn(
                "does not resolve through the generated authority",
                validate_evidence_citation(root, citation) or "",
            )

            independent_authority = shim.replace(
                "`endif",
                "// Compatibility padding one.\n"
                "// Compatibility padding two.\n"
                "// Compatibility padding three.\n"
                "`define FAULT_NONE 8'h00\n"
                "`endif",
            )
            self.assertGreaterEqual(len(independent_authority.splitlines()), 11)
            fault_defs.write_text(independent_authority, encoding="utf-8")
            self.assertIn(
                "shim with numeric ownership",
                validate_evidence_citation(root, citation) or "",
            )

            fault_defs.write_text(shim, encoding="utf-8")
            generated_defs.write_text(
                generated.replace("FAULT_SENSOR_STUCK 8'h05", "FAULT_SENSOR_STUCK 8'h07"),
                encoding="utf-8",
            )
            self.assertIn(
                "changed frozen definition FAULT_SENSOR_STUCK",
                validate_evidence_citation(root, citation) or "",
            )

    def test_positive_and_negative_fixture_manifest_passes(self) -> None:
        positive, negative, errors = validate_fixtures(ROOT, self.contract, self.schema)
        self.assertEqual(1, positive)
        self.assertEqual(29, negative)
        self.assertEqual([], errors)

    def test_cross_artifact_fixture_manifest_passes(self) -> None:
        fixture = load_json(ROOT / FIXTURE_DIR / "cross_artifact_negative_mutations.json")
        documents = {
            "audit": (ROOT / "docs/architecture/stage2g_reset_wait_first_fault_policy_audit.md").read_text(encoding="utf-8"),
            "source": (ROOT / "docs/architecture/stage2g_reset_wait_first_fault_policy_source_map.md").read_text(encoding="utf-8"),
            "tradeoff": (ROOT / "docs/architecture/stage2g_reset_wait_first_fault_policy_tradeoff.md").read_text(encoding="utf-8"),
            "verification": (ROOT / "docs/verification/stage2g_reset_wait_first_fault_verification_plan.md").read_text(encoding="utf-8"),
        }
        self.assertEqual([], cross_artifact_errors(ROOT, self.contract, documents))
        passed, errors = validate_cross_fixtures(ROOT, self.contract)
        self.assertEqual(27, fixture["expected_count"])
        self.assertEqual(27, passed)
        self.assertEqual([], errors)

    def test_authority_mutations_fail_closed(self) -> None:
        mutations = {
            "normalized gate": ("authorities", "normalized_telemetry_gates_fault_policy", True),
            "persistent retrigger": ("fault_model", "persistent_fault_retrigger", True),
            "live clear": ("clear_recovery", "clear_while_any_live_fault", "ACCEPT"),
            "new offset": ("authorities", "new_axi_offsets_added", True),
            "gap reduction": ("scope", "remaining_contract_gaps", 1),
            "clear equals public recovery": (
                "public_recovery_contract_addendum",
                "clear_acceptance_equals_public_recovery_complete",
                True,
            ),
            "public code clears on clear": (
                "public_recovery_contract_addendum",
                "clear_acceptance_public_behavior",
                "CLEAR_PUBLIC_CODE",
            ),
        }
        for label, (section, field, value) in mutations.items():
            with self.subTest(label=label):
                candidate = copy.deepcopy(self.contract)
                candidate[section][field] = value
                self.assertTrue(validate_contract(candidate, self.schema), label)

    def test_episode_and_priority_mutations_fail_closed(self) -> None:
        candidate = copy.deepcopy(self.contract)
        candidate["fault_model"]["simultaneous_priority"] = []
        self.assertTrue(validate_contract(candidate, self.schema))
        candidate = copy.deepcopy(self.contract)
        candidate["clear_recovery"]["successful_clear_starts_new_episode"] = False
        self.assertTrue(validate_contract(candidate, self.schema))
        candidate = copy.deepcopy(self.contract)
        candidate["reset_policy"]["stale_sample_rule"] = "ALLOW_PRE_RESET_SAMPLE"
        self.assertTrue(validate_contract(candidate, self.schema))

    def test_error_and_decision_dispositions_fail_closed(self) -> None:
        candidate = copy.deepcopy(self.contract)
        candidate["error_classification"][-1]["protection_trip"] = True
        self.assertTrue(validate_contract(candidate, self.schema))
        candidate = copy.deepcopy(self.contract)
        candidate["error_classification"][4]["temporal_classification"] = "TRANSACTION_CORRELATED_BLOCKER"
        self.assertTrue(validate_contract(candidate, self.schema))
        candidate = copy.deepcopy(self.contract)
        candidate["required_decisions"]["RESET_WAIT_EXIT"]["status"] = "OWNER_DECISION_REQUIRED"
        self.assertTrue(validate_contract(candidate, self.schema))

    def test_duplicate_json_keys_fail_closed(self) -> None:
        text = (ROOT / CONTRACT_PATH).read_text(encoding="utf-8")
        duplicate = text.replace(
            '"schema_version": "stage2g-reset-wait-first-fault-policy-v2",',
            '"schema_version": "stage2g-reset-wait-first-fault-policy-v2",\n  "schema_version": "stage2g-reset-wait-first-fault-policy-v2",',
            1,
        )
        with tempfile.TemporaryDirectory(prefix="stage2g_duplicate_json_") as directory:
            path = Path(directory) / "duplicate.json"
            path.write_text(duplicate, encoding="utf-8")
            with self.assertRaises(AuditError):
                load_json(path)

    def test_schema_is_closed_and_public_visibility_is_deferred(self) -> None:
        self.assertFalse(self.schema.get("additionalProperties") is not False)
        self.assertFalse(self.contract["authorities"]["new_axi_offsets_added"])
        self.assertEqual("DEFERRED_TO_STAGE2H", self.contract["bitmaps"]["public_visibility"])

    def test_fault_evaluation_boundary_mutations_fail_closed(self) -> None:
        mutations = {
            "compatibility valid reused": ("current_fault_valid_is_evaluation_valid", True),
            "zero is not explicit health": ("healthy_evaluation_definition", "!fault_valid"),
            "fields tear": ("fields_aligned", False),
        }
        for label, (field, value) in mutations.items():
            with self.subTest(label=label):
                candidate = copy.deepcopy(self.contract)
                candidate["fault_evaluation_transaction"][field] = value
                self.assertTrue(validate_contract(candidate, self.schema))
        candidate = copy.deepcopy(self.contract)
        candidate["fault_evaluation_transaction"]["pipeline"]["policy_decision_edge_offset"] = 2
        self.assertTrue(validate_contract(candidate, self.schema))

    def test_clear_fence_mutations_fail_closed(self) -> None:
        mutations = {
            "global empty": ("protocol", "GLOBAL_PIPELINE_EMPTY"),
            "same edge resolves": ("same_edge_evaluation_order", "SAME_EDGE_RESOLVES"),
            "continuous stream starves": ("continuous_ii1_progress", "WAIT_FOR_PIPELINE_EMPTY"),
            "resolution releases": ("resolution_transaction_reset_wait_role", "ALSO_ARMS"),
        }
        for label, (field, value) in mutations.items():
            with self.subTest(label=label):
                candidate = copy.deepcopy(self.contract)
                candidate["clear_recovery"][field] = value
                self.assertTrue(validate_contract(candidate, self.schema))

    def test_temporal_integrity_and_reset_mutations_fail_closed(self) -> None:
        candidate = copy.deepcopy(self.contract)
        candidate["transaction_integrity"]["source_component"] = "DELAYED_SYNCHRONIZED_SOURCE_COUNTER"
        self.assertTrue(validate_contract(candidate, self.schema))
        candidate = copy.deepcopy(self.contract)
        candidate["transaction_integrity"]["software_clear_dependency"] = True
        self.assertTrue(validate_contract(candidate, self.schema))
        candidate = copy.deepcopy(self.contract)
        candidate["transaction_integrity"]["alignment_identity"] = "NONE"
        self.assertTrue(validate_contract(candidate, self.schema))
        candidate = copy.deepcopy(self.contract)
        candidate["reset_policy"]["stale_sample_rule"] = "ALLOW_PRE_RESET_RETIREMENT"
        self.assertTrue(validate_contract(candidate, self.schema))


if __name__ == "__main__":
    unittest.main()
