from __future__ import annotations

import contextlib
import copy
import csv
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from sw import stage2i_board_runtime as board_runtime
from tests import stage2i_release_test_support as support
from tools import stage2i_physical_authority as physical_authority
from tools.board_validation import build_stage1_board_execution_package as builder
from tools.board_validation import stage1_board_evidence_analyzer as analyzer
from tools.board_validation import stage1_board_functional_validation as board


REPO_ROOT = Path(__file__).resolve().parents[1]


def clean_state(
    *,
    source_accept_count: int = 0,
    destination_delivery_count: int = 0,
    backpressure_cycle_count: int = 0,
    last_sequence: int = 0,
) -> dict[str, object]:
    observability_status = (
        int(board.ObservabilityStatus.BACKPRESSURE_SEEN)
        if backpressure_cycle_count
        else 0
    )
    observability = {
        "status": observability_status,
        "source_accept_count": source_accept_count,
        "destination_delivery_count": destination_delivery_count,
        "backpressure_cycle_count": backpressure_cycle_count,
        "last_source_sequence": last_sequence,
        "last_destination_sequence": last_sequence,
    }
    observability.update({field: 0 for field in board.ERROR_COUNTER_FIELDS})
    return {
        "register_map_version": {"explicit": True, "major": 1, "minor": 1},
        "status": {"ctrl": 0, "status": 0, "fault_code": 0},
        "observability": observability,
        "policy_status": {
            "armed_ready": True,
            "fault_latched_state": False,
            "reset_wait_state": False,
            "clear_pending": False,
            "post_clear_recovery_pending": False,
        },
        "first_fault_bitmap": {"raw_value": 0},
        "live_fault_bitmap": {"raw_value": 0},
        "fault_seen_bitmap": {"raw_value": 0},
        "policy_evaluation_sequence": last_sequence,
    }


