#!/usr/bin/env python3
"""Stage2I C1/C2 board functional validation, offline by default."""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Protocol


SOURCE_ROOT = Path(__file__).resolve().parents[2]
if (SOURCE_ROOT / "sw").is_dir() and str(SOURCE_ROOT) not in sys.path:
    sys.path.insert(0, str(SOURCE_ROOT))

try:
    from sw.generated.protection_register_map import (
        CTRL_CLEAR_FAULT,
        FaultCause,
        FaultCode,
        ObservabilityStatus,
        RegisterOffset,
    )
    from sw.stage2i_board_runtime import (
        READY_AWARE,
        SAFE_INERT,
        Stage2IBoardError,
        issue_b2_command,
        load_profile,
        open_overlay_mmio,
        read_b2_status,
        read_current_state,
        validate_package,
        wait_b2_idle,
    )
except ModuleNotFoundError:
    from generated.protection_register_map import (  # type: ignore
        CTRL_CLEAR_FAULT,
        FaultCause,
        FaultCode,
        ObservabilityStatus,
        RegisterOffset,
    )
    from stage2i_board_runtime import (  # type: ignore
        READY_AWARE,
        SAFE_INERT,
        Stage2IBoardError,
        issue_b2_command,
        load_profile,
        open_overlay_mmio,
        read_b2_status,
        read_current_state,
        validate_package,
        wait_b2_idle,
    )


SCHEMA_VERSION = "stage2i-board-functional-result-v1"
FROZEN_SCENARIOS = (
    "CLEAN_TRANSACTION",
    "INDIVIDUAL_FAULT_CAUSES",
    "MULTI_CAUSE",
    "FAULT_EPISODE",
    "SOURCE_PROTOCOL",
    "DISTINCT_CLOCK_CDC",
)
REG_CTRL = int(RegisterOffset.CTRL)
COUNTER_MASK = 0xFFFF_FFFF
PRODUCER_COUNT_MASK = 0xFF
DEFAULT_TIMEOUT_SECONDS = 5.0
DEFAULT_POLL_SECONDS = 0.001
CLEAN_SAMPLE = (1024, 1025)

ERROR_COUNTER_FIELDS = (
    "source_protocol_violation_count",
    "source_drop_count",
    "fifo_overflow_attempt_count",
    "fifo_underflow_attempt_count",
    "duplicate_delivery_count",
    "sequence_gap_count",
    "reorder_or_stale_count",
    "aggregate_error_count",
)

INDIVIDUAL_FAULT_CASES = (
    {
        "id": "CH1_OVERCURRENT",
        "commands": ((3001, 2802, 1),),
        "expected_bitmap": int(FaultCause.CH1_OVERCURRENT),
        "expected_code": int(FaultCode.OVERCURRENT),
    },
    {
        "id": "CH2_OVERCURRENT",
        "commands": ((2802, 3001, 1),),
        "expected_bitmap": int(FaultCause.CH2_OVERCURRENT),
        "expected_code": int(FaultCode.OVERCURRENT),
    },
    {
        "id": "SENSOR_MISMATCH",
        "commands": ((1000, 1300, 1),),
        "expected_bitmap": int(FaultCause.SENSOR_MISMATCH_OR_DIFFERENTIAL),
        "expected_code": int(FaultCode.SENSOR_MISMATCH),
    },
    {
        "id": "SENSOR_OPEN",
        "commands": ((0, 1, 127), (0, 2, 127), (0, 1, 2)),
        "expected_bitmap": int(FaultCause.SENSOR_OPEN),
        "expected_code": int(FaultCode.SENSOR_OPEN),
    },
    {
        "id": "SENSOR_SATURATION",
        "commands": ((4095, 4094, 127), (4095, 4093, 127), (4095, 4094, 2)),
        "expected_bitmap": int(
            FaultCause.CH1_OVERCURRENT
            | FaultCause.CH2_OVERCURRENT
            | FaultCause.SENSOR_SATURATION
        ),
        "expected_first_bitmap": int(FaultCause.CH1_OVERCURRENT | FaultCause.CH2_OVERCURRENT),
        "expected_code": int(FaultCode.OVERCURRENT),
    },
    {
        "id": "SENSOR_STUCK",
        "prelude": ((1024, 1026, 1),),
        # The changed first pair establishes history; 256 stable comparisons follow.
        "commands": ((1024, 1024, 127), (1024, 1024, 127), (1024, 1024, 3)),
        "expected_bitmap": int(FaultCause.SENSOR_STUCK),
        "expected_code": int(FaultCode.SENSOR_STUCK),
    },
)


