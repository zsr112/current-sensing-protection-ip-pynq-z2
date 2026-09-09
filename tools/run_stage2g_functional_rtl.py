#!/usr/bin/env python3
"""Run the Stage 2G functional RTL and invariance verification matrix."""

from __future__ import annotations

import argparse
import ast
import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path

try:
    from tools.runtime_config import optional_git_identity, resolve_tool, resolve_vivado_bin
except ModuleNotFoundError:
    from runtime_config import optional_git_identity, resolve_tool, resolve_vivado_bin  # type: ignore


ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"
TB = ROOT / "tb/stage2g"
TB_STAGE2E = ROOT / "tb/stage2e"
TB_STAGE2H = ROOT / "tb/stage2h"
TB_STAGE2I = ROOT / "tb/stage2i"
TB_GENERATED = ROOT / "tb/generated"
HISTORICAL_STAGE2G_REPLAY_REQUIRED_RUNTIME = "CPython_3_12"
STAGE2I_B_REVIEWED_CANDIDATE = "cde94b6cee8bd4423e7cf0e03b35a9596a666dd4"

STAGE2E_CONNECTED_MUTATIONS = (
    (
        "backpressure_drop",
        "01_BACKPRESSURE_COUNTED_AS_DROP",
        "BACKPRESSURE_MISCLASSIFIED_AS_DROP",
    ),
    (
        "withdrawal",
        "02_VALID_WITHDRAWAL_NOT_RECORDED",
        "VALID_WITHDRAWAL_NOT_RECORDED",
    ),
    (
        "payload_change",
        "03_PAYLOAD_CHANGE_NOT_RECORDED",
        "STALLED_PAYLOAD_CHANGE_NOT_RECORDED",
    ),
    (
        "episode_recount",
        "04_STALL_EPISODE_RECOUNTED",
        "STALL_EPISODE_RECOUNTED",
    ),
    (
        "payload_identity",
        "05_PAYLOAD_EQUALITY_USED_AS_DUPLICATE_IDENTITY",
        "PAYLOAD_EQUALITY_USED_AS_IDENTITY",
    ),
    (
        "nonatomic_sequence",
        "06_SEQUENCE_NOT_ATOMIC_WITH_PAYLOAD",
        "SEQUENCE_NOT_ATOMIC_WITH_PAYLOAD",
    ),
    (
        "accept_sequence",
        "07_SEQUENCE_NOT_INCREMENTED_ON_ACCEPTANCE",
        "SEQUENCE_NOT_INCREMENTED_ON_ACCEPTANCE",
    ),
    (
        "delivery_accounting",
        "08_DELIVERY_ACCOUNTING_MISMATCH",
        "DESTINATION_DELIVERY_COUNT_MISMATCH",
    ),
    ("gap", "09_FORWARD_GAP_NOT_RECORDED", "FORWARD_GAP_NOT_RECORDED"),
    (
        "stale_reorder",
        "10_SEQUENCE_RELATIVE_STALE_REORDER_NOT_RECORDED",
        "SEQUENCE_RELATIVE_STALE_OR_REORDER_NOT_RECORDED",
    ),
    (
        "binary_cdc",
        "11_BINARY_COUNTER_BUS_SYNCHRONIZED_PER_BIT",
        "BINARY_COUNTER_CDC_OR_UNREGISTERED_GRAY",
    ),
    (
        "pulse_cdc",
        "12_SOURCE_SHORT_PULSE_DIRECTLY_SYNCHRONIZED",
        "SHORT_SOURCE_PULSE_DIRECTLY_SYNCHRONIZED",
    ),
    (
        "counter_wrap",
        "13_COUNTER_WRAPS",
        "DIAGNOSTIC_COUNTER_WRAPPED_OR_SATURATION_HIDDEN",
    ),
    (
        "w1c_race",
        "14_W1C_LOSES_SAME_CYCLE_EVENT",
        "W1C_LOST_SAME_CYCLE_EVENT",
    ),
    (
        "any_error_backpressure",
        "15_ANY_ERROR_INCLUDES_LEGAL_BACKPRESSURE",
        "ANY_ERROR_INCLUDES_LEGAL_BACKPRESSURE",
    ),
    (
        "writable_counter",
        "16_READ_ONLY_COUNTER_WRITABLE",
        "READ_ONLY_COUNTER_IS_WRITABLE",
    ),
    (
        "reset_nonzero",
        "17_RESET_STATE_NONZERO",
        "OBSERVABILITY_RESET_STATE_NONZERO",
    ),
    (
        "wrap_misclassified",
        "18_LEGAL_SEQUENCE_WRAP_MISCLASSIFIED",
        "LEGAL_SEQUENCE_WRAP_MISCLASSIFIED",
    ),
)


class RunnerError(RuntimeError):
    pass


def run_logged(
    command: list[str], cwd: Path, log: Path, *, env: dict[str, str] | None = None
) -> tuple[int, str]:
    log.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    log.write_text(result.stdout, encoding="utf-8", newline="\n")
    return result.returncode, result.stdout


def require_marker(
    code: int, text: str, marker: str, label: str, *, reject: tuple[str, ...] = ()
) -> None:
    if code != 0:
        raise RunnerError(f"{label} exited {code}")
    if marker not in text:
        raise RunnerError(f"{label} omitted marker {marker!r}")
    for token in reject:
        if token in text:
            raise RunnerError(f"{label} contains failure token {token!r}")


def reject_sequence_width_warnings(text: str, label: str) -> None:
    """Fail on any compiler diagnostic that can imply sequence resizing."""

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
    if offenders:
        raise RunnerError(
            f"{label} emitted sequence-width compiler warning(s): "
            + " | ".join(offenders)
        )


def require_cdc_event_authority_markers(text: str, label: str) -> None:
    for marker in (
        "SINGLE_TRANSACTION_CYCLE_TRACE=PASS",
        "BACK_TO_BACK_TRANSACTIONS=PASS",
        "CONTINUOUS_TRAFFIC=PASS",
        "DESTINATION_PAUSE_RESUME=PASS",
        "FIFO_EMPTY_TO_NONEMPTY=PASS",
        "FIFO_FULL_TO_RESUME=PASS",
        "SEQUENCE_WRAP=PASS_FFFE_FFFF_0000",
        "NO_GHOST_DESTINATION_DELIVERY_AFTER_RESET=PASS",
        "NO_STALE_PREFETCH_REPLAY_AFTER_RESET=PASS",
        "FIRST_POST_RESET_TRANSACTION_EXACTLY_ONCE=PASS",
        "PREFETCH_BEFORE_CLEAR_DELIVERY_SAME_CLEAR_EDGE=PASS",
        "PREFETCH_BEFORE_CLEAR_DELIVERY_AFTER_CLEAR=PASS",
        "DELIVERY_BEFORE_CLEAR=PASS",
        "DELIVERY_SAME_CLEAR_EDGE=PASS",
        "EVALUATION_RETIREMENT_SAME_CLEAR_EDGE=PASS",
        "EVALUATION_RETIREMENT_STRICTLY_AFTER_CLEAR=PASS",
        "CLEAR_FENCE_ORDER=EVALUATION_RETIREMENT",
        "PRE_REQUEST_RETIREMENT_RESOLVES_CLEAR=NO",
        "INTERNAL_FIFO_PREFETCH_EVENT=IMPLEMENTATION_DETAIL_NOT_POLICY_AUTHORITY",
        (
            "ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT="
            "DST_SAMPLE_VALID_ACCEPTED_EDGE"
        ),
        "STAGE2B_N0=ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT",
        (
            "STAGE2G_SAMPLE_EVENT_AUTHORITY="
            "ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT"
        ),
        "STAGE2G_DELIVERY_TO_POLICY_LATENCY_ACLK=3",
        "PIPELINE_INITIATION_INTERVAL=1",
        "CDC_EVENT_AUTHORITY_CHARACTERIZATION=PASS",
    ):
        require_marker(0, text, marker, label)