class ScriptedB2Backend:
    def __init__(self) -> None:
        self.state = clean_state()
        self.clear_requested = False
        self.history: list[tuple[int, int, int]] = []
        self.clear_count = 0
        self.open_samples = 0
        self.saturation_samples = 0
        self.stuck_samples = 0

    def read_state(self) -> dict[str, object]:
        return copy.deepcopy(self.state)

    def _fault_for(self, ch1: int, ch2: int, burst: int) -> tuple[int, int]:
        if (ch1, ch2) == (3001, 2802):
            return (
                int(board.FaultCause.CH1_OVERCURRENT),
                int(board.FaultCode.OVERCURRENT),
            )
        if (ch1, ch2) == (2802, 3001):
            return (
                int(board.FaultCause.CH2_OVERCURRENT),
                int(board.FaultCode.OVERCURRENT),
            )
        if (ch1, ch2) == (3200, 2500):
            return (
                int(
                    board.FaultCause.CH1_OVERCURRENT
                    | board.FaultCause.SENSOR_MISMATCH_OR_DIFFERENTIAL
                ),
                int(board.FaultCode.OC_WITH_ANY_SENSOR),
            )
        if (ch1, ch2) == (1000, 1300):
            return (
                int(board.FaultCause.SENSOR_MISMATCH_OR_DIFFERENTIAL),
                int(board.FaultCode.SENSOR_MISMATCH),
            )
        if ch1 == 0:
            self.open_samples += burst
            if self.open_samples >= 256:
                return (
                    int(board.FaultCause.SENSOR_OPEN),
                    int(board.FaultCode.SENSOR_OPEN),
                )
        if ch1 == 4095:
            self.saturation_samples += burst
            if self.saturation_samples >= 256:
                return (
                    int(
                        board.FaultCause.CH1_OVERCURRENT
                        | board.FaultCause.CH2_OVERCURRENT
                        | board.FaultCause.SENSOR_SATURATION
                    ),
                    int(board.FaultCode.OC_WITH_ANY_SENSOR),
                )
            return (
                int(board.FaultCause.CH1_OVERCURRENT | board.FaultCause.CH2_OVERCURRENT),
                int(board.FaultCode.OVERCURRENT),
            )
        if (ch1, ch2) == (1024, 1024):
            self.stuck_samples += burst
            if self.stuck_samples >= 257:
                return (
                    int(board.FaultCause.SENSOR_STUCK),
                    int(board.FaultCode.SENSOR_STUCK),
                )
        return 0, 0

    def _reset_detectors(self) -> None:
        self.open_samples = 0
        self.saturation_samples = 0
        self.stuck_samples = 0

    def issue(self, ch1: int, ch2: int, burst: int) -> dict[str, object]:
        before = self.read_state()
        self.history.append((ch1, ch2, burst))
        observability = self.state["observability"]
        assert isinstance(observability, dict)
        observability["source_accept_count"] = (
            int(observability["source_accept_count"]) + burst
        ) & board.COUNTER_MASK
        observability["destination_delivery_count"] = (
            int(observability["destination_delivery_count"]) + burst
        ) & board.COUNTER_MASK
        sequence = (int(observability["last_source_sequence"]) + burst) & board.COUNTER_MASK
        observability["last_source_sequence"] = sequence
        observability["last_destination_sequence"] = sequence
        self.state["policy_evaluation_sequence"] = sequence
        if burst == board_runtime.B2_MAX_BURST:
            observability["backpressure_cycle_count"] = (
                int(observability["backpressure_cycle_count"]) + 1
            ) & board.COUNTER_MASK
            observability["status"] = int(observability["status"]) | int(
                board.ObservabilityStatus.BACKPRESSURE_SEEN
            )

        bitmap, code = self._fault_for(ch1, ch2, burst)
        policy = self.state["policy_status"]
        status = self.state["status"]
        first = self.state["first_fault_bitmap"]
        live = self.state["live_fault_bitmap"]
        seen = self.state["fault_seen_bitmap"]
        assert all(isinstance(item, dict) for item in (policy, status, first, live, seen))
        if bitmap:
            if not bool(policy["fault_latched_state"]):
                first["raw_value"] = bitmap
                status["fault_code"] = code
            live["raw_value"] = bitmap
            seen["raw_value"] = int(seen["raw_value"]) | bitmap
            policy.update({"armed_ready": False, "fault_latched_state": True})
            status["status"] = 3
            self.clear_requested = False
        else:
            live["raw_value"] = 0
            if self.clear_requested:
                first["raw_value"] = 0
                seen["raw_value"] = 0
                policy.update({"armed_ready": True, "fault_latched_state": False})
                status.update({"status": 0, "fault_code": 0})
                self.clear_requested = False
                self._reset_detectors()

        after = self.read_state()
        return {
            "ch1": ch1,
            "ch2": ch2,
            "burst_count": burst,
            "state_before": before,
            "state_after": after,
        }

    def clear_fault(self) -> None:
        self.clear_count += 1
        self.clear_requested = True

    def cleanup(self) -> dict[str, object]:
        return {"status": "PASS", "state": self.read_state()}


def board_result_fixture() -> dict[str, object]:
    coverage = {name: {"status": "PASS"} for name in board.FROZEN_SCENARIOS}
    coverage["SOURCE_PROTOCOL"].update(
        {
            "accepted_delta": 127,
            "delivered_delta": 127,
            "backpressure_cycle_delta": 3,
        }
    )
    coverage["DISTINCT_CLOCK_CDC"].update(
        {
            "source_clock_mhz": 125,
            "destination_clock_mhz": 100,
            "source_accept_count": 2048,
            "destination_delivery_count": 2048,
            "last_source_sequence": 2047,
            "last_destination_sequence": 2047,
        }
    )
    return {
        "schema_version": board.SCHEMA_VERSION,
        "status": "PASS",
        "implementation_profile": board_runtime.READY_AWARE,
        "board_hardware_execution": "C2_FULL_DIGITAL_PATH_PASS",
        "cleanup": {"status": "PASS"},
        "scenario_coverage": coverage,
        "source_commit": support.SOURCE_COMMIT,
        "source_tree": support.SOURCE_TREE,
        "execution_id": support.EXECUTION_ID,
    }


