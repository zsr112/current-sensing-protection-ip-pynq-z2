from __future__ import annotations

import copy
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from tools.stage2f_adc_contract_audit import (
    AUDIT_DOC,
    AUTHORITY_PATH,
    CLOSURE_PATH,
    FACT_PATH,
    REFERENCE_PROFILE_PATH,
    REQUIRED_PATHS,
    SOURCE_PROFILE_PATH,
    SOURCE_SCHEMA_PATH,
    TARGET_DOC,
    audit_contract,
    configured_simulation_profile,
    validate_source_profile_contract,
)
from tools.build_stage2f_audit_review import (
    BuildError,
    FIXTURE_CREDENTIAL_ASSIGNMENT,
    OTHER_CREDENTIAL_ASSIGNMENT,
    _validate_sidecar,
    package_credential_scan,
    sha256_file,
    validate_manifest,
    write_inventory_and_manifest,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


class Stage2fAdcContractAuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="stage2f_adc_audit_")
        self.root = Path(self.temporary.name)
        for relative in REQUIRED_PATHS:
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REPOSITORY_ROOT / relative, destination)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def load(self, relative: Path) -> dict:
        return json.loads((self.root / relative).read_text(encoding="utf-8"))

    def store(self, relative: Path, value: dict) -> None:
        (self.root / relative).write_text(
            json.dumps(value, indent=2) + "\n", encoding="utf-8"
        )

    def errors(self) -> list[str]:
        return audit_contract(
            self.root,
            validate_references=False,
            check_git=False,
        )

    def assert_rejected(self, expected: str) -> None:
        errors = self.errors()
        self.assertTrue(errors, "mutated contract unexpectedly passed")
        self.assertTrue(
            any(expected.lower() in error.lower() for error in errors),
            f"expected {expected!r} in errors: {errors}",
        )

    def test_tracked_contract_passes(self) -> None:
        self.assertEqual([], self.errors())

    def test_rejects_conflicting_raw_widths(self) -> None:
        data = self.load(FACT_PATH)
        mutant = copy.deepcopy(data["facts"][0])
        mutant["id"] = "MUTANT-WIDTH"
        mutant["value"] = 14
        data["facts"].append(mutant)
        self.store(FACT_PATH, data)
        self.assert_rejected("conflicting authoritative raw widths")

    def test_rejects_signedness_authority_conflict(self) -> None:
        data = self.load(FACT_PATH)
        source = next(row for row in data["facts"] if row["id"] == "F-SIGNED-001")
        mutant = copy.deepcopy(source)
        mutant["id"] = "MUTANT-SIGNEDNESS"
        mutant["value"] = "SIGNED"
        data["facts"].append(mutant)
        self.store(FACT_PATH, data)
        self.assert_rejected("signedness authority conflict")

    def test_rejects_unsupported_physical_unit_claim(self) -> None:
        data = self.load(AUTHORITY_PATH)
        physical = next(
            row for row in data["parameters"] if row["parameter"] == "physical_unit_scale"
        )
        physical["authority"] = "SOURCE_PROFILE"
        physical["target_value"] = "MILLIAMPERES"
        self.store(AUTHORITY_PATH, data)
        self.assert_rejected("unsupported physical-unit claim")

    def test_rejects_undocumented_threshold_domain(self) -> None:
        data = self.load(FACT_PATH)
        data["facts"] = [row for row in data["facts"] if row["id"] != "F-THRESHOLD-002"]
        self.store(FACT_PATH, data)
        self.assert_rejected("threshold domain undocumented")

    def test_rejects_unknown_hardware_constant_as_fact(self) -> None:
        data = self.load(FACT_PATH)
        device = next(row for row in data["facts"] if row["id"] == "F-HARDWARE-002")
        device["value"] = "UNSUPPORTED_PART_NUMBER"
        device["classification"] = "REPOSITORY_FACT"
        self.store(FACT_PATH, data)
        self.assert_rejected("unknown hardware constant represented as a fact")

    def test_rejects_duplicate_scaling_parameter_authority(self) -> None:
        data = self.load(AUTHORITY_PATH)
        data["parameters"].append(copy.deepcopy(data["parameters"][0]))
        self.store(AUTHORITY_PATH, data)
        self.assert_rejected("duplicate scaling-parameter authority")

    def test_rejects_incorrect_stage2f_gap_closure(self) -> None:
        data = self.load(FACT_PATH)
        data["audit_state"]["stage2f_contract_gap_closed"] = True
        data["audit_state"]["remaining_contract_gaps"] = 1
        self.store(FACT_PATH, data)
        self.assert_rejected("stage2f_contract_gap_closed")

    def test_rejects_incorrect_implementation_started_claim(self) -> None:
        data = self.load(FACT_PATH)
        data["audit_state"]["stage2f_implementation_started"] = True
        self.store(FACT_PATH, data)
        self.assert_rejected("stage2f_implementation_started")

    def test_rejects_closure_claim_in_document(self) -> None:
        path = self.root / AUDIT_DOC
        text = path.read_text(encoding="utf-8").replace(
            "STAGE2F_CONTRACT_GAP_CLOSED=NO",
            "STAGE2F_CONTRACT_GAP_CLOSED=YES",
        )
        path.write_text(text, encoding="utf-8")
        self.assert_rejected("incorrect Stage 2F closure claim")

    # Required isolated hardening mutations.
    def test_rejects_physical_gap_claimed_closed_with_unsupported_unit(self) -> None:
        data = self.load(CLOSURE_PATH)
        data["physical_scaling_status"] = "CLOSED"
        self.store(CLOSURE_PATH, data)
        self.assert_rejected("physical gap claimed closed while physical unit remains unsupported")

    def test_rejects_digital_foundation_reducing_gap_count(self) -> None:
        data = self.load(CLOSURE_PATH)
        data["remaining_contract_gaps"] = 1
        self.store(CLOSURE_PATH, data)
        self.assert_rejected("digital foundation reduces remaining gap count")

    def test_rejects_telemetry_only_stage2g_normalized_gating(self) -> None:
        data = self.load(AUTHORITY_PATH)
        data["stage2g_contract"]["normalized_telemetry_gates_fault_policy"] = True
        self.store(AUTHORITY_PATH, data)
        self.assert_rejected("telemetry-only path paired with Stage 2G normalized gating")

    def test_rejects_numeric_latency_authority(self) -> None:
        data = self.load(AUTHORITY_PATH)
        data["pipeline_contract"]["pipeline_latency"] = 3
        self.store(AUTHORITY_PATH, data)
        self.assert_rejected("numeric latency conflicts with implementation-derived authority")

    def test_rejects_missing_initiation_interval(self) -> None:
        data = self.load(AUTHORITY_PATH)
        data["pipeline_contract"].pop("pipeline_initiation_interval")
        self.store(AUTHORITY_PATH, data)
        self.assert_rejected("missing initiation interval")

    def test_rejects_unbounded_offset_with_fixed_intermediate_width(self) -> None:
        data = self.load(AUTHORITY_PATH)
        data["arithmetic_scope"]["runtime_offset_supported"] = True
        data["arithmetic_scope"]["fixed_intermediate_width_claim"] = True
        self.store(AUTHORITY_PATH, data)
        self.assert_rejected("unbounded offset paired with fixed intermediate-width claim")

    def test_rejects_read_only_sticky_status_without_clear_semantics(self) -> None:
        data = self.load(AUTHORITY_PATH)
        data["register_contract"]["sticky_status_supported"] = True
        data["register_contract"]["sticky_clear_semantics"] = None
        self.store(AUTHORITY_PATH, data)
        self.assert_rejected("read-only register paired with undefined sticky clear semantics")

    def test_rejects_unconfigured_profile_claimed_functional(self) -> None:
        data = self.load(AUTHORITY_PATH)
        data["current_production_normalized_telemetry"] = "AVAILABLE_FUNCTIONAL"
        self.store(AUTHORITY_PATH, data)
        self.assert_rejected("production UNCONFIGURED profile claimed as normalized functional")

    def test_rejects_reference_profile_promoted_to_production_authority(self) -> None:
        data = self.load(REFERENCE_PROFILE_PATH)
        data["profile_status"] = "PRODUCTION_AUTHORITY"
        self.store(REFERENCE_PROFILE_PATH, data)
        self.assert_rejected("reference profile promoted to production authority")

    def test_rejects_reference_arithmetic_labeled_calibrated(self) -> None:
        data = self.load(REFERENCE_PROFILE_PATH)
        data["illustrative_electrical_example"]["calibrated"] = True
        self.store(REFERENCE_PROFILE_PATH, data)
        self.assert_rejected("reference arithmetic labeled calibrated")

    def test_rejects_pmod_precision_external_reference_claim(self) -> None:
        data = self.load(REFERENCE_PROFILE_PATH)
        data["hardware"]["adc_reference_type"] = "PRECISION_EXTERNAL_REFERENCE"
        self.store(REFERENCE_PROFILE_PATH, data)
        self.assert_rejected("Pmod AD1 claimed as precision external-reference ADC")

    def test_rejects_dma_mandatory_for_protection(self) -> None:
        data = self.load(REFERENCE_PROFILE_PATH)
        data["integration_boundaries"]["dma_mandatory_for_protection_path"] = True
        self.store(REFERENCE_PROFILE_PATH, data)
        self.assert_rejected("DMA made mandatory for protection path")

    def test_rejects_community_repository_as_hardware_authority(self) -> None:
        data = self.load(REFERENCE_PROFILE_PATH)
        project = next(
            row
            for row in data["public_reference_projects"]
            if row["owner_type"] == "COMMUNITY"
        )
        project["hardware_authority"] = True
        self.store(REFERENCE_PROFILE_PATH, data)
        self.assert_rejected("community repository classified as hardware authority")

    def test_rejects_reference_constraining_final_hardware_selection(self) -> None:
        data = self.load(REFERENCE_PROFILE_PATH)
        data["final_hardware_selection_constrained"] = True
        self.store(REFERENCE_PROFILE_PATH, data)
        self.assert_rejected("reference profile constraining final hardware selection")

    def test_rejects_purchase_authorization(self) -> None:
        data = self.load(REFERENCE_PROFILE_PATH)
        data["purchase_authorized"] = True
        self.store(REFERENCE_PROFILE_PATH, data)
        self.assert_rejected("purchase authorization incorrectly implied")

    def test_rejects_new_offset_above_0x60(self) -> None:
        path = self.root / TARGET_DOC
        path.write_text(
            path.read_text(encoding="utf-8") + "\nProposed offset `0x64` is reserved.\n",
            encoding="utf-8",
        )
        self.assert_rejected("new register offset above 0x60")

    def test_rejects_invalid_source_profile_encoding(self) -> None:
        path = self.root / Path("spec/stage2f_adc_source_profile_unconfigured.json")
        data = self.load(Path("spec/stage2f_adc_source_profile_unconfigured.json"))
        data["encoding"] = "STRAIGHT_BINARY"
        self.store(Path("spec/stage2f_adc_source_profile_unconfigured.json"), data)
        self.assert_rejected("source profile schema validation")

    def test_rejects_digital_capability_requiring_production_selection(self) -> None:
        data = self.load(CLOSURE_PATH)
        data["stage2_digital_foundation_requires_production_adc_selection"] = True
        data["STAGE2_DIGITAL_FOUNDATION_REQUIRES_PRODUCTION_ADC_SELECTION"] = "YES"
        self.store(CLOSURE_PATH, data)
        self.assert_rejected("digital capability incorrectly requires production ADC selection")

    def test_rejects_stage2_freeze_forbidden_by_unconfigured_production(self) -> None:
        data = self.load(CLOSURE_PATH)
        data["stage2_digital_foundation_can_freeze_with_unconfigured_production_profile"] = False
        data["STAGE2_DIGITAL_FOUNDATION_CAN_FREEZE_WITH_UNCONFIGURED_PRODUCTION_PROFILE"] = "NO"
        self.store(CLOSURE_PATH, data)
        self.assert_rejected(
            "Stage 2 digital freeze forbidden solely because production is unconfigured"
        )

    def test_valid_configured_simulation_profile_passes_schema(self) -> None:
        schema = self.load(SOURCE_SCHEMA_PATH)
        self.assertEqual(
            [],
            validate_source_profile_contract(schema, configured_simulation_profile()),
        )

    def test_rejects_configured_profile_with_reserved_identity(self) -> None:
        data = configured_simulation_profile()
        data["profile_identity"] = "UNCONFIGURED"
        self.store(SOURCE_PROFILE_PATH, data)
        self.assert_rejected("source profile schema validation")

    def test_rejects_production_selected_reserved_identity(self) -> None:
        data = configured_simulation_profile()
        data["profile_identity"] = "UNCONFIGURED"
        data["production_selection"] = True
        self.store(SOURCE_PROFILE_PATH, data)
        self.assert_rejected("source profile schema validation")

    def test_rejects_bidirectional_reference_raw_path_compatibility_claim(self) -> None:
        data = self.load(REFERENCE_PROFILE_PATH)
        compatibility = data["protection_compatibility"]
        compatibility[
            "reference_bidirectional_negative_overcurrent_supported_by_current_raw_path"
        ] = True
        compatibility["reference_profile_is_end_to_end_protection_compatible"] = True
        self.store(REFERENCE_PROFILE_PATH, data)
        self.assert_rejected("reference bidirectional negative overcurrent incorrectly marked supported")

    def test_rejects_linux_device_tree_as_complete_fpga_implementation(self) -> None:
        data = self.load(REFERENCE_PROFILE_PATH)
        project = next(
            row
            for row in data["public_reference_projects"]
            if row["id"] == "ADI_AD7476A_PMOD_LINUX_DEVICE_TREE"
        )
        project["complete_fpga_implementation"] = True
        self.store(REFERENCE_PROFILE_PATH, data)
        self.assert_rejected("Linux device-tree-only pin incorrectly labeled complete FPGA implementation")

    def test_package_credential_allowlist_is_exact(self) -> None:
        with tempfile.TemporaryDirectory(prefix="stage2f_credential_fixture_") as temporary:
            root = Path(temporary)
            fixture = root / "source/tree/tests/test_stage1_board_functional_validation.py"
            fixture.parent.mkdir(parents=True)
            fixture.write_text(FIXTURE_CREDENTIAL_ASSIGNMENT + "\n", encoding="utf-8")
            self.assertEqual(1, package_credential_scan(root))
            fixture.write_text(OTHER_CREDENTIAL_ASSIGNMENT + "\n", encoding="utf-8")
            with self.assertRaises(BuildError):
                package_credential_scan(root)

    def test_outer_manifest_includes_nested_evidence_manifest(self) -> None:
        with tempfile.TemporaryDirectory(prefix="stage2f_nested_manifest_") as temporary:
            root = Path(temporary)
            nested = root / "evidence/final/MANIFEST_SHA256.txt"
            nested.parent.mkdir(parents=True)
            nested.write_text("nested manifest fixture\n", encoding="utf-8")
            (root / "payload.txt").write_text("payload\n", encoding="utf-8")
            write_inventory_and_manifest(root)
            validate_manifest(root)

    def test_sidecar_reports_separate_manifest_counts(self) -> None:
        with tempfile.TemporaryDirectory(prefix="stage2f_sidecar_") as temporary:
            root = Path(temporary)
            archive = root / "review.zip"
            archive.write_bytes(b"review package fixture")
            evidence = root / "evidence"
            sidecar = root / "review.zip.sha256.txt"
            head = "a" * 40
            sidecar.write_text(
                "\n".join(
                    [
                        f"FILE={archive.resolve()}",
                        f"SIZE_BYTES={archive.stat().st_size}",
                        f"SHA256={sha256_file(archive)}",
                        "ZIP_FULL_READ_VALIDATION=PASS",
                        "ZIP_CRC_VALIDATION=PASS",
                        "OUTER_ZIP_MANIFEST_VALIDATION=PASS_3_OF_3",
                        "EVIDENCE_MANIFEST_VALIDATION=PASS_2_OF_2",
                        "AGGREGATE_MANIFEST_VALIDATION=PASS_5_OF_5",
                        f"AUDIT_COMMIT={head}",
                        f"EVIDENCE_ROOT={evidence.resolve()}",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            _validate_sidecar(
                sidecar,
                archive,
                head=head,
                evidence=evidence,
                outer_manifest_count=3,
                evidence_manifest_count=2,
            )


if __name__ == "__main__":
    unittest.main()