class ValidationError(RuntimeError):
    """The requested board validation did not satisfy its exact contract."""


class B2Backend(Protocol):
    def read_state(self) -> dict[str, Any]: ...

    def issue(self, ch1: int, ch2: int, burst: int) -> dict[str, Any]: ...

    def clear_fault(self) -> None: ...

    def cleanup(self) -> dict[str, Any]: ...


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace(
        "+00:00", "Z"
    )


def canonical_json(value: Any) -> str:
    return (
        json.dumps(value, ensure_ascii=True, allow_nan=False, indent=2, sort_keys=True)
        + "\n"
    )


def counter_delta(after: int, before: int, mask: int = COUNTER_MASK) -> int:
    return (int(after) - int(before)) & mask


def c2_execution_plan() -> dict[str, Any]:
    return {
        "schema_version": "stage2i-c2-execution-plan-v1",
        "scenarios": list(FROZEN_SCENARIOS),
        "clean_sample": {"ch1": CLEAN_SAMPLE[0], "ch2": CLEAN_SAMPLE[1]},
        "source_protocol": {
            "ch1": 1500,
            "ch2": 1501,
            "burst_count": 127,
            "backpressure_required": True,
        },
        "individual_fault_cases": [
            {
                "id": case["id"],
                "prelude": [list(command) for command in case.get("prelude", ())],
                "commands": [list(command) for command in case["commands"]],
                "expected_bitmap": case["expected_bitmap"],
                "expected_first_bitmap": case.get("expected_first_bitmap", case["expected_bitmap"]),
                "expected_code": case["expected_code"],
            }
            for case in INDIVIDUAL_FAULT_CASES
        ],
        "multi_cause": {
            "commands": [[3200, 2500, 1]],
            "expected_bitmap": int(
                FaultCause.CH1_OVERCURRENT
                | FaultCause.SENSOR_MISMATCH_OR_DIFFERENTIAL
            ),
            "expected_code": int(FaultCode.OC_WITH_ANY_SENSOR),
        },
        "fault_episode": {
            "fault_sample": [1000, 1300],
            "clear_while_fault_present": "REJECTED_OR_NONQUALIFIED_RECOVERY",
            "qualified_recovery_clean_transactions": 2,
        },
        "clock_contract": {
            "destination_clock_mhz": 100,
            "source_clock_mhz": 125,
        },
    }


def _policy(state: dict[str, Any]) -> dict[str, Any]:
    return state["policy_status"]


def _bitmap(state: dict[str, Any], name: str) -> int:
    return int(state[name]["raw_value"])


def _observability(state: dict[str, Any]) -> dict[str, Any]:
    return state["observability"]


def require_no_integrity_errors(state: dict[str, Any], label: str) -> None:
    observability = _observability(state)
    nonzero = {
        field: int(observability[field])
        for field in ERROR_COUNTER_FIELDS
        if int(observability[field]) != 0
    }
    if nonzero:
        raise ValidationError(f"{label}: transaction integrity counters are nonzero: {nonzero}")
    status = int(observability["status"])
    if status & int(ObservabilityStatus.ANY_ERROR):
        raise ValidationError(f"{label}: observability ANY_ERROR is asserted")