def capture_row(
    probes: dict[int, tuple[int, str]], **values: int
) -> dict[str, int]:
    row = {signal: 0 for _index, (_width, signal) in probes.items()}
    row.update(values)
    return row


def write_capture(
    root: Path,
    name: str,
    probes: dict[int, tuple[int, str]],
    rows: list[dict[str, int]],
    *,
    role: str,
    mode: str,
) -> Path:
    path = root / f"{name}.csv"
    indices = list(probes)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(["Sample in Buffer", *[f"probe{index}" for index in indices]])
        writer.writerow(["Radix - UNSIGNED", *(["BINARY"] * len(indices))])
        for sample, row in enumerate(rows):
            values = []
            for index in indices:
                width, signal = probes[index]
                values.append(format(int(row[signal]), f"0{width}b"))
            writer.writerow([sample, *values])

    metadata = {
        "implementation_profile": board_runtime.READY_AWARE,
        "core_role": role,
        "capture_mode": mode,
        "ila_logical_probe_count": str(len(probes)),
        "probe_csv_radix": "BINARY",
        "fpga_programming_calls": "0",
        "device_reset_calls": "0",
        "automatic_retries": "0",
        "bit_path": "/stage2i/protection_system.bit",
        "ltx_path": "/stage2i/protection_system.ltx",
        "ila_cell_name": f"stage2i/{role}/ila_lib",
    }
    with path.with_suffix(".metadata.tsv").open(
        "w", encoding="utf-8", newline=""
    ) as stream:
        writer = csv.writer(stream, dialect="excel-tab", lineterminator="\n")
        writer.writerow(["field", "value"])
        writer.writerows(metadata.items())
    return path


class Stage2IBoardValidationOfflineTests(unittest.TestCase):
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

    def test_b1_and_b2_are_offline_by_default(self) -> None:
        b1 = board.run(
            self.build_tree(board_runtime.SAFE_INERT), board_runtime.SAFE_INERT
        )
        b2 = board.run(
            self.build_tree(board_runtime.READY_AWARE), board_runtime.READY_AWARE
        )
        self.assertEqual("PASS_OFFLINE", b1["status"])
        self.assertEqual("PASS_OFFLINE", b2["status"])
        self.assertFalse(b1["execute_requested"])
        self.assertFalse(b2["execute_requested"])
        self.assertEqual("NOT_RUN", b1["board_hardware_execution"])
        self.assertEqual("NOT_RUN", b2["board_hardware_execution"])
        self.assertEqual(board.c2_execution_plan(), b2["execution_plan"])

    def test_c2_execution_plan_is_frozen_and_complete(self) -> None:
        plan = board.c2_execution_plan()
        self.assertEqual("stage2i-c2-execution-plan-v1", plan["schema_version"])
        self.assertEqual(list(board.FROZEN_SCENARIOS), plan["scenarios"])
        self.assertEqual(
            {
                "ch1": 1500,
                "ch2": 1501,
                "burst_count": 127,
                "backpressure_required": True,
            },
            plan["source_protocol"],
        )
        self.assertEqual(
            {"destination_clock_mhz": 100, "source_clock_mhz": 125},
            plan["clock_contract"],
        )
        self.assertEqual(
            [case["id"] for case in board.INDIVIDUAL_FAULT_CASES],
            [case["id"] for case in plan["individual_fault_cases"]],
        )


