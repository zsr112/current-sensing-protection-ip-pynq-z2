#!/usr/bin/env python3
"""Fail-closed static checks for the Stage 2F-D implementation boundary."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any

try:
    from tools.generate_stage2f_adc_profile import generate, validate_profile
    from tools import stage2f_normalization_reference as reference
except ModuleNotFoundError:
    from generate_stage2f_adc_profile import generate, validate_profile  # type: ignore[no-redef]
    import stage2f_normalization_reference as reference  # type: ignore[no-redef]


ROOT = Path(__file__).resolve().parents[1]
BASE_COMMIT = "3399e4fdc28f9d4c66cf90cb5c1dc1e386eda6ae"
INVENTORY = ROOT / "spec/stage2f_digital_normalization_implementation.json"
SCHEMA = ROOT / "spec/stage2f_adc_source_profile.schema.json"
PRODUCTION = ROOT / "spec/stage2f_adc_source_profile_unconfigured.json"
GENERATED = ROOT / "rtl/generated/stage2f_adc_source_profile.svh"
NORMALIZER = ROOT / "rtl/adc_sample_code_normalizer.sv"
TOP = ROOT / "rtl/protection_ip_top_async_adc_axi_lite.v"
GENERATED_PROFILE_RUNNER = ROOT / "tools/run_stage2f_generated_profile_rtl.py"
GENERATED_PROFILE_TB = ROOT / "tb/stage2f/tb_stage2f_generated_profile_vectors.sv"
BOUNDARY_RUNNER = ROOT / "tools/run_stage2f_width_sequence_boundary.py"
BOUNDARY_TB = ROOT / "tb/stage2f/tb_stage2f_width_sequence_boundary.sv"
VALIDATION_RUNNER = ROOT / "sim/stage2f/run_stage2f_digital_normalization.ps1"


def strict_json(path: Path) -> dict[str, Any]:
    def hook(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=hook)
    if not isinstance(value, dict):
        raise ValueError(f"JSON root must be an object: {path}")
    return value


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def check_inventory() -> None:
    data = strict_json(INVENTORY)
    require(data["base_commit"] == BASE_COMMIT, "implementation base commit drifted")
    require(data["module"] == "rtl/adc_sample_code_normalizer.sv", "module authority drifted")
    require(data["production_profile"] == "UNCONFIGURED", "production profile is not UNCONFIGURED")
    require(data["production_normalized_telemetry"] == "UNAVAILABLE", "unconfigured telemetry is not unavailable")
    require(data["normalized_width"] == 13, "normalized width is not 13")
    require(data["normalized_unit"] == "SIGNED_CODE_COUNT", "normalized unit drifted")
    require(data["pipeline"] == {
        "latency_aclk": 1,
        "initiation_interval": 1,
        "data_dependent_latency": False,
        "backpressure_to_atomic_cdc": False,
        "transaction_drop": False,
    }, "pipeline contract drifted")
    require(data["raw_protection_path_active_and_unchanged"] is True, "raw path contract drifted")
    require(data["compatibility"] == {
        "data_width_policy": "RAW_GENERIC_NORMALIZATION_ONLY_AT_12",
        "normalization_data_width": 12,
        "tested_raw_data_widths": [8, 12, 16],
        "tested_sequence_widths": [16, 24, 32],
        "explicit_raw_width_binding": True,
        "explicit_sequence_width_binding": True,
        "unsupported_normalization_tied_low": True,
    }, "width/sequence compatibility authority drifted")
    require(data["verification_authority"] == {
        "configured_capability": "GENERATED_HEADER_DEFAULT_INSTANCE",
        "direct_parameter_tests": "SUPPLEMENTAL_ONLY",
        "python_reference_vectors_connected_to": ["ICARUS", "XSIM"],
        "duplicate_json_keys": "REJECTED_AT_ALL_NESTING_LEVELS",
    }, "verification authority drifted")
    require(data["placement"]["public_ports_added"] is False, "public normalized ports added")
    require(data["placement"]["axi_offsets_added"] is False, "new AXI offsets added")
    require(data["stage2g_authority"]["normalized_telemetry_gates_fault_policy"] is False,
            "normalized telemetry gates fault policy")
    require(data["validation_profile_contract"] == {
        "production_selection": False,
        "physical_unit_status": "NOT_CONFIGURED",
        "physical_accuracy_claim": False,
        "board_calibration_claim": False,
    }, "validation profile non-claim contract drifted")
    require(data["status"] == {
        "stage2f_contract_gap_closed": False,
        "physical_scaling_status": "BLOCKED_EXTERNAL_HARDWARE_FACTS",
        "remaining_contract_gaps": 2,
        "stage2_complete": False,
    }, "closure status drifted")


def check_profile() -> None:
    schema = strict_json(SCHEMA)
    production = strict_json(PRODUCTION)
    inventory = strict_json(INVENTORY)
    validate_profile(schema, production)
    require(production["profile_identity"] == "UNCONFIGURED", "reserved production identity drifted")
    require(production["production_selection"] is False, "production profile selected unexpectedly")
    require(generate(SCHEMA, PRODUCTION, GENERATED, True), "generated profile is stale")
    generated = GENERATED.read_text(encoding="utf-8")
    digest = hashlib.sha256(PRODUCTION.read_bytes()).hexdigest()
    require(f"PROFILE_INPUT_SHA256={digest}" in generated, "generated profile provenance mismatch")
    profiles = sorted((ROOT / "spec/stage2f_profiles").glob("*.json"))
    profile_identities = {profile.stem for profile in profiles}
    require(profile_identities == set(inventory["validation_profiles"]),
            "validation profile file set does not match implementation authority")
    for profile in profiles:
        value = strict_json(profile)
        validate_profile(schema, value)
        require(value["profile_identity"] == profile.stem,
                f"validation profile identity/path mismatch: {profile.name}")
        require(value["production_selection"] is False, f"validation profile selected for production: {profile.name}")
        require(value["physical_unit_status"] == "NOT_CONFIGURED", f"physical claim in {profile.name}")


def check_duplicate_key_rejection() -> None:
    profile_text = PRODUCTION.read_text(encoding="utf-8")
    schema_text = SCHEMA.read_text(encoding="utf-8")
    profile_anchor = '  "encoding": "UNKNOWN",'
    schema_anchor = '  "$schema": "https://json-schema.org/draft/2020-12/schema",'
    require(profile_text.count(profile_anchor) == 1, "profile duplicate-key fixture anchor drifted")
    require(schema_text.count(schema_anchor) == 1, "schema duplicate-key fixture anchor drifted")
    with tempfile.TemporaryDirectory(prefix="stage2f_duplicate_static_") as name:
        temporary = Path(name)
        output = temporary / "generated.svh"
        fixtures = (
            (
                "profile",
                SCHEMA,
                temporary / "duplicate_profile.json",
                profile_text.replace(profile_anchor, profile_anchor + "\n" + profile_anchor, 1),
            ),
            (
                "schema",
                temporary / "duplicate_schema.json",
                PRODUCTION,
                schema_text.replace(schema_anchor, schema_anchor + "\n" + schema_anchor, 1),
            ),
        )
        for label, schema_path, profile_path, duplicate_text in fixtures:
            target = profile_path if label == "profile" else schema_path
            target.write_text(duplicate_text, encoding="utf-8", newline="\n")
            rejected = False
            try:
                generate(schema_path, profile_path, output, False)
            except ValueError as exc:
                rejected = "duplicate JSON key" in str(exc)
            require(rejected, f"generator accepted duplicate {label} JSON key")


def check_reference_model() -> None:
    require(
        reference.exhaustive_reference_verification() == 57344,
        "reference exhaustive domain count drifted",
    )
    require(reference.verify_reference_mutations() == 5, "reference mutation count drifted")
    original = reference.normalize_code

    def wrong_normalize(raw_code: int, profile: Any, channel: int = 1) -> int | None:
        del raw_code, channel
        return 0 if profile.configured else None

    rejected = False
    reference.normalize_code = wrong_normalize
    try:
        reference.exhaustive_reference_verification()
    except AssertionError:
        rejected = True
    finally:
        reference.normalize_code = original
    require(rejected, "exhaustive reference checker accepted a wrong normalize_code")


def check_top_boundary_text(top: str) -> None:
    match = re.search(
        r"if\s*\(\s*DATA_WIDTH\s*==\s*12\s*\)\s*begin\s*:\s*"
        r"g_stage2f_normalization_supported(?P<supported>.*?)"
        r"end\s+else\s+begin\s*:\s*g_stage2f_normalization_unsupported"
        r"(?P<unsupported>.*?)end",
        top,
        re.DOTALL,
    )
    require(match is not None, "top lacks explicit supported/unsupported normalization generate boundary")
    supported = match.group("supported")
    unsupported = match.group("unsupported")
    require(
        re.search(r"adc_sample_code_normalizer\s*#\s*\(", supported) is not None,
        "supported branch does not parameterize the normalizer",
    )
    bindings = {
        key: re.sub(r"\s+", "", value)
        for key, value in re.findall(r"\.([A-Z_]+)\s*\(\s*([^()]+?)\s*\)", supported)
    }
    require(bindings.get("RAW_WIDTH") == "DATA_WIDTH", "top lacks exact RAW_WIDTH binding")
    require(
        bindings.get("SEQUENCE_WIDTH") == "OBS_SEQUENCE_WIDTH",
        "top lacks exact SEQUENCE_WIDTH binding",
    )
    require(bindings.get("NORMALIZED_WIDTH") == "13", "top lacks explicit normalized width binding")
    expected_ties = {
        "normalized_sample_valid": "1'b0",
        "normalized_sample_sequence": "{OBS_SEQUENCE_WIDTH{1'b0}}",
        "normalized_sample_ch1": "13'sd0",
        "normalized_sample_ch2": "13'sd0",
        "normalized_profile_configured": "1'b0",
        "normalized_profile_valid": "1'b0",
        "normalized_width_supported": "1'b0",
        "normalized_profile_encoding_supported": "1'b0",
        "normalized_profile_zero_code_valid": "1'b0",
        "normalized_profile_polarity_valid": "1'b0",
    }
    assignments = {
        key: re.sub(r"\s+", "", value)
        for key, value in re.findall(r"assign\s+(\w+)\s*=\s*([^;]+);", unsupported)
    }
    for signal, expected in expected_ties.items():
        require(
            assignments.get(signal) == expected,
            f"unsupported normalization tie drifted: {signal}",
        )
    require(
        re.search(r"assign\s+normalized_width_supported\s*=\s*1'b1\s*;", supported)
        is not None,
        "supported width status is not asserted",
    )


def check_top_boundary_mutation_controls(top: str) -> None:
    mutations = (
        (
            "width gate",
            "if (DATA_WIDTH == 12) begin : g_stage2f_normalization_supported",
            "if (1'b1) begin : g_stage2f_normalization_supported",
        ),
        (
            "unsupported tie",
            "assign normalized_sample_valid = 1'b0;",
            "assign normalized_sample_valid = dst_sample_valid;",
        ),
        (
            "sequence binding",
            ".RAW_WIDTH(DATA_WIDTH),\n                .SEQUENCE_WIDTH(OBS_SEQUENCE_WIDTH),\n                .NORMALIZED_WIDTH(13)",
            ".RAW_WIDTH(DATA_WIDTH),\n                .SEQUENCE_WIDTH(16),\n                .NORMALIZED_WIDTH(13)",
        ),
    )
    for label, old, new in mutations:
        require(top.count(old) == 1, f"top mutation control anchor drifted: {label}")
        rejected = False
        try:
            check_top_boundary_text(top.replace(old, new, 1))
        except ValueError:
            rejected = True
        require(rejected, f"top boundary checker accepted mutation: {label}")


def check_generated_profile_flow() -> None:
    runner = GENERATED_PROFILE_RUNNER.read_text(encoding="utf-8")
    testbench = GENERATED_PROFILE_TB.read_text(encoding="utf-8")
    validation = VALIDATION_RUNNER.read_text(encoding="utf-8")
    require('`include "generated/stage2f_adc_source_profile.svh"' in testbench,
            "generated-profile bench does not consume the generated include")
    require(
        re.search(r"adc_sample_code_normalizer\s+dut\s*\(", testbench) is not None,
        "generated-profile bench does not use a default-parameter normalizer instance",
    )
    require(
        re.search(r"adc_sample_code_normalizer\s*#\s*\(", testbench) is None,
        "generated-profile bench uses direct parameter overrides",
    )
    for token in (
        "prepare_profile_case",
        "run_matrix",
        "GENERATED_PROFILE_RTL_MATRIX=PASS_6_OF_6_ICARUS_AND_XSIM",
        "PYTHON_REFERENCE_TO_RTL_COMPARISON=PASS",
        "generated_profile_rtl_matrix.txt",
    ):
        require(token in runner, f"generated-profile runner missing contract: {token}")
    required_runs = (
        "tools/run_stage2f_generated_profile_rtl.py",
        "tools/run_stage2f_generator_mutations.py",
        "tools/run_stage2f_width_sequence_boundary.py",
        "tools/run_stage2f_boundary_mutations.py",
    )
    for script in required_runs:
        require(script in validation, f"full validation omits connected run record: {script}")

    try:
        from tools.run_stage2f_generated_profile_rtl import prepare_profile_case
    except ModuleNotFoundError:
        from run_stage2f_generated_profile_rtl import prepare_profile_case  # type: ignore[no-redef]
    profile = ROOT / "spec/stage2f_profiles/SIM_UNSIGNED_ZERO_EDGE_0.json"
    with tempfile.TemporaryDirectory(prefix="stage2f_generated_static_") as name:
        case = prepare_profile_case(profile, Path(name) / "case")
        generated = case.header.read_text(encoding="utf-8")
        require("`define STAGE2F_PROFILE_CONFIGURED 1'b1" in generated,
                "configured default-instance fixture did not generate configured RTL")
        require(case.row_count > 0 and case.vector_sha256,
                "generated-profile fixture omitted provenance-bound vectors")


def check_rtl() -> None:
    normalizer = NORMALIZER.read_text(encoding="utf-8")
    top = TOP.read_text(encoding="utf-8")
    for token in (
        "module adc_sample_code_normalizer",
        "output reg signed [NORMALIZED_WIDTH-1:0] normalized_ch1",
        "decoded = raw_wide - zero_wide;",
        "decoded = $signed({raw_code[RAW_WIDTH-1], raw_code});",
        "always @(posedge ACLK or negedge local_resetn)",
        "normalized_valid <= 1'b0;",
        "if (!profile_valid) begin",
        "raw_delivery_valid",
    ):
        require(token in normalizer, f"normalizer missing contract token: {token}")
    code_only = re.sub(r"//.*", "", normalizer)
    code_only = re.sub(r"`include[^\n]*", "", code_only)
    require(not re.search(r"\s/\s", code_only), "normalizer contains a divider")
    require(not re.search(r"\s\*\s", code_only), "normalizer contains gain arithmetic")
    require(".raw_delivery_valid(dst_sample_valid)" in top, "normalizer is not on atomic destination delivery")
    require(".sample_valid(dst_sample_valid)," in top, "raw protection sample event changed")
    require(".sample_valid(dst_sample_valid && normalized_sample_valid)," not in top,
            "raw protection is gated by normalized validity")
    require("normalized_sample_valid" not in top.split(".sample_valid(dst_sample_valid),", 1)[-1].split(";", 1)[0],
            "raw consumer sample_valid is normalized-gated")
    require("input wire normalized" not in top, "normalized signal became a public input")
    require("output wire normalized" not in top, "normalized signal became a public output")
    require("0x64" not in top and "0x68" not in top, "new AXI offsets added")
    check_top_boundary_text(top)
    check_top_boundary_mutation_controls(top)


def check_source_closure() -> None:
    required = (
        "rtl/adc_sample_code_normalizer.sv",
        "rtl/generated/stage2f_adc_source_profile.svh",
    )
    paths = (
        ROOT / "fpga/vivado/build/config/stage1d_build_config.dict",
        ROOT / "fpga/vivado/build/config/stage1e_phase2_synthesis_config_v1.dict",
        ROOT / "fpga/vivado/build/runtime/runner/stage1e_production_vivado_runner_v2.tcl",
        ROOT / "fpga/vivado/package_protection_ip_stage2_axi_lite.tcl",
        ROOT / "fpga/vivado/create_pynq_z2_project_stage1_boardpart.tcl",
        ROOT / "fpga/vivado/create_pynq_z2_project_preboard.tcl",
        ROOT / "fpga/vivado/build/tests/stage2d_source_closure_tests.tcl",
        ROOT / "fpga/vivado/build/tests/stage2e_source_closure_tests.tcl",
    )
    for path in paths:
        text = path.read_text(encoding="utf-8")
        for token in required:
            basename = token.replace("rtl/", "")
            spaced = basename.replace("/", " ")
            require(token in text or basename in text or spaced in text,
                    f"source closure missing {token}: {path.relative_to(ROOT)}")


def check_docs() -> None:
    docs = (
        ROOT / "docs/architecture/stage2f_digital_normalization_implementation.md",
        ROOT / "docs/verification/stage2f_digital_normalization_verification.md",
        ROOT / "docs/architecture/stage2f_digital_normalization_latency.md",
    )
    required = (
        "PRODUCTION_PROFILE=UNCONFIGURED",
        "NORMALIZED_UNIT=SIGNED_CODE_COUNT",
        "STAGE2F_CONTRACT_GAP_CLOSED=NO",
        "PHYSICAL_SCALING_STATUS=BLOCKED_EXTERNAL_HARDWARE_FACTS",
        "REMAINING_CONTRACT_GAPS=2",
        "STAGE2_COMPLETE=NO",
    )
    for path in docs:
        text = path.read_text(encoding="utf-8")
        for token in required:
            require(token in text, f"documentation missing {token}: {path.name}")
        for relative in re.findall(
            r"`((?:docs|spec|rtl|sw|fpga|tools|tb|sim)/[^` ]+)`", text
        ):
            require((ROOT / relative).exists(),
                    f"documentation path does not exist: {path.name}: {relative}")
    combined = "\n".join(path.read_text(encoding="utf-8") for path in docs)
    for token in (
        "CONFIGURED_CAPABILITY=GENERATED_HEADER_DEFAULT_INSTANCE",
        "DIRECT_PARAMETER_TESTS=SUPPLEMENTAL_ONLY",
        "DATA_WIDTH_COMPATIBILITY_POLICY=RAW_GENERIC_NORMALIZATION_ONLY_AT_12",
        "OBS_SEQUENCE_WIDTH_PROPAGATION=EXACT",
        "PYTHON_REFERENCE_VECTORS=CONNECTED_TO_ICARUS_AND_XSIM",
        "DUPLICATE_JSON_KEYS=REJECTED",
    ):
        require(token in combined, f"documentation missing hardening contract: {token}")


def credential_scan() -> None:
    if (ROOT / '.git').exists() and shutil.which('git'):
        result = subprocess.run(
            ['git', '-C', str(ROOT), 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
            capture_output=True, check=True,
        )
        paths = {Path(name) for name in result.stdout.decode('utf-8').split('\0') if name}
    else:
        paths = {path.relative_to(ROOT) for path in ROOT.rglob('*') if path.is_file()
                 and '__pycache__' not in path.parts}
    patterns = (
        re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
        re.compile(r"AKIA[0-9A-Z]{16}"),
        re.compile(r"gh[pousr]_[A-Za-z0-9]{30,}"),
        re.compile(r"sk-[A-Za-z0-9]{20,}"),
        re.compile(r"(?:password|passwd|api[_-]?key|client[_-]?secret)\s*[:=]\s*[\"'][^\"']{8,}[\"']", re.I),
    )
    findings: list[str] = []
    for relative in sorted(paths):
        path = ROOT / relative
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for pattern in patterns:
            if pattern.search(text):
                findings.append(f"{relative.as_posix()}:{pattern.pattern}")
    require(not findings, "credential-like material found: " + "; ".join(findings))


def main() -> int:
    try:
        check_inventory()
        check_profile()
        check_duplicate_key_rejection()
        check_reference_model()
        check_generated_profile_flow()
        check_rtl()
        check_source_closure()
        check_docs()
        credential_scan()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as exc:
        print(f"STAGE2F_IMPLEMENTATION_STATIC=FAIL: {exc}", file=sys.stderr)
        return 1
    print("STAGE2F_IMPLEMENTATION_STATIC=PASS")
    print("PRODUCTION_PROFILE=UNCONFIGURED")
    print("NORMALIZER_PIPELINE_LATENCY_ACLK=1")
    print("RAW_PROTECTION_PATH_INVARIANCE_CONTRACT=PASS")
    print("DUPLICATE_JSON_KEY_REJECTION=PASS")
    print("REFERENCE_NEGATIVE_CONTROL=PASS")
    print("TOP_BOUNDARY_NEGATIVE_CONTROLS=PASS_3_OF_3")
    print("GENERATED_PROFILE_DEFAULT_INSTANCE_STATIC=PASS")
    print("CREDENTIAL_SCAN=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