def require_clean_state(state: dict[str, Any], label: str) -> None:
    policy = _policy(state)
    if not policy["armed_ready"] or any(
        policy[name]
        for name in (
            "fault_latched_state",
            "reset_wait_state",
            "clear_pending",
            "post_clear_recovery_pending",
        )
    ):
        raise ValidationError(f"{label}: policy is not armed and clean: {policy}")
    if any(
        _bitmap(state, name) != 0
        for name in (
            "first_fault_bitmap",
            "live_fault_bitmap",
            "fault_seen_bitmap",
        )
    ):
        raise ValidationError(f"{label}: fault bitmap state is not clear")
    status = state["status"]
    if int(status["status"]) != 0 or int(status["fault_code"]) != 0:
        raise ValidationError(f"{label}: compatibility status is not fault-free")
    require_no_integrity_errors(state, label)


def require_fault_state(
    state: dict[str, Any], expected_bitmap: int, expected_code: int, label: str,
    *, expected_first_bitmap: int | None = None,
) -> None:
    policy = _policy(state)
    if not policy["fault_latched_state"] or policy["armed_ready"]:
        raise ValidationError(f"{label}: policy did not latch the fault: {policy}")
    observed = {
        "first": _bitmap(state, "first_fault_bitmap"),
        "live": _bitmap(state, "live_fault_bitmap"),
        "seen": _bitmap(state, "fault_seen_bitmap"),
        "code": int(state["status"]["fault_code"]),
    }
    first_bitmap = expected_bitmap if expected_first_bitmap is None else expected_first_bitmap
    if observed["first"] != first_bitmap or observed["live"] != expected_bitmap:
        raise ValidationError(
            f"{label}: fault bitmap mismatch: {observed} "
            f"expected_first={first_bitmap:#x} expected_live={expected_bitmap:#x}"
        )
    if observed["seen"] & expected_bitmap != expected_bitmap:
        raise ValidationError(f"{label}: fault-seen bitmap omitted the expected cause")
    if observed["code"] != expected_code:
        raise ValidationError(
            f"{label}: fault code mismatch: {observed['code']} != {expected_code}"
        )
    require_no_integrity_errors(state, label)


def run_commands(
    backend: B2Backend, commands: Iterable[tuple[int, int, int]]
) -> list[dict[str, Any]]:
    return [backend.issue(ch1, ch2, burst) for ch1, ch2, burst in commands]


def recover_fault(backend: B2Backend, label: str) -> dict[str, Any]:
    backend.clear_fault()
    transactions = run_commands(
        backend, ((CLEAN_SAMPLE[0], CLEAN_SAMPLE[1], 2),)
    )
    state = backend.read_state()
    require_clean_state(state, f"{label} qualified recovery")
    return {"status": "PASS", "transactions": transactions, "state": state}