class Stage2IB2SequenceTests(unittest.TestCase):
    def test_scripted_backend_covers_the_complete_c2_sequence(self) -> None:
        backend = ScriptedB2Backend()
        result = board.run_c2_sequence(backend)
        coverage = result["scenario_coverage"]
        self.assertEqual(tuple(coverage), board.FROZEN_SCENARIOS)
        self.assertTrue(all(item["status"] == "PASS" for item in coverage.values()))
        self.assertEqual(127, coverage["SOURCE_PROTOCOL"]["accepted_delta"])
        self.assertEqual(127, coverage["SOURCE_PROTOCOL"]["delivered_delta"])
        self.assertGreater(
            coverage["SOURCE_PROTOCOL"]["backpressure_cycle_delta"], 0
        )
        self.assertEqual(
            coverage["DISTINCT_CLOCK_CDC"]["source_accept_count"],
            coverage["DISTINCT_CLOCK_CDC"]["destination_delivery_count"],
        )
        self.assertEqual((1500, 1501, 127), backend.history[0])
        self.assertGreaterEqual(backend.clear_count, 8)
        self.assertEqual("PASS", backend.cleanup()["status"])

    def test_saturation_retains_first_overcurrent_identity(self) -> None:
        plan = board.c2_execution_plan()
        expected = next(case for case in plan["individual_fault_cases"] if case["id"] == "SENSOR_SATURATION")
        self.assertEqual(3, expected["expected_first_bitmap"])
        self.assertEqual(19, expected["expected_bitmap"])
        backend = ScriptedB2Backend()
        result = board.run_c2_sequence(backend)
        cases = result["scenario_coverage"]["INDIVIDUAL_FAULT_CAUSES"]["cases"]
        state = next(case["fault_state"] for case in cases if case["id"] == "SENSOR_SATURATION")
        self.assertEqual(3, state["first_fault_bitmap"]["raw_value"])
        self.assertEqual(19, state["live_fault_bitmap"]["raw_value"])
        self.assertEqual(1, state["status"]["fault_code"])
        state["first_fault_bitmap"]["raw_value"] = 19
        with self.assertRaises(board.ValidationError):
            board.require_fault_state(state, 19, 1, "saturation", expected_first_bitmap=3)

    def test_execute_b2_always_runs_cleanup_and_propagates_cleanup_failure(self) -> None:
        backend = mock.Mock()
        backend.cleanup.side_effect = board.ValidationError("cleanup failed")
        with (
            mock.patch.object(
                board,
                "open_overlay_mmio",
                return_value=(object(), object(), object(), "fixture"),
            ),
            mock.patch.object(board, "RealB2Backend", return_value=backend),
            mock.patch.object(
                board,
                "run_c2_sequence",
                return_value={
                    "scenario_coverage": {},
                    "final_state": clean_state(),
                },
            ),
        ):
            with self.assertRaisesRegex(board.ValidationError, "cleanup failed"):
                board.execute_b2(Path("."), {"implementation_profile": board_runtime.READY_AWARE})
        backend.cleanup.assert_called_once_with()


