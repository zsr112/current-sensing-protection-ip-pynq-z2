#!/usr/bin/env python3
"""Stage2I C1 current ABI 1.1 Overlay/MMIO smoke, offline by default."""

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


STAGE = "Stage2I C1 current ABI 1.1 PYNQ MMIO smoke"
REG_CTRL = int(RegisterOffset.CTRL)
READ_REGISTERS = [(register.name, int(register)) for register in RegisterOffset]


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
    result.add_argument("--idempotent-ctrl-zero", action="store_true")
    result.add_argument("--output", type=Path)
    return result


def run(args: argparse.Namespace) -> dict[str, Any]:
    package_root = args.package_root.resolve(strict=True)
    offline = validate_package(package_root, expected_profile=SAFE_INERT)
    result: dict[str, Any] = {
        "schema_version": "stage2i-c1-mmio-smoke-v1",
        "stage": STAGE,
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "implementation_profile": SAFE_INERT,
        "package_root": str(package_root),
        "offline_validation": offline,
        "execute_requested": bool(args.execute),
        "register_inventory": [name for name, _offset in READ_REGISTERS],
        "register_access_performed": False,
        "register_write_performed": False,
        "board_hardware_execution": "NOT_RUN",
        "status": "PASS_OFFLINE",
    }
    if not args.execute:
        return result

    profile_path = package_root / "stage2i_board_profile.json"
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    _overlay, protection, _gpio, pynq_version = open_overlay_mmio(
        package_root, profile
    )
    before = read_current_state(protection)
    raw_registers = read_all_registers(protection)
    result.update(
        {
            "pynq_version": pynq_version,
            "state": before,
            "registers": raw_registers,
            "register_access_performed": True,
            "board_hardware_execution": "C1_READ_ONLY_MMIO_PASS",
            "status": "PASS",
        }
    )
    if args.idempotent_ctrl_zero:
        if raw_registers[RegisterOffset.CTRL.name] != 0:
            raise Stage2IBoardError("CTRL is nonzero; idempotent zero write is not allowed")
        protection.write(REG_CTRL, 0)
        if int(protection.read(REG_CTRL)) != 0:
            raise Stage2IBoardError("CTRL idempotent zero readback failed")
        result["register_write_performed"] = True
        result["idempotent_ctrl_zero"] = "PASS"
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