def run_c2_sequence(backend: B2Backend) -> dict[str, Any]:
    coverage: dict[str, Any] = {}

    source_before = backend.read_state()
    source_transaction = backend.issue(1500, 1501, 127)
    source_after = source_transaction["state_after"]
    before_obs = _observability(source_before)
    after_obs = _observability(source_after)
    accepted_delta = counter_delta(
        after_obs["source_accept_count"], before_obs["source_accept_count"]
    )
    delivered_delta = counter_delta(
        after_obs["destination_delivery_count"],
        before_obs["destination_delivery_count"],
    )
    backpressure_delta = counter_delta(
        after_obs["backpressure_cycle_count"],
        before_obs["backpressure_cycle_count"],
    )
    if accepted_delta != 127 or delivered_delta != 127 or backpressure_delta <= 0:
        raise ValidationError(
            "SOURCE_PROTOCOL did not prove exact acceptance, delivery, and backpressure"
        )
    if not int(after_obs["status"]) & int(ObservabilityStatus.BACKPRESSURE_SEEN):
        raise ValidationError("SOURCE_PROTOCOL did not latch BACKPRESSURE_SEEN")
    require_no_integrity_errors(source_after, "SOURCE_PROTOCOL")
    coverage["SOURCE_PROTOCOL"] = {
        "status": "PASS",
        "accepted_delta": accepted_delta,
        "delivered_delta": delivered_delta,
        "backpressure_cycle_delta": backpressure_delta,
        "transaction": source_transaction,
    }

    clean_transaction = backend.issue(CLEAN_SAMPLE[0], CLEAN_SAMPLE[1], 1)
    require_clean_state(clean_transaction["state_after"], "CLEAN_TRANSACTION")
    coverage["CLEAN_TRANSACTION"] = {
        "status": "PASS",
        "transaction": clean_transaction,
    }

    individual_results = []
    for case in INDIVIDUAL_FAULT_CASES:
        if case.get("prelude"):
            prelude = run_commands(backend, case["prelude"])
            require_clean_state(backend.read_state(), f"{case['id']} prelude")
        else:
            prelude = []
        transactions = run_commands(backend, case["commands"])
        state = backend.read_state()
        require_fault_state(
            state,
            int(case["expected_bitmap"]),
            int(case["expected_code"]),
            str(case["id"]),
            expected_first_bitmap=case.get("expected_first_bitmap"),
        )
        recovery = recover_fault(backend, str(case["id"]))
        individual_results.append(
            {
                "id": case["id"],
                "status": "PASS",
                "expected_bitmap": case["expected_bitmap"],
                "expected_first_bitmap": case.get("expected_first_bitmap", case["expected_bitmap"]),
                "expected_code": case["expected_code"],
                "prelude": prelude,
                "transactions": transactions,
                "fault_state": state,
                "recovery": recovery,
            }
        )
    coverage["INDIVIDUAL_FAULT_CAUSES"] = {
        "status": "PASS",
        "cases": individual_results,
    }

    multi_bitmap = int(
        FaultCause.CH1_OVERCURRENT
        | FaultCause.SENSOR_MISMATCH_OR_DIFFERENTIAL
    )
    multi_transaction = backend.issue(3200, 2500, 1)
    multi_state = backend.read_state()
    require_fault_state(
        multi_state,
        multi_bitmap,
        int(FaultCode.OC_WITH_ANY_SENSOR),
        "MULTI_CAUSE",
    )
    multi_recovery = recover_fault(backend, "MULTI_CAUSE")
    coverage["MULTI_CAUSE"] = {
        "status": "PASS",
        "expected_bitmap": multi_bitmap,
        "expected_code": int(FaultCode.OC_WITH_ANY_SENSOR),
        "transaction": multi_transaction,
        "fault_state": multi_state,
        "recovery": multi_recovery,
    }

    episode_bitmap = int(FaultCause.SENSOR_MISMATCH_OR_DIFFERENTIAL)
    initial = backend.issue(1000, 1300, 1)
    require_fault_state(
        backend.read_state(),
        episode_bitmap,
        int(FaultCode.SENSOR_MISMATCH),
        "FAULT_EPISODE initial",
    )
    persistent = backend.issue(1000, 1300, 1)
    persistent_state = backend.read_state()
    require_fault_state(
        persistent_state,
        episode_bitmap,
        int(FaultCode.SENSOR_MISMATCH),
        "FAULT_EPISODE persistent",
    )
    backend.clear_fault()
    rejected = backend.issue(1000, 1300, 1)
    rejected_state = backend.read_state()
    require_fault_state(
        rejected_state,
        episode_bitmap,
        int(FaultCode.SENSOR_MISMATCH),
        "FAULT_EPISODE rejected clear",
    )
    qualified = recover_fault(backend, "FAULT_EPISODE")
    coverage["FAULT_EPISODE"] = {
        "status": "PASS",
        "initial_fault": initial,
        "persistent_fault": persistent,
        "rejected_or_nonqualified_recovery": rejected,
        "qualified_recovery": qualified,
    }

    final_state = backend.read_state()
    require_clean_state(final_state, "DISTINCT_CLOCK_CDC final state")
    final_obs = _observability(final_state)
    if int(final_obs["source_accept_count"]) != int(
        final_obs["destination_delivery_count"]
    ):
        raise ValidationError("DISTINCT_CLOCK_CDC transaction counts diverged")
    if int(final_obs["last_source_sequence"]) != int(
        final_obs["last_destination_sequence"]
    ):
        raise ValidationError("DISTINCT_CLOCK_CDC last sequence identities diverged")
    coverage["DISTINCT_CLOCK_CDC"] = {
        "status": "PASS",
        "source_clock_mhz": 125,
        "destination_clock_mhz": 100,
        "source_accept_count": int(final_obs["source_accept_count"]),
        "destination_delivery_count": int(final_obs["destination_delivery_count"]),
        "last_source_sequence": int(final_obs["last_source_sequence"]),
        "last_destination_sequence": int(final_obs["last_destination_sequence"]),
    }

    if set(coverage) != set(FROZEN_SCENARIOS):
        raise ValidationError(f"C2 scenario coverage differs: {sorted(coverage)}")
    ordered_coverage = {name: coverage[name] for name in FROZEN_SCENARIOS}
    return {"scenario_coverage": ordered_coverage, "final_state": final_state}