class Stage2IEvidenceAnalyzerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.board_path = self.root / "board-result.json"
        self.board_path.write_text(
            json.dumps(board_result_fixture(), indent=2) + "\n", encoding="utf-8"
        )
        self.capture_paths = self.write_valid_captures()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_valid_captures(self) -> dict[str, Path]:
        source_stall = write_capture(
            self.root,
            "source-stall",
            board_runtime.SOURCE_PROBES,
            [
                capture_row(
                    board_runtime.SOURCE_PROBES,
                    adc_sample_ready=1,
                ),
                capture_row(
                    board_runtime.SOURCE_PROBES,
                    adc_sample_valid=1,
                    adc_sample_ready=0,
                    adc_sample_ch1=1500,
                    adc_sample_ch2=1501,
                    producer_active=1,
                    producer_remaining=12,
                ),
                capture_row(
                    board_runtime.SOURCE_PROBES,
                    adc_sample_valid=1,
                    adc_sample_ready=0,
                    adc_sample_ch1=1500,
                    adc_sample_ch2=1501,
                    producer_active=1,
                    producer_remaining=12,
                ),
            ],
            role="source",
            mode="source_stall",
        )
        source_accept = write_capture(
            self.root,
            "source-accept",
            board_runtime.SOURCE_PROBES,
            [
                capture_row(
                    board_runtime.SOURCE_PROBES,
                    adc_sample_valid=1,
                    adc_sample_ready=1,
                    adc_sample_ch1=1500,
                    adc_sample_ch2=1501,
                    producer_active=1,
                    producer_remaining=11,
                    producer_accept=1,
                )
            ],
            role="source",
            mode="source_accept",
        )
        destination_fault = write_capture(
            self.root,
            "destination-fault",
            board_runtime.READY_AWARE_DESTINATION_PROBES,
            [
                capture_row(
                    board_runtime.READY_AWARE_DESTINATION_PROBES,
                    aresetn=1,
                    pwm_raw=1,
                    pwm_out=0,
                    fault_valid=1,
                    fault_latched=1,
                    fault_code=2,
                    fault_code_latched=2,
                    fsm_state=1,
                )
            ],
            role="destination",
            mode="destination_fault_latched",
        )
        return {
            "source_stall": source_stall,
            "source_accept": source_accept,
            "destination_fault": destination_fault,
        }

    def test_source_and_destination_evidence_reconcile(self) -> None:
        result = analyzer.analyze(self.board_path, self.capture_paths)
        self.assertEqual("PASS", result["status"])
        self.assertEqual(2, result["proofs"]["source_stall"]["stall_sample_count"])
        self.assertEqual(
            [1500, 1501], result["proofs"]["source_stall"]["stable_payload"]
        )
        self.assertEqual(
            1, result["proofs"]["source_accept"]["accepted_sample_count"]
        )
        self.assertEqual([2], result["proofs"]["destination_fault"]["fault_codes"])

    def test_stall_payload_mutation_is_rejected(self) -> None:
        path = self.capture_paths["source_stall"]
        with path.open("r", encoding="utf-8", newline="") as stream:
            rows = list(csv.reader(stream))
        ch1_column = rows[0].index("probe2")
        rows[3][ch1_column] = format(1502, "012b")
        with path.open("w", encoding="utf-8", newline="") as stream:
            csv.writer(stream, lineterminator="\n").writerows(rows)
        with self.assertRaisesRegex(analyzer.EvidenceError, "payload changed"):
            analyzer.analyze(self.board_path, self.capture_paths)

    def test_canonical_board_json_round_trip_is_accepted(self) -> None:
        self.board_path.write_text(
            board.canonical_json(board_result_fixture()), encoding="utf-8"
        )
        self.assertEqual("PASS", analyzer.analyze(self.board_path, self.capture_paths)["status"])

    def test_malformed_board_result_is_rejected(self) -> None:
        payload = board_result_fixture()
        payload["scenario_coverage"]["SOURCE_PROTOCOL"]["accepted_delta"] = 126
        self.board_path.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaisesRegex(analyzer.EvidenceError, "do not prove C2"):
            analyzer.analyze(self.board_path, self.capture_paths)

    def test_missing_capture_returns_a_fail_closed_cli_result(self) -> None:
        missing = self.capture_paths["source_accept"]
        missing.unlink()
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            exit_code = analyzer.main(
                [
                    "--board-result",
                    str(self.board_path),
                    "--source-stall",
                    str(self.capture_paths["source_stall"]),
                    "--source-accept",
                    str(missing),
                    "--destination-fault",
                    str(self.capture_paths["destination_fault"]),
                ]
            )
        result = json.loads(output.getvalue())
        self.assertEqual(1, exit_code)
        self.assertEqual("FAIL", result["status"])
        self.assertEqual(analyzer.FINAL_FAIL_CLASS, result["result_class"])


if __name__ == "__main__":
    unittest.main()