def resolve(name: str) -> str:
    value = resolve_tool(ROOT, name, aliases=(f"{name}.exe",))
    if not value:
        raise RunnerError(f"required executable not found: {name}")
    return str(value)


def iverilog_case(
    output: Path,
    name: str,
    top: str,
    sources: list[Path],
    marker: str,
    plusargs: list[str] | None = None,
    run_cwd: Path | None = None,
    strict_sequence_width: bool = False,
) -> str:
    work = output / "icarus" / name
    work.mkdir(parents=True, exist_ok=True)
    iverilog = resolve("iverilog")
    vvp = resolve("vvp")
    image = work / f"{name}.vvp"
    compile_command = [
            iverilog,
            "-g2012",
            *(["-Wall"] if strict_sequence_width else []),
            "-I",
            str(RTL),
            "-I",
            str(TB_GENERATED),
            "-s",
            top,
            "-o",
            str(image),
            *[str(path) for path in sources],
        ]
    code, text = run_logged(
        compile_command,
        work,
        work / "compile.log",
    )
    require_marker(code, text, "", f"Icarus {name} compile")
    if strict_sequence_width:
        reject_sequence_width_warnings(text, f"Icarus {name} compile")
    waves = work / 'waves'
    waves.mkdir(exist_ok=True)
    args = [vvp, str(image), '+CSIP_WAVE_DIR=' + waves.as_posix()] + (plusargs or [])
    code, text = run_logged(args, run_cwd or work, work / "run.log")
    require_marker(
        code,
        text,
        marker,
        f"Icarus {name}",
        reject=(
            "STAGE2G_POLICY_MATRIX=FAIL",
            "STAGE2G_CORE_DIRECTED=FAIL",
            "STAGE2G_PRODUCTION_PATH=FAIL",
            "STAGE2G_SEQUENCE_MATRIX=FAIL",
            "REFERENCE_MODEL_COMPARISON=FAIL",
        ),
    )
    return text