class RealB2Backend:
    def __init__(
        self,
        protection_mmio: Any,
        gpio_mmio: Any,
        *,
        timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
        poll_seconds: float = DEFAULT_POLL_SECONDS,
    ) -> None:
        self.protection = protection_mmio
        self.gpio = gpio_mmio
        self.timeout_seconds = timeout_seconds
        self.poll_seconds = poll_seconds

    def read_state(self) -> dict[str, Any]:
        return read_current_state(self.protection)

    def _wait_transaction_counts(
        self, before: dict[str, Any], burst: int
    ) -> dict[str, Any]:
        before_obs = _observability(before)
        deadline = time.monotonic() + self.timeout_seconds
        last: dict[str, Any] | None = None
        while time.monotonic() < deadline:
            last = self.read_state()
            observed = _observability(last)
            source_delta = counter_delta(
                observed["source_accept_count"], before_obs["source_accept_count"]
            )
            destination_delta = counter_delta(
                observed["destination_delivery_count"],
                before_obs["destination_delivery_count"],
            )
            if source_delta == burst and destination_delta == burst:
                if int(last["policy_evaluation_sequence"]) == int(
                    observed["last_destination_sequence"]
                ):
                    return last
            if source_delta > burst or destination_delta > burst:
                raise ValidationError(
                    "B2 command produced more transactions than requested"
                )
            time.sleep(self.poll_seconds)
        raise ValidationError(f"B2 transaction counters did not converge: {last}")

    def issue(self, ch1: int, ch2: int, burst: int) -> dict[str, Any]:
        before = self.read_state()
        command = issue_b2_command(self.gpio, ch1, ch2, burst)
        producer_after = wait_b2_idle(
            self.gpio,
            int(command["epoch"]),
            timeout_seconds=self.timeout_seconds,
            poll_seconds=self.poll_seconds,
        )
        producer_delta = counter_delta(
            producer_after["accepted_count"],
            command["status_before"]["accepted_count"],
            PRODUCER_COUNT_MASK,
        )
        if producer_delta != burst:
            raise ValidationError(
                f"B2 producer acceptance count differs: {producer_delta} != {burst}"
            )
        after = self._wait_transaction_counts(before, burst)
        return {
            "ch1": ch1,
            "ch2": ch2,
            "burst_count": burst,
            "control_word": command["control_word"],
            "epoch": command["epoch"],
            "producer_status_before": command["status_before"],
            "producer_status_after": producer_after,
            "producer_accepted_delta": producer_delta,
            "state_before": before,
            "state_after": after,
        }

    def clear_fault(self) -> None:
        self.protection.write(REG_CTRL, int(CTRL_CLEAR_FAULT))

    def cleanup(self) -> dict[str, Any]:
        self.protection.write(REG_CTRL, 0)
        deadline = time.monotonic() + self.timeout_seconds
        producer = None
        while time.monotonic() < deadline:
            producer = read_b2_status(self.gpio)
            if not producer["request_pending"] and not producer["active"]:
                break
            time.sleep(self.poll_seconds)
        if producer is None or producer["request_pending"] or producer["active"]:
            raise ValidationError(f"B2 cleanup could not reach producer idle: {producer}")
        state = self.read_state()
        if int(state["status"]["ctrl"]) != 0:
            raise ValidationError("B2 cleanup did not leave CTRL disabled")
        return {"status": "PASS", "producer": producer, "state": state}


