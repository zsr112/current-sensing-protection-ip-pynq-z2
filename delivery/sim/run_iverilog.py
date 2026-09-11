#!/usr/bin/env python3
"""Run all canonical Icarus testbenches without a shell dependency."""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.runtime_config import resolve_tool

RTL = (
    "reset_release_sync", "pwm_gen", "pwm_gate", "current_compare_dual",
    "moving_avg_filter", "sensor_health_monitor", "transaction_destination_observer",
    "fault_classifier", "protection_fsm", "protection_core_top", "protection_reg_bank",
    "protection_ip_top_reg_controlled", "protection_ip_top_axi_lite",
)
TESTS = tuple("tb_" + name for name in RTL if name not in (
    "reset_release_sync", "pwm_gate", "transaction_destination_observer"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.is_relative_to(ROOT) or ROOT.is_relative_to(output):
        parser.error("Output must be external to the source tree")
    output.mkdir(parents=True, exist_ok=False)
    waves = output / "waves"
    waves.mkdir()
    compiler = resolve_tool(ROOT, "iverilog")
    simulator = resolve_tool(ROOT, "vvp")
    if compiler is None or simulator is None:
        parser.error("Icarus iverilog and vvp are required")
    passed = 0
    for top in TESTS:
        image = output / (top + ".vvp")
        command = [str(compiler), "-g2012", "-I", str(ROOT / "rtl"), "-I",
                   str(ROOT / "tb/generated"), "-s", top, "-o", str(image),
                   *(str(ROOT / "rtl" / (name + ".v")) for name in RTL),
                   str(ROOT / "tb" / (top + ".sv"))]
        compiled = subprocess.run(command, cwd=output, capture_output=True, text=True, errors="replace")
        text = compiled.stdout + compiled.stderr
        ok = False
        if compiled.returncode == 0:
            run = subprocess.run([str(simulator), str(image), "+CSIP_WAVE_DIR=" + waves.as_posix()],
                                 cwd=output, capture_output=True, text=True, errors="replace")
            text += run.stdout + run.stderr
            ok = run.returncode == 0 and bool(re.search(r"ALL TESTS PASSED| PASS", run.stdout))
        (output / (top + ".log")).write_text(text, encoding="utf-8")
        print(f"{top}={'PASS' if ok else 'FAIL'}", flush=True)
        passed += ok
    print(f"SUMMARY: PASS={passed} FAIL={len(TESTS) - passed}")
    return 0 if passed == len(TESTS) else 1


if __name__ == "__main__":
    raise SystemExit(main())
