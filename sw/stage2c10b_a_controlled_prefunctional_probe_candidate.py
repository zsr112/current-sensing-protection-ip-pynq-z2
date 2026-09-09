#!/usr/bin/env python3
"""Stage2I C1 fail-closed prefunctional probe, dry-run by default."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    from sw.stage2i_board_runtime import (
        SAFE_INERT,
        Stage2IBoardError,
        open_overlay_mmio,
        read_all_registers,
        read_current_state,
        validate_package,
    )
except ModuleNotFoundError:
    from stage2i_board_runtime import (  # type: ignore
        SAFE_INERT,
        Stage2IBoardError,
        open_overlay_mmio,
        read_all_registers,
        read_current_state,
        validate_package,
    )


STAGE = "Stage2I C1 controlled prefunctional probe"


def default_package_root() -> Path:
    script = Path(__file__).resolve()
    for candidate in (script.parent, *script.parents):
        if (candidate / "stage2i_board_profile.json").is_file():
            return candidate
    return Path.cwd()


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--package-root", type=Path, default=default_package_root())
    result.add_argument("--execute-reviewed-plan", action="store_true")
    result.add_argument("--output", type=Path)
    return result


def run(args: argparse.Namespace) -> dict[str, Any]:
    package_root = args.package_root.resolve(strict=True)
    offline = validate_package(package_root, expected_profile=SAFE_INERT)
    result: dict[str, Any] = {
        "schema_version": "stage2i-c1-prefunctional-probe-v1",
        "stage": STAGE,
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "implementation_profile": SAFE_INERT,
        "offline_validation": offline,
        "dry_run": not args.execute_reviewed_plan,
        "execute_reviewed_plan": bool(args.execute_reviewed_plan),
        "planned_operations": [
            "validate exact Stage2I B1 profile and artifacts",
            "load the SAFE_INERT Overlay only when explicitly requested",
            "resolve protection and GPIO addresses from Overlay metadata",
            "require explicit ABI 1.1 and capture one read-only state",
            "perform no register writes",
        ],
        "register_write_performed": False,
        "board_hardware_execution": "NOT_RUN",
        "status": "PASS_OFFLINE",
    }
    if not args.execute_reviewed_plan:
        return result

    profile = json.loads(
        (package_root / "stage2i_board_profile.json").read_text(encoding="utf-8")
    )
    _overlay, protection, _gpio, pynq_version = open_overlay_mmio(
        package_root, profile
    )
    result.update(
        {
            "pynq_version": pynq_version,
            "state": read_current_state(protection),
            "registers": read_all_registers(protection),
            "board_hardware_execution": "C1_PREFUNCTIONAL_READ_ONLY_PASS",
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
