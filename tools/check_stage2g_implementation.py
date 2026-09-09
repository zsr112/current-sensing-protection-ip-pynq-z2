#!/usr/bin/env python3
"""Fail-closed static and frozen-base invariance checks for Stage 2G RTL."""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path


BASE_COMMIT = "ef6a990b154edd03b0b144d7d7cd0e41303dc095"
BRANCH = "codex/stage2g-reset-wait-first-fault-policy-implementation"
FINGERPRINT_PATH = Path("spec/stage2g_implementation_base_fingerprints.json")
GENERATED_REGISTER_MAP_PATH = Path("rtl/generated/protection_register_map.vh")

LEGACY_INTERFACES = {
    "rtl/adc_sample_cdc_bridge.v": ("adc_sample_cdc_bridge",),
    "rtl/transaction_source_observer.v": ("transaction_source_observer",),
    "rtl/transaction_destination_observer.v": (
        "transaction_destination_observer",
    ),
    "rtl/fault_classifier.v": ("fault_classifier",),
    "rtl/protection_fsm.v": ("protection_fsm",),
    "rtl/protection_core_top.v": ("protection_core_top",),
    "rtl/protection_ip_top_reg_controlled.v": (
        "protection_ip_top_reg_controlled",
    ),
    "rtl/protection_ip_top_axi_lite.v": ("protection_ip_top_axi_lite",),
    "rtl/protection_ip_top_async_adc_axi_lite.v": (
        "protection_ip_top_async_adc_axi_lite",
    ),
}

EXPECTED_NEW_MODULES = {
    "stage2g_source_integrity_tracker",
    "stage2g_transaction_source_observer",
    "stage2g_adc_sample_cdc_bridge",
    "stage2g_fault_evaluation_pipeline",
    "stage2g_fault_episode_controller",
    "stage2g_protection_core",
    "stage2g_protection_ip_reg_controlled",
    "stage2g_protection_ip_axi_lite",
    "stage2e_transaction_sequence_classifier",
}

RTL_CHANGE_ALLOWLIST = set(LEGACY_INTERFACES)
NON_RTL_PREFIXES = (
    "docs/architecture/stage2g_",
    "docs/verification/stage2g_",
    "fpga/vivado/build/tests/stage2g_",
    "fpga/vivado/build/tests/stage2d_source_closure_tests.tcl",
    "sim/stage2g/",
    "sim/run_iverilog.sh",
    "tb/stage2g/",
    "tools/check_stage2g_implementation.py",
    "tools/check_stage2g_recovery_snapshots.py",
    "tools/run_stage2g_mutations.py",
    "tools/run_stage2g_functional_rtl.py",
    "tools/stage2g_reference_model.py",
    "tools/build_stage2g_functional_review.py",
    "tools/replay_stage2g_source_archive.py",
    "tools/stage2g_reset_wait_first_fault_policy_audit.py",
    "tools/tests/test_stage2g_reset_wait_first_fault_policy_audit.py",
    "spec/stage2g_reset_wait_first_fault_policy.json",
    "spec/stage2g_reset_wait_first_fault_policy.schema.json",
    "spec/stage2g_reset_wait_first_fault_policy_status.json",
    "spec/stage2g_reset_wait_first_fault_policy_source_map.json",
    "spec/stage2g_implementation_base_fingerprints.json",
    "spec/stage2g_fixtures/positive_contract.json",
)


class CheckError(RuntimeError):
    """Raised when an implementation invariant is not satisfied."""


def load_fingerprints(root: Path) -> dict[str, object]:
    path = root / FINGERPRINT_PATH
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise CheckError(f"unreadable frozen-base fingerprints: {path}") from exc
    if data.get("fingerprint_version") != "stage2g-frozen-base-fingerprints-v1":
        raise CheckError("unsupported frozen-base fingerprint version")
    if data.get("base_commit") != BASE_COMMIT:
        raise CheckError("frozen-base fingerprint commit mismatch")
    return data


def interface_digest(text: str, module: str) -> str:
    return hashlib.sha256(
        module_interface(text, module).encode("utf-8")
    ).hexdigest()