def xsim_case(
    output: Path,
    name: str,
    top: str,
    sources: list[Path],
    marker: str,
    *,
    vivado_bin: Path,
    vector_file: Path | None = None,
    strict_sequence_width: bool = False,
) -> str:
    work = output / "xsim" / name
    work.mkdir(parents=True, exist_ok=True)
    xvlog = vivado_bin / "xvlog.bat"
    xelab = vivado_bin / "xelab.bat"
    xsim = vivado_bin / "xsim.bat"
    if not all(path.is_file() for path in (xvlog, xelab, xsim)):
        raise RunnerError(f"XSim tools missing below {vivado_bin}")
    if vector_file is not None:
        shutil.copy2(vector_file, work / "vectors.txt")
    code, text = run_logged(
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
    require_marker(code, text, "", f"XSim {name} compile")
    if strict_sequence_width:
        reject_sequence_width_warnings(text, f"XSim {name} compile")
    snapshot = f"{name}_snapshot"
    code, text = run_logged(
        [
            str(xelab),
            f"work.{top}",
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
    require_marker(code, text, "", f"XSim {name} elaboration")
    if strict_sequence_width:
        reject_sequence_width_warnings(text, f"XSim {name} elaboration")
    args = [
        str(xsim),
        snapshot,
        "-runall",
        "--onerror",
        "quit",
        "--onfinish",
        "quit",
        "--log",
        str(work / "xsim.log"),
    ]
    if vector_file is not None:
        args += ["--testplusarg", "VECTORS"]
    code, text = run_logged(args, work, work / "xsim.console.log")
    # XSim may return zero after an HDL $fatal; explicit FAIL markers remain
    # authoritative for these fixtures.
    if marker not in text:
        raise RunnerError(f"XSim {name} omitted marker {marker!r}")
    failure_tokens = (
        "STAGE2G_POLICY_MATRIX=FAIL",
        "STAGE2G_CORE_DIRECTED=FAIL",
        "STAGE2G_PRODUCTION_PATH=FAIL",
        "STAGE2G_SEQUENCE_MATRIX=FAIL",
        "REFERENCE_MODEL_COMPARISON=FAIL",
    )
    if any(token in text for token in failure_tokens):
        raise RunnerError(f"XSim {name} contains a fixture failure marker")
    return text


def stage2e_connected_mutation_regression(
    output: Path, vivado_bin: Path, *, include_xsim: bool
) -> None:
    sources = [
        RTL / "transaction_source_observer.v",
        RTL / "transaction_destination_observer.v",
        RTL / "protection_reg_bank.v",
        TB_STAGE2E / "stage2e_transaction_observability_checker.sv",
        TB_STAGE2E / "tb_stage2e_mutation_connected.sv",
    ]
    summary = []
    control_text = iverilog_case(
        output,
        "stage2e_mutation_control",
        "tb_stage2e_mutation_control",
        sources,
        "MUTATION_CONNECTED_CONTROL=PASS_18_BEHAVIORS",
    )
    require_marker(
        0,
        control_text,
        "MUTATION_ID=CONTROL",
        "Icarus Stage2E connected mutation control",
    )
    summary.append("IVERILOG_CONTROL=PASS")

    iverilog = resolve("iverilog")
    vvp = resolve("vvp")
    for suffix, mutation_id, reason in STAGE2E_CONNECTED_MUTATIONS:
        top = f"tb_stage2e_mutation_{suffix}"
        work = output / "icarus" / f"stage2e_mutation_{suffix}"
        work.mkdir(parents=True, exist_ok=True)
        image = work / f"{suffix}.vvp"
        code, text = run_logged(
            [
                iverilog,
                "-g2012",
                "-I",
                str(RTL),
                "-s",
                top,
                "-o",
                str(image),
                *[str(path) for path in sources],
            ],
            work,
            work / "compile.log",
        )
        if code != 0:
            raise RunnerError(f"Icarus Stage2E mutation {mutation_id} failed compile")
        code, text = run_logged(
            [vvp, str(image)], work, work / "run.log"
        )
        required = (
            f"MUTATION_ID={mutation_id}",
            "MUTATION_CHANGED_BEHAVIOR=",
            f"MUTATION_EXPECTED_REJECTION={reason}",
            f"STAGE2E CHECK FAILED: {reason}",
        )
        if code == 0 or any(marker not in text for marker in required):
            raise RunnerError(
                f"Icarus Stage2E mutation {mutation_id} was not rejected"
            )
        summary.append(f"IVERILOG_{mutation_id}=PASS")

    if include_xsim:
        work = output / "xsim" / "stage2e_connected_mutations"
        work.mkdir(parents=True, exist_ok=True)
        xvlog = vivado_bin / "xvlog.bat"
        xelab = vivado_bin / "xelab.bat"
        xsim = vivado_bin / "xsim.bat"
        if not all(path.is_file() for path in (xvlog, xelab, xsim)):
            raise RunnerError(f"XSim tools missing below {vivado_bin}")
        code, text = run_logged(
            [
                str(xvlog),
                "--sv",
                "-i",
                str(RTL),
                "--log",
                str(work / "xvlog.log"),
                *[str(path) for path in sources],
            ],
            work,
            work / "xvlog.console.log",
        )
        if code != 0:
            raise RunnerError("XSim Stage2E connected mutations failed compile")

        xsim_cases = (("control", "CONTROL", "NONE"),) + tuple(
            STAGE2E_CONNECTED_MUTATIONS
        )
        for suffix, mutation_id, reason in xsim_cases:
            top = f"tb_stage2e_mutation_{suffix}"
            snapshot = f"stage2e_mutation_{suffix}_snapshot"
            code, text = run_logged(
                [
                    str(xelab),
                    f"work.{top}",
                    "-s",
                    snapshot,
                    "--timescale",
                    "1ns/1ps",
                    "--log",
                    str(work / f"{suffix}.xelab.log"),
                ],
                work,
                work / f"{suffix}.xelab.console.log",
            )
            if code != 0:
                raise RunnerError(
                    f"XSim Stage2E mutation {mutation_id} failed elaboration"
                )
            code, text = run_logged(
                [
                    str(xsim),
                    snapshot,
                    "-runall",
                    "--onerror",
                    "quit",
                    "--onfinish",
                    "quit",
                    "--log",
                    str(work / f"{suffix}.xsim.log"),
                ],
                work,
                work / f"{suffix}.xsim.console.log",
            )
            if suffix == "control":
                required = (
                    "MUTATION_ID=CONTROL",
                    "MUTATION_CONNECTED_CONTROL=PASS_18_BEHAVIORS",
                )
                if code != 0 or any(marker not in text for marker in required):
                    raise RunnerError("XSim Stage2E mutation control failed")
            else:
                required = (
                    f"MUTATION_ID={mutation_id}",
                    "MUTATION_CHANGED_BEHAVIOR=",
                    f"MUTATION_EXPECTED_REJECTION={reason}",
                    f"STAGE2E CHECK FAILED: {reason}",
                )
                if any(marker not in text for marker in required):
                    raise RunnerError(
                        f"XSim Stage2E mutation {mutation_id} was not rejected"
                    )
            summary.append(f"XSIM_{mutation_id}=PASS")

    summary.extend(
        (
            "STAGE2E_MUTATION_CONNECTED_NEGATIVES=PASS",
            "MUTATION_CONNECTED_NEGATIVE_FIXTURES=PASS_18_OF_18_"
            + ("BOTH_SIMULATORS" if include_xsim else "IVERILOG"),
        )
    )
    (output / "stage2e_connected_mutation_summary.txt").write_text(
        "\n".join(summary) + "\n", encoding="utf-8", newline="\n"
    )


def run_python(
    output: Path, name: str, args: list[str], marker: str | None = None
) -> str:
    code, text = run_logged(
        [sys.executable, *args], ROOT, output / "python" / f"{name}.log"
    )
    if code != 0:
        raise RunnerError(f"Python {name} exited {code}")
    if marker and marker not in text:
        raise RunnerError(f"Python {name} omitted marker {marker}")
    return text


def run_tcl(output: Path, name: str, script: Path, vivado_bin: Path) -> str:
    launcher = vivado_bin / "xtclsh.bat"
    if not launcher.is_file():
        raise RunnerError(f"Tcl launcher missing: {launcher}")
    environment = None
    if os.name == "nt":
        environment = dict(os.environ)
        # Tcl's traced env array needs canonical casing after Python uppercases keys.
        for canonical in ("SystemRoot", "PSModulePath"):
            for key in list(environment):
                if key.casefold() == canonical.casefold():
                    value = environment.pop(key)
                    environment[canonical] = value
        if environment.get("SystemRoot"):
            modules = Path(environment["SystemRoot"]) / "System32/WindowsPowerShell/v1.0/Modules"
            if modules.is_dir():
                # The fixture invokes Windows PowerShell; PS7 modules cannot shadow its own.
                inherited = environment.get("PSModulePath", "")
                environment["PSModulePath"] = str(modules) + (os.pathsep + inherited if inherited else "")
    code, text = run_logged(
        [str(launcher), str(script)],
        ROOT,
        output / "tcl" / f"{name}.log",
        env=environment,
    )
    if code != 0 or "FAILED" in text or "FAILED" in text.upper():
        raise RunnerError(f"Tcl {name} failed")
    return text


def git_identity(output: Path, require_clean: bool) -> None:
    identity = optional_git_identity(ROOT)
    if identity is None:
        (output / "git_identity.txt").write_text(
            "GIT_AVAILABLE=NO\nCURRENT_TREE_EXECUTION_ALLOWED=YES\n",
            encoding="utf-8",
        )
        if require_clean:
            raise RunnerError("--require-clean needs a working Git checkout")
        return
    branch, head = identity["branch"], identity["commit"]
    def optional_ref(name: str) -> str:
        result = subprocess.run(["git", "rev-parse", "--verify", name], cwd=ROOT,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        return result.stdout.strip() if result.returncode == 0 else "UNAVAILABLE"
    main, remote_main = optional_ref("main"), optional_ref("origin/main")
    status = subprocess.check_output(
        ["git", "status", "--porcelain", "--untracked-files=all"],
        cwd=ROOT,
        text=True,
    )
    if require_clean and status.strip():
        raise RunnerError("worktree is not clean")
    (output / "git_identity.txt").write_text(
        f"BRANCH={branch}\nHEAD={head}\nMAIN={main}\nREMOTE_MAIN={remote_main}\n"
        f"CLEAN={str(not bool(status.strip())).upper()}\n"
        "CURRENT_TREE_EXECUTION_ALLOWED=YES\n",
        encoding="utf-8",
    )


def validate_current_orchestration_source(
    runner_source: str, core_fixture_source: str
) -> None:
    frozen_branch = "codex/stage2g-" + "reset-wait-first-fault-policy-implementation"
    frozen_commit = "ef6a990b154edd03b0" + "b144d7d7cd0e41303dc095"
    obsolete_fixture = "tb_stage2g_sequence_" + "integrity_matrix.sv"
    for token, label in (
        (frozen_branch, "frozen Stage 2G branch gate"),
        (frozen_commit, "frozen Stage 2G commit gate"),
        (obsolete_fixture, "removed sequence matrix"),
    ):
        if token in runner_source:
            raise RunnerError(f"current runner retains {label}")

    try:
        tree = ast.parse(runner_source)
    except SyntaxError as exc:
        raise RunnerError(f"current runner source is invalid Python: {exc}") from exc
    current = next(
        (
            node
            for node in tree.body
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
            and node.name == "run_current"
        ),
        None,
    )
    if current is None:
        raise RunnerError("current runner entrypoint is missing")
    current_source = ast.get_source_segment(runner_source, current) or ""
    for token in (
        "replay_stage2g_source_archive.py",
        "stage2g_reset_wait_first_fault_policy_audit.py",
        "check_stage2g_implementation.py",
    ):
        if token in current_source:
            raise RunnerError(f"current default invokes historical oracle: {token}")

    for token in (
        "reg sample_source_integrity_clean = 1'b1;",
        "reg sample_destination_integrity_clean = 1'b1;",
        ".sample_source_integrity_clean(sample_source_integrity_clean)",
        ".sample_destination_integrity_clean(\n"
        "            sample_destination_integrity_clean)",
    ):
        if core_fixture_source.count(token) != 1:
            raise RunnerError(
                f"current direct-core fixture must contain {token!r} exactly once"
            )


def require_historical_stage2g_replay_runtime() -> str:
    implementation = platform.python_implementation()
    version = sys.version_info
    current = f"{implementation}_{version.major}_{version.minor}_{version.micro}"
    if implementation != "CPython" or (version.major, version.minor) != (3, 12):
        raise RunnerError(
            "HISTORICAL_STAGE2G_REPLAY_RUNTIME_UNSUPPORTED\n"
            f"REQUIRED_RUNTIME={HISTORICAL_STAGE2G_REPLAY_REQUIRED_RUNTIME}\n"
            f"CURRENT_RUNTIME={current}"
        )
    return current


def full_regression(
    output: Path, vivado_bin: Path, *, include_xsim: bool
) -> None:
    code, text = run_logged(
        [sys.executable, "sim/run_iverilog.py", "--output", str(output / "canonical")],
        ROOT,
        output / "regression" / "canonical_iverilog.log",
    )
    if code != 0 or "SUMMARY: PASS=10 FAIL=0" not in text:
        raise RunnerError("canonical Icarus regression failed")
    # Prior-stage dedicated Icarus fixtures are rerun from the current source
    # closure; this avoids their historical branch guards while preserving the
    # same testbench and RTL inputs.
    common = [
        RTL / "reset_release_sync.v",
        RTL / "pwm_gen.v",
        RTL / "pwm_gate.v",
        RTL / "current_compare_dual.v",
        RTL / "moving_avg_filter.v",
        RTL / "sensor_health_monitor.v",
        RTL / "transaction_destination_observer.v",
        RTL / "fault_classifier.v",
        RTL / "protection_fsm.v",
        RTL / "protection_core_top.v",
        RTL / "protection_reg_bank.v",
        RTL / "protection_ip_top_reg_controlled.v",
        RTL / "protection_ip_top_axi_lite.v",
    ]
    for top in (
        "tb_fault_classifier",
        "tb_protection_fsm",
        "tb_protection_core_top",
        "tb_protection_reg_bank",
        "tb_protection_ip_top_reg_controlled",
        "tb_protection_ip_top_axi_lite",
    ):
        iverilog_case(
            output,
            f"prior_{top}",
            top,
            common + [ROOT / "tb" / f"{top}.sv"],
            "PASS",
            run_cwd=ROOT,
        )

    stage2b_sources = common + [
        ROOT / "tb/stage2b/stage2b_sample_acceptance_checker.sv",
        ROOT / "tb/stage2b/tb_stage2b_unified_sample_acceptance.sv",
    ]
    stage2c_sources = common + [
        ROOT / "tb/stage2c/stage2c_reset_release_checker.sv",
        ROOT / "tb/stage2c/tb_stage2c_reset_release_cdc.sv",
    ]
    stage2_core = [
        RTL / "reset_release_sync.v",
        RTL / "async_fifo_gray.v",
        RTL / "transaction_source_observer.v",
        RTL / "adc_sample_cdc_bridge.v",
        RTL / "transaction_destination_observer.v",
        RTL / "current_compare_dual.v",
        RTL / "sensor_health_monitor.v",
        RTL / "fault_classifier.v",
        RTL / "protection_fsm.v",
        RTL / "pwm_gen.v",
        RTL / "pwm_gate.v",
        RTL / "protection_core_top.v",
    ]
    stage2_full = stage2_core + [
        RTL / "adc_sample_code_normalizer.sv",
        RTL / "source_observability_cdc.v",
        RTL / "protection_reg_bank.v",
        RTL / "protection_ip_top_reg_controlled.v",
        RTL / "protection_ip_top_axi_lite.v",
        RTL / "protection_ip_top_async_adc_axi_lite.v",
    ]
    prior_fixtures = (
        (
            "stage2b_regression",
            "tb_stage2b_unified_sample_acceptance",
            stage2b_sources,
            "STAGE2B_UNIFIED_SAMPLE_ACCEPTANCE_DUT=PASS",
        ),
        (
            "stage2c_regression",
            "tb_stage2c_reset_release_cdc",
            stage2c_sources,
            "STAGE2C_RESET_RELEASE_CDC_DUT=PASS",
        ),
        (
            "stage2d_regression",
            "tb_stage2d_async_adc_atomic_cdc",
            stage2_core
            + [ROOT / "tb/stage2d/tb_stage2d_async_adc_atomic_cdc.sv"],
            "STAGE2D_POSITIVE_SCENARIOS=PASS_30_OF_30",
        ),
        (
            "stage2d_production_regression",
            "tb_stage2d_production_wrapper",
            stage2_full
            + [ROOT / "tb/stage2d/tb_stage2d_production_wrapper.sv"],
            "PRODUCTION_WRAPPER_INTEGRATION=PASS",
        ),
        (
            "stage2e_regression",
            "tb_stage2e_transaction_error_observability",
            stage2_full
            + [
                ROOT
                / "tb/stage2e/tb_stage2e_transaction_error_observability.sv"
            ],
            "STAGE2E_POSITIVE_SCENARIOS=PASS_35_OF_35",
        ),
        (
            "stage2e_aggregate_saturation_equivalence",
            "tb_stage2e_aggregate_saturation_equivalence",
            [
                RTL / "transaction_destination_observer.v",
                ROOT
                / "tb/stage2e/"
                "tb_stage2e_aggregate_saturation_equivalence.sv",
            ],
            "AGGREGATE_SATURATION_EQUIVALENCE=PASS_1024_OF_1024",
        ),
        (
            "stage2e_axi_regression",
            "tb_stage2e_axi_register_contract",
            stage2_full
            + [ROOT / "tb/stage2e/tb_stage2e_axi_register_contract.sv"],
            "AXI_REGISTER_CONTRACT_TESTS=PASS_23_OF_23",
        ),
        (
            "stage2e_any_error_regression",
            "tb_stage2e_any_error_partial_clear",
            stage2_full
            + [ROOT / "tb/stage2e/tb_stage2e_any_error_partial_clear.sv"],
            "ANY_ERROR_PARTIAL_CLEAR_TESTS=PASS_5_OF_5",
        ),
    )
    additional_fixture_markers = {
        "stage2e_regression": (
            "DESTINATION_DELIVERY_ACCOUNTING=PASS",
            "TOTAL_DELIVERY_ACCOUNTING=PASS",
            "HARDWARE_COUNTERS_MATCH_SCOREBOARD=PASS",
            "STICKY_BITS_MATCH_SCOREBOARD=PASS",
        ),
        "stage2e_aggregate_saturation_equivalence": (
            "AGGREGATE_SATURATION_EQUIVALENCE=PASS_1024_OF_1024",
            "AGGREGATE_CYCLE_SEMANTICS=PASS",
            "AGGREGATE_REGISTERED_INPUT_BOUNDARY=PASS",
            "AGGREGATE_REGISTERED_ARITHMETIC_BOUNDARY=PASS",
        ),
        "stage2e_any_error_regression": (
            "ANY_ERROR_PARTIAL_CLEAR_TESTS=PASS_5_OF_5",
            "ANY_ERROR_MAINTAINED_POST_CLEAR_AGGREGATE=PASS",
            "ANY_ERROR_READ_ONLY_AGGREGATE=PASS",
        ),
    }
    for name, top, sources, marker in prior_fixtures:
        fixture_text = iverilog_case(
            output, name, top, sources, marker, run_cwd=ROOT
        )
        for additional_marker in additional_fixture_markers.get(name, ()):
            require_marker(
                0, fixture_text, additional_marker, f"Icarus {name}"
            )
        if include_xsim:
            fixture_text = xsim_case(
                output,
                name,
                top,
                sources,
                marker,
                vivado_bin=vivado_bin,
            )
            for additional_marker in additional_fixture_markers.get(name, ()):
                require_marker(
                    0, fixture_text, additional_marker, f"XSim {name}"
                )

    # Stage 2F-D generated-profile, boundary, and mutation suites operate on
    # the unchanged normalization fork while the Stage 2G raw policy evolves.
    run_python(
        output,
        "stage2f_static",
        ["tools/check_stage2f_implementation.py"],
        "STAGE2F_IMPLEMENTATION_STATIC=PASS",
    )
    run_python(
        output,
        "stage2f_frozen_audit",
        [
            "tools/stage2f_adc_contract_audit.py",
            "--root",
            ".",
            "--no-git-check",
            "--no-reference-check",
        ],
        "STAGE2F_ADC_CONTRACT_AUDIT=PASS",
    )
    run_python(
        output,
        "stage2f_profile_generation",
        [
            "tools/generate_stage2f_adc_profile.py",
            "--profile",
            "spec/stage2f_adc_source_profile_unconfigured.json",
            "--check",
        ],
        "STAGE2F_PROFILE_GENERATION=PASS",
    )
    stage2f_tools = (
        "run_stage2f_raw_path_invariance.py",
        "run_stage2f_generated_profile_rtl.py",
        "run_stage2f_width_sequence_boundary.py",
        "run_stage2f_boundary_mutations.py",
        "run_stage2f_generator_mutations.py",
        "run_stage2f_mutations.py",
    )
    for tool in stage2f_tools:
        label = Path(tool).stem
        args = [
            f"tools/{tool}",
            "--output",
            str(output / "stage2f" / label),
        ]
        if include_xsim:
            args.append("--xsim")
        if tool == "run_stage2f_raw_path_invariance.py":
            args.extend(("--base-commit", STAGE2I_B_REVIEWED_CANDIDATE))
        marker = None
        if tool == "run_stage2f_raw_path_invariance.py":
            marker = (
                "STAGE2F_RAW_PATH_INVARIANCE=PASS_2"
                if include_xsim
                else "STAGE2F_RAW_PATH_INVARIANCE=PASS_1"
            )
        run_python(output, label, args, marker)

    # Repository and software API tests are part of the frozen public
    # interface regression. They perform no board or hardware action.
    run_python(
        output,
        "stage2f_unit_tests",
        [
            "-m",
            "unittest",
            "tools.tests.test_stage2f_profile_generator",
            "tools.tests.test_stage2f_adc_contract_audit",
            "-v",
        ],
        "OK",
    )
    run_python(
        output,
        "software_interface_tests",
        [
            "-m",
            "unittest",
            "discover",
            "-s",
            "sw/tests",
            "-p",
            "test_*.py",
            "-v",
        ],
        "OK",
    )
    run_python(
        output,
        "repository_python_tests",
        [
            "-m",
            "unittest",
            "discover",
            "-s",
            "tests",
            "-p",
            "test_*.py",
            "-v",
        ],
        "OK",
    )
    # Controlled prior-stage Tcl/static closure and CDC tests.
    tcl_scripts = (
        "delivery_bundle_generator_tests.tcl",
        "delivery_bundle_instance_tests.tcl",
        "delivery_bundle_loader_tests.tcl",
        "stage1e_reconstruction_profile_tests.tcl",
        "stage1e_ip_packaging_adapter_tests.tcl",
        "stage1e_base_design_adapter_tests.tcl",
        "stage1e_debug_design_adapter_tests.tcl",
        "stage1e_controller_skeleton_tests.tcl",
        "stage1e_phase2_controller_tests.tcl",
        "stage1e_project_creation_adapter_tests.tcl",
        "stage1e_bd_creation_adapter_tests.tcl",
        "stage1e_mutation_bridge_tests.tcl",
        "stage1e_build_target_adapter_tests.tcl",
        "stage1e_synthesis_adapter_tests.tcl",
        "stage1e_execution_architecture_convergence_tests.tcl",
        "stage2d_cdc_constraint_tests.tcl",
        "stage2d_source_closure_tests.tcl",
        "stage2d_profile_convergence_tests.tcl",
        "stage2e_observability_cdc_constraint_tests.tcl",
        "stage2e_source_closure_tests.tcl",
        "stage2e_ipxact_metadata_scope_tests.tcl",
        "stage2g_source_closure_tests.tcl",
    )
    for filename in tcl_scripts:
        run_tcl(
            output,
            Path(filename).stem,
            ROOT / "fpga/vivado/build/tests" / filename,
            vivado_bin,
        )

    if optional_git_identity(ROOT) is not None:
        code, _ = run_logged(
            ["git", "diff", "--check"], ROOT,
            output / "regression" / "git_diff_check.log",
        )
        if code != 0:
            raise RunnerError("git diff --check failed")
    else:
        (output / "regression" / "git_diff_check.log").write_text(
            "NOT_RUN: no Git checkout; exported source integrity is checked by the delivery manifest.\n",
            encoding="utf-8",
        )


def run_current(
    output: Path,
    *,
    include_xsim: bool,
    include_mutations: bool,
    full: bool,
    require_clean: bool,
    vivado_bin: Path,
) -> None:
    if output.exists():
        raise RunnerError(f"output must not already exist: {output}")
    output.mkdir(parents=True)
    git_identity(output, require_clean)
    validate_current_orchestration_source(
        Path(__file__).read_text(encoding="utf-8"),
        (TB / "tb_stage2g_core_directed.sv").read_text(encoding="utf-8"),
    )

    # Current independent model and live-topology fixtures.
    vectors = output / "reference" / "vectors.txt"
    reference_generation = run_python(
        output,
        "reference_generation",
        [
            "tools/stage2g_reference_model.py",
            "--output",
            str(vectors),
            "--episodes",
            "1000",
        ],
        "RANDOM_EPISODES=PASS_1000",
    )
    (output / "reference" / "generation_summary.txt").write_text(
        reference_generation, encoding="utf-8", newline="\n"
    )

    core_sources = [
        RTL / "fault_defs.vh",
        RTL / "current_compare_dual.v",
        RTL / "sensor_health_monitor.v",
        RTL / "fault_classifier.v",
        RTL / "protection_fsm.v",
        RTL / "pwm_gen.v",
        RTL / "pwm_gate.v",
        RTL / "protection_core_top.v",
        TB / "tb_stage2g_core_directed.sv",
    ]
    policy_sources = [
        RTL / "fault_defs.vh",
        RTL / "fault_classifier.v",
        RTL / "protection_fsm.v",
        TB / "tb_stage2g_policy_matrix.sv",
    ]
    reference_sources = [
        RTL / "fault_defs.vh",
        RTL / "fault_classifier.v",
        RTL / "protection_fsm.v",
        TB / "tb_stage2g_reference_vectors.sv",
    ]
    production_sources = [
        RTL / "fault_defs.vh",
        *[
            RTL / name
            for name in (
                "reset_release_sync.v",
                "async_fifo_gray.v",
                "adc_sample_cdc_bridge.v",
                "transaction_source_observer.v",
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
                "source_observability_cdc.v",
                "transaction_destination_observer.v",
                "adc_sample_code_normalizer.sv",
                "protection_ip_top_async_adc_axi_lite.v",
            )
        ],
        TB / "tb_stage2g_production_path.sv",
    ]
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
        TB_STAGE2H / "tb_stage2h_b2_destination_sequence.sv",
    ]
    cdc_event_authority_sources = [
        RTL / "fault_defs.vh",
        RTL / "reset_release_sync.v",
        RTL / "async_fifo_gray.v",
        RTL / "transaction_source_observer.v",
        RTL / "adc_sample_cdc_bridge.v",
        RTL / "current_compare_dual.v",
        RTL / "sensor_health_monitor.v",
        RTL / "fault_classifier.v",
        RTL / "protection_fsm.v",
        RTL / "pwm_gen.v",
        RTL / "pwm_gate.v",
        RTL / "protection_core_top.v",
        TB_STAGE2I / "tb_stage2i_b_cdc_event_authority.sv",
    ]

    iverilog_case(
        output, "core_directed", "tb_stage2g_core_directed", core_sources,
        "STAGE2G_CORE_DIRECTED=PASS"
    )
    iverilog_case(
        output, "policy_matrix", "tb_stage2g_policy_matrix", policy_sources,
        "STAGE2G_POLICY_MATRIX=PASS"
    )
    iverilog_case(
        output,
        "reference_vectors",
        "tb_stage2g_reference_vectors",
        reference_sources,
        "REFERENCE_MODEL_COMPARISON=PASS",
        [f"+VECTORS={vectors}"],
    )
    production_text = iverilog_case(
        output,
        "production_path",
        "tb_stage2g_production_path",
        production_sources,
        "STAGE2G_PRODUCTION_PATH=PASS",
    )
    cdc_authority_text = iverilog_case(
        output,
        "cdc_event_authority",
        "tb_stage2i_b_cdc_event_authority",
        cdc_event_authority_sources,
        "CDC_EVENT_AUTHORITY_CHARACTERIZATION=PASS",
    )
    require_cdc_event_authority_markers(
        cdc_authority_text, "Icarus CDC event authority"
    )
    for marker in (
        "PRODUCTION_SAFE_HOLD=PASS",
        "PRODUCTION_SAFE_RELEASE_AFTER_LATER_HEALTHY=PASS",
        "PRODUCTION_UNSAFE_PULSE_COUNT=0",
        "STATUS_FAULT_LATCHED_DURING_POST_CLEAR_RESET_WAIT=1",
        "FAULT_CODE_DURING_POST_CLEAR_RESET_WAIT=RETAIN_PRIOR_FIRST_CAUSE",
        "LATER_HEALTHY_CLEARS_COMPATIBILITY_STATUS=PASS",
        "POST_CLEAR_FAULT_REPLACES_WITH_NEW_FIRST_CAUSE=PASS",
        "RESET_CLEARS_COMPATIBILITY_STATUS=PASS",
    ):
        require_marker(0, production_text, marker, "Icarus production path")
    for sequence_width in (16, 24, 32):
        destination_text = iverilog_case(
            output,
            f"b2_destination_width_{sequence_width}",
            f"tb_stage2h_b2_destination_sequence_{sequence_width}",
            destination_sources,
            f"SEQUENCE_WIDTH_{sequence_width}=PASS",
            strict_sequence_width=True,
        )
        for marker in (
            "DESTINATION_SEQUENCE_BEHAVIOR=PASS",
            "POLICY_OBSERVABILITY_SEQUENCE_CLASSIFICATION_AGREEMENT=PASS",
            "FAULT_EVALUATION_LATENCY_ACLK=3",
        ):
            require_marker(
                0,
                destination_text,
                marker,
                f"Icarus B2 destination width {sequence_width}",
            )

    if include_xsim:
        xsim_case(
            output, "core_directed", "tb_stage2g_core_directed", core_sources,
            "STAGE2G_CORE_DIRECTED=PASS", vivado_bin=vivado_bin
        )
        xsim_case(
            output, "policy_matrix", "tb_stage2g_policy_matrix", policy_sources,
            "STAGE2G_POLICY_MATRIX=PASS", vivado_bin=vivado_bin
        )
        xsim_case(
            output,
            "reference_vectors",
            "tb_stage2g_reference_vectors",
            reference_sources,
            "REFERENCE_MODEL_COMPARISON=PASS",
            vivado_bin=vivado_bin,
            vector_file=vectors,
        )
        production_text = xsim_case(
            output,
            "production_path",
            "tb_stage2g_production_path",
            production_sources,
            "STAGE2G_PRODUCTION_PATH=PASS",
            vivado_bin=vivado_bin,
        )
        cdc_authority_text = xsim_case(
            output,
            "cdc_event_authority",
            "tb_stage2i_b_cdc_event_authority",
            cdc_event_authority_sources,
            "CDC_EVENT_AUTHORITY_CHARACTERIZATION=PASS",
            vivado_bin=vivado_bin,
        )
        require_cdc_event_authority_markers(
            cdc_authority_text, "XSim CDC event authority"
        )
        for marker in (
            "PRODUCTION_SAFE_HOLD=PASS",
            "PRODUCTION_SAFE_RELEASE_AFTER_LATER_HEALTHY=PASS",
            "PRODUCTION_UNSAFE_PULSE_COUNT=0",
            "STATUS_FAULT_LATCHED_DURING_POST_CLEAR_RESET_WAIT=1",
            "FAULT_CODE_DURING_POST_CLEAR_RESET_WAIT=RETAIN_PRIOR_FIRST_CAUSE",
            "LATER_HEALTHY_CLEARS_COMPATIBILITY_STATUS=PASS",
            "POST_CLEAR_FAULT_REPLACES_WITH_NEW_FIRST_CAUSE=PASS",
            "RESET_CLEARS_COMPATIBILITY_STATUS=PASS",
        ):
            require_marker(0, production_text, marker, "XSim production path")
        for sequence_width in (16, 24, 32):
            destination_text = xsim_case(
                output,
                f"b2_destination_width_{sequence_width}",
                f"tb_stage2h_b2_destination_sequence_{sequence_width}",
                destination_sources,
                f"SEQUENCE_WIDTH_{sequence_width}=PASS",
                vivado_bin=vivado_bin,
                strict_sequence_width=True,
            )
            for marker in (
                "DESTINATION_SEQUENCE_BEHAVIOR=PASS",
                "POLICY_OBSERVABILITY_SEQUENCE_CLASSIFICATION_AGREEMENT=PASS",
                "FAULT_EVALUATION_LATENCY_ACLK=3",
            ):
                require_marker(
                    0,
                    destination_text,
                    marker,
                    f"XSim B2 destination width {sequence_width}",
                )

    snapshot_args = [
        "tools/check_stage2g_recovery_snapshots.py",
        "--icarus",
        str(output / "icarus" / "production_path" / "recovery_snapshots.tsv"),
    ]
    if include_xsim:
        snapshot_args.extend(
            [
                "--xsim",
                str(output / "xsim" / "production_path" / "recovery_snapshots.tsv"),
            ]
        )
    recovery_text = run_python(
        output,
        "software_rtl_recovery_equivalence",
        snapshot_args,
        "SOFTWARE_RECOVERY_API_SEMANTICS_PRESERVED=PASS",
    )
    for marker in (
        "POST_CLEAR_RESET_WAIT_RECOVERY_VERIFIED=NO",
        "NO_SAMPLE_POST_CLEAR_RECOVERY_VERIFIED=NO",
        "NONCLEAN_POST_CLEAR_RECOVERY_VERIFIED=NO",
        "ARMED_AFTER_LATER_HEALTHY_RECOVERY_VERIFIED=YES",
    ):
        require_marker(0, recovery_text, marker, "software/RTL recovery equivalence")

    closure_text = run_tcl(
        output,
        "stage2g_source_closure",
        ROOT / "fpga/vivado/build/tests/stage2g_source_closure_tests.tcl",
        vivado_bin,
    )
    for marker in (
        "PRODUCTION_RTL_SOURCE_COUNT=21",
        "PRODUCTION_XDC_SOURCE_COUNT=2",
        "LIVE_PRODUCTION_PACKAGE_USES_GENERATED_IPXACT=YES",
        "LIVE_PRODUCTION_REGISTER_COUNT=33",
        "CURRENT_SOURCE_CLOSURE_TARGETS_B2_TOPOLOGY=YES",
        "CURRENT_SOURCE_CLOSURE_NEGATIVE_FIXTURES=PASS_4_OF_4",
    ):
        require_marker(0, closure_text, marker, "current source closure")

    if include_mutations:
        mutation_output = output / "mutations"
        args = [
            "tools/run_stage2g_mutations.py",
            "--output",
            str(mutation_output),
        ]
        if include_xsim:
            args.append("--xsim")
        mutation_text = run_python(
            output,
            "mutation_runner",
            args,
            "MUTATION_CONNECTED_FIXTURES=PASS_36_OF_36",
        )
        for marker in (
            "PREVIOUS_MUTATION_CONNECTED_FIXTURES=PASS_28_OF_28",
            "RECOVERY_OBSERVABILITY_MUTATION_FIXTURES=PASS_8_OF_8",
        ):
            require_marker(0, mutation_text, marker, "mutation runner")
        stage2e_connected_mutation_regression(
            output, vivado_bin, include_xsim=include_xsim
        )

    if full:
        full_regression(output, vivado_bin, include_xsim=include_xsim)

    summary = [
        "STAGE2G_FUNCTIONAL_RTL_RUNNER=PASS",
        "CURRENT_STAGE2G_RUNNER=PASS",
        "CURRENT_TREE_EXECUTION_ALLOWED=YES",
        "CURRENT_ORCHESTRATION_STATIC=PASS",
        "CURRENT_DEFAULT_EXECUTES_HISTORICAL_REPLAY=NO",
        "HISTORICAL_STAGE2G_ORACLES=NOT_REQUESTED",
        "HISTORICAL_REPLAY_REQUIRES_EXPLICIT_CONTEXT=YES",
        "REFERENCE_MODEL_COMPARISON=PASS",
        "ICARUS_DIRECTED=PASS",
        "STAGE2G_CORE_DIRECTED_CURRENT_TOPOLOGY=PASS",
        f"XSIM_DIRECTED={'PASS' if include_xsim else 'NOT_REQUESTED'}",
        "RANDOM_EPISODES=PASS_1000",
        "FAULT_EVAL_SEQUENCE_WIDTH=OBS_SEQUENCE_WIDTH",
        "SUPPORTED_SEQUENCE_WIDTHS=16_TO_32",
        "IMPLICIT_STAGE2G_SEQUENCE_PORT_RESIZE=NO",
        "SEQUENCE_WIDTH_16=PASS",
        "SEQUENCE_WIDTH_24=PASS",
        "SEQUENCE_WIDTH_32=PASS",
        "B2_DESTINATION_WIDTH16=PASS",
        "B2_DESTINATION_WIDTH24=PASS",
        "B2_DESTINATION_WIDTH32=PASS",
        "DESTINATION_SEQUENCE_BEHAVIOR=PASS",
        "POLICY_OBSERVABILITY_SEQUENCE_CLASSIFICATION_AGREEMENT=PASS",
        "CDC_EVENT_AUTHORITY_CHARACTERIZATION=PASS",
        "CDC_EVENT_AUTHORITY_ICARUS=PASS",
        (
            "CDC_EVENT_AUTHORITY_XSIM=PASS"
            if include_xsim
            else "CDC_EVENT_AUTHORITY_XSIM=NOT_REQUESTED"
        ),
        "INTERNAL_FIFO_PREFETCH_EVENT=IMPLEMENTATION_DETAIL_NOT_POLICY_AUTHORITY",
        (
            "ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT="
            "DST_SAMPLE_VALID_ACCEPTED_EDGE"
        ),
        "STAGE2B_N0=ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT",
        (
            "STAGE2G_SAMPLE_EVENT_AUTHORITY="
            "ATOMIC_RAW_CDC_DESTINATION_DELIVERY_EVENT"
        ),
        "STAGE2G_FIXED_3_EDGE_DELIVERY_TO_POLICY=PASS",
        "STAGE2G_DELIVERY_TO_POLICY_LATENCY_ACLK=3",
        "NO_GHOST_DESTINATION_DELIVERY_AFTER_RESET=PASS",
        "NO_STALE_PREFETCH_REPLAY_AFTER_RESET=PASS",
        "FIRST_POST_RESET_TRANSACTION_EXACTLY_ONCE=PASS",
        "CLEAR_FENCE_ORDER=EVALUATION_RETIREMENT",
        "PRE_REQUEST_RETIREMENT_RESOLVES_CLEAR=NO",
        "FAULT_EVALUATION_LATENCY_ACLK=3",
        "PIPELINE_INITIATION_INTERVAL=1",
        "FAULT_EPISODE_MODEL=PASS",
        "CLEAR_PROTOCOL=REQUEST_EVALUATION_FENCED",
        "FIRST_FAULT_IMMUTABLE_DURING_EPISODE=PASS",
        "SIMULTANEOUS_FAULT_INFORMATION_PRESERVED=PASS",
        "RESET_RACE_TESTS=PASS",
        "PRODUCTION_SAFE_HOLD=PASS",
        "PRODUCTION_SAFE_RELEASE_AFTER_LATER_HEALTHY=PASS",
        "PRODUCTION_UNSAFE_PULSE_COUNT=0",
        "INTERNAL_EPISODE_END=LEGAL_CLEAR_ACCEPTANCE",
        "PUBLIC_RECOVERY_COMPLETE=LATER_CLEAN_HEALTHY_EVALUATION_ENTERING_ARMED",
        "CLEAR_ACCEPTANCE_EQUALS_PUBLIC_RECOVERY_COMPLETE=NO",
        "STATUS_FAULT_LATCHED_DURING_POST_CLEAR_RESET_WAIT=1",
        "FAULT_CODE_DURING_POST_CLEAR_RESET_WAIT=RETAIN_PRIOR_FIRST_CAUSE",
        "POST_CLEAR_RESET_WAIT_RECOVERY_VERIFIED=NO",
        "NO_SAMPLE_POST_CLEAR_RECOVERY_VERIFIED=NO",
        "NONCLEAN_POST_CLEAR_RECOVERY_VERIFIED=NO",
        "ARMED_AFTER_LATER_HEALTHY_RECOVERY_VERIFIED=YES",
        "LATER_HEALTHY_CLEARS_COMPATIBILITY_STATUS=PASS",
        "POST_CLEAR_FAULT_REPLACES_WITH_NEW_FIRST_CAUSE=PASS",
        "RESET_CLEARS_COMPATIBILITY_STATUS=PASS",
        "SOFTWARE_RECOVERY_API_SEMANTICS_PRESERVED=PASS",
        "SOFTWARE_API_CHANGED=NO",
        "STAGE2G_DIRECTED=PASS",
        "STAGE2G_RANDOM_LONGEVITY=PASS",
        "STAGE2G_CLEAR_FENCE=PASS",
        "STAGE2G_RESET_RACES=PASS",
        (
            "STAGE2G_MUTATIONS=PASS"
            if include_mutations
            else "STAGE2G_MUTATIONS=NOT_REQUESTED"
        ),
        (
            "MUTATION_CONNECTED_FIXTURES=PASS_36_OF_36"
            if include_mutations
            else "MUTATION_CONNECTED_FIXTURES=NOT_REQUESTED"
        ),
        (
            "PREVIOUS_MUTATION_CONNECTED_FIXTURES=PASS_28_OF_28"
            if include_mutations
            else "PREVIOUS_MUTATION_CONNECTED_FIXTURES=NOT_REQUESTED"
        ),
        "OBSOLETE_STAGE2G_SEQUENCE_MUTATIONS=SUPERSEDED_BY_B2_CONNECTED_SUITE",
        (
            "RECOVERY_OBSERVABILITY_MUTATION_FIXTURES=PASS_8_OF_8"
            if include_mutations
            else "RECOVERY_OBSERVABILITY_MUTATION_FIXTURES=NOT_REQUESTED"
        ),
        (
            "STAGE2E_MUTATION_CONNECTED_NEGATIVES=PASS"
            if include_mutations
            else "STAGE2E_MUTATION_CONNECTED_NEGATIVES=NOT_REQUESTED"
        ),
        "SOURCE_ARCHIVE_STATIC_REPLAY=NOT_REQUESTED",
        "OBSOLETE_SEQUENCE_MATRIX_CURRENT_RUNNER_REFERENCE=NO",
        "OBSOLETE_STAGE2G_SEQUENCE_MATRIX_REMOVED=YES",
        "LIVE_PRODUCTION_PACKAGE_USES_GENERATED_IPXACT=YES",
        "LIVE_PRODUCTION_REGISTER_COUNT=33",
        "CURRENT_SOURCE_CLOSURE_TARGETS_B2_TOPOLOGY=YES",
        "CONTROLLED_BUILD_SOURCE_CLOSURE=PASS",
        "STAGE2D_DEDICATED_IVERILOG="
        + ("PASS" if full else "NOT_REQUESTED"),
        "STAGE2D_DEDICATED_XSIM="
        + ("PASS" if full and include_xsim else "NOT_REQUESTED"),
        "STAGE2D_PRODUCTION_WRAPPER="
        + ("PASS" if full and include_xsim else "NOT_REQUESTED"),
        "STAGE2E_FULL_IVERILOG=" + ("PASS" if full else "NOT_REQUESTED"),
        "STAGE2E_FULL_XSIM="
        + ("PASS" if full and include_xsim else "NOT_REQUESTED"),
        "STAGE2E_DESTINATION_DELIVERY_ACCOUNTING="
        + ("PASS" if full else "NOT_REQUESTED"),
        "STAGE2E_TOTAL_DELIVERY_ACCOUNTING="
        + ("PASS" if full else "NOT_REQUESTED"),
        "STAGE2E_ANY_ERROR_SEMANTICS="
        + ("PASS" if full else "NOT_REQUESTED"),
        "STAGE2E_AGGREGATE_SATURATION_EQUIVALENCE="
        + ("PASS_1024_OF_1024" if full else "NOT_REQUESTED"),
        "STAGE2E_AGGREGATE_PIPELINED_CYCLE_SEMANTICS="
        + ("PASS" if full else "NOT_REQUESTED"),
        "STAGE2F_RAW_PATH_INVARIANCE="
        + ("PASS" if full else "NOT_REQUESTED"),
        "STAGE2F_REGRESSION=" + ("PASS" if full else "NOT_REQUESTED"),
        "STAGE2E_REGRESSION=" + ("PASS" if full else "NOT_REQUESTED"),
        "STAGE2D_REGRESSION=" + ("PASS" if full else "NOT_REQUESTED"),
        "STAGE2C_REGRESSION=" + ("PASS" if full else "NOT_REQUESTED"),
        "STAGE2B_REGRESSION=" + ("PASS" if full else "NOT_REQUESTED"),
        "CANONICAL_REGRESSION=" + ("PASS" if full else "NOT_REQUESTED"),
        "SOFTWARE_INTERFACE_TESTS=" + ("PASS" if full else "NOT_REQUESTED"),
        "STAGE1E_STATIC_SUITES=" + ("PASS" if full else "NOT_REQUESTED"),
        "FULL_PRIOR_STAGE_REGRESSION=" + ("PASS" if full else "NOT_REQUESTED"),
    ]
    (output / "runner_summary.txt").write_text(
        "\n".join(summary) + "\n", encoding="utf-8", newline="\n"
    )
    print("\n".join(summary))


def run_historical_replay(output: Path, archive: Path) -> None:
    current_runtime = require_historical_stage2g_replay_runtime()
    if output.exists():
        raise RunnerError(f"output must not already exist: {output}")
    output.mkdir(parents=True)
    replay_text = run_python(
        output,
        "historical_source_archive_replay",
        [
            "tools/replay_stage2g_source_archive.py",
            "--archive",
            str(archive),
            "--output",
            str(output / "source_archive_replay"),
            "--cleanup-repository",
        ],
        "SOURCE_ARCHIVE_STATIC_REPLAY=PASS",
    )
    require_marker(
        0,
        replay_text,
        "REPOSITORY_FALLBACK_USED=NO",
        "historical source archive replay",
    )
    summary = [
        "STAGE2G_HISTORICAL_REPLAY=PASS",
        "HISTORICAL_CONTEXT=EXPLICIT_SOURCE_ARCHIVE",
        "HISTORICAL_REPLAY_REQUIRES_EXPLICIT_CONTEXT=YES",
        "HISTORICAL_REPLAY_RUNTIME_CONTEXT_EXPLICIT=YES",
        "HISTORICAL_STAGE2G_REPLAY_REQUIRED_RUNTIME="
        f"{HISTORICAL_STAGE2G_REPLAY_REQUIRED_RUNTIME}",
        f"HISTORICAL_STAGE2G_REPLAY_CURRENT_RUNTIME={current_runtime}",
        "HISTORICAL_REPLAY_PY312=PASS",
        "SOURCE_ARCHIVE_STATIC_REPLAY=PASS",
        "REPOSITORY_FALLBACK_USED=NO",
        "CURRENT_TREE_EXECUTION=NOT_REQUESTED",
    ]
    (output / "runner_summary.txt").write_text(
        "\n".join(summary) + "\n", encoding="utf-8", newline="\n"
    )
    print("\n".join(summary))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--xsim", action="store_true")
    parser.add_argument("--no-mutations", action="store_true")
    parser.add_argument("--full-regression", action="store_true")
    parser.add_argument("--require-clean", action="store_true")
    parser.add_argument("--historical-replay-archive", type=Path)
    parser.add_argument("--vivado-bin", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.historical_replay_archive is not None:
            if any(
                (
                    args.xsim,
                    args.no_mutations,
                    args.full_regression,
                    args.require_clean,
                )
            ):
                raise RunnerError(
                    "historical replay cannot be combined with current-run options"
                )
            run_historical_replay(
                args.output.resolve(),
                args.historical_replay_archive.resolve(strict=True),
            )
        else:
            vivado_bin = resolve_vivado_bin(ROOT, args.vivado_bin)
            if vivado_bin is None:
                raise RunnerError("Vivado is required for the current Stage 2G run; pass --vivado-bin or set CSIP_VIVADO_BIN")
            run_current(
                args.output.resolve(),
                include_xsim=args.xsim,
                include_mutations=not args.no_mutations,
                full=args.full_regression,
                require_clean=args.require_clean,
                vivado_bin=vivado_bin,
            )
    except (OSError, RunnerError, subprocess.CalledProcessError) as exc:
        print(f"STAGE2G_FUNCTIONAL_RTL_RUNNER=FAIL: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
