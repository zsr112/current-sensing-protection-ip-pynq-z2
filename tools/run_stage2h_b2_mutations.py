#!/usr/bin/env python3
"""Run twelve targeted Stage 2H-B2 architecture-boundary mutations."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


ROOT = Path(__file__).resolve().parents[1]
TB = ROOT / "tb/stage2h"


class MutationError(RuntimeError):
    pass


@dataclass(frozen=True)
class Mutation:
    name: str
    proof: str
    apply: Callable[[Path], None]


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count < 1:
        raise MutationError(f"{path.name}: mutation target not found")
    path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")


def replace_last(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise MutationError(f"{path.name}: mutation target not found")
    prefix, suffix = text.rsplit(old, 1)
    path.write_text(prefix + new + suffix, encoding="utf-8", newline="\n")


def make_root(parent: Path) -> Path:
    root = parent / "mutated_root"
    shutil.copytree(ROOT / "rtl", root / "rtl")
    shutil.copytree(ROOT / "spec", root / "spec")
    return root


def run(command: list[str], cwd: Path) -> tuple[int, str]:
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
    return result.returncode, result.stdout


def static_detected(root: Path, log: Path) -> bool:
    code, text = run(
        [
            sys.executable,
            str(ROOT / "tools/check_stage2h_b2_architecture.py"),
            "--root",
            str(root),
        ],
        ROOT,
    )
    log.write_text(text, encoding="utf-8", newline="\n")
    return code != 0 and "ARCHITECTURE_AUTHORITY_CLOSURE=FAIL" in text


def behavioral_detected(
    root: Path,
    log: Path,
    top: str,
    sources: list[str],
    testbench: Path,
) -> bool:
    iverilog = shutil.which("iverilog") or shutil.which("iverilog.exe")
    vvp = shutil.which("vvp") or shutil.which("vvp.exe")
    if not iverilog or not vvp:
        raise MutationError("iverilog/vvp not found")
    image = log.parent / "mutation.vvp"
    compile_code, compile_text = run(
        [
            iverilog,
            "-g2012",
            "-I",
            str(root / "rtl"),
            "-s",
            top,
            "-o",
            str(image),
            *[str(root / "rtl" / name) for name in sources],
            str(testbench),
        ],
        ROOT,
    )
    if compile_code != 0:
        log.write_text(
            "COMPILE_FAILED\n" + compile_text,
            encoding="utf-8",
            newline="\n",
        )
        return True
    run_code, run_text = run([vvp, str(image)], ROOT)
    log.write_text(
        "COMPILE_OUTPUT\n"
        + compile_text
        + "\nRUN_OUTPUT\n"
        + run_text,
        encoding="utf-8",
        newline="\n",
    )
    return run_code != 0 or "=FAIL" in run_text or "FAILED:" in run_text


def mutate_axi_duplicate_state(root: Path) -> None:
    replace_once(
        root / "rtl/protection_ip_top_axi_lite.v",
        "    wire reg_wr_en;\n    wire reg_rd_en;",
        "    reg [1:0] wr_state;\n"
        "    wire reg_wr_en;\n    wire reg_rd_en;",
    )


def mutate_destination_wiring(root: Path) -> None:
    replace_once(
        root / "rtl/protection_ip_top_async_adc_axi_lite.v",
        ".sample_destination_integrity_clean(\n"
        "            destination_expected_delivery),",
        ".sample_destination_integrity_clean(\n"
        "            destination_sequence_gap),",
    )


def mutate_destination_duplicate_state(root: Path) -> None:
    replace_once(
        root / "rtl/protection_core_top.v",
        "    reg accepted_integrity_clean;\n\n"
        "    reg sample_decision_valid;",
        "    reg accepted_integrity_clean;\n"
        "    reg [SEQUENCE_WIDTH-1:0] expected_sample_sequence;\n\n"
        "    reg sample_decision_valid;",
    )


def mutate_first_nonzero_advance(root: Path) -> None:
    replace_once(
        root / "rtl/transaction_destination_observer.v",
        "            else if (sequence_gap)\n"
        "                expected_sequence <= delivery_sequence +",
        "            else if (sequence_gap || stale_first_delivery)\n"
        "                expected_sequence <= delivery_sequence +",
    )


def mutate_gap_no_resync(root: Path) -> None:
    replace_once(
        root / "rtl/transaction_destination_observer.v",
        "            else if (sequence_gap)\n"
        "                expected_sequence <= delivery_sequence +",
        "            else if (1'b0 && sequence_gap)\n"
        "                expected_sequence <= delivery_sequence +",
    )


def mutate_stale_advance(root: Path) -> None:
    replace_once(
        root / "rtl/transaction_destination_observer.v",
        "            else if (sequence_gap)\n"
        "                expected_sequence <= delivery_sequence +",
        "            else if (sequence_gap || reorder_or_stale)\n"
        "                expected_sequence <= delivery_sequence +",
    )


def mutate_latency(root: Path) -> None:
    replace_last(
        root / "rtl/protection_core_top.v",
        "            sample_decision_valid <= accepted_sample_valid;",
        "            sample_decision_valid <= sample_accept_event;",
    )


def mutate_source_second_tracker(root: Path) -> None:
    source = root / "rtl/transaction_source_observer.v"
    tracker = """