def git(root: Path, *args: str) -> str:
    if os.environ.get("STAGE2G_FORBID_GIT") == "1":
        raise CheckError("Git command attempted while archive replay forbids Git")
    result = subprocess.run(
        ["git", *args],
        cwd=root,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise CheckError(
            f"git {' '.join(args)} failed: {result.stderr.strip()}"
        )
    return result.stdout


def git_file(root: Path, revision: str, relative_path: str) -> str:
    return git(root, "show", f"{revision}:{relative_path}")


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    return re.sub(r"//[^\r\n]*", " ", text)


def balanced_end(text: str, start: int) -> int:
    if start >= len(text) or text[start] != "(":
        raise CheckError("balanced expression does not start with '('")
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            depth -= 1
            if depth == 0:
                return index + 1
    raise CheckError("unterminated module interface expression")


def module_interface(text: str, module: str) -> str:
    source = strip_comments(text)
    match = re.search(rf"\bmodule\s+{re.escape(module)}\b", source)
    if match is None:
        raise CheckError(f"module definition missing: {module}")
    index = match.end()
    while index < len(source) and source[index].isspace():
        index += 1
    end = index
    if index < len(source) and source[index] == "#":
        index += 1
        while index < len(source) and source[index].isspace():
            index += 1
        end = balanced_end(source, index)
        index = end
        while index < len(source) and source[index].isspace():
            index += 1
    if index >= len(source) or source[index] != "(":
        raise CheckError(f"ANSI port list missing for module {module}")
    end = balanced_end(source, index)
    interface = source[match.start() : end]
    # Whitespace is not an interface property. Punctuation and declaration
    # tokens remain significant, including parameter defaults and widths.
    return re.sub(r"\s+", "", interface)


def module_names(text: str) -> set[str]:
    return set(
        re.findall(
            r"\bmodule\s+([A-Za-z_][A-Za-z0-9_$]*)",
            strip_comments(text),
        )
    )


def require(text: str, pattern: str, label: str, *, regex: bool = False) -> None:
    found = re.search(pattern, text, flags=re.DOTALL) if regex else pattern in text
    if not found:
        raise CheckError(f"missing implementation invariant: {label}")


def reject(text: str, pattern: str, label: str, *, regex: bool = False) -> None:
    found = re.search(pattern, text, flags=re.DOTALL) if regex else pattern in text
    if found:
        raise CheckError(f"forbidden implementation dependency: {label}")


def extract_module(text: str, module: str) -> str:
    source = strip_comments(text)
    match = re.search(rf"\bmodule\s+{re.escape(module)}\b", source)
    if match is None:
        raise CheckError(f"module definition missing: {module}")
    end = re.search(r"\bendmodule\b", source[match.end() :])
    if end is None:
        raise CheckError(f"endmodule missing: {module}")
    return source[match.start() : match.end() + end.end()]


def register_offsets(text: str) -> dict[str, int]:
    result: dict[str, int] = {}
    source = strip_comments(text)
    patterns = (
        r"\blocalparam(?:\s+\[[^\]]+\])?\s+"
        r"(REG_[A-Z0-9_]+)\s*=\s*8'h([0-9a-fA-F]+)",
        r"(?m)^\s*`define\s+PROTECTION_(REG_[A-Z0-9_]+)\s+"
        r"8'h([0-9a-fA-F]+)\s*$",
    )
    for pattern in patterns:
        for name, value in re.findall(pattern, source):
            if name in result:
                raise CheckError(f"duplicate register constant: {name}")
            result[name] = int(value, 16)
    if not result:
        raise CheckError("no AXI register offsets found")
    return result


def repository_changed_paths(root: Path) -> set[str]:
    tracked = set(
        line
        for line in git(root, "diff", "--name-only", BASE_COMMIT).splitlines()
        if line
    )
    tracked.update(
        line
        for line in git(
            root, "ls-files", "--others", "--exclude-standard"
        ).splitlines()
        if line
    )
    return tracked


def path_is_allowed(path: str) -> bool:
    if path.startswith("rtl/"):
        return path in RTL_CHANGE_ALLOWLIST
    return any(path.startswith(prefix) for prefix in NON_RTL_PREFIXES)


def check_scope(
    root: Path,
    fingerprints: dict[str, object],
    *,
    check_git_identity: bool,
) -> int:
    raw_paths = fingerprints.get("expected_changed_paths")
    if not isinstance(raw_paths, list) or not raw_paths:
        raise CheckError("frozen diff fingerprint path inventory is empty")
    paths = {str(path) for path in raw_paths}
    for path in sorted(paths):
        if not path_is_allowed(path):
            raise CheckError(f"unapproved Stage 2G path: {path}")
        if not (root / path).is_file():
            raise CheckError(f"fingerprinted Stage 2G path is missing: {path}")
    if check_git_identity:
        actual = repository_changed_paths(root)
        if actual != paths:
            raise CheckError(
                "implementation diff fingerprint mismatch: "
                f"missing={sorted(paths-actual)}, extra={sorted(actual-paths)}"
            )
    return len(paths)


def check_interfaces(
    root: Path,
    fingerprints: dict[str, object],
    *,
    check_git_identity: bool,
) -> int:
    count = 0
    current_modules: set[str] = set()
    base_modules: set[str] = set()
    records = fingerprints.get("legacy_files")
    if not isinstance(records, dict):
        raise CheckError("legacy interface fingerprints are missing")
    for relative_path, modules in LEGACY_INTERFACES.items():
        record = records.get(relative_path)
        if not isinstance(record, dict):
            raise CheckError(f"interface fingerprint missing: {relative_path}")
        names = record.get("base_module_names")
        digests = record.get("interfaces")
        if not isinstance(names, list) or not isinstance(digests, dict):
            raise CheckError(f"malformed interface fingerprint: {relative_path}")
        current = (root / relative_path).read_text(encoding="utf-8")
        base_modules.update(str(name) for name in names)
        current_modules.update(module_names(current))
        for module in modules:
            expected_digest = digests.get(module)
            if not isinstance(expected_digest, str):
                raise CheckError(f"module fingerprint missing: {module}")
            if interface_digest(current, module) != expected_digest:
                raise CheckError(
                    f"legacy/public module interface changed: {module}"
                )
            if check_git_identity:
                base = git_file(root, BASE_COMMIT, relative_path)
                if interface_digest(base, module) != expected_digest:
                    raise CheckError(
                        f"stored interface fingerprint disagrees with base: {module}"
                    )
                if sorted(module_names(base)) != sorted(str(name) for name in names):
                    raise CheckError(
                        f"stored module inventory disagrees with base: {relative_path}"
                    )
            count += 1
    new_modules = current_modules - base_modules
    missing = EXPECTED_NEW_MODULES - new_modules
    unexpected = new_modules - EXPECTED_NEW_MODULES
    if missing or unexpected:
        raise CheckError(
            f"Stage 2G module inventory mismatch: missing={sorted(missing)}, "
            f"unexpected={sorted(unexpected)}"
        )
    return count


def check_register_map(
    root: Path,
    fingerprints: dict[str, object],
    *,
    check_git_identity: bool,
) -> int:
    record = fingerprints.get("register_map")
    if not isinstance(record, dict):
        raise CheckError("register-map fingerprint is missing")
    relative = str(record.get("path", ""))
    raw_offsets = record.get("offsets")
    if not relative or not isinstance(raw_offsets, dict):
        raise CheckError("register-map fingerprint is malformed")
    expected = {str(name): int(value) for name, value in raw_offsets.items()}
    current = register_offsets(
        (root / GENERATED_REGISTER_MAP_PATH).read_text(encoding="utf-8")
    )
    if current != expected:
        raise CheckError(
            f"AXI offset map changed: base={expected!r}, current={current!r}"
        )
    if check_git_identity:
        base = register_offsets(git_file(root, BASE_COMMIT, relative))
        if base != expected:
            raise CheckError("stored register fingerprint disagrees with base")
    if max(current.values()) != 0x60:
        raise CheckError("public AXI register range is no longer 0x00..0x60")
    return len(current)


def check_pipeline(root: Path) -> None:
    core_text = (root / "rtl/protection_core_top.v").read_text(
        encoding="utf-8"
    )
    core = extract_module(core_text, "stage2g_protection_core")
    pipeline = extract_module(
        (root / "rtl/fault_classifier.v").read_text(encoding="utf-8"),
        "stage2g_fault_evaluation_pipeline",
    )
    controller = extract_module(
        (root / "rtl/protection_fsm.v").read_text(encoding="utf-8"),
        "stage2g_fault_episode_controller",
    )

    # Edge 0 -> edge 1 -> edge 2 -> edge 3, with no bubble insertion.
    for token, label in (
        ("accepted_sample_valid <= sample_accept_event;", "edge-0 capture"),
        ("sample_decision_valid <= accepted_sample_valid;", "edge-1 decision"),
        (".evaluation_input_valid(sample_decision_valid)", "edge-2 input"),
        (".fault_eval_valid(fault_eval_valid)", "edge-3 policy input"),
        ("accepted_sample_sequence <= sample_sequence;", "sequence capture"),
        ("decision_sequence <= accepted_sample_sequence;", "sequence carry"),
        (
            "decision_integrity_clean <= accepted_integrity_clean;",
            "integrity carry",
        ),
    ):
        require(core, token, label)
    require(
        pipeline,
        "fault_eval_valid <= evaluation_input_valid;",
        "one evaluation valid per pipeline input",
    )
    require(
        pipeline,
        "fault_eval_bitmap <= evaluation_bitmap;",
        "bitmap registered with evaluation",
    )
    require(
        pipeline,
        "fault_eval_sequence <= evaluation_input_sequence;",
        "sequence registered with evaluation",
    )
    require(
        pipeline,
        r"fault_eval_integrity_clean\s*<=\s*"
        r"evaluation_input_integrity_clean\s*;",
        "integrity registered with evaluation",
        regex=True,
    )
    reject(
        pipeline,
        r"fault_eval_valid\s*<=\s*evaluation_input_valid\s*&&",
        "zero-bitmap evaluation suppression",
        regex=True,
    )

    # Clear is retirement ordered: an already-pending request and a current
    # valid evaluation resolve; a same-edge new request is captured afterward.
    require(
        controller,
        "if (clear_pending && fault_eval_valid)",
        "evaluation-fenced clear resolution",
    )
    require(
        controller,
        "if (!clear_pending && clear_fault)",
        "same-edge request capture",
    )
    require(
        controller,
        r"fault_eval_integrity_clean\s*&&\s*"
        r"\(fault_eval_bitmap\s*==\s*6'd0\)",
        "clean-zero clear acceptance",
        regex=True,
    )
    require(
        controller,
        r"fault_seen_bitmap\s*<=\s*fault_seen_bitmap\s*\|\s*"
        r"fault_eval_bitmap\s*;",
        "monotonic seen bitmap",
        regex=True,
    )
    require(controller, "state <= ST_RESET_WAIT;", "accepted-clear state")
    require(controller, "pwm_disable <= 1'b1;", "safe-output hold")


def check_production_wiring(root: Path) -> None:
    wrapper_text = (
        root / "rtl/protection_ip_top_async_adc_axi_lite.v"
    ).read_text(encoding="utf-8")
    wrapper = extract_module(
        wrapper_text, "protection_ip_top_async_adc_axi_lite"
    )
    require(
        wrapper,
        "stage2g_adc_sample_cdc_bridge",
        "metadata-aware CDC bridge",
    )
    require(
        wrapper,
        "stage2g_protection_ip_axi_lite",
        "metadata-aware destination",
    )
    for token, label in (
        (".sample_valid(dst_sample_valid)", "raw destination-delivery valid authority"),
        (".sample_sequence(dst_sample_sequence)", "raw sequence authority"),
        (
            ".sample_source_integrity_clean(\n            dst_sample_integrity_clean)",
            "transaction integrity authority",
        ),
    ):
        require(wrapper, token, label)

    reg_text = (root / "rtl/protection_ip_top_reg_controlled.v").read_text(
        encoding="utf-8"
    )
    reg_module = extract_module(reg_text, "stage2g_protection_ip_reg_controlled")
    core_call_start = reg_module.index("stage2g_protection_core")
    core_call = reg_module[core_call_start:]
    core_call = core_call[: core_call.index(");") + 2]
    reject(core_call, "normalized_", "normalized telemetry gates policy")
    reject(
        core_call,
        "obs_status_w1c_clear",
        "software W1C gates policy",
    )
    reject(
        core_call,
        "synced_source_",
        "delayed synchronized counters gate policy",
    )

    # Stage 2F-D remains an observational fork of the same accepted raw destination delivery.
    require(
        wrapper,
        ".raw_delivery_valid(dst_sample_valid)",
        "normalized observational fork",
    )
    require(
        wrapper,
        ".raw_sequence(dst_sample_sequence)",
        "normalized sequence fork",
    )


def check_nonclaims(
    root: Path, fingerprints: dict[str, object]
) -> None:
    raw_paths = fingerprints.get("expected_changed_paths")
    if not isinstance(raw_paths, list):
        raise CheckError("frozen diff fingerprint path inventory is missing")
    changed_rtl = "\n".join(
        (root / str(path)).read_text(encoding="utf-8")
        for path in raw_paths
        if str(path).startswith("rtl/")
    )
    for pattern, label in (
        (r"\bwatchdog\b", "sample-liveness watchdog"),
        (r"\bcalibrat(?:e|ed|ion)\b", "calibration"),
        (r"\b(?:ampere|amps|volt|watts?|celsius)\b", "physical-unit claim"),
    ):
        if re.search(pattern, changed_rtl, flags=re.IGNORECASE):
            raise CheckError(f"forbidden Stage 2G scope addition: {label}")


def compact(text: str) -> str:
    return re.sub(r"\s+", "", strip_comments(text))


def check_sequence_integrity(root: Path) -> None:
    destination_text = (
        root / "rtl/transaction_destination_observer.v"
    ).read_text(encoding="utf-8")
    classifier = extract_module(
        destination_text, "stage2e_transaction_sequence_classifier"
    )
    observer = extract_module(
        destination_text, "transaction_destination_observer"
    )
    core_text = (root / "rtl/protection_core_top.v").read_text(
        encoding="utf-8"
    )
    core = extract_module(core_text, "stage2g_protection_core")
    pipeline = extract_module(
        (root / "rtl/fault_classifier.v").read_text(encoding="utf-8"),
        "stage2g_fault_evaluation_pipeline",
    )
    controller = extract_module(
        (root / "rtl/protection_fsm.v").read_text(encoding="utf-8"),
        "stage2g_fault_episode_controller",
    )
    reg_controlled = extract_module(
        (root / "rtl/protection_ip_top_reg_controlled.v").read_text(
            encoding="utf-8"
        ),
        "stage2g_protection_ip_reg_controlled",
    )
    axi = extract_module(
        (root / "rtl/protection_ip_top_axi_lite.v").read_text(
            encoding="utf-8"
        ),
        "stage2g_protection_ip_axi_lite",
    )
    production = extract_module(
        (root / "rtl/protection_ip_top_async_adc_axi_lite.v").read_text(
            encoding="utf-8"
        ),
        "protection_ip_top_async_adc_axi_lite",
    )

    for body, module in (
        (classifier, "stage2e_transaction_sequence_classifier"),
        (pipeline, "stage2g_fault_evaluation_pipeline"),
        (controller, "stage2g_fault_episode_controller"),
        (core, "stage2g_protection_core"),
        (reg_controlled, "stage2g_protection_ip_reg_controlled"),
        (axi, "stage2g_protection_ip_axi_lite"),
    ):
        require(
            compact(body),
            "parameterSEQUENCE_WIDTH=",
            f"{module} SEQUENCE_WIDTH parameter",
        )

    sequence_fields = {
        "stage2g_fault_evaluation_pipeline": (
            "evaluation_input_sequence",
            "fault_eval_sequence",
        ),
        "stage2g_fault_episode_controller": (
            "fault_eval_sequence",
            "clear_resolution_sequence",
        ),
        "stage2g_protection_core": (
            "sample_sequence",
            "accepted_sample_sequence",
            "expected_sample_sequence",
            "last_sample_sequence",
            "decision_sequence",
            "fault_eval_sequence",
            "clear_resolution_sequence",
            "sequence_delta",
        ),
        "stage2g_protection_ip_reg_controlled": (
            "sample_sequence",
            "fault_eval_sequence",
            "clear_resolution_sequence",
        ),
        "stage2g_protection_ip_axi_lite": ("sample_sequence",),
    }
    module_bodies = {
        "stage2g_fault_evaluation_pipeline": pipeline,
        "stage2g_fault_episode_controller": controller,
        "stage2g_protection_core": core,
        "stage2g_protection_ip_reg_controlled": reg_controlled,
        "stage2g_protection_ip_axi_lite": axi,
    }
    for module, fields in sequence_fields.items():
        body = module_bodies[module]
        for field in fields:
            require(
                body,
                rf"\[\s*SEQUENCE_WIDTH\s*-\s*1\s*:\s*0\s*\]"
                rf"(?:\s|\n)+{re.escape(field)}\b",
                f"parameterized {module}.{field}",
                regex=True,
            )

    classifier_compact = compact(classifier)
    for expression, label in (
        (
            "assignexpected_delivery=delivery_valid&&"
            "(delivery_sequence==expected_sequence);",
            "expected-delivery classification",
        ),
        (
            "assignduplicate_delivery=delivery_valid&&!expected_delivery&&"
            "has_last_delivery&&"
            "(delivery_sequence==last_destination_sequence);",
            "duplicate classification",
        ),
        (
            "assignstale_first_delivery=delivery_valid&&!expected_delivery&&"
            "!has_last_delivery;",
            "first-stale classification",
        ),
        (
            "assignsequence_gap=delivery_valid&&!expected_delivery&&"
            "!duplicate_delivery&&!stale_first_delivery&&"
            "!sequence_delta[SEQUENCE_WIDTH-1];",
            "forward-gap classification",
        ),
        (
            "assignreorder_or_stale=delivery_valid&&!expected_delivery&&"
            "!duplicate_delivery&&!sequence_gap;",
            "reorder/stale classification",
        ),
    ):
        require(classifier_compact, expression, label)
    require(
        classifier_compact,
        "assignsequence_delta=delivery_sequence-expected_sequence;",
        "modulo-width sequence delta",
    )
    reject(
        classifier,
        r"sequence_delta\s*\[\s*31\s*\]",
        "bit-31 sequence delta classification",
        regex=True,
    )

    for body, label in (
        (observer, "Stage 2E observer"),
        (core, "Stage 2G policy"),
    ):
        if compact(body).count("stage2e_transaction_sequence_classifier#(") != 1:
            raise CheckError(
                f"{label} does not instantiate exactly one shared classifier"
            )
        require(
            compact(body),
            ".SEQUENCE_WIDTH(SEQUENCE_WIDTH)",
            f"{label} classifier width binding",
        )

    observer_compact = compact(observer)
    require(
        observer_compact,
        "if(expected_delivery)expected_sequence<=expected_sequence+"
        "{{(SEQUENCE_WIDTH-1){1'b0}},1'b1};"
        "elseif(sequence_gap_event)expected_sequence<=delivery_sequence+"
        "{{(SEQUENCE_WIDTH-1){1'b0}},1'b1};",
        "Stage 2E retain-or-resync expected sequence",
    )
    core_compact = compact(core)
    require(
        core_compact,
        "if(destination_sequence_clean||destination_sequence_gap)"
        "expected_sample_sequence<=sample_sequence+"
        "{{(SEQUENCE_WIDTH-1){1'b0}},1'b1};",
        "Stage 2G retain-or-resync expected sequence",
    )
    require(
        core_compact,
        "accepted_integrity_clean<=sample_source_integrity_clean&&"
        "destination_sequence_clean;",
        "only matching transaction restores policy eligibility",
    )

    for body, token, label in (
        (core, ".SEQUENCE_WIDTH(SEQUENCE_WIDTH)", "core child propagation"),
        (
            reg_controlled,
            ".SEQUENCE_WIDTH(SEQUENCE_WIDTH)",
            "reg-controlled propagation",
        ),
        (axi, ".SEQUENCE_WIDTH(SEQUENCE_WIDTH)", "AXI propagation"),
        (
            production,
            ".SEQUENCE_WIDTH(OBS_SEQUENCE_WIDTH)",
            "production OBS sequence binding",
        ),
    ):
        require(compact(body), token, label)
    if compact(core).count(".SEQUENCE_WIDTH(SEQUENCE_WIDTH)") < 3:
        raise CheckError("core sequence width is not propagated to all children")
    require(
        compact(axi),
        "parameterSEQUENCE_WIDTH=OBS_SEQUENCE_WIDTH",
        "AXI sequence-width equality default",
    )
    require(
        compact(reg_controlled),
        "parameterSEQUENCE_WIDTH=OBS_SEQUENCE_WIDTH",
        "reg-controlled sequence-width equality default",
    )

    matrix = (root / "tb/stage2g/tb_stage2g_sequence_integrity_matrix.sv").read_text(
        encoding="utf-8"
    )
    runner = (root / "tools/run_stage2g_functional_rtl.py").read_text(
        encoding="utf-8"
    )
    for width in (16, 24, 32):
        require(
            matrix,
            f"module tb_stage2g_sequence_width_{width};",
            f"sequence matrix width {width}",
        )
        require(
            runner,
            f"f\"tb_stage2g_sequence_width_{{sequence_width}}\"",
            f"runner width {width} dispatch",
        )
    require(
        compact(runner),
        "forsequence_widthin(16,24,32):",
        "16/24/32 runner matrix",
    )
    if runner.count("strict_sequence_width=True") < 2:
        raise CheckError("Icarus/XSim sequence warning gates are incomplete")
    if runner.count("reject_sequence_width_warnings(") < 3:
        raise CheckError("sequence compiler warnings are not fail-closed")
    require(
        runner,
        '"STAGE2G_SEQUENCE_MATRIX=FAIL"',
        "sequence fixture failure-token rejection",
    )


def check_status(root: Path) -> None:
    status = (root / "spec/stage2g_reset_wait_first_fault_policy_status.json").read_text(
        encoding="utf-8"
    )
    for token in (
        '"reset_wait_first_fault_policy_gap_closed": false',
        '"remaining_contract_gaps": 2',
        '"stage2_complete": false',
    ):
        require(status, token, f"preserved status {token}")


def check_software_recovery_predicate(
    root: Path, fingerprints: dict[str, object]
) -> None:
    record = fingerprints.get("software_recovery_predicate")
    if not isinstance(record, dict):
        raise CheckError("software recovery predicate fingerprint is missing")
    relative = str(record.get("path", ""))
    function_name = str(record.get("function", ""))
    expected = str(record.get("ast_sha256", ""))
    if not relative or not function_name or not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise CheckError("software recovery predicate fingerprint is malformed")
    tree = ast.parse((root / relative).read_text(encoding="utf-8"))
    matches = [
        node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == function_name
    ]
    if len(matches) != 1:
        raise CheckError("software recovery predicate definition is not unique")
    digest = hashlib.sha256(
        ast.dump(matches[0], include_attributes=False).encode("utf-8")
    ).hexdigest()
    if digest != expected:
        raise CheckError("software recovery predicate changed")


def check_recovery_observability(root: Path) -> None:
    controller = extract_module(
        (root / "rtl/protection_fsm.v").read_text(encoding="utf-8"),
        "stage2g_fault_episode_controller",
    )
    core = extract_module(
        (root / "rtl/protection_core_top.v").read_text(encoding="utf-8"),
        "stage2g_protection_core",
    )
    reg_controlled = extract_module(
        (root / "rtl/protection_ip_top_reg_controlled.v").read_text(
            encoding="utf-8"
        ),
        "stage2g_protection_ip_reg_controlled",
    )
    register_bank = extract_module(
        (root / "rtl/protection_reg_bank.v").read_text(encoding="utf-8"),
        "protection_reg_bank",
    )

    controller_compact = compact(controller)
    for token, label in (
        ("outputregpublic_fault_latched_compat", "public compatibility latch"),
        ("outputreg[7:0]public_fault_code_compat", "public compatibility code"),
        ("outputregpost_clear_recovery_pending", "post-clear pending state"),
        ("public_fault_latched_compat<=1'b1;", "episode-start public latch"),
        ("public_fault_code_compat<=fault_eval_code;", "episode-start public code"),
        ("post_clear_recovery_pending<=1'b1;", "clear recovery pending"),
    ):
        require(controller_compact, token, label)
    if controller_compact.count("public_fault_latched_compat<=1'b0;") != 4:
        raise CheckError(
            "public compatibility latch must clear only on reset, healthy re-arm, ARMED hold, and invalid-state recovery"
        )
    if controller_compact.count("public_fault_code_compat<=`FAULT_NONE;") != 4:
        raise CheckError(
            "public compatibility code must clear only on reset, healthy re-arm, ARMED hold, and invalid-state recovery"
        )
    if controller_compact.count("post_clear_recovery_pending<=1'b1;") != 1:
        raise CheckError("post-clear recovery pending must be set only by legal clear")

    accept_start_token = (
        "if(fault_eval_integrity_clean&&(fault_eval_bitmap==6'd0))begin"
    )
    accept_start = controller_compact.find(accept_start_token)
    if accept_start < 0:
        raise CheckError("legal clear acceptance block is missing")
    accept_end = controller_compact.find("endelsebegin", accept_start)
    if accept_end < 0:
        raise CheckError("legal clear acceptance block is malformed")
    accept_block = controller_compact[accept_start:accept_end]
    require(
        accept_block,
        "post_clear_recovery_pending<=1'b1;",
        "clear enters public recovery pending",
    )
    for forbidden, label in (
        ("public_fault_latched_compat<=1'b0;", "clear acceptance clears public STATUS latch"),
        ("public_fault_code_compat<=`FAULT_NONE;", "clear acceptance clears public FAULT_CODE"),
    ):
        reject(accept_block, forbidden, label)

    require(
        controller_compact,
        "if(fault_eval_valid&&fault_eval_integrity_clean)begin"
        "if(fault_eval_bitmap!=6'd0)start_fault_episode();elsebegin"
        "state<=ST_ARMED;public_fault_latched_compat<=1'b0;"
        "public_fault_code_compat<=`FAULT_NONE;"
        "post_clear_recovery_pending<=1'b0;",
        "only a clean healthy RESET_WAIT evaluation clears public recovery status",
    )

    core_compact = compact(core)
    for token, label in (
        (".fault_latched(episode_active)", "internal episode-active connection"),
        (".fault_code_latched(episode_fault_code)", "internal episode-code connection"),
        (".public_fault_latched_compat(fault_latched)", "public latch boundary"),
        (".public_fault_code_compat(fault_code_latched)", "public code boundary"),
        (".post_clear_recovery_pending(post_clear_recovery_pending)", "pending boundary"),
    ):
        require(core_compact, token, label)

    reg_compact = compact(reg_controlled)
    if reg_compact.count(".fault_latched(fault_latched)") < 2:
        raise CheckError("register bank is not wired to the public compatibility latch")
    if reg_compact.count(".fault_code_latched(fault_code_latched)") < 2:
        raise CheckError("register bank is not wired to the public compatibility code")
    register_bank_compact = compact(register_bank)
    legacy_status = "REG_STATUS:rd_data={30'd0,fault_latched,fault_valid};"
    generated_status = (
        "`PROTECTION_REG_STATUS:begin"
        "rd_data[`PROTECTION_STATUS_FAULT_VALID_LSB]=fault_valid;"
        "rd_data[`PROTECTION_STATUS_FAULT_LATCHED_LSB]=fault_latched;end"
    )
    if (
        legacy_status not in register_bank_compact
        and generated_status not in register_bank_compact
    ):
        raise CheckError("missing existing STATUS register public latch input")

    legacy_fault_code = (
        "REG_FAULT_CODE:rd_data={24'd0,fault_code_latched};"
    )
    generated_fault_code = (
        "`PROTECTION_REG_FAULT_CODE:"
        "rd_data[`PROTECTION_FAULT_CODE_LATCHED_MSB:"
        "`PROTECTION_FAULT_CODE_LATCHED_LSB]=fault_code_latched;"
    )
    if (
        legacy_fault_code not in register_bank_compact
        and generated_fault_code not in register_bank_compact
    ):
        raise CheckError("missing existing FAULT_CODE register public code input")


def check_source_map_implementation(root: Path) -> tuple[int, int]:
    source_map = json.loads(
        (root / "spec/stage2g_reset_wait_first_fault_policy_source_map.json")
        .read_text(encoding="utf-8")
    )
    baseline = source_map.get("baseline_entries")
    implementation = source_map.get("implementation_entries")
    trace = source_map.get("implemented_path_trace")
    if not isinstance(baseline, list) or len(baseline) != 17:
        raise CheckError("source map does not preserve 17 baseline entries")
    if not isinstance(implementation, list) or len(implementation) < 9:
        raise CheckError("implemented source path lacks implementation entries")
    required = {
        "module_file",
        "module",
        "signals",
        "clock_reset_domain",
        "producer",
        "consumer",
        "logic_kind",
        "pipeline_offset",
        "reset_behavior",
        "visibility",
        "tests",
    }
    ids = set()
    for entry in implementation:
        if not isinstance(entry, dict) or not required.issubset(entry):
            raise CheckError("source map implementation entry is incomplete")
        if any(entry[field] in (None, "", []) for field in required):
            raise CheckError("source map implementation entry has an empty field")
        ids.add(entry.get("implementation_id"))
    if not isinstance(trace, dict) or trace.get("path_status") != "IMPLEMENTED_AND_VALIDATED":
        raise CheckError("source map implemented path trace is missing")
    traced = set(trace.get("source_to_public_status", [])) | set(
        trace.get("source_to_safe_output", [])
    )
    if None in ids or not ids.issubset(traced):
        raise CheckError("source map implemented path trace is incomplete")
    return len(baseline), len(implementation)


def run(root: Path, *, check_git_identity: bool) -> dict[str, int]:
    fingerprints = load_fingerprints(root)
    if check_git_identity:
        branch = git(root, "branch", "--show-current").strip()
        if branch != BRANCH:
            raise CheckError(f"wrong implementation branch: {branch}")
        main = git(root, "rev-parse", "main").strip()
        remote_main = git(root, "rev-parse", "origin/main").strip()
        if main != BASE_COMMIT or remote_main != BASE_COMMIT:
            raise CheckError("main/origin-main does not match the frozen base")
    scope_count = check_scope(
        root, fingerprints, check_git_identity=check_git_identity
    )
    interface_count = check_interfaces(
        root, fingerprints, check_git_identity=check_git_identity
    )
    register_count = check_register_map(
        root, fingerprints, check_git_identity=check_git_identity
    )
    check_pipeline(root)
    check_production_wiring(root)
    check_sequence_integrity(root)
    check_recovery_observability(root)
    check_software_recovery_predicate(root, fingerprints)
    source_baseline, source_implementation = check_source_map_implementation(root)
    check_nonclaims(root, fingerprints)
    check_status(root)
    return {
        "changed_paths": scope_count,
        "interfaces": interface_count,
        "registers": register_count,
        "source_baseline": source_baseline,
        "source_implementation": source_implementation,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).parents[1])
    parser.add_argument("--no-git-check", action="store_true")
    args = parser.parse_args(argv)
    try:
        result = run(
            args.root.resolve(), check_git_identity=not args.no_git_check
        )
    except (OSError, CheckError) as exc:
        print(f"STAGE2G_IMPLEMENTATION_STATIC=FAIL: {exc}", file=sys.stderr)
        return 1
    print("STAGE2G_IMPLEMENTATION_STATIC=PASS")
    print("REPOSITORY_FALLBACK_USED=NO")
    print(f"STAGE2G_CHANGED_PATH_SCOPE=PASS_{result['changed_paths']}")
    print(
        "LEGACY_MODULE_PORT_LIST_INVARIANCE="
        f"PASS_{result['interfaces']}_OF_{result['interfaces']}"
    )
    print(
        "AXI_REGISTER_OFFSET_INVARIANCE="
        f"PASS_{result['registers']}_OF_{result['registers']}"
    )
    print("FAULT_EVALUATION_FIXED_LATENCY_STATIC=PASS")
    print("FAULT_EVALUATION_ALIGNMENT_STATIC=PASS")
    print("FAULT_EVAL_SEQUENCE_WIDTH=OBS_SEQUENCE_WIDTH")
    print("SUPPORTED_SEQUENCE_WIDTHS=16_TO_32")
    print("IMPLICIT_STAGE2G_SEQUENCE_PORT_RESIZE=NO")
    print("POLICY_INTEGRITY_EQUALS_STAGE2E_TRANSACTION_CLASSIFICATION=PASS")
    print("NORMALIZED_TELEMETRY_GATES_FAULT_POLICY=NO")
    print("EVENTUALLY_CONSISTENT_SOURCE_COUNTER_GATES_POLICY=NO")
    print("SOFTWARE_W1C_STICKY_GATES_POLICY=NO")
    print("NEW_AXI_OFFSETS_ADDED=NO")
    print("EXTERNAL_INTERFACE_CHANGE_REQUIRED=NO")
    print("SAMPLE_LIVENESS_WATCHDOG_ADDED=NO")
    print("PHYSICAL_UNIT_CLAIM=NO")
    print("INTERNAL_EPISODE_END=LEGAL_CLEAR_ACCEPTANCE")
    print(
        "PUBLIC_RECOVERY_COMPLETE="
        "LATER_CLEAN_HEALTHY_EVALUATION_ENTERING_ARMED"
    )
    print("CLEAR_ACCEPTANCE_EQUALS_PUBLIC_RECOVERY_COMPLETE=NO")
    print("PUBLIC_STATUS_OWNER=EXISTING_STATUS_AND_FAULT_CODE_REGISTERS")
    print("SOFTWARE_RECOVERY_PREDICATE_FINGERPRINT=PASS")
    print(f"SOURCE_MAP_BASELINE_ENTRIES=PASS_{result['source_baseline']}")
    print(
        "SOURCE_MAP_IMPLEMENTATION_ENTRIES="
        f"PASS_{result['source_implementation']}"
    )
    print("SOURCE_MAP_IMPLEMENTED_PATH_TRACE=PASS")
    print("RESET_WAIT_FIRST_FAULT_POLICY_GAP_CLOSED=NO")
    print("REMAINING_CONTRACT_GAPS=2")
    print("STAGE2_COMPLETE=NO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
