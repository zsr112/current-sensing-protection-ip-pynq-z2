#!/usr/bin/env python3
"""Run configured Stage 2F top-level width and sequence boundary tests."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import shutil
import subprocess
import sys

try:
    from tools.generate_stage2f_adc_profile import generate
except ModuleNotFoundError:
    from generate_stage2f_adc_profile import generate  # type: ignore[no-redef]


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.runtime_config import resolve_vivado_bin
RTL = ROOT / "rtl"
SCHEMA = ROOT / "spec/stage2f_adc_source_profile.schema.json"
PROFILE = ROOT / "spec/stage2f_profiles/SIM_UNSIGNED_ZERO_EDGE_0.json"
TESTBENCH = ROOT / "tb/stage2f/tb_stage2f_width_sequence_boundary.sv"
RTL_NAMES = (
    "reset_release_sync.v",
    "async_fifo_gray.v",
    "transaction_source_observer.v",
    "adc_sample_cdc_bridge.v",
    "adc_sample_code_normalizer.sv",
    "source_observability_cdc.v",
    "transaction_destination_observer.v",
    "current_compare_dual.v",
    "sensor_health_monitor.v",
    "fault_classifier.v",
    "protection_fsm.v",
    "pwm_gen.v",
    "pwm_gate.v",
    "protection_core_top.v",
    "protection_reg_bank.v",
    "protection_ip_top_reg_controlled.v",
    "protection_ip_top_axi_lite.v",
    "protection_ip_top_async_adc_axi_lite.v",
)
RTL_INCLUDE_NAMES = (
    "fault_defs.vh",
    "generated/protection_register_map.vh",
)
NORMALIZER_PORTS = (
    "raw_sequence",
    "normalized_sequence",
    "raw_ch1",
    "raw_ch2",
    "normalized_ch1",
    "normalized_ch2",
)
PASS_MARKER = "WIDTH_SEQUENCE_BOUNDARY=PASS"


@dataclass(frozen=True)
class Result:
    simulator: str
    build_passed: bool
    run_returncode: int
    compile_text: str
    run_text: str

    @property
    def passed(self) -> bool:
        return self.build_passed and PASS_MARKER in self.run_text


def run_process(arguments: list[str], cwd: Path, log: Path) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        arguments,
        cwd=cwd,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    log.write_text(result.stdout, encoding="utf-8", newline="\n")
    return result


def prepare_rtl_root(output: Path, top_text: str | None = None) -> Path:
    rtl_root = output / "rtl"
    generated = rtl_root / "generated"
    generated.mkdir(parents=True)
    for name in RTL_INCLUDE_NAMES:
        shutil.copy2(RTL / name, rtl_root / name)
    for name in RTL_NAMES:
        source = RTL / name
        destination = rtl_root / name
        if name == "protection_ip_top_async_adc_axi_lite.v" and top_text is not None:
            destination.write_text(top_text, encoding="utf-8", newline="\n")
        else:
            shutil.copy2(source, destination)
    generate(
        SCHEMA,
        PROFILE,
        generated / "stage2f_adc_source_profile.svh",
        False,
    )
    return rtl_root


def run_icarus(rtl_root: Path, output: Path) -> Result:
    output.mkdir(parents=True)
    iverilog = shutil.which("iverilog") or shutil.which("iverilog.exe")
    vvp = shutil.which("vvp") or shutil.which("vvp.exe")
    if not iverilog or not vvp:
        raise RuntimeError("Icarus tools are required")
    image = output / "width_sequence.vvp"
    sources = [rtl_root / name for name in RTL_NAMES]
    compile_result = run_process(
        [
            iverilog,
            "-g2012",
            "-Wall",
            "-I",
            str(rtl_root),
            "-s",
            TESTBENCH.stem,
            "-o",
            str(image),
            *map(str, sources),
            str(TESTBENCH),
        ],
        output,
        output / "compile.log",
    )
    if compile_result.returncode != 0:
        return Result("ICARUS", False, 1, compile_result.stdout, "")
    run_result = run_process(
        [vvp, str(image)], output, output / "run.log"
    )
    return Result(
        "ICARUS", True, run_result.returncode, compile_result.stdout, run_result.stdout
    )


def run_xsim(rtl_root: Path, output: Path) -> Result:
    output.mkdir(parents=True)
    vivado = resolve_vivado_bin(ROOT)
    if vivado is None:
        raise RuntimeError('Vivado/XSim tools are required')
    xvlog = vivado / "xvlog.bat"
    xelab = vivado / "xelab.bat"
    xsim = vivado / "xsim.bat"
    if not all(path.is_file() for path in (xvlog, xelab, xsim)):
        raise RuntimeError("Vivado/XSim tools are required")
    sources = [rtl_root / name for name in RTL_NAMES]
    compile_result = run_process(
        [
            str(xvlog),
            "--sv",
            "-i",
            str(rtl_root),
            "--log",
            str(output / "xvlog.log"),
            *map(str, sources),
            str(TESTBENCH),
        ],
        output,
        output / "xvlog.console.log",
    )
    if compile_result.returncode != 0:
        return Result("XSIM", False, 1, compile_result.stdout, "")
    snapshot = "width_sequence_snapshot"
    elaborate_result = run_process(
        [
            str(xelab),
            f"work.{TESTBENCH.stem}",
            "-s",
            snapshot,
            "--timescale",
            "1ns/1ps",
            "--log",
            str(output / "xelab.log"),
        ],
        output,
        output / "xelab.console.log",
    )
    compile_text = compile_result.stdout + "\n" + elaborate_result.stdout
    if elaborate_result.returncode != 0:
        return Result("XSIM", False, 1, compile_text, "")
    run_result = run_process(
        [
            str(xsim),
            snapshot,
            "-runall",
            "--onerror",
            "quit",
            "--onfinish",
            "quit",
            "--log",
            str(output / "xsim.log"),
        ],
        output,
        output / "xsim.console.log",
    )
    return Result("XSIM", True, run_result.returncode, compile_text, run_result.stdout)


def run_case(simulator: str, rtl_root: Path, output: Path) -> Result:
    if simulator == "ICARUS":
        return run_icarus(rtl_root, output)
    if simulator == "XSIM":
        return run_xsim(rtl_root, output)
    raise ValueError(f"unsupported simulator: {simulator}")


def has_normalizer_width_warning(text: str) -> bool:
    width_terms = ("expects", "padding", "pruning", "width mismatch", "bit length")
    for line in text.splitlines():
        lowered = line.lower()
        if not any(term in lowered for term in width_terms):
            continue
        if "adc_sample_code_normalizer" in lowered:
            return True
        if any(port in lowered for port in NORMALIZER_PORTS):
            return True
    return False


def require_pass(result: Result) -> None:
    if not result.passed:
        raise RuntimeError(f"{result.simulator} width/sequence boundary failed")
    if has_normalizer_width_warning(result.compile_text):
        raise RuntimeError(f"{result.simulator} emitted a normalizer port width warning")


def run(output: Path, include_xsim: bool) -> list[str]:
    if output.exists():
        raise RuntimeError(f"output already exists: {output}")
    output.mkdir(parents=True)
    rtl_root = prepare_rtl_root(output)
    simulators = ("ICARUS", "XSIM") if include_xsim else ("ICARUS",)
    for simulator in simulators:
        require_pass(run_case(simulator, rtl_root, output / simulator.lower()))
    lines = [
        "WIDTH_SEQUENCE_BOUNDARY=PASS",
        "DATA_WIDTH_COMPATIBILITY_POLICY=RAW_GENERIC_NORMALIZATION_ONLY_AT_12",
        "DATA_WIDTH_8_RAW_PATH=PASS",
        "DATA_WIDTH_12_NORMALIZATION=PASS",
        "DATA_WIDTH_16_RAW_PATH=PASS",
        "OBS_SEQUENCE_WIDTH_16=PASS",
        "OBS_SEQUENCE_WIDTH_24=PASS",
        "OBS_SEQUENCE_WIDTH_32=PASS",
        "IMPLICIT_NORMALIZER_PORT_RESIZE=NO",
        "SIMULATORS=ICARUS,XSIM" if include_xsim else "SIMULATORS=ICARUS",
    ]
    (output / "width_sequence_boundary_results.txt").write_text(
        "\n".join(lines) + "\n", encoding="utf-8", newline="\n"
    )
    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--xsim", action="store_true")
    args = parser.parse_args(argv)
    try:
        lines = run(args.output.resolve(), args.xsim)
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"WIDTH_SEQUENCE_BOUNDARY=FAIL: {exc}", file=sys.stderr)
        return 1
    for line in lines:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
