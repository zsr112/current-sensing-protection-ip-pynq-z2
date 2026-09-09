#!/usr/bin/env python3
"""Run connected Stage 2F normalizer and raw-path mutation fixtures."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from typing import Callable


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.runtime_config import resolve_vivado_bin
RTL = ROOT / "rtl"
NORMALIZER = RTL / "adc_sample_code_normalizer.sv"
TOP = RTL / "protection_ip_top_async_adc_axi_lite.v"
MUTATION_TB = ROOT / "tb/stage2f/tb_stage2f_mutation.sv"
RAW_GATE_TB = ROOT / "tb/stage2f/tb_stage2f_raw_gate_mutation.sv"
FULL_RTL_NAMES = [
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
]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise ValueError(f"{label}: expected one source anchor, found {count}")
    return text.replace(old, new, 1)


def mutant_zero_minus_raw(text: str) -> str:
    return replace_once(text, "decoded = raw_wide - zero_wide;", "decoded = zero_wide - raw_wide;", "zero-minus-raw")


def mutant_missing_signed_extension(text: str) -> str:
    return replace_once(text, "decoded = $signed({raw_code[RAW_WIDTH-1], raw_code});", "decoded = $signed({1'b0, raw_code});", "missing-signed-extension")


def mutant_twos_as_unsigned(text: str) -> str:
    return replace_once(text, "decoded = $signed({raw_code[RAW_WIDTH-1], raw_code});", "decoded = raw_wide;", "twos-as-unsigned")


def mutant_wrong_sign_bit(text: str) -> str:
    return replace_once(text, "decoded = $signed({raw_code[RAW_WIDTH-1], raw_code});", "decoded = $signed({raw_code[RAW_WIDTH-2], raw_code});", "wrong-sign-bit")


def mutant_reversed_polarity(text: str) -> str:
    return replace_once(text, "if (polarity_negative)\n                polarity_value", "if (!polarity_negative)\n                polarity_value", "reversed-polarity")


def mutant_negate_overflow(text: str) -> str:
    return replace_once(text, "polarity_value = $signed(-decoded);", "polarity_value = $signed(-decoded[RAW_WIDTH-1:0]);", "negate-overflow")


def mutant_channel_polarity_swap(text: str) -> str:
    old = """normalized_ch1 <= normalize_code(
                    raw_ch1, CH1_POLARITY_NEGATIVE);
                normalized_ch2 <= normalize_code(
                    raw_ch2, CH2_POLARITY_NEGATIVE);"""
    new = """normalized_ch1 <= normalize_code(
                    raw_ch1, CH2_POLARITY_NEGATIVE);
                normalized_ch2 <= normalize_code(
                    raw_ch2, CH1_POLARITY_NEGATIVE);"""
    return replace_once(text, old, new, "channel-polarity-swap")


def mutant_channel_payload_swap(text: str) -> str:
    old = """normalized_ch1 <= normalize_code(
                    raw_ch1, CH1_POLARITY_NEGATIVE);
                normalized_ch2 <= normalize_code(
                    raw_ch2, CH2_POLARITY_NEGATIVE);"""
    new = """normalized_ch1 <= normalize_code(
                    raw_ch2, CH1_POLARITY_NEGATIVE);
                normalized_ch2 <= normalize_code(
                    raw_ch1, CH2_POLARITY_NEGATIVE);"""
    return replace_once(text, old, new, "channel-payload-swap")


def mutant_sequence_latency(text: str) -> str:
    return replace_once(text, "normalized_sequence <= raw_sequence;", "normalized_sequence <= raw_sequence + 1'b1;", "sequence-latency")


def mutant_valid_data_latency(text: str) -> str:
    return replace_once(text, "else if (raw_delivery_valid) begin", "else begin", "valid-data-latency")


def mutant_unconfigured_valid(text: str) -> str:
    return replace_once(text, "if (!profile_valid) begin", "if (1'b0) begin", "unconfigured-valid")


def mutant_drop_every_second(text: str) -> str:
    return replace_once(text, "else if (raw_delivery_valid) begin", "else if (raw_delivery_valid && raw_sequence[0]) begin", "drop-every-second")


def mutant_reset_not_cleared(text: str) -> str:
    old = """if (!local_resetn) begin
            normalized_valid <= 1'b0;"""
    new = """if (!local_resetn) begin
            normalized_valid <= 1'b1;"""
    return replace_once(text, old, new, "reset-not-cleared")


