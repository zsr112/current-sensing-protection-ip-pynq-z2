#!/usr/bin/env python3
"""Create, connect, and kill Stage 2G RTL mutants in real simulators."""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.runtime_config import resolve_vivado_bin
RTL = ROOT / "rtl"
TB = ROOT / "tb/stage2g"
TB_GENERATED = ROOT / "tb/generated"
VIVADO_BIN = resolve_vivado_bin(ROOT)

POLICY_SOURCES = [
    RTL / "fault_classifier.v",
    RTL / "protection_fsm.v",
    TB / "tb_stage2g_policy_matrix.sv",
]
CORE_SOURCES = [
    RTL / "transaction_destination_observer.v",
    RTL / "current_compare_dual.v",
    RTL / "sensor_health_monitor.v",
    RTL / "fault_classifier.v",
    RTL / "protection_fsm.v",
    RTL / "pwm_gen.v",
    RTL / "pwm_gate.v",
    RTL / "protection_core_top.v",
    TB / "tb_stage2g_core_directed.sv",
]
PRODUCTION_NAMES = [
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
PRODUCTION_SOURCES = [RTL / name for name in PRODUCTION_NAMES] + [
    TB / "tb_stage2g_production_path.sv"
]
PREVIOUS_MUTATION_COUNT = 28
RECOVERY_MUTATION_NAMES = {
    "PUBLIC_LATCH_CLEARS_ON_CLEAR_ACCEPTANCE",
    "PUBLIC_CODE_CLEARS_ON_CLEAR_ACCEPTANCE",
    "POST_CLEAR_RESET_WAIT_REPORTS_RECOVERED",
    "NO_SAMPLE_DROPS_COMPATIBILITY_LATCH",
    "NONCLEAN_DROPS_COMPATIBILITY_LATCH",
    "LATER_HEALTHY_FAILS_TO_CLEAR_COMPATIBILITY_STATUS",
    "NEW_FAULT_BEFORE_REARM_FAILS_TO_REPLACE_PUBLIC_CODE",
    "AXI_STATUS_WIRED_TO_INTERNAL_EPISODE_ACTIVE",
}


@dataclass(frozen=True)
class Fixture:
    top: str
    sources: tuple[Path, ...]
    pass_marker: str
    strict_sequence_width: bool = False


@dataclass(frozen=True)
class Mutation:
    name: str
    target: Path
    fixture: str
    coverage: tuple[str, ...]
    transform: Callable[[str], str]


FIXTURES = {
    "policy": Fixture(
        "tb_stage2g_policy_matrix",
        tuple(POLICY_SOURCES),
        "STAGE2G_POLICY_MATRIX=PASS",
    ),
    "core": Fixture(
        "tb_stage2g_core_directed",
        tuple(CORE_SOURCES),
        "STAGE2G_CORE_DIRECTED=PASS",
    ),
    "production": Fixture(
        "tb_stage2g_production_path",
        tuple(PRODUCTION_SOURCES),
        "STAGE2G_PRODUCTION_PATH=PASS",
    ),
}


class MutationError(RuntimeError):
    pass


class MutationKilled(RuntimeError):
    def __init__(self, phase: str) -> None:
        super().__init__(phase)
        self.phase = phase


def replace_exact(
    text: str, old: str, new: str, label: str, *, expected: int = 1
) -> str:
    count = text.count(old)
    if count != expected:
        raise MutationError(
            f"{label}: source anchor count={count}, expected={expected}"
        )
    return text.replace(old, new)


def mutate_module(
    text: str,
    module: str,
    callback: Callable[[str], str],
) -> str:
    match = re.search(rf"\bmodule\s+{re.escape(module)}\b", text)
    if match is None:
        raise MutationError(f"module missing for mutation: {module}")
    end = re.search(r"\bendmodule\b", text[match.end() :])
    if end is None:
        raise MutationError(f"endmodule missing for mutation: {module}")
    end_index = match.end() + end.end()
    original = text[match.start() : end_index]
    mutated = callback(original)
    if mutated == original:
        raise MutationError(f"mutation did not change module: {module}")
    return text[: match.start()] + mutated + text[end_index:]


def module_replacement(
    module: str,
    old: str,
    new: str,
    label: str,
    *,
    expected: int = 1,
) -> Callable[[str], str]:
    return lambda text: mutate_module(
        text,
        module,
        lambda body: replace_exact(
            body, old, new, label, expected=expected
        ),
    )


def module_replacements(
    module: str,
    replacements: tuple[tuple[str, str, str], ...],
) -> Callable[[str], str]:
    def transform(text: str) -> str:
        def apply_all(body: str) -> str:
            for old, new, label in replacements:
                body = replace_exact(body, old, new, label)
            return body

        return mutate_module(text, module, apply_all)

    return transform


PIPELINE = "stage2g_fault_evaluation_pipeline"
CONTROLLER = "stage2g_fault_episode_controller"


def controller_injection(statement: str, label: str) -> Callable[[str], str]:
    anchor = """ST_FAULT_LATCHED: begin
                    fault_latched <= 1'b1;
                    pwm_disable <= 1'b1;
"""
    return module_replacement(
        CONTROLLER,
        anchor,
        anchor + statement,
        label,
    )


ACCEPT_BLOCK = """if (fault_eval_integrity_clean &&
                            (fault_eval_bitmap == 6'd0)) begin
                            state <= ST_RESET_WAIT;
                            fault_latched <= 1'b0;
                            post_clear_recovery_pending <= 1'b1;
                            pwm_disable <= 1'b1;
                            clear_accept_event <= 1'b1;
                            clear_episode_fields();
"""


def mutations() -> list[Mutation]:
    classifier = RTL / "fault_classifier.v"
    controller = RTL / "protection_fsm.v"
    core = RTL / "protection_core_top.v"
    destination = RTL / "transaction_destination_observer.v"
    axi = RTL / "protection_ip_top_axi_lite.v"
    reg_controlled = RTL / "protection_ip_top_reg_controlled.v"
    production = RTL / "protection_ip_top_async_adc_axi_lite.v"

    return [
        Mutation(
            "FAULT_VALID_USED_AS_EVAL_VALID",
            classifier,
            "policy",
            ("fault_valid used as eval_valid",),
            module_replacement(
                PIPELINE,
                "fault_eval_valid <= evaluation_input_valid;",
                "fault_eval_valid <= evaluation_input_valid && "
                "(evaluation_bitmap != 6'd0);",
                "fault-valid-as-eval-valid",
            ),
        ),
        Mutation(
            "ZERO_BITMAP_EVALUATION_DROPPED",
            controller,
            "policy",
            ("zero-bitmap evaluation dropped",),
            module_replacement(
                CONTROLLER,
                "if (fault_eval_valid &&\n                        fault_eval_integrity_clean) begin",
                "if (fault_eval_valid &&\n                        fault_eval_integrity_clean &&\n"
                "                        (fault_eval_bitmap != 6'd0)) begin",
                "zero-bitmap-policy-drop",
            ),
        ),
        Mutation(
            "MISSING_EVALUATION",
            classifier,
            "policy",
            ("missing evaluation",),
            module_replacement(
                PIPELINE,
                "fault_eval_valid <= evaluation_input_valid;",
                "fault_eval_valid <= evaluation_input_valid && "
                "!evaluation_input_sequence[0];",
                "missing-evaluation",
            ),
        ),
        Mutation(
            "DUPLICATE_EVALUATION",
            classifier,
            "policy",
            ("duplicate evaluation",),
            module_replacement(
                PIPELINE,
                "fault_eval_valid <= evaluation_input_valid;",
                "fault_eval_valid <= evaluation_input_valid || "
                "fault_eval_valid;",
                "duplicate-evaluation",
            ),
        ),
        Mutation(
            "SEQUENCE_MISALIGNMENT",
            classifier,
            "policy",
            ("sequence misalignment",),
            module_replacement(
                PIPELINE,
                "fault_eval_sequence <= evaluation_input_sequence;",
                "fault_eval_sequence <= evaluation_input_sequence + 32'd1;",
                "sequence-misalignment",
            ),
        ),
        Mutation(
            "BITMAP_MISALIGNMENT",
            classifier,
            "policy",
            ("bitmap misalignment",),
            module_replacement(
                PIPELINE,
                "fault_eval_bitmap <= evaluation_bitmap;",
                "fault_eval_bitmap <= {evaluation_bitmap[4:0], "
                "evaluation_bitmap[5]};",
                "bitmap-misalignment",
            ),
        ),
        Mutation(
            "CODE_MISALIGNMENT",
            classifier,
            "policy",
            ("code misalignment",),
            module_replacement(
                PIPELINE,
                "fault_eval_code <= priority_encode_bitmap(\n"
                "                    evaluation_bitmap);",
                "fault_eval_code <= priority_encode_bitmap(\n"
                "                    evaluation_bitmap) + 8'd1;",
                "code-misalignment",
            ),
        ),
        Mutation(
            "INTEGRITY_MISALIGNMENT",
            classifier,
            "policy",
            ("integrity misalignment",),
            module_replacement(
                PIPELINE,
                "fault_eval_integrity_clean <=\n"
                "                    evaluation_input_integrity_clean;",
                "fault_eval_integrity_clean <=\n"
                "                    !evaluation_input_integrity_clean;",
                "integrity-misalignment",
            ),
        ),
        Mutation(
            "FIRST_CODE_OVERWRITTEN",
            controller,
            "policy",
            ("first code overwritten",),
            controller_injection(
                """                    if (fault_eval_valid &&
                        fault_eval_integrity_clean)
                        first_fault_code <= fault_eval_code;
""",
                "first-code-overwrite",
            ),
        ),
        Mutation(
            "FIRST_BITMAP_OVERWRITTEN",
            controller,
            "policy",
            ("first bitmap overwritten",),
            controller_injection(
                """                    if (fault_eval_valid &&
                        fault_eval_integrity_clean)
                        first_fault_bitmap <= fault_eval_bitmap;
""",
                "first-bitmap-overwrite",
            ),
        ),
        Mutation(
            "SEEN_BITMAP_ASSIGNED",
            controller,
            "policy",
            ("seen bitmap assigned instead of ORed",),
            module_replacement(
                CONTROLLER,
                "fault_seen_bitmap <= fault_seen_bitmap |\n"
                "                                                 fault_eval_bitmap;",
                "fault_seen_bitmap <= fault_eval_bitmap;",
                "seen-assigned",
                expected=2,
            ),
        ),
        Mutation(
            "PERSISTENT_FAULT_RETRIGGER",
            controller,
            "policy",
            ("persistent retrigger",),
            controller_injection(
                """                    if (fault_eval_valid &&
                        fault_eval_integrity_clean &&
                        (fault_eval_bitmap != 6'd0))
                        first_fault_event <= 1'b1;
""",
                "persistent-retrigger",
            ),
        ),
        Mutation(
            "PRIORITY_REVERSAL",
            classifier,
            "policy",
            ("priority reversal",),
            module_replacement(
                PIPELINE,
                """else if (bitmap[4])
                priority_encode_bitmap = `FAULT_SENSOR_SATURATION;
            else if (bitmap[3])
                priority_encode_bitmap = `FAULT_SENSOR_OPEN;
            else if (bitmap[5])
                priority_encode_bitmap = `FAULT_SENSOR_STUCK;
            else if (bitmap[2])
                priority_encode_bitmap = `FAULT_SENSOR_MISMATCH;
""",
                """else if (bitmap[2])
                priority_encode_bitmap = `FAULT_SENSOR_MISMATCH;
            else if (bitmap[5])
                priority_encode_bitmap = `FAULT_SENSOR_STUCK;
            else if (bitmap[3])
                priority_encode_bitmap = `FAULT_SENSOR_OPEN;
            else if (bitmap[4])
                priority_encode_bitmap = `FAULT_SENSOR_SATURATION;
""",
                "priority-reversal",
            ),
        ),
        Mutation(
            "SIMULTANEOUS_BITMAP_DISCARDED",
            classifier,
            "policy",
            ("simultaneous bitmap discarded",),
            module_replacement(
                PIPELINE,
                "fault_eval_bitmap <= evaluation_bitmap;",
                "fault_eval_bitmap <= {5'd0, |evaluation_bitmap};",
                "simultaneous-bitmap-discarded",
            ),
        ),
        Mutation(
            "STALE_LIVE_BITMAP_ACCEPTS_CLEAR",
            controller,
            "policy",
            ("stale live bitmap accepts clear",),
            module_replacement(
                CONTROLLER,
                "(fault_eval_bitmap == 6'd0)",
                "(live_fault_bitmap == 6'd0)",
                "stale-live-clear",
            ),
        ),
        Mutation(
            "GLOBAL_PIPELINE_EMPTY_CLEAR",
            controller,
            "policy",
            ("global pipeline-empty clear",),
            module_replacement(
                CONTROLLER,
                "if (clear_pending && fault_eval_valid) begin",
                "if (clear_pending) begin",
                "pipeline-empty-clear",
            ),
        ),
        Mutation(
            "HISTORICAL_EVAL_RESOLVES_NEW_CLEAR",
            controller,
            "policy",
            ("pre-request retiring evaluation resolves new clear",),
            module_replacement(
                CONTROLLER,
                """if (!clear_pending && clear_fault)
                            clear_pending <= 1'b1;
""",
                """if (!clear_pending && clear_fault) begin
                            if (live_fault_bitmap == 6'd0) begin
                                state <= ST_RESET_WAIT;
                                fault_latched <= 1'b0;
                                pwm_disable <= 1'b1;
                                clear_pending <= 1'b0;
                                clear_accept_event <= 1'b1;
                                clear_episode_fields();
                            end else begin
                                clear_pending <= 1'b1;
                            end
                        end
""",
                "historical-eval-clear",
            ),
        ),
        Mutation(
            "SAME_EDGE_EVAL_RESOLVES_NEW_CLEAR",
            controller,
            "policy",
            ("same-edge evaluation resolves new clear",),
            module_replacement(
                CONTROLLER,
                "if (clear_pending && fault_eval_valid) begin",
                "if ((clear_pending || clear_fault) && "
                "fault_eval_valid) begin",
                "same-edge-clear",
            ),
        ),
        Mutation(
            "FAULT_CLEAR_ACCEPTED",
            controller,
            "policy",
            ("fault clear accepted",),
            module_replacement(
                CONTROLLER,
                "fault_eval_integrity_clean &&\n"
                "                            (fault_eval_bitmap == 6'd0)",
                "fault_eval_integrity_clean",
                "fault-clear-accepted",
            ),
        ),
        Mutation(
            "NONCLEAN_CLEAR_ACCEPTED",
            controller,
            "policy",
            ("non-clean clear accepted",),
            module_replacement(
                CONTROLLER,
                "fault_eval_integrity_clean &&\n"
                "                            (fault_eval_bitmap == 6'd0)",
                "(fault_eval_bitmap == 6'd0)",
                "nonclean-clear-accepted",
            ),
        ),
        Mutation(
            "CLEAR_RESOLUTION_RELEASES_SAFE",
            controller,
            "policy",
            ("clear resolution releases safe",),
            module_replacement(
                CONTROLLER,
                ACCEPT_BLOCK,
                ACCEPT_BLOCK.replace(
                    "pwm_disable <= 1'b1;", "pwm_disable <= 1'b0;"
                ),
                "clear-releases-safe",
            ),
        ),
        Mutation(
            "CLEAR_RESOLUTION_ARMS",
            controller,
            "policy",
            ("clear resolution also arms",),
            module_replacement(
                CONTROLLER,
                ACCEPT_BLOCK,
                ACCEPT_BLOCK.replace(
                    "state <= ST_RESET_WAIT;", "state <= ST_ARMED;"
                ),
                "clear-arms",
            ),
        ),
        Mutation(
            "SOURCE_REMOVAL_AUTO_CLEARS",
            controller,
            "policy",
            ("source removal auto-clears",),
            controller_injection(
                """                    if (!fault_eval_valid) begin
                        state <= ST_RESET_WAIT;
                        fault_latched <= 1'b0;
                        clear_pending <= 1'b0;
                        clear_episode_fields();
                    end
""",
                "source-removal-clear",
            ),
        ),
        Mutation(
            "RESET_FAILS_TO_CLEAR_PENDING",
            controller,
            "policy",
            ("reset fails to flush",),
            module_replacement(
                CONTROLLER,
                """state <= ST_RESET_WAIT;
            fault_latched <= 1'b0;
            public_fault_latched_compat <= 1'b0;
            public_fault_code_compat <= `FAULT_NONE;
            post_clear_recovery_pending <= 1'b0;
            pwm_disable <= 1'b1;
            clear_pending <= 1'b0;
""",
                """state <= ST_RESET_WAIT;
            fault_latched <= 1'b0;
            public_fault_latched_compat <= 1'b0;
            public_fault_code_compat <= `FAULT_NONE;
            post_clear_recovery_pending <= 1'b0;
            pwm_disable <= 1'b1;
            clear_pending <= clear_pending;
""",
                "reset-pending-not-cleared",
            ),
        ),
        Mutation(
            "PRE_RESET_RETIREMENT_LEAKS",
            classifier,
            "policy",
            ("pre-reset retirement leaks",),
            module_replacement(
                PIPELINE,
                """if (!rst_n) begin
            fault_eval_valid <= 1'b0;
""",
                """if (!rst_n) begin
            fault_eval_valid <= fault_eval_valid;
""",
                "pre-reset-retirement-leak",
            ),
        ),
        Mutation(
            "DELAYED_SOURCE_COUNTER_GATES_POLICY",
            production,
            "production",
            ("delayed source counter gates policy",),
            module_replacement(
                "protection_ip_top_async_adc_axi_lite",
                ".sample_valid(dst_sample_valid),",
                ".sample_valid(dst_sample_valid &&\n"
                "            (obs_source_protocol_violation_count == 32'd0)),",
                "counter-gates-policy",
            ),
        ),
        Mutation(
            "W1C_STICKY_GATES_POLICY",
            production,
            "production",
            ("W1C sticky gates policy",),
            module_replacement(
                "protection_ip_top_async_adc_axi_lite",
                ".sample_source_integrity_clean(\n"
                "            dst_sample_integrity_clean),",
                ".sample_source_integrity_clean(\n"
                "            dst_sample_integrity_clean &&\n"
                "            !(|obs_sticky_status)),",
                "sticky-gates-policy",
            ),
        ),
        Mutation(
            "NORMALIZED_TELEMETRY_GATES_POLICY",
            production,
            "production",
            ("normalized telemetry gates policy",),
            module_replacement(
                "protection_ip_top_async_adc_axi_lite",
                ".sample_valid(dst_sample_valid),",
                ".sample_valid(dst_sample_valid && "
                "normalized_sample_valid),",
                "normalized-gates-policy",
            ),
        ),
        Mutation(
            "PUBLIC_LATCH_CLEARS_ON_CLEAR_ACCEPTANCE",
            controller,
            "production",
            ("public latch clears on clear acceptance",),
            module_replacement(
                CONTROLLER,
                "fault_latched <= 1'b0;\n"
                "                            post_clear_recovery_pending <= 1'b1;",
                "fault_latched <= 1'b0;\n"
                "                            public_fault_latched_compat <= 1'b0;\n"
                "                            post_clear_recovery_pending <= 1'b1;",
                "clear-drops-public-latch",
            ),
        ),
        Mutation(
            "PUBLIC_CODE_CLEARS_ON_CLEAR_ACCEPTANCE",
            controller,
            "production",
            ("public code clears on clear acceptance",),
            module_replacement(
                CONTROLLER,
                "post_clear_recovery_pending <= 1'b1;\n"
                "                            pwm_disable <= 1'b1;",
                "post_clear_recovery_pending <= 1'b1;\n"
                "                            public_fault_code_compat <= `FAULT_NONE;\n"
                "                            pwm_disable <= 1'b1;",
                "clear-drops-public-code",
            ),
        ),
        Mutation(
            "POST_CLEAR_RESET_WAIT_REPORTS_RECOVERED",
            controller,
            "production",
            ("post-clear RESET_WAIT reports recovery verified",),
            module_replacement(
                CONTROLLER,
                "post_clear_recovery_pending <= 1'b1;\n"
                "                            pwm_disable <= 1'b1;",
                "post_clear_recovery_pending <= 1'b1;\n"
                "                            public_fault_latched_compat <= 1'b0;\n"
                "                            public_fault_code_compat <= `FAULT_NONE;\n"
                "                            pwm_disable <= 1'b1;",
                "post-clear-false-recovery",
            ),
        ),
        Mutation(
            "NO_SAMPLE_DROPS_COMPATIBILITY_LATCH",
            controller,
            "production",
            ("no-sample state drops compatibility latch",),
            module_replacement(
                CONTROLLER,
                "ST_RESET_WAIT: begin\n"
                "                    fault_latched <= 1'b0;\n"
                "                    pwm_disable <= 1'b1;",
                "ST_RESET_WAIT: begin\n"
                "                    fault_latched <= 1'b0;\n"
                "                    if (!fault_eval_valid)\n"
                "                        public_fault_latched_compat <= 1'b0;\n"
                "                    pwm_disable <= 1'b1;",
                "no-sample-drops-public-latch",
            ),
        ),
        Mutation(
            "NONCLEAN_DROPS_COMPATIBILITY_LATCH",
            controller,
            "production",
            ("non-clean evaluation drops compatibility latch",),
            module_replacement(
                CONTROLLER,
                "ST_RESET_WAIT: begin\n"
                "                    fault_latched <= 1'b0;\n"
                "                    pwm_disable <= 1'b1;",
                "ST_RESET_WAIT: begin\n"
                "                    fault_latched <= 1'b0;\n"
                "                    if (fault_eval_valid &&\n"
                "                        !fault_eval_integrity_clean)\n"
                "                        public_fault_latched_compat <= 1'b0;\n"
                "                    pwm_disable <= 1'b1;",
                "nonclean-drops-public-latch",
            ),
        ),
        Mutation(
            "LATER_HEALTHY_FAILS_TO_CLEAR_COMPATIBILITY_STATUS",
            controller,
            "production",
            ("later healthy fails to clear compatibility status",),
            module_replacements(
                CONTROLLER,
                (
                    (
                        "state <= ST_ARMED;\n"
                        "                            public_fault_latched_compat <= 1'b0;\n"
                        "                            public_fault_code_compat <= `FAULT_NONE;\n"
                        "                            post_clear_recovery_pending <= 1'b0;",
                        "state <= ST_ARMED;\n"
                        "                            public_fault_latched_compat <= public_fault_latched_compat;\n"
                        "                            public_fault_code_compat <= public_fault_code_compat;\n"
                        "                            post_clear_recovery_pending <= 1'b0;",
                        "healthy-transition-retains-public-status",
                    ),
                    (
                        "ST_ARMED: begin\n"
                        "                    fault_latched <= 1'b0;\n"
                        "                    public_fault_latched_compat <= 1'b0;\n"
                        "                    public_fault_code_compat <= `FAULT_NONE;",
                        "ST_ARMED: begin\n"
                        "                    fault_latched <= 1'b0;\n"
                        "                    public_fault_latched_compat <= public_fault_latched_compat;\n"
                        "                    public_fault_code_compat <= public_fault_code_compat;",
                        "armed-hold-retains-public-status",
                    ),
                ),
            ),
        ),
        Mutation(
            "NEW_FAULT_BEFORE_REARM_FAILS_TO_REPLACE_PUBLIC_CODE",
            controller,
            "production",
            ("new fault before re-arm fails to replace public code",),
            module_replacement(
                CONTROLLER,
                "public_fault_code_compat <= fault_eval_code;",
                "public_fault_code_compat <= post_clear_recovery_pending ?\n"
                "                public_fault_code_compat : fault_eval_code;",
                "pre-rearm-fault-retains-old-code",
            ),
        ),
        Mutation(
            "AXI_STATUS_WIRED_TO_INTERNAL_EPISODE_ACTIVE",
            reg_controlled,
            "production",
            ("AXI status wired to internal episode-active state",),
            module_replacement(
                "stage2g_protection_ip_reg_controlled",
                ".fault_valid(fault_valid),\n"
                "        .fault_latched(fault_latched),\n"
                "        .fault_code_latched(fault_code_latched),",
                ".fault_valid(fault_valid),\n"
                "        .fault_latched(fsm_state == 4'd1),\n"
                "        .fault_code_latched(fault_code_latched),",
                "register-status-uses-internal-episode",
            ),
        ),
    ]


def run_process(
    args: list[str], cwd: Path, log: Path
) -> subprocess.CompletedProcess[str]:
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
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(result.stdout, encoding="utf-8", newline="\n")
    return result


def sequence_width_warnings(text: str) -> list[str]:
    offenders = []
    for line in text.splitlines():
        if not re.search(r"warning|warn", line, flags=re.IGNORECASE):
            continue
        if re.search(
            r"width|bit\s+length|port|formal|resize|trunc|extend|padding|"
            r"out[- ]of[- ]range|select",
            line,
            flags=re.IGNORECASE,
        ):
            offenders.append(line.strip())
    return offenders


def reject_or_kill_compile(
    result: subprocess.CompletedProcess[str],
    *,
    label: str,
    allow_kill: bool,
    strict_sequence_width: bool,
) -> None:
    if result.returncode != 0:
        if allow_kill:
            raise MutationKilled("COMPILE")
        raise MutationError(f"{label} did not compile")
    if strict_sequence_width:
        warnings = sequence_width_warnings(result.stdout)
        if warnings:
            if allow_kill:
                raise MutationKilled("WIDTH_WARNING")
            raise MutationError(
                f"{label} emitted sequence-width warning(s): "
                + " | ".join(warnings)
            )


def replace_source(
    sources: tuple[Path, ...], target: Path, replacement: Path
) -> list[Path]:
    result = [replacement if path == target else path for path in sources]
    if replacement not in result:
        raise MutationError(f"mutated target is not connected: {target}")
    return result


def compile_icarus(
    fixture: Fixture,
    sources: list[Path],
    work: Path,
    *,
    allow_kill: bool = False,
) -> Path:
    iverilog = shutil.which("iverilog") or shutil.which("iverilog.exe")
    if not iverilog:
        raise MutationError("Icarus compiler not found")
    work.mkdir(parents=True, exist_ok=True)
    image = work / "case.vvp"
    result = run_process(
        [
            iverilog,
            "-g2012",
            *(["-Wall"] if fixture.strict_sequence_width else []),
            "-I",
            str(RTL),
            "-I",
            str(TB_GENERATED),
            "-s",
            fixture.top,
            "-o",
            str(image),
            *[str(path) for path in sources],
        ],
        work,
        work / "compile.log",
    )
    reject_or_kill_compile(
        result,
        label=f"Icarus fixture at {work}",
        allow_kill=allow_kill,
        strict_sequence_width=fixture.strict_sequence_width,
    )
    return image


def run_icarus(image: Path, work: Path) -> subprocess.CompletedProcess[str]:
    vvp = shutil.which("vvp") or shutil.which("vvp.exe")
    if not vvp:
        raise MutationError("Icarus runtime not found")
    return run_process([vvp, str(image)], work, work / "run.log")


def compile_xsim(
    fixture: Fixture,
    sources: list[Path],
    work: Path,
    *,
    allow_kill: bool = False,
) -> str:
    if VIVADO_BIN is None:
        raise MutationError('XSim is not configured')
    xvlog = VIVADO_BIN / "xvlog.bat"
    xelab = VIVADO_BIN / "xelab.bat"
    if not xvlog.is_file() or not xelab.is_file():
        raise MutationError("XSim compiler/elaborator not found")
    work.mkdir(parents=True, exist_ok=True)
    compile_result = run_process(
        [
            str(xvlog),
            "--sv",
            "-i",
            str(RTL),
            "-i",
            str(TB_GENERATED),
            "--log",
            str(work / "xvlog.log"),
            *[str(path) for path in sources],
        ],
        work,
        work / "xvlog.console.log",
    )
    reject_or_kill_compile(
        compile_result,
        label=f"XSim fixture at {work}",
        allow_kill=allow_kill,
        strict_sequence_width=fixture.strict_sequence_width,
    )
    snapshot = "mutation_snapshot"
    elaboration = run_process(
        [
            str(xelab),
            f"work.{fixture.top}",
            "-s",
            snapshot,
            "--timescale",
            "1ns/1ps",
            "--log",
            str(work / "xelab.log"),
        ],
        work,
        work / "xelab.console.log",
    )
    if elaboration.returncode != 0:
        if allow_kill:
            raise MutationKilled("ELABORATION")
        raise MutationError(f"XSim fixture did not elaborate: {work}")
    if fixture.strict_sequence_width:
        warnings = sequence_width_warnings(elaboration.stdout)
        if warnings:
            if allow_kill:
                raise MutationKilled("WIDTH_WARNING")
            raise MutationError(
                f"XSim fixture at {work} emitted sequence-width warning(s): "
                + " | ".join(warnings)
            )
    return snapshot


def run_xsim(snapshot: str, work: Path) -> subprocess.CompletedProcess[str]:
    xsim = VIVADO_BIN / "xsim.bat"
    if not xsim.is_file():
        raise MutationError("XSim runtime not found")
    return run_process(
        [
            str(xsim),
            snapshot,
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


def assert_control(
    result: subprocess.CompletedProcess[str], fixture: Fixture, label: str
) -> None:
    failure_marker = re.search(
        r"(?:^|\n)(?:FAIL(?:ED)?|FATAL|Error:|Fatal:)",
        result.stdout,
        re.IGNORECASE,
    )
    if (
        result.returncode != 0
        or fixture.pass_marker not in result.stdout
        or failure_marker is not None
    ):
        raise MutationError(f"{label} control oracle failed")


def assert_killed(
    result: subprocess.CompletedProcess[str], fixture: Fixture, label: str
) -> None:
    failure_marker = re.search(
        r"(?:FAIL(?:ED)?|FATAL|Error:|Fatal:)", result.stdout, re.IGNORECASE
    )
    # Vivado XSim reports an HDL $fatal in its transcript but, under some
    # launcher combinations, continues to the following statements and exits
    # zero.  The explicit FAIL/FATAL oracle is therefore authoritative; a
    # compile/elaboration failure is rejected earlier and never counted.
    if failure_marker is None:
        raise MutationError(f"{label} mutation survived or was not observed")


def validated_mutations() -> list[Mutation]:
    items = mutations()
    names = [item.name for item in items]
    if len(names) != len(set(names)):
        raise MutationError("mutation inventory contains duplicate names")
    if len(items) != PREVIOUS_MUTATION_COUNT + len(RECOVERY_MUTATION_NAMES):
        raise MutationError("mutation inventory count changed unexpectedly")
    previous = set(names[:PREVIOUS_MUTATION_COUNT])
    recovery = set(names) & RECOVERY_MUTATION_NAMES
    if (
        previous & RECOVERY_MUTATION_NAMES
        or recovery != RECOVERY_MUTATION_NAMES
    ):
        raise MutationError("previous/recovery mutation partition mismatch")
    return items


def run(output: Path, *, include_xsim: bool) -> tuple[int, int]:
    if output.exists():
        raise MutationError(f"output must not already exist: {output}")
    output.mkdir(parents=True)
    items = validated_mutations()
    rows = [
        "NAME\tGROUP\tFIXTURE\tTARGET\tSHA256\tCOVERAGE\tICARUS\tXSIM"
    ]

    # Each oracle must first demonstrate that the unmodified RTL survives.
    used_fixtures = sorted({item.fixture for item in items})
    for fixture_name in used_fixtures:
        fixture = FIXTURES[fixture_name]
        control = output / "controls" / fixture_name / "icarus"
        image = compile_icarus(fixture, list(fixture.sources), control)
        assert_control(run_icarus(image, control), fixture, f"Icarus {fixture_name}")
        if include_xsim:
            xsim_work = output / "controls" / fixture_name / "xsim"
            snapshot = compile_xsim(fixture, list(fixture.sources), xsim_work)
            assert_control(
                run_xsim(snapshot, xsim_work), fixture, f"XSim {fixture_name}"
            )

    killed_icarus = 0
    killed_xsim = 0
    previous_icarus = 0
    previous_xsim = 0
    recovery_icarus = 0
    recovery_xsim = 0
    for item in items:
        fixture = FIXTURES[item.fixture]
        recovery_mutation = item.name in RECOVERY_MUTATION_NAMES
        source_text = item.target.read_text(encoding="utf-8")
        mutant_text = item.transform(source_text)
        digest = hashlib.sha256(mutant_text.encode("utf-8")).hexdigest()
        case_root = output / "mutants" / item.name.lower()
        mutant_source = case_root / "source" / item.target.name
        mutant_source.parent.mkdir(parents=True)
        mutant_source.write_text(mutant_text, encoding="utf-8", newline="\n")
        sources = replace_source(fixture.sources, item.target, mutant_source)

        icarus_work = case_root / "icarus"
        try:
            image = compile_icarus(
                fixture,
                sources,
                icarus_work,
                allow_kill=False,
            )
            result = run_icarus(image, icarus_work)
            assert_killed(result, fixture, f"Icarus {item.name}")
            icarus_status = "KILLED_RUNTIME"
        except MutationKilled as exc:
            icarus_status = f"KILLED_{exc.phase}"
        killed_icarus += 1
        if recovery_mutation:
            recovery_icarus += 1
        else:
            previous_icarus += 1

        xsim_status = "NOT_REQUESTED"
        if include_xsim:
            xsim_work = case_root / "xsim"
            try:
                snapshot = compile_xsim(
                    fixture,
                    sources,
                    xsim_work,
                    allow_kill=False,
                )
                result = run_xsim(snapshot, xsim_work)
                assert_killed(result, fixture, f"XSim {item.name}")
                xsim_status = "KILLED_RUNTIME"
            except MutationKilled as exc:
                xsim_status = f"KILLED_{exc.phase}"
            killed_xsim += 1
            if recovery_mutation:
                recovery_xsim += 1
            else:
                previous_xsim += 1
        rows.append(
            "\t".join(
                (
                    item.name,
                    "RECOVERY" if recovery_mutation else "PREVIOUS",
                    item.fixture,
                    item.target.relative_to(ROOT).as_posix(),
                    digest,
                    ";".join(item.coverage),
                    icarus_status,
                    xsim_status,
                )
            )
        )

    (output / "mutation_inventory.tsv").write_text(
        "\n".join(rows) + "\n", encoding="utf-8", newline="\n"
    )
    summary = [
        f"MUTATION_CONNECTED_FIXTURES=PASS_{killed_icarus}_OF_{killed_icarus}",
        "PREVIOUS_MUTATION_CONNECTED_FIXTURES="
        f"PASS_{previous_icarus}_OF_{PREVIOUS_MUTATION_COUNT}",
        "OBSOLETE_STAGE2G_SEQUENCE_MUTATIONS="
        "SUPERSEDED_BY_B2_CONNECTED_SUITE",
        "RECOVERY_OBSERVABILITY_MUTATION_FIXTURES="
        f"PASS_{recovery_icarus}_OF_{len(RECOVERY_MUTATION_NAMES)}",
        f"ICARUS_MUTATIONS=PASS_{killed_icarus}_OF_{killed_icarus}",
        f"ICARUS_PREVIOUS_MUTATIONS=PASS_{previous_icarus}_OF_"
        f"{PREVIOUS_MUTATION_COUNT}",
        f"ICARUS_RECOVERY_MUTATIONS=PASS_{recovery_icarus}_OF_"
        f"{len(RECOVERY_MUTATION_NAMES)}",
        (
            f"XSIM_MUTATIONS=PASS_{killed_xsim}_OF_{killed_xsim}"
            if include_xsim
            else "XSIM_MUTATIONS=NOT_REQUESTED"
        ),
        (
            f"XSIM_PREVIOUS_MUTATIONS=PASS_{previous_xsim}_OF_"
            f"{PREVIOUS_MUTATION_COUNT}"
            if include_xsim
            else "XSIM_PREVIOUS_MUTATIONS=NOT_REQUESTED"
        ),
        (
            f"XSIM_RECOVERY_MUTATIONS=PASS_{recovery_xsim}_OF_"
            f"{len(RECOVERY_MUTATION_NAMES)}"
            if include_xsim
            else "XSIM_RECOVERY_MUTATIONS=NOT_REQUESTED"
        ),
        f"MUTATION_INVENTORY={output / 'mutation_inventory.tsv'}",
    ]
    (output / "mutation_results.txt").write_text(
        "\n".join(summary) + "\n", encoding="utf-8", newline="\n"
    )
    return killed_icarus, killed_xsim


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--xsim", action="store_true")
    args = parser.parse_args(argv)
    try:
        icarus_count, xsim_count = run(
            args.output.resolve(), include_xsim=args.xsim
        )
    except (OSError, MutationError) as exc:
        print(f"STAGE2G_MUTATION_CONNECTED=FAIL: {exc}", file=sys.stderr)
        return 1
    print(
        f"MUTATION_CONNECTED_FIXTURES=PASS_{icarus_count}_OF_{icarus_count}"
    )
    print(
        "PREVIOUS_MUTATION_CONNECTED_FIXTURES="
        f"PASS_{PREVIOUS_MUTATION_COUNT}_OF_{PREVIOUS_MUTATION_COUNT}"
    )
    print("OBSOLETE_STAGE2G_SEQUENCE_MUTATIONS=SUPERSEDED_BY_B2_CONNECTED_SUITE")
    print(
        "RECOVERY_OBSERVABILITY_MUTATION_FIXTURES="
        f"PASS_{len(RECOVERY_MUTATION_NAMES)}_OF_{len(RECOVERY_MUTATION_NAMES)}"
    )
    print(f"ICARUS_MUTATIONS=PASS_{icarus_count}_OF_{icarus_count}")
    if args.xsim:
        print(f"XSIM_MUTATIONS=PASS_{xsim_count}_OF_{xsim_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
