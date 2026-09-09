#!/usr/bin/env python3
"""Run the focused Stage 2H-B2 connected RTL verification boundary."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"
TB = ROOT / "tb/stage2h"


class RunnerError(RuntimeError):
    pass


def executable(name: str) -> str:
    value = shutil.which(name) or shutil.which(f"{name}.exe")
    if not value:
        raise RunnerError(f"required executable not found: {name}")
    return value


def run_logged(command: list[str], cwd: Path, log: Path) -> str:
    result = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(result.stdout, encoding="utf-8", newline="\n")
    if result.returncode != 0:
        raise RunnerError(f"{log.stem} exited {result.returncode}")
    return result.stdout


def require_marker(text: str, marker: str, label: str) -> None:
    if marker not in text:
        raise RunnerError(f"{label} omitted marker {marker!r}")
    if "=FAIL" in text or "FAILED:" in text:
        raise RunnerError(f"{label} reported a failure marker")


def reject_width_warnings(text: str, label: str) -> None:
    offenders = []
    for line in text.splitlines():
        if not re.search(r"warning|warn", line, flags=re.IGNORECASE):
            continue
        if re.search(
            r"width|bit\s+length|port|resize|trunc|extend|padding|"
            r"out[- ]of[- ]range|select",
            line,
            flags=re.IGNORECASE,
        ):
            offenders.append(line.strip())
    if offenders:
        raise RunnerError(
            f"{label} emitted width warning(s): " + " | ".join(offenders)
        )


def iverilog_case(
    output: Path,
    name: str,
    top: str,
    sources: list[Path],
    markers: tuple[str, ...],
    *,
    strict_width: bool = False,
) -> str:
    work = output / name
    work.mkdir(parents=True, exist_ok=True)
    image = work / f"{name}.vvp"
    compile_text = run_logged(
        [
            executable("iverilog"),
            "-g2012",
            *(["-Wall"] if strict_width else []),
            "-I",
            str(RTL),
            "-s",
            top,
            "-o",
            str(image),
            *[str(path) for path in sources],
        ],
        ROOT,
        work / "compile.log",
    )
    if strict_width:
        reject_width_warnings(compile_text, f"Icarus {name} compile")
    run_text = run_logged(
        [executable("vvp"), str(image)],
        ROOT,
        work / "run.log",
    )
    for marker in markers:
        require_marker(run_text, marker, f"Icarus {name}")
    return run_text


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    try:
        architecture_text = run_logged(
            [
                sys.executable,
                str(ROOT / "tools/check_stage2h_b2_architecture.py"),
                "--root",
                str(ROOT),
            ],
            ROOT,
            output / "architecture_authority_closure.log",
        )
        require_marker(
            architecture_text,
            "STAGE2H_B2_ARCHITECTURE_AUTHORITY_CLOSURE=PASS",
            "architecture closure",
        )

        source_sources = [
            RTL / "async_fifo_gray.v",
            RTL / "transaction_source_observer.v",
            RTL / "adc_sample_cdc_bridge.v",
            RTL / "source_observability_cdc.v",
            RTL / "transaction_destination_observer.v",
            RTL / "current_compare_dual.v",
            RTL / "sensor_health_monitor.v",
            RTL / "fault_classifier.v",
            RTL / "protection_fsm.v",
            RTL / "pwm_gen.v",
            RTL / "pwm_gate.v",
            RTL / "protection_core_top.v",
            RTL / "protection_reg_bank.v",
            RTL / "protection_ip_top_reg_controlled.v",
            TB / "tb_stage2h_b2_source_protocol.sv",
        ]
        source_text = iverilog_case(
            output,
            "source_protocol",
            "tb_stage2h_b2_source_protocol",
            source_sources,
            (
                "SOURCE_PROTOCOL_BEHAVIOR=PASS",
                "SOURCE_DIAGNOSTIC_POLICY_INTEGRITY_AGREEMENT=PASS",
                "SOURCE_POLICY_RESULT_FROM_DIRECT_PROTOCOL_STATE=YES",
            ),
        )

        destination_sources = [
            RTL / "transaction_destination_observer.v",
            RTL / "current_compare_dual.v",
            RTL / "sensor_health_monitor.v",
            RTL / "fault_classifier.v",
            RTL / "protection_fsm.v",
            RTL / "pwm_gen.v",
            RTL / "pwm_gate.v",
            RTL / "protection_core_top.v",
            RTL / "protection_reg_bank.v",
            RTL / "protection_ip_top_reg_controlled.v",
            TB / "tb_stage2h_b2_destination_sequence.sv",
        ]
        destination_texts = []
        for width in (16, 24, 32):
            destination_texts.append(
                iverilog_case(
                    output,
                    f"destination_sequence_{width}",
                    f"tb_stage2h_b2_destination_sequence_{width}",
                    destination_sources,
                    (
                        f"SEQUENCE_WIDTH_{width}=PASS",
                        "DESTINATION_SEQUENCE_BEHAVIOR=PASS",
                        "POLICY_OBSERVABILITY_SEQUENCE_CLASSIFICATION_AGREEMENT=PASS",
                        "FAULT_EVALUATION_LATENCY_ACLK=3",
                    ),
                    strict_width=True,
                )
            )

        axi_sources = [
            RTL / "reset_release_sync.v",
            RTL / "current_compare_dual.v",
            RTL / "sensor_health_monitor.v",
            RTL / "fault_classifier.v",
            RTL / "protection_fsm.v",
            RTL / "pwm_gen.v",
            RTL / "pwm_gate.v",
            RTL / "protection_core_top.v",
            RTL / "protection_reg_bank.v",
            RTL / "protection_ip_top_reg_controlled.v",
            RTL / "protection_ip_top_axi_lite.v",
            TB / "tb_stage2h_b2_axi_transport.sv",
        ]
        axi_text = iverilog_case(
            output,
            "axi_transport",
            "tb_stage2h_b2_axi_transport",
            axi_sources,
            (
                "AXI_TRANSPORT_PARITY=PASS",
                "AXI_LEGACY_WRAPPER=PASS",
                "AXI_STAGE2G_WRAPPER=PASS",
            ),
        )

        summary = "\n".join(
            [
                "STAGE2H_B2_CONNECTED_BEHAVIORAL_VERIFICATION=PASS",
                "SOURCE_PROTOCOL_BEHAVIOR=PASS",
                "SOURCE_DIAGNOSTIC_POLICY_INTEGRITY_AGREEMENT=PASS",
                "DESTINATION_SEQUENCE_BEHAVIOR=PASS",
                "SEQUENCE_WIDTH_MATRIX=PASS_16_24_32",
                "POLICY_OBSERVABILITY_SEQUENCE_CLASSIFICATION_AGREEMENT=PASS",
                "FAULT_EVALUATION_LATENCY_ACLK=3",
                "FAULT_EVALUATION_LATENCY_PRESERVED=YES",
                "AXI_TRANSPORT_PARITY=PASS",
                "ARCHITECTURE_AUTHORITY_CLOSURE=PASS",
                f"SOURCE_LOG_BYTES={len(source_text.encode('utf-8'))}",
                "DESTINATION_CASE_COUNT=3",
                f"DESTINATION_LOG_BYTES={sum(len(text.encode('utf-8')) for text in destination_texts)}",
                f"AXI_LOG_BYTES={len(axi_text.encode('utf-8'))}",
            ]
        ) + "\n"
        (output / "runner_summary.txt").write_text(
            summary, encoding="utf-8", newline="\n"
        )
        print(summary, end="")
        return 0
    except (OSError, RunnerError) as exc:
        failure = f"STAGE2H_B2_CONNECTED_BEHAVIORAL_VERIFICATION=FAIL: {exc}\n"
        (output / "runner_summary.txt").write_text(
            failure, encoding="utf-8", newline="\n"
        )
        print(failure, end="")
        return 1


if __name__ == "__main__":
    sys.exit(main())