NORMALIZER_MUTANTS: list[tuple[str, Callable[[str], str]]] = [
    ("ZERO_MINUS_RAW", mutant_zero_minus_raw),
    ("MISSING_SIGNED_EXTENSION", mutant_missing_signed_extension),
    ("TWOS_COMPLEMENT_AS_UNSIGNED", mutant_twos_as_unsigned),
    ("WRONG_SIGN_BIT", mutant_wrong_sign_bit),
    ("REVERSED_POLARITY_MAPPING", mutant_reversed_polarity),
    ("NEGATE_12_BIT_OVERFLOW", mutant_negate_overflow),
    ("CHANNEL_POLARITY_SWAP", mutant_channel_polarity_swap),
    ("CHANNEL_PAYLOAD_SWAP", mutant_channel_payload_swap),
    ("SEQUENCE_WRONG_LATENCY", mutant_sequence_latency),
    ("VALID_DATA_LATENCY_MISMATCH", mutant_valid_data_latency),
    ("VALID_WHEN_UNCONFIGURED", mutant_unconfigured_valid),
    ("DROP_EVERY_SECOND_TRANSACTION", mutant_drop_every_second),
    ("RESET_PENDING_VALID_NOT_CLEARED", mutant_reset_not_cleared),
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


def iverilog_case(source: Path, testbench: Path, work: Path) -> tuple[int, str]:
    work.mkdir(parents=True, exist_ok=True)
    image = work / "case.vvp"
    iverilog = shutil.which("iverilog") or shutil.which("iverilog.exe")
    vvp = shutil.which("vvp") or shutil.which("vvp.exe")
    if not iverilog or not vvp:
        raise RuntimeError("Icarus tools are required for mutation fixtures")
    compile_result = run_process(
        [
            iverilog,
            "-g2012",
            "-I",
            str(RTL),
            "-s",
            testbench.stem,
            "-o",
            str(image),
            str(source),
            str(testbench),
        ],
        work,
        work / "compile.log",
    )
    if compile_result.returncode != 0:
        return compile_result.returncode, compile_result.stdout
    run_result = run_process([vvp, str(image)], work, work / "run.log")
    return run_result.returncode, run_result.stdout


def vivado_tools() -> tuple[Path, Path, Path] | None:
    directory = resolve_vivado_bin(ROOT)
    if directory is None:
        return None
    tools = tuple(directory / name for name in ("xvlog.bat", "xelab.bat", "xsim.bat"))
    if all(path.is_file() for path in tools):
        return tools  # type: ignore[return-value]
    return None


def xsim_case(sources: list[Path], testbench: Path, top: str, work: Path) -> tuple[int, str]:
    tools = vivado_tools()
    if tools is None:
        raise RuntimeError("Vivado/XSim tools are required for XSim mutation fixtures")
    xvlog, xelab, xsim = tools
    work.mkdir(parents=True, exist_ok=True)
    xvlog_result = run_process(
        [str(xvlog), "--sv", "-i", str(RTL), "--log", str(work / "xvlog.log")]
        + [str(path) for path in sources + [testbench]],
        work,
        work / "xvlog.console.log",
    )
    if xvlog_result.returncode != 0:
        return xvlog_result.returncode, xvlog_result.stdout
    xelab_result = run_process(
        [
            str(xelab),
            f"work.{top}",
            "-s",
            "mutation_snapshot",
            "--timescale",
            "1ns/1ps",
            "--log",
            str(work / "xelab.log"),
        ],
        work,
        work / "xelab.console.log",
    )
    if xelab_result.returncode != 0:
        return xelab_result.returncode, xelab_result.stdout
    xsim_result = run_process(
        [
            str(xsim),
            "mutation_snapshot",
            "-runall",
            "--onerror",
            "quit",
            "--onfinish",
            "quit",
            "--log",
            str(work / "xsim.log"),
        ],
        work,
        work / "xsim.console.log",
    )
    return xsim_result.returncode, xsim_result.stdout


def run(output: Path, include_xsim: bool) -> list[str]:
    output.mkdir(parents=True, exist_ok=True)
    base_text = NORMALIZER.read_text(encoding="utf-8")
    results: list[str] = []
    with tempfile.TemporaryDirectory(prefix="stage2f_mutants_") as temp_name:
        temporary = Path(temp_name)
        control_source = temporary / "control_normalizer.sv"
        control_source.write_text(base_text, encoding="utf-8")
        control_code, control_text = iverilog_case(
            control_source, MUTATION_TB, output / "icarus_control"
        )
        # Icarus/vvp may report zero even when the testbench calls $finish(1).
        # The explicit survival marker is therefore the control oracle.
        if "MUTATION_SURVIVED=NO_MISMATCH" not in control_text:
            raise RuntimeError("mutation oracle control did not fail closed")
        results.append("CONTROL_ORACLE=PASS")

        for name, transform in NORMALIZER_MUTANTS:
            mutant = transform(base_text)
            source = temporary / f"{name}.sv"
            source.write_text(mutant, encoding="utf-8")
            digest = hashlib.sha256(mutant.encode("utf-8")).hexdigest()
            case_output = output / f"icarus_{name.lower()}"
            code, text = iverilog_case(source, MUTATION_TB, case_output)
            if code != 0 or "MUTATION_DETECTED=PASS" not in text:
                raise RuntimeError(
                    f"Icarus mutation {name} survived or failed to connect; see {case_output}"
                )
            results.append(f"ICARUS_{name}=KILLED_SHA256_{digest}")
            if include_xsim:
                xsim_output = output / f"xsim_{name.lower()}"
                code, text = xsim_case(
                    [source], MUTATION_TB, "tb_stage2f_mutation", xsim_output
                )
                if code != 0 or "MUTATION_DETECTED=PASS" not in text:
                    raise RuntimeError(
                        f"XSim mutation {name} survived or failed to connect; see {xsim_output}"
                    )
                results.append(f"XSIM_{name}=KILLED")

        raw_mutant = replace_once(
            TOP.read_text(encoding="utf-8"),
            ".sample_valid(dst_sample_valid),",
            ".sample_valid(dst_sample_valid && normalized_sample_valid),",
            "raw-path-gating",
        )
        raw_source = temporary / "protection_ip_top_async_adc_axi_lite.v"
        raw_source.write_text(raw_mutant, encoding="utf-8")
        full_sources = [
            RTL / name
            for name in FULL_RTL_NAMES
            if name != "protection_ip_top_async_adc_axi_lite.v"
        ]
        full_sources.append(raw_source)
        raw_output = output / "icarus_raw_path_gate"
        raw_output.mkdir(parents=True, exist_ok=True)
        iverilog = shutil.which("iverilog") or shutil.which("iverilog.exe")
        vvp = shutil.which("vvp") or shutil.which("vvp.exe")
        image = raw_output / "raw_gate.vvp"
        compile_result = run_process(
            [
                iverilog,
                "-g2012",
                "-I",
                str(RTL),
                "-s",
                "tb_stage2f_raw_gate_mutation",
                "-o",
                str(image),
            ]
            + [str(path) for path in full_sources + [RAW_GATE_TB]],
            raw_output,
            raw_output / "compile.log",
        )
        if compile_result.returncode != 0:
            raise RuntimeError("raw-path mutant did not compile")
        run_result = run_process(
            [vvp, str(image)], raw_output, raw_output / "run.log"
        )
        if (
            run_result.returncode != 0
            or "MUTATION_DETECTED=PASS_RAW_PATH_GATED" not in run_result.stdout
        ):
            raise RuntimeError("raw-path gating mutation survived")
        results.append("ICARUS_RAW_PATH_GATED=KILLED")
        if include_xsim:
            xsim_output = output / "xsim_raw_path_gate"
            code, text = xsim_case(
                full_sources, RAW_GATE_TB, "tb_stage2f_raw_gate_mutation", xsim_output
            )
            if (
                code != 0
                or "MUTATION_DETECTED=PASS_RAW_PATH_GATED" not in text
            ):
                raise RuntimeError("XSim raw-path gating mutation survived")
            results.append("XSIM_RAW_PATH_GATED=KILLED")
    (output / "mutation_results.txt").write_text(
        "\n".join(results) + "\n", encoding="utf-8"
    )
    return results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--xsim", action="store_true")
    args = parser.parse_args(argv)
    try:
        results = run(args.output.resolve(), args.xsim)
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"STAGE2F_MUTATION_TESTS=FAIL: {exc}", file=sys.stderr)
        return 1
    killed = len([result for result in results if "KILLED" in result])
    print(f"STAGE2F_MUTATION_TESTS=PASS_{killed}_CONNECTED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
