#!/usr/bin/env python3
"""Compile and run the focused Stage2I-B ready-aware producer simulation."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path


REQUIRED_MARKERS = (
    "TEST_PRODUCER_RESET=PASS",
    "TEST_PRODUCER_STALL_BEHAVIOR=PASS",
    "TEST_PRODUCER_EXACT_ACCEPT_COUNT=PASS",
    "TEST_PRODUCER_REPEATED_COMMAND=PASS",
    "TEST_PRODUCER_ZERO_BURST=PASS",
    "COMMAND_CONFIG_CDC_INTEGRITY=PASS",
    "BACKPRESSURE_INDUCTION_METHOD=REAL_PRODUCTION_ASYNC_FIFO_FILL",
    "STAGE2I_B2_TEST_PRODUCER_VERIFICATION=PASS",
)


def resolve_tool(name: str) -> str:
    executable = shutil.which(name) or shutil.which(f"{name}.exe")
    if executable is None:
        raise RuntimeError(f"required simulation tool is missing: {name}")
    return executable


def run(output_root: Path, repo_root: Path) -> str:
    output_root.mkdir(parents=True, exist_ok=True)
    image = output_root / "stage2i_b2_ready_aware_stimulus.vvp"
    compile_log = output_root / "compile.log"
    simulation_log = output_root / "simulation.log"
    sources = (
        repo_root / "fpga/vivado/test_profile/stage2i_b2_ready_aware_stimulus.v",
        repo_root / "rtl/async_fifo_gray.v",
        repo_root / "rtl/transaction_source_observer.v",
        repo_root / "rtl/adc_sample_cdc_bridge.v",
        repo_root / "tb/stage2i/tb_stage2i_b2_ready_aware_stimulus.sv",
    )
    compile_result = subprocess.run(
        [
            resolve_tool("iverilog"),
            "-g2012",
            "-s",
            "tb_stage2i_b2_ready_aware_stimulus",
            "-o",
            str(image),
            *(str(path) for path in sources),
        ],
        cwd=repo_root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    compile_log.write_text(compile_result.stdout, encoding="utf-8")
    if compile_result.returncode != 0:
        raise RuntimeError(f"producer compilation failed; see {compile_log}")
    simulation_result = subprocess.run(
        [resolve_tool("vvp"), str(image)],
        cwd=repo_root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    simulation_log.write_text(simulation_result.stdout, encoding="utf-8")
    if simulation_result.returncode != 0:
        raise RuntimeError(f"producer simulation failed; see {simulation_log}")
    missing = [marker for marker in REQUIRED_MARKERS if marker not in simulation_result.stdout]
    if missing:
        raise RuntimeError(f"producer simulation omitted markers: {missing}")
    return simulation_result.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path)
    parser.add_argument(
        "--repo-root", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    repo_root = args.repo_root.resolve()
    if args.output_root is None:
        with tempfile.TemporaryDirectory(prefix="stage2i-b2-producer-") as temporary:
            print(run(Path(temporary), repo_root), end="")
    else:
        print(run(args.output_root.resolve(), repo_root), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
