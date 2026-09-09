#!/usr/bin/env python3
"""Stage2I C1 generated-map idempotent writable-register check."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    from sw.generated.protection_register_map import RegisterOffset
    from sw.stage2i_board_runtime import (
        SAFE_INERT,
        Stage2IBoardError,
        open_overlay_mmio,
        read_all_registers,
        read_current_state,
        validate_package,
    )
except ModuleNotFoundError:
    from generated.protection_register_map import RegisterOffset  # type: ignore
    from stage2i_board_runtime import (  # type: ignore
        SAFE_INERT,
        Stage2IBoardError,
        open_overlay_mmio,
        read_all_registers,
        read_current_state,
        validate_package,
    )


STAGE = "Stage2I C1 controlled idempotent writable-register check"
READ_REGISTERS = [(register.name, int(register)) for register in RegisterOffset]
WRITE_CANDIDATES = [
    (register.name, int(register))
    for register in (
        RegisterOffset.CTRL,
        RegisterOffset.TH_OC1,
        RegisterOffset.TH_OC2,
        RegisterOffset.TH_DIFF,
        RegisterOffset.PWM_PERIOD,
        RegisterOffset.PWM_DUTY,
    )
]


def default_package_root() -> Path:
    script = Path(__file__).resolve()
    for candidate in (script.parent, *script.parents):
        if (candidate / "stage2i_board_profile.json").is_file():
            return candidate
    return Path.cwd()


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--package-root", type=Path, default=default_package_root())
    result.add_argument("--execute", action="store_true")
    result.add_argument("--output", type=Path)
    return result


def run(args: argparse.Namespace) -> dict[str, Any]:
    package_root = args.package_root.resolve(strict=True)
    offline = validate_package(package_root, expected_profile=SAFE_INERT)
    result: dict[str, Any] = {
        "schema_version": "stage2i-c1-idempotent-rw-v1",
        "stage": STAGE,
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "implementation_profile": SAFE_INERT,
        "offline_validation": offline,
        "execute_requested": bool(args.execute),
        "read_register_inventory": [name for name, _offset in READ_REGISTERS],
        "write_candidate_inventory": [name for name, _offset in WRITE_CANDIDATES],
        "write_results": [],
        "register_write_performed": False,
        "board_hardware_execution": "NOT_RUN",
        "status": "PASS_OFFLINE",
    }
    if not args.execute:
        return result

    profile = json.loads(
        (package_root / "stage2i_board_profile.json").read_text(encoding="utf-8")
    )
    _overlay, protection, _gpio, pynq_version = open_overlay_mmio(
        package_root, profile
    )
    state_before = read_current_state(protection)
    registers_before = read_all_registers(protection)
    if registers_before[RegisterOffset.CTRL.name] != 0:
        raise Stage2IBoardError("CTRL must be zero before idempotent C1 writes")
    for name, offset in WRITE_CANDIDATES:
        before = int(protection.read(offset))
        if name == RegisterOffset.CTRL.name and before != 0:
            raise Stage2IBoardError("CTRL clear/enable bits make the write non-idempotent")
        protection.write(offset, before)
        after = int(protection.read(offset))
        if after != before:
            raise Stage2IBoardError(f"idempotent write readback failed: {name}")
        result["write_results"].append(
            {"register": name, "offset": offset, "before": before, "after": after}
        )
    result.update(
        {
            "pynq_version": pynq_version,
            "state_before": state_before,
            "registers_before": registers_before,
            "registers_after": read_all_registers(protection),
            "register_write_performed": True,
            "board_hardware_execution": "C1_IDEMPOTENT_RW_PASS",
            "status": "PASS",
        }
    )
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        result = run(args)
    except (OSError, ValueError, json.JSONDecodeError, Stage2IBoardError) as exc:
        result = {"status": "FAIL", "stage": STAGE, "reason": str(exc)}
    payload = json.dumps(result, ensure_ascii=True, allow_nan=False, indent=2, sort_keys=True) + "\n"
    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload, encoding="utf-8", newline="\n")
    print(payload, end="")
    return 0 if result["status"].startswith("PASS") else 1


if __name__ == "__main__":
    raise SystemExit(main())