def execute_b1(package_root: Path, profile: dict[str, Any]) -> dict[str, Any]:
    _overlay, protection, _gpio, pynq_version = open_overlay_mmio(
        package_root, profile
    )
    state = read_current_state(protection)
    if int(state["status"]["ctrl"]) != 0:
        raise ValidationError("C1 CTRL is not disabled")
    if int(state["status"]["status"]) != 0 or int(
        state["status"]["fault_code"]
    ) != 0:
        raise ValidationError("C1 SAFE_INERT startup is not fault-free")
    require_no_integrity_errors(state, "C1 SAFE_INERT")
    return {
        "status": "PASS",
        "pynq_version": pynq_version,
        "scenario_coverage": {
            "C1_PRODUCTION_PLATFORM_AND_REGISTER_PATH": {
                "status": "PASS",
                "abi": state["register_map_version"],
                "safe_startup": state,
            }
        },
        "cleanup": {"status": "PASS", "ctrl_disabled": True},
        "board_hardware_execution": "C1_PRODUCTION_PLATFORM_PASS",
    }


def execute_b2(package_root: Path, profile: dict[str, Any]) -> dict[str, Any]:
    _overlay, protection, gpio, pynq_version = open_overlay_mmio(
        package_root, profile
    )
    backend = RealB2Backend(protection, gpio)
    sequence: dict[str, Any] | None = None
    cleanup: dict[str, Any]
    try:
        sequence = run_c2_sequence(backend)
    finally:
        cleanup = backend.cleanup()
    return {
        "status": "PASS",
        "pynq_version": pynq_version,
        **sequence,
        "cleanup": cleanup,
        "board_hardware_execution": "C2_FULL_DIGITAL_PATH_PASS",
    }


def run(
    package_root: Path, expected_profile: str, *, execute: bool = False
) -> dict[str, Any]:
    package_root = package_root.resolve(strict=True)
    offline = validate_package(package_root, expected_profile=expected_profile)
    profile = load_profile(package_root, expected_profile=expected_profile)
    result: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "timestamp_utc": utc_now(),
        "implementation_profile": expected_profile,
        "package_root": str(package_root),
        "source_commit": profile["source_commit"],
        "source_tree": profile["source_tree"],
        "execution_id": profile["execution_id"],
        "offline_validation": offline,
        "execute_requested": bool(execute),
        "execution_plan": (
            c2_execution_plan()
            if expected_profile == READY_AWARE
            else {"scenario": "C1_PRODUCTION_PLATFORM_AND_REGISTER_PATH"}
        ),
        "persistent_deployment_claim": "NOT_CLAIMED",
        "board_hardware_execution": "NOT_RUN",
        "status": "PASS_OFFLINE",
    }
    if not execute:
        return result
    executed = (
        execute_b1(package_root, profile)
        if expected_profile == SAFE_INERT
        else execute_b2(package_root, profile)
    )
    result.update(executed)
    return result


def default_package_root() -> Path:
    path = Path(__file__).resolve()
    for candidate in (path.parent, *path.parents):
        if (candidate / "stage2i_board_profile.json").is_file():
            return candidate
    return Path.cwd()


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--package-root", type=Path, default=default_package_root())
    result.add_argument(
        "--profile", choices=(SAFE_INERT, READY_AWARE), required=True
    )
    result.add_argument("--execute", action="store_true")
    result.add_argument("--output", type=Path)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        result = run(args.package_root, args.profile, execute=args.execute)
    except (OSError, ValueError, KeyError, Stage2IBoardError, ValidationError) as exc:
        result = {
            "schema_version": SCHEMA_VERSION,
            "timestamp_utc": utc_now(),
            "implementation_profile": args.profile,
            "execute_requested": bool(args.execute),
            "board_hardware_execution": "FAILED_OR_NOT_RUN",
            "status": "FAIL",
            "reason": str(exc),
        }
    payload = canonical_json(result)
    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload, encoding="utf-8", newline="\n")
    print(payload, end="")
    return 0 if str(result["status"]).startswith("PASS") else 1


if __name__ == "__main__":
    raise SystemExit(main())
