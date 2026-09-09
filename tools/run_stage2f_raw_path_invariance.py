#!/usr/bin/env python3
"""Compare the Stage 2F working top with the frozen raw-path base top."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.runtime_config import resolve_vivado_bin
RTL = ROOT / "rtl"
BASE_COMMIT = "3399e4fdc28f9d4c66cf90cb5c1dc1e386eda6ae"
TOP_RELATIVE = Path("rtl/protection_ip_top_async_adc_axi_lite.v")
TESTBENCH = ROOT / "tb/stage2f/tb_stage2f_raw_path_invariance.sv"
RTL_NAMES = [
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
]


def run_process(args: list[str], cwd: Path, log: Path) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        args,
        cwd=cwd,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    log.write_text(result.stdout, encoding="utf-8")
    return result


def git_base_top(base_commit: str) -> str:
    manifest = ROOT / 'tb/fixtures/raw_path/ORACLES.json'
    if manifest.is_file():
        records = json.loads(manifest.read_text(encoding='utf-8'))['files']
        if base_commit in records:
            record = records[base_commit]
            path = ROOT / record['path']
            data = path.read_bytes()
            if hashlib.sha256(data).hexdigest() != record['sha256']:
                raise RuntimeError('Frozen raw-path oracle hash mismatch')
            return data.decode('utf-8')
    if not (ROOT / '.git').exists():
        raise RuntimeError('Requested frozen base is not included in this source export')
    result = subprocess.run(
        ["git", "-C", str(ROOT), "show", f"{base_commit}:{TOP_RELATIVE.as_posix()}"],
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"unable to read frozen base top: {result.stderr.strip()}")
    return result.stdout


def alias_top(source: str, alias: str) -> str:
    anchor = "module protection_ip_top_async_adc_axi_lite"
    if source.count(anchor) != 1:
        raise RuntimeError(f"top alias anchor count is not one for {alias}")
    return source.replace(anchor, f"module {alias}", 1)


def iverilog_run(output: Path, base_source: Path, impl_source: Path) -> tuple[int, str]:
    iverilog = shutil.which("iverilog") or shutil.which("iverilog.exe")
    vvp = shutil.which("vvp") or shutil.which("vvp.exe")
    if not iverilog or not vvp:
        raise RuntimeError("Icarus tools are required for raw-path invariance")
    output.mkdir(parents=True, exist_ok=True)
    image = output / "raw_path_invariance.vvp"
    sources = [RTL / name for name in RTL_NAMES]
    sources += [base_source, impl_source, TESTBENCH]
    compile_result = run_process(
        [
            iverilog,
            "-g2012",
            "-I",
            str(RTL),
            "-s",
            TESTBENCH.stem,
            "-o",
            str(image),
        ]
        + [str(path) for path in sources],
        output,
        output / "compile.log",
    )
    if compile_result.returncode != 0:
        return compile_result.returncode, compile_result.stdout
    run_result = run_process([vvp, str(image)], output, output / "run.log")
    return run_result.returncode, run_result.stdout


def vivado_tools() -> tuple[Path, Path, Path] | None:
    directory = resolve_vivado_bin(ROOT)
    if directory is None:
        return None
    tools = tuple(directory / name for name in ("xvlog.bat", "xelab.bat", "xsim.bat"))
    if all(path.is_file() for path in tools):
        return tools  # type: ignore[return-value]
    return None


def xsim_run(output: Path, base_source: Path, impl_source: Path) -> tuple[int, str]:
    tools = vivado_tools()
    if tools is None:
        raise RuntimeError("Vivado/XSim tools are required for raw-path invariance")
    output.mkdir(parents=True, exist_ok=True)
    xvlog, xelab, xsim = tools
    sources = [RTL / name for name in RTL_NAMES]
    sources += [base_source, impl_source, TESTBENCH]
    xvlog_result = run_process(
        [str(xvlog), "--sv", "-i", str(RTL), "--log", str(output / "xvlog.log")]
        + [str(path) for path in sources],
        output,
        output / "xvlog.console.log",
    )
    if xvlog_result.returncode != 0:
        return xvlog_result.returncode, xvlog_result.stdout
    xelab_result = run_process(
        [
            str(xelab),
            f"work.{TESTBENCH.stem}",
            "-s",
            "raw_path_snapshot",
            "--timescale",
            "1ns/1ps",
            "--log",
            str(output / "xelab.log"),
        ],
        output,
        output / "xelab.console.log",
    )
    if xelab_result.returncode != 0:
        return xelab_result.returncode, xelab_result.stdout
    xsim_result = run_process(
        [
            str(xsim),
            "raw_path_snapshot",
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
    return xsim_result.returncode, xsim_result.stdout


def run(output: Path, include_xsim: bool, base_commit: str = BASE_COMMIT) -> list[str]:
    output.mkdir(parents=True, exist_ok=True)
    base_text = git_base_top(base_commit)
    impl_text = (ROOT / TOP_RELATIVE).read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory(prefix="stage2f_raw_invariance_") as temp_name:
        temp = Path(temp_name)
        base_source = temp / "protection_ip_top_async_adc_axi_lite_base.v"
        impl_source = temp / "protection_ip_top_async_adc_axi_lite_impl.v"
        base_source.write_text(
            alias_top(base_text, "protection_ip_top_async_adc_axi_lite_base"),
            encoding="utf-8",
        )
        impl_source.write_text(
            alias_top(impl_text, "protection_ip_top_async_adc_axi_lite_impl"),
            encoding="utf-8",
        )
        results: list[str] = []
        output.mkdir(parents=True, exist_ok=True)
        code, text = iverilog_run(output / "icarus", base_source, impl_source)
        if code != 0 or "RAW_PATH_INVARIANCE=PASS" not in text:
            raise RuntimeError("Icarus raw-path invariance failed; see output logs")
        results.append("ICARUS_RAW_PATH_INVARIANCE=PASS")
        if include_xsim:
            code, text = xsim_run(output / "xsim", base_source, impl_source)
            if code != 0 or "RAW_PATH_INVARIANCE=PASS" not in text:
                raise RuntimeError("XSim raw-path invariance failed; see output logs")
            results.append("XSIM_RAW_PATH_INVARIANCE=PASS")
    (output / "raw_path_invariance_result.txt").write_text(
        "BASE_COMMIT=" + base_commit + "\n" + "\n".join(results) + "\n",
        encoding="utf-8",
    )
    return results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--xsim", action="store_true")
    parser.add_argument("--base-commit", default=BASE_COMMIT)
    args = parser.parse_args(argv)
    try:
        results = run(args.output.resolve(), args.xsim, args.base_commit)
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"STAGE2F_RAW_PATH_INVARIANCE=FAIL: {exc}", file=sys.stderr)
        return 1
    print("STAGE2F_RAW_PATH_INVARIANCE=PASS_" + str(len(results)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
