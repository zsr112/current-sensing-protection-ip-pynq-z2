#!/usr/bin/env python3
"""Reconcile Stage2I C2 board results with explicit source/destination ILA captures."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


SOURCE_ROOT = Path(__file__).resolve().parents[2]
if (SOURCE_ROOT / "sw").is_dir() and str(SOURCE_ROOT) not in sys.path:
    sys.path.insert(0, str(SOURCE_ROOT))

try:
    from sw.stage2i_board_runtime import (
        READY_AWARE,
        READY_AWARE_DESTINATION_PROBES,
        SOURCE_PROBES,
    )
    from tools.board_validation.stage1_board_functional_validation import (
        FROZEN_SCENARIOS,
        SCHEMA_VERSION as BOARD_RESULT_SCHEMA,
    )
except ModuleNotFoundError:
    from stage2i_board_runtime import (  # type: ignore
        READY_AWARE,
        READY_AWARE_DESTINATION_PROBES,
        SOURCE_PROBES,
    )
    from stage1_board_functional_validation import (  # type: ignore
        FROZEN_SCENARIOS,
        SCHEMA_VERSION as BOARD_RESULT_SCHEMA,
    )


SCHEMA_VERSION = "stage2i-board-functional-closeout-v1"
FINAL_PASS_CLASS = "STAGE2I_C2_FULL_DIGITAL_PROTECTION_PATH_EVIDENCE_PASS"
FINAL_FAIL_CLASS = "STAGE2I_C2_FULL_DIGITAL_PROTECTION_PATH_EVIDENCE_FAILED"
CAPTURE_CONTRACT = {
    "source_stall": {
        "role": "source",
        "mode": "source_stall",
        "probes": SOURCE_PROBES,
    },
    "source_accept": {
        "role": "source",
        "mode": "source_accept",
        "probes": SOURCE_PROBES,
    },
    "destination_fault": {
        "role": "destination",
        "mode": "destination_fault_latched",
        "probes": READY_AWARE_DESTINATION_PROBES,
    },
}


class EvidenceError(RuntimeError):
    """Evidence is missing, malformed, or does not prove the required result."""


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace(
        "+00:00", "Z"
    )


def canonical_json(value: Any) -> str:
    return (
        json.dumps(value, ensure_ascii=True, allow_nan=False, indent=2, sort_keys=True)
        + "\n"
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def reject_duplicate_keys(pairs: Iterable[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise EvidenceError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=reject_duplicate_keys,
            parse_constant=lambda item: (_ for _ in ()).throw(
                EvidenceError(f"non-finite JSON value: {item}")
            ),
        )
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise EvidenceError(f"invalid JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise EvidenceError(f"JSON root is not an object: {path}")
    return value


def load_metadata(path: Path) -> dict[str, str]:
    if not path.is_file() or path.stat().st_size == 0:
        raise EvidenceError(f"capture metadata is missing or empty: {path}")
    try:
        with path.open("r", encoding="utf-8", newline="") as stream:
            reader = csv.reader(stream, dialect="excel-tab", strict=True)
            rows = list(reader)
    except (OSError, UnicodeError, csv.Error) as exc:
        raise EvidenceError(f"cannot parse capture metadata {path}: {exc}") from exc
    if not rows or rows[0] != ["field", "value"]:
        raise EvidenceError(f"capture metadata header differs: {path}")
    result: dict[str, str] = {}
    for row in rows[1:]:
        if len(row) != 2 or not row[0] or row[0] in result:
            raise EvidenceError(f"capture metadata row is invalid: {row}")
        result[row[0]] = row[1]
    return result


def parse_scalar(value: str, radix: str) -> int:
    token = value.strip().replace("_", "")
    if not token:
        raise EvidenceError("empty ILA cell")
    normalized_radix = radix.strip().upper()
    lowered = token.lower()
    if normalized_radix == "BINARY":
        if lowered.startswith("0b"):
            lowered = lowered[2:]
        if not re.fullmatch(r"[01]+", lowered):
            raise EvidenceError(f"invalid binary ILA value: {value!r}")
        return int(lowered, 2)
    if normalized_radix == "HEX":
        if lowered.startswith("0x"):
            lowered = lowered[2:]
        if not re.fullmatch(r"[0-9a-f]+", lowered):
            raise EvidenceError(f"invalid hexadecimal ILA value: {value!r}")
        return int(lowered, 16)
    if normalized_radix == "UNSIGNED":
        if not re.fullmatch(r"[0-9]+", token):
            raise EvidenceError(f"invalid unsigned ILA value: {value!r}")
        return int(token, 10)
    if normalized_radix == "SIGNED":
        if not re.fullmatch(r"-?[0-9]+", token):
            raise EvidenceError(f"invalid signed ILA value: {value!r}")
        return int(token, 10)
    raise EvidenceError(f"unsupported ILA radix: {radix!r}")


def probe_columns(fieldnames: list[str], probe_index: int) -> list[str]:
    pattern = re.compile(
        rf"(?:^|[/._])probe{probe_index}(?:_1)?(?:\[[0-9:]+\])?(?:$|[^0-9])",
        re.IGNORECASE,
    )
    matches = [name for name in fieldnames if pattern.search(name)]
    if not matches:
        raise EvidenceError(f"ILA CSV is missing probe{probe_index}")
    return matches


def value_from_columns(
    row: dict[str, str], columns: list[str], radices: dict[str, str]
) -> int:
    if len(columns) == 1:
        return parse_scalar(row[columns[0]], radices[columns[0]])
    bits: dict[int, int] = {}
    for name in columns:
        match = re.search(r"\[(\d+)\](?:$|[^0-9])", name)
        if match is None:
            raise EvidenceError(f"ambiguous multi-column ILA probe: {columns}")
        bit = int(match.group(1))
        if radices[name] != "BINARY":
            raise EvidenceError(f"bit-column ILA probe is not binary: {name}")
        value = parse_scalar(row[name], radices[name])
        if value not in {0, 1} or bit in bits:
            raise EvidenceError(f"invalid bit-column ILA probe: {name}={value}")
        bits[bit] = value
    if sorted(bits) != list(range(max(bits) + 1)):
        raise EvidenceError(f"incomplete bit-column ILA probe: {sorted(bits)}")
    return sum(value << bit for bit, value in bits.items())


def load_capture(
    path: Path, probes: dict[int, tuple[int, str]]
) -> tuple[list[dict[str, int]], dict[str, Any]]:
    if not path.is_file() or path.stat().st_size == 0:
        raise EvidenceError(f"required ILA capture missing or empty: {path}")
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as stream:
            raw_rows = list(csv.reader(stream, strict=True))
    except (OSError, UnicodeError, csv.Error) as exc:
        raise EvidenceError(f"cannot parse ILA CSV {path}: {exc}") from exc
    if len(raw_rows) < 3:
        raise EvidenceError(f"ILA CSV requires header, radix row, and samples: {path}")
    fieldnames = [str(name) for name in raw_rows[0]]
    if not fieldnames or len(fieldnames) != len(set(fieldnames)):
        raise EvidenceError(f"ILA CSV header is empty or duplicated: {path}")
    radix_cells = raw_rows[1]
    if len(radix_cells) != len(fieldnames):
        raise EvidenceError(f"ILA CSV radix width mismatch: {path}")
    first_radix = radix_cells[0].strip()
    match = re.fullmatch(
        r"Radix\s*-\s*(BINARY|HEX|UNSIGNED|SIGNED)",
        first_radix,
        re.IGNORECASE,
    )
    if match is None:
        raise EvidenceError(f"ILA CSV radix row missing: {path}")
    radix_cells[0] = match.group(1)
    radices = {
        name: value.strip().upper() for name, value in zip(fieldnames, radix_cells)
    }
    columns = {index: probe_columns(fieldnames, index) for index in probes}
    for index, names in columns.items():
        for name in names:
            if radices[name] != "BINARY":
                raise EvidenceError(
                    f"probe{index} CSV radix is not BINARY: {name}={radices[name]}"
                )
    rows: list[dict[str, int]] = []
    for row_number, values in enumerate(raw_rows[2:], start=3):
        if len(values) != len(fieldnames):
            raise EvidenceError(f"ILA CSV row {row_number} width mismatch: {path}")
        source = dict(zip(fieldnames, values))
        parsed = {
            signal: value_from_columns(source, columns[index], radices)
            for index, (width, signal) in probes.items()
        }
        for index, (width, signal) in probes.items():
            if not (0 <= parsed[signal] < (1 << width)):
                raise EvidenceError(
                    f"probe{index} value exceeds {width} bits: {parsed[signal]}"
                )
        rows.append(parsed)
    if not rows:
        raise EvidenceError(f"ILA CSV has no samples: {path}")
    return rows, {
        "path": str(path.resolve()),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
        "row_count": len(rows),
        "probe_radix": "BINARY",
    }


def validate_capture_metadata(
    metadata: dict[str, str], *, role: str, mode: str, probe_count: int
) -> None:
    required = {
        "implementation_profile": READY_AWARE,
        "core_role": role,
        "capture_mode": mode,
        "ila_logical_probe_count": str(probe_count),
        "probe_csv_radix": "BINARY",
        "fpga_programming_calls": "0",
        "device_reset_calls": "0",
        "automatic_retries": "0",
    }
    for field, expected in required.items():
        if metadata.get(field) != expected:
            raise EvidenceError(
                f"capture metadata mismatch: {field}={metadata.get(field)!r} "
                f"expected={expected!r}"
            )
    for field in ("bit_path", "ltx_path", "ila_cell_name"):
        if not metadata.get(field):
            raise EvidenceError(f"capture metadata is missing {field}")


def require_source_stall(rows: list[dict[str, int]]) -> dict[str, Any]:
    intervals: list[list[dict[str, int]]] = []
    current: list[dict[str, int]] = []
    for row in rows:
        if row["adc_sample_valid"] == 1 and row["adc_sample_ready"] == 0:
            current.append(row)
        elif current:
            intervals.append(current)
            current = []
    if current:
        intervals.append(current)
    if not intervals:
        raise EvidenceError("source-stall capture has no valid-high/ready-low interval")
    interval = max(intervals, key=len)
    payloads = {(row["adc_sample_ch1"], row["adc_sample_ch2"]) for row in interval}
    if len(payloads) != 1:
        raise EvidenceError(f"source payload changed while stalled: {sorted(payloads)}")
    if any(row["producer_accept"] != 0 for row in interval):
        raise EvidenceError("producer_accept asserted while ready was low")
    if any(row["producer_active"] != 1 for row in interval):
        raise EvidenceError("producer was not active throughout the stall interval")
    return {
        "status": "PASS",
        "stall_sample_count": len(interval),
        "stable_payload": list(next(iter(payloads))),
        "acceptance_while_stalled": 0,
    }


def require_source_accept(rows: list[dict[str, int]]) -> dict[str, Any]:
    candidates = [row for row in rows if row["producer_accept"] == 1]
    if not candidates:
        raise EvidenceError("source-accept capture has no producer_accept sample")
    if any(
        row["adc_sample_valid"] != 1 or row["adc_sample_ready"] != 1
        for row in candidates
    ):
        raise EvidenceError("producer_accept was not coincident with valid and ready")
    return {
        "status": "PASS",
        "accepted_sample_count": len(candidates),
        "first_payload": [
            candidates[0]["adc_sample_ch1"],
            candidates[0]["adc_sample_ch2"],
        ],
    }


def require_destination_fault(rows: list[dict[str, int]]) -> dict[str, Any]:
    candidates = [row for row in rows if row["fault_latched"] == 1]
    if not candidates:
        raise EvidenceError("destination capture has no latched-fault sample")
    if any(row["fault_code_latched"] == 0 for row in candidates):
        raise EvidenceError("latched fault has a zero compatibility code")
    if any(row["pwm_out"] != 0 for row in candidates):
        raise EvidenceError("pwm_out was not suppressed during a latched fault")
    return {
        "status": "PASS",
        "latched_sample_count": len(candidates),
        "fault_codes": sorted({row["fault_code_latched"] for row in candidates}),
    }


def verify_board_result(board: dict[str, Any]) -> dict[str, Any]:
    if board.get("schema_version") != BOARD_RESULT_SCHEMA:
        raise EvidenceError("board result schema differs")
    if board.get("status") != "PASS" or board.get("implementation_profile") != READY_AWARE:
        raise EvidenceError("board result is not a passing B2 execution")
    if board.get("board_hardware_execution") != "C2_FULL_DIGITAL_PATH_PASS":
        raise EvidenceError("board result does not claim the bounded C2 execution")
    if board.get("cleanup", {}).get("status") != "PASS":
        raise EvidenceError("board result cleanup did not pass")
    coverage = board.get("scenario_coverage")
    if not isinstance(coverage, dict) or set(coverage) != set(FROZEN_SCENARIOS):
        raise EvidenceError("board result scenario coverage differs")
    for scenario in FROZEN_SCENARIOS:
        if coverage[scenario].get("status") != "PASS":
            raise EvidenceError(f"board scenario did not pass: {scenario}")
    source = coverage["SOURCE_PROTOCOL"]
    if (
        int(source.get("accepted_delta", -1)) != 127
        or int(source.get("delivered_delta", -1)) != 127
        or int(source.get("backpressure_cycle_delta", 0)) <= 0
    ):
        raise EvidenceError("board source-protocol counters do not prove C2")
    clocks = coverage["DISTINCT_CLOCK_CDC"]
    if clocks.get("source_clock_mhz") != 125 or clocks.get("destination_clock_mhz") != 100:
        raise EvidenceError("board distinct-clock contract differs")
    if clocks.get("source_accept_count") != clocks.get("destination_delivery_count"):
        raise EvidenceError("board source/destination transaction counts differ")
    if clocks.get("last_source_sequence") != clocks.get("last_destination_sequence"):
        raise EvidenceError("board source/destination sequence identities differ")
    return {
        "status": "PASS",
        "source_commit": board.get("source_commit"),
        "source_tree": board.get("source_tree"),
        "execution_id": board.get("execution_id"),
        "scenario_count": len(coverage),
        "accepted_transactions": clocks.get("source_accept_count"),
    }


def analyze(
    board_result_path: Path, capture_paths: dict[str, Path]
) -> dict[str, Any]:
    board = load_json(board_result_path)
    board_proof = verify_board_result(board)
    capture_evidence: dict[str, Any] = {}
    proofs: dict[str, Any] = {}
    proof_functions = {
        "source_stall": require_source_stall,
        "source_accept": require_source_accept,
        "destination_fault": require_destination_fault,
    }
    for name, contract in CAPTURE_CONTRACT.items():
        path = capture_paths[name].resolve(strict=True)
        metadata_path = path.with_suffix(".metadata.tsv")
        metadata = load_metadata(metadata_path)
        validate_capture_metadata(
            metadata,
            role=contract["role"],
            mode=contract["mode"],
            probe_count=len(contract["probes"]),
        )
        rows, identity = load_capture(path, contract["probes"])
        capture_evidence[name] = {
            **identity,
            "metadata_path": str(metadata_path),
            "metadata_bytes": metadata_path.stat().st_size,
            "metadata_sha256": sha256_file(metadata_path),
            "core_role": contract["role"],
            "capture_mode": contract["mode"],
        }
        proofs[name] = proof_functions[name](rows)
    return {
        "schema_version": SCHEMA_VERSION,
        "timestamp_utc": utc_now(),
        "status": "PASS",
        "result_class": FINAL_PASS_CLASS,
        "implementation_profile": READY_AWARE,
        "board_result": {
            "path": str(board_result_path.resolve()),
            "bytes": board_result_path.stat().st_size,
            "sha256": sha256_file(board_result_path),
            "proof": board_proof,
        },
        "captures": capture_evidence,
        "proofs": proofs,
        "c2_real_backpressure_observed": "YES",
        "c2_stall_payload_stability": "PASS",
        "c2_one_acceptance_per_transaction": "PASS",
        "c2_distinct_clock_transaction_continuity": "PASS",
    }


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--board-result", type=Path, required=True)
    result.add_argument("--source-stall", type=Path, required=True)
    result.add_argument("--source-accept", type=Path, required=True)
    result.add_argument("--destination-fault", type=Path, required=True)
    result.add_argument("--output", type=Path)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        result = analyze(
            args.board_result,
            {
                "source_stall": args.source_stall,
                "source_accept": args.source_accept,
                "destination_fault": args.destination_fault,
            },
        )
    except (OSError, ValueError, KeyError, EvidenceError) as exc:
        result = {
            "schema_version": SCHEMA_VERSION,
            "timestamp_utc": utc_now(),
            "status": "FAIL",
            "result_class": FINAL_FAIL_CLASS,
            "reason": str(exc),
        }
    payload = canonical_json(result)
    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload, encoding="utf-8", newline="\n")
    print(payload, end="")
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
