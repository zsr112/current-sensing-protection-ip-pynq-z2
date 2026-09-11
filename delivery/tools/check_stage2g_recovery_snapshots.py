#!/usr/bin/env python3
"""Apply the unchanged software recovery predicate to RTL AXI snapshots."""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from sw.protection_ip_interface import (
    FAULT_NONE,
    STATUS_FAULT_LATCHED,
    ProtectionSnapshot,
    recovery_is_verified,
)


# These expected fault causes are deliberately frozen oracle values.  They
# validate RTL snapshot semantics and must remain independent of generated
# register-map authority.
FAULT_OVERCURRENT = 0x01
FAULT_SENSOR_MISMATCH = 0x02


class SnapshotError(RuntimeError):
    """Raised when RTL-derived recovery evidence is incomplete or invalid."""


def load_snapshots(path: Path) -> dict[str, dict[str, int]]:
    rows: dict[str, dict[str, int]] = {}
    with path.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        required = {
            "LABEL",
            "CTRL",
            "STATUS",
            "FAULT_CODE",
            "I_CH1",
            "I_CH2",
            "FSM_STATE",
            "PWM_OUT",
        }
        if reader.fieldnames is None or set(reader.fieldnames) != required:
            raise SnapshotError(f"malformed snapshot header: {path}")
        for raw in reader:
            label = raw["LABEL"]
            if label in rows:
                raise SnapshotError(f"duplicate snapshot label {label}: {path}")
            rows[label] = {
                key: int(raw[key], 16)
                for key in ("CTRL", "STATUS", "FAULT_CODE", "I_CH1", "I_CH2")
            }
            rows[label]["FSM_STATE"] = int(raw["FSM_STATE"], 10)
            rows[label]["PWM_OUT"] = int(raw["PWM_OUT"], 10)
    return rows


def software_result(row: dict[str, int]) -> bool:
    return recovery_is_verified(
        ProtectionSnapshot(
            ctrl=row["CTRL"],
            status=row["STATUS"],
            fault_code=row["FAULT_CODE"],
            i_ch1=row["I_CH1"],
            i_ch2=row["I_CH2"],
        )
    )


def validate(path: Path) -> None:
    rows = load_snapshots(path)
    required_labels = {
        "FAULT_LATCHED",
        "POST_CLEAR_RESET_WAIT",
        "NO_SAMPLE_POST_CLEAR",
        "NONCLEAN_POST_CLEAR",
        "ARMED_AFTER_LATER_HEALTHY",
        "POST_CLEAR_NEW_FAULT",
        "PRE_RESET_POST_CLEAR",
        "RESET_DURING_POST_CLEAR",
    }
    if set(rows) != required_labels:
        raise SnapshotError(
            f"snapshot label mismatch in {path}: "
            f"missing={sorted(required_labels-set(rows))}, "
            f"extra={sorted(set(rows)-required_labels)}"
        )

    fault = rows["FAULT_LATCHED"]
    if (
        fault["FSM_STATE"] != 1
        or not (fault["STATUS"] & STATUS_FAULT_LATCHED)
        or fault["FAULT_CODE"] != FAULT_OVERCURRENT
        or software_result(fault)
    ):
        raise SnapshotError(f"initial fault snapshot is invalid: {path}")

    for label in (
        "POST_CLEAR_RESET_WAIT",
        "NO_SAMPLE_POST_CLEAR",
        "NONCLEAN_POST_CLEAR",
    ):
        row = rows[label]
        if (
            row["FSM_STATE"] != 2
            or row["PWM_OUT"] != 0
            or not (row["STATUS"] & STATUS_FAULT_LATCHED)
            or row["FAULT_CODE"] != FAULT_OVERCURRENT
            or software_result(row)
        ):
            raise SnapshotError(f"{label} reports public recovery in {path}")

    pre_reset = rows["PRE_RESET_POST_CLEAR"]
    if (
        pre_reset["FSM_STATE"] != 2
        or pre_reset["PWM_OUT"] != 0
        or not (pre_reset["STATUS"] & STATUS_FAULT_LATCHED)
        or pre_reset["FAULT_CODE"] != FAULT_SENSOR_MISMATCH
        or software_result(pre_reset)
    ):
        raise SnapshotError(f"pre-reset post-clear snapshot is invalid: {path}")

    armed = rows["ARMED_AFTER_LATER_HEALTHY"]
    if (
        armed["FSM_STATE"] != 0
        or armed["STATUS"] != 0
        or armed["FAULT_CODE"] != FAULT_NONE
        or not software_result(armed)
    ):
        raise SnapshotError(f"later healthy snapshot is not recovered: {path}")

    new_fault = rows["POST_CLEAR_NEW_FAULT"]
    if (
        new_fault["FSM_STATE"] != 1
        or not (new_fault["STATUS"] & STATUS_FAULT_LATCHED)
        or new_fault["FAULT_CODE"] != FAULT_SENSOR_MISMATCH
        or software_result(new_fault)
    ):
        raise SnapshotError(f"new pre-arm fault did not replace cause: {path}")

    reset = rows["RESET_DURING_POST_CLEAR"]
    if (
        reset["FSM_STATE"] != 2
        or reset["STATUS"] != 0
        or reset["FAULT_CODE"] != FAULT_NONE
    ):
        raise SnapshotError(f"reset did not clear compatibility state: {path}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--icarus", type=Path, required=True)
    parser.add_argument("--xsim", type=Path)
    args = parser.parse_args(argv)
    try:
        paths = [args.icarus.resolve(strict=True)]
        if args.xsim is not None:
            paths.append(args.xsim.resolve(strict=True))
        for path in paths:
            validate(path)
    except (OSError, ValueError, SnapshotError) as exc:
        print(f"SOFTWARE_RECOVERY_API_SEMANTICS_PRESERVED=FAIL: {exc}", file=sys.stderr)
        return 1
    print("POST_CLEAR_RESET_WAIT_RECOVERY_VERIFIED=NO")
    print("NO_SAMPLE_POST_CLEAR_RECOVERY_VERIFIED=NO")
    print("NONCLEAN_POST_CLEAR_RECOVERY_VERIFIED=NO")
    print("ARMED_AFTER_LATER_HEALTHY_RECOVERY_VERIFIED=YES")
    print("SOFTWARE_RECOVERY_API_SEMANTICS_PRESERVED=PASS")
    print("RECOVERY_SNAPSHOT_ORACLE_PARITY=PASS")
    print(f"RTL_RECOVERY_SNAPSHOT_SOURCES=PASS_{len(paths)}_OF_{len(paths)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