module stage2g_source_integrity_tracker #(
    parameter DATA_WIDTH = 12
)(
    input wire clk,
    input wire rst_n,
    input wire source_valid,
    input wire source_ready,
    input wire [DATA_WIDTH-1:0] source_ch1,
    input wire [DATA_WIDTH-1:0] source_ch2,
    output wire integrity_clean
);
    localparam PAYLOAD_WIDTH = 2 * DATA_WIDTH;
    reg stall_pending;
    reg violation_recorded;
    reg [PAYLOAD_WIDTH-1:0] stall_payload_snapshot;
    assign integrity_clean = !violation_recorded;
endmodule
"""
    text = source.read_text(encoding="utf-8")
    source.write_text(text + tracker, encoding="utf-8", newline="\n")
    replace_once(
        root / "rtl/adc_sample_cdc_bridge.v",
        "        .transaction_integrity_clean(source_integrity_clean),",
        "        .transaction_integrity_clean(),",
    )
    bridge = root / "rtl/adc_sample_cdc_bridge.v"
    replace_last(
        bridge,
        "    always @(posedge dst_clk or negedge dst_rst_n) begin\n"
        "        if (!dst_rst_n) begin\n"
        "            destination_data <= {PAYLOAD_WIDTH{1'b0}};",
        "    stage2g_source_integrity_tracker #(.DATA_WIDTH(DATA_WIDTH))\n"
        "        u_source_integrity_tracker (\n"
        "        .clk(src_clk), .rst_n(src_rst_n),\n"
        "        .source_valid(src_sample_valid),\n"
        "        .source_ready(src_sample_ready),\n"
        "        .source_ch1(src_sample_ch1),\n"
        "        .source_ch2(src_sample_ch2),\n"
        "        .integrity_clean(source_integrity_clean)\n"
        "    );\n\n"
        "    always @(posedge dst_clk or negedge dst_rst_n) begin\n"
        "        if (!dst_rst_n) begin\n"
        "            destination_data <= {PAYLOAD_WIDTH{1'b0}};",
    )


def mutate_source_dirty_clean(root: Path) -> None:
    replace_once(
        root / "rtl/transaction_source_observer.v",
        "    assign transaction_integrity_clean =\n"
        "        !(stall_violation_recorded || source_protocol_violation_event);",
        "    assign transaction_integrity_clean = 1'b1;",
    )


def mutate_source_sticky_after_violation(root: Path) -> None:
    replace_once(
        root / "rtl/transaction_source_observer.v",
        "                if (!source_valid || source_accept) begin\n"
        "                    stall_pending <= 1'b0;\n"
        "                    stall_violation_recorded <= 1'b0;\n"
        "                end",
        "                if (!source_valid || source_accept) begin\n"
        "                    stall_pending <= 1'b0;\n"
        "                    stall_violation_recorded <=\n"
        "                        stall_violation_recorded;\n"
        "                end",
    )


def mutate_source_policy_telemetry(root: Path) -> None:
    replace_once(
        root / "rtl/protection_ip_top_async_adc_axi_lite.v",
        ".sample_source_integrity_clean(\n"
        "            dst_sample_integrity_clean),",
        ".sample_source_integrity_clean(\n"
        "            !obs_sticky_status[1]),",
    )


def mutate_axi_bvalid_hold(root: Path) -> None:
    replace_once(
        root / "rtl/protection_ip_top_axi_lite.v",
        "                    if (S_AXI_BVALID && S_AXI_BREADY) begin",
        "                    if (S_AXI_BVALID) begin",
    )


DESTINATION_SOURCES = [
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
]

SOURCE_SOURCES = [
    "async_fifo_gray.v",
    "transaction_source_observer.v",
    "adc_sample_cdc_bridge.v",
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
]

AXI_SOURCES = [
    "reset_release_sync.v",
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


MUTATIONS = (
    Mutation("axi_wrapper_duplicate_state", "static", mutate_axi_duplicate_state),
    Mutation(
        "destination_policy_observability_divergence",
        "static",
        mutate_destination_wiring,
    ),
    Mutation(
        "destination_duplicate_state_reintroduced",
        "static",
        mutate_destination_duplicate_state,
    ),
    Mutation(
        "destination_first_nonzero_advances_expected",
        "destination",
        mutate_first_nonzero_advance,
    ),
    Mutation(
        "destination_gap_fails_resynchronization",
        "destination",
        mutate_gap_no_resync,
    ),
    Mutation(
        "destination_stale_advances_expected",
        "destination",
        mutate_stale_advance,
    ),
    Mutation(
        "destination_latency_changes_one_cycle",
        "destination",
        mutate_latency,
    ),
    Mutation(
        "source_fifo_uses_second_stall_tracker",
        "static",
        mutate_source_second_tracker,
    ),
    Mutation(
        "source_dirty_accepted_reported_clean",
        "source",
        mutate_source_dirty_clean,
    ),
    Mutation(
        "source_clean_after_violation_remains_dirty",
        "source",
        mutate_source_sticky_after_violation,
    ),
    Mutation(
        "source_policy_consumes_sticky_telemetry",
        "static",
        mutate_source_policy_telemetry,
    ),
    Mutation(
        "axi_bvalid_backpressure_hold_lost",
        "axi",
        mutate_axi_bvalid_hold,
    ),
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    results = []
    try:
        with tempfile.TemporaryDirectory(prefix="stage2h_b2_mutations_") as temp:
            temp_root = Path(temp)
            for index, mutation in enumerate(MUTATIONS, start=1):
                case_dir = temp_root / f"{index:02d}_{mutation.name}"
                case_dir.mkdir(parents=True)
                root = make_root(case_dir)
                mutation.apply(root)
                persistent = output / f"{index:02d}_{mutation.name}"
                persistent.mkdir(parents=True, exist_ok=True)
                log = persistent / "detection.log"
                if mutation.proof == "static":
                    detected = static_detected(root, log)
                elif mutation.proof == "destination":
                    detected = behavioral_detected(
                        root,
                        log,
                        "tb_stage2h_b2_destination_sequence_16",
                        DESTINATION_SOURCES,
                        TB / "tb_stage2h_b2_destination_sequence.sv",
                    )
                elif mutation.proof == "source":
                    detected = behavioral_detected(
                        root,
                        log,
                        "tb_stage2h_b2_source_protocol",
                        SOURCE_SOURCES,
                        TB / "tb_stage2h_b2_source_protocol.sv",
                    )
                elif mutation.proof == "axi":
                    detected = behavioral_detected(
                        root,
                        log,
                        "tb_stage2h_b2_axi_transport",
                        AXI_SOURCES,
                        TB / "tb_stage2h_b2_axi_transport.sv",
                    )
                else:
                    raise MutationError(
                        f"unknown mutation proof type {mutation.proof}"
                    )
                results.append((mutation.name, mutation.proof, detected))
                if not detected:
                    raise MutationError(
                        f"mutation escaped detection: {mutation.name}"
                    )
    except (MutationError, OSError) as exc:
        summary = "\n".join(
            [
                *(f"{name}={proof}:{'DETECTED' if detected else 'MISSED'}"
                  for name, proof, detected in results),
                f"TARGETED_B2_MUTATIONS=FAIL: {exc}",
            ]
        ) + "\n"
        (output / "mutation_summary.txt").write_text(
            summary, encoding="utf-8", newline="\n"
        )
        print(summary, end="")
        return 1

    summary = "\n".join(
        [
            *(f"{name}={proof}:DETECTED" for name, proof, _ in results),
            f"TARGETED_B2_MUTATIONS=PASS_{len(results)}_OF_{len(MUTATIONS)}",
        ]
    ) + "\n"
    (output / "mutation_summary.txt").write_text(
        summary, encoding="utf-8", newline="\n"
    )
    print(summary, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
