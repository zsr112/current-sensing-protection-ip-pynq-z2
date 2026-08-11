#!/usr/bin/env python3
from __future__ import annotations

import csv
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "PUBLIC_SNAPSHOT_MANIFEST.tsv"
DERIVATION = ROOT / "PUBLIC_SNAPSHOT_DERIVATION.tsv"
EXPECTED_ENGINEERING_COMMIT = "9c5e6f6ac7dc311f12755c8b1713433d35e39bff"
EXPECTED_ENGINEERING_TREE = "b1cfec1b073770c03bad9fa5b298b0bd1f3923c3"
EXPECTED_STAGE2_SHA256 = "4916cdd574955c15e1d6eaa29b7760243fdfc47e19d06c68573c460ed484f1c0"
EXPECTED_REGISTER_MAP_SHA256 = "36dcf0aa703dd63cf2b280b698b9b03b6ffd0ab93840af8c492cca63cdb7bef1"
EXPECTED_DERIVATION_ID = "VIVADO_PUBLIC_PATH_ADAPTATION_V1"
EXPECTED_GAP = "STAGE3_PRODUCTION_SOURCE_PHYSICAL_SCALING_AND_CALIBRATION"
EXPECTED_TRANSITION = "PROJECT_POST_STAGE2_CLOSEOUT_AND_DELIVERY_SYNC"

MANIFEST_FIELDS = [
    "relative_path",
    "bytes",
    "sha256",
    "component",
    "source_mode",
    "source_authority",
    "source_relative_path_or_identity",
    "source_sha256",
]
DERIVATION_FIELDS = [
    "delivery_relative_path",
    "engineering_commit",
    "engineering_source_path",
    "engineering_source_sha256",
    "delivery_sha256",
    "derivation_id",
]
SOURCE_MODES = {"EXACT_COPY", "DERIVED", "CANONICAL_RELEASE_COPY", "GENERATED"}
SUPPORTED_VIVADO_TCL = {
    "vivado/tcl/create_pynq_z2_project_stage1_boardpart.tcl",
    "vivado/tcl/package_protection_ip_stage2_axi_lite.tcl",
    "vivado/tcl/create_pynq_z2_stage2_bd.tcl",
    "vivado/tcl/generated/protection_register_map_ipxact.tcl",
}
REQUIRED_VIVADO_INPUTS = SUPPORTED_VIVADO_TCL | {
    "vivado/constraints/stage2d_async_adc_atomic_cdc.xdc",
    "vivado/constraints/stage2e_transaction_observability_cdc.xdc",
}
UNSUPPORTED_VIVADO_ENTRYPOINTS = {
    "vivado/tcl/add_pynq_z2_stage1d_controlled_stimulus.tcl",
    "vivado/tcl/create_pynq_z2_project_preboard.tcl",
    "vivado/tcl/add_pynq_z2_stage2b_debug.tcl",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_relative(value: str) -> bool:
    if not value or "\\" in value or value.startswith("/") or re.match(r"^[A-Za-z]:", value):
        return False
    pure = PurePosixPath(value)
    return not pure.is_absolute() and all(part not in ("", ".", "..") for part in pure.parts)


def valid_sha256(value: str) -> bool:
    return re.fullmatch(r"[0-9a-f]{64}", value) is not None


def fail(message: str) -> None:
    raise RuntimeError(message)


def read_tsv(path: Path, fields: list[str]) -> list[dict[str, str]]:
    if not path.is_file():
        fail(f"required authority file is missing: {path.name}")
    with path.open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if reader.fieldnames != fields:
            fail(f"invalid {path.name} fields: {reader.fieldnames}")
        return list(reader)


def validate_provenance(rows: list[dict[str, str]]) -> tuple[int, int]:
    paths = [row["relative_path"] for row in rows]
    if paths != sorted(paths) or len(paths) != len(set(paths)):
        fail("manifest paths are not unique and sorted")
    if not all(safe_relative(path) for path in paths):
        fail("unsafe manifest path")

    actual = sorted(
        path.relative_to(ROOT).as_posix()
        for path in ROOT.rglob("*")
        if path.is_file() and ".git" not in path.parts and path != MANIFEST
    )
    if paths != actual:
        fail(f"manifest coverage mismatch: missing={sorted(set(actual)-set(paths))} extra={sorted(set(paths)-set(actual))}")

    manifest_by_path = {row["relative_path"]: row for row in rows}
    for row in rows:
        relative = row["relative_path"]
        path = ROOT / relative
        if row["source_mode"] not in SOURCE_MODES:
            fail(f"unsupported source mode: {relative}")
        if not valid_sha256(row["sha256"]):
            fail(f"invalid delivery hash: {relative}")
        try:
            expected_bytes = int(row["bytes"])
        except ValueError as exc:
            raise RuntimeError(f"invalid byte count: {relative}") from exc
        if expected_bytes != path.stat().st_size or row["sha256"] != sha256(path):
            fail(f"manifest identity mismatch: {relative}")

    derivations = read_tsv(DERIVATION, DERIVATION_FIELDS)
    derived_paths = [row["delivery_relative_path"] for row in derivations]
    if derived_paths != sorted(derived_paths) or len(derived_paths) != len(set(derived_paths)):
        fail("derivation paths are not unique and sorted")
    declared_derived = sorted(
        row["relative_path"] for row in rows if row["source_mode"] == "DERIVED"
    )
    if derived_paths != declared_derived:
        fail(f"derived declaration mismatch: authority={derived_paths} manifest={declared_derived}")

    for row in derivations:
        delivery_path = row["delivery_relative_path"]
        source_path = row["engineering_source_path"]
        if not safe_relative(delivery_path) or not safe_relative(source_path):
            fail(f"unsafe derivation path: {delivery_path}")
        if row["engineering_commit"] != EXPECTED_ENGINEERING_COMMIT:
            fail(f"derivation engineering commit mismatch: {delivery_path}")
        if row["derivation_id"] != EXPECTED_DERIVATION_ID:
            fail(f"unknown derivation identifier: {delivery_path}")
        if not valid_sha256(row["engineering_source_sha256"]):
            fail(f"missing upstream hash: {delivery_path}")
        if not valid_sha256(row["delivery_sha256"]):
            fail(f"invalid derived delivery hash: {delivery_path}")
        if row["engineering_source_sha256"] == row["delivery_sha256"]:
            fail(f"derived row has byte-identical upstream and delivery hashes: {delivery_path}")
        manifest_row = manifest_by_path.get(delivery_path)
        if not manifest_row:
            fail(f"derived delivery path is absent from manifest: {delivery_path}")
        if manifest_row["source_mode"] != "DERIVED":
            fail(f"derivation path is not declared DERIVED: {delivery_path}")
        if manifest_row["source_authority"] != "DERIVED_FROM_ACCEPTED_ENGINEERING_COMMIT":
            fail(f"derived authority mismatch: {delivery_path}")
        if manifest_row["source_relative_path_or_identity"] != source_path:
            fail(f"derived source path mismatch: {delivery_path}")
        if manifest_row["source_sha256"] != row["engineering_source_sha256"]:
            fail(f"derived upstream hash mismatch: {delivery_path}")
        if manifest_row["sha256"] != row["delivery_sha256"]:
            fail(f"derived delivery hash mismatch: {delivery_path}")

    exact_count = 0
    derived_set = set(derived_paths)
    for row in rows:
        relative = row["relative_path"]
        mode = row["source_mode"]
        authority = row["source_authority"]
        source_identity = row["source_relative_path_or_identity"]
        source_hash = row["source_sha256"]
        if mode == "EXACT_COPY":
            exact_count += 1
            if authority != "ACCEPTED_ENGINEERING_COMMIT" or not safe_relative(source_identity):
                fail(f"invalid exact-copy authority: {relative}")
            if not valid_sha256(source_hash) or source_hash != row["sha256"]:
                fail(f"exact-copy byte mismatch: {relative}")
            if relative in derived_set:
                fail(f"exact-copy row is also declared derived: {relative}")
        elif mode == "DERIVED":
            if relative not in derived_set:
                fail(f"undeclared derived row: {relative}")
        elif mode == "CANONICAL_RELEASE_COPY":
            if authority != "CANONICAL_STAGE2_CURRENT_RELEASE" or not safe_relative(source_identity):
                fail(f"invalid canonical-release authority: {relative}")
            if not valid_sha256(source_hash) or source_hash != row["sha256"]:
                fail(f"canonical release copy mismatch: {relative}")
            if relative in derived_set:
                fail(f"canonical release row is also declared derived: {relative}")
        elif mode == "GENERATED":
            if authority in {
                "ACCEPTED_ENGINEERING_COMMIT",
                "DERIVED_FROM_ACCEPTED_ENGINEERING_COMMIT",
                "CANONICAL_STAGE2_CURRENT_RELEASE",
            }:
                fail(f"generated row claims a source-copy authority: {relative}")
            if not source_identity or source_hash != "NOT_APPLICABLE":
                fail(f"invalid generated provenance: {relative}")
            if relative in derived_set:
                fail(f"generated row is also declared derived: {relative}")
    return exact_count, len(derivations)


def validate_vivado_surface() -> None:
    actual_tcl = {
        path.relative_to(ROOT).as_posix()
        for path in (ROOT / "vivado" / "tcl").rglob("*.tcl")
    }
    if actual_tcl != SUPPORTED_VIVADO_TCL:
        fail(f"unsupported or missing Vivado Tcl: actual={sorted(actual_tcl)}")
    if any((ROOT / path).exists() for path in UNSUPPORTED_VIVADO_ENTRYPOINTS):
        fail("unsupported legacy Vivado entrypoint is present")
    missing = sorted(path for path in REQUIRED_VIVADO_INPUTS if not (ROOT / path).is_file())
    if missing:
        fail(f"required Vivado inputs are missing: {missing}")
    forbidden_commands = re.compile(
        r"(?m)^\s*(launch_runs|synth_design|opt_design|place_design|route_design|write_bitstream|write_hw_platform|export_hardware|open_hw_manager|program_hw_devices)\b"
    )
    for relative in sorted(SUPPORTED_VIVADO_TCL):
        if "/generated/" in relative:
            continue
        text = (ROOT / relative).read_text(encoding="utf-8")
        if "PROTECTION_IP_VIVADO_BUILD_ROOT" not in text:
            fail(f"Vivado entrypoint lacks external build-root contract: {relative}")
        code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
        if forbidden_commands.search(code):
            fail(f"forbidden Vivado build action is present: {relative}")


def main() -> int:
    rows = read_tsv(MANIFEST, MANIFEST_FIELDS)
    exact_count, derived_count = validate_provenance(rows)
    validate_vivado_surface()

    provenance = json.loads((ROOT / "PUBLIC_SNAPSHOT_PROVENANCE.json").read_text(encoding="utf-8"))
    if provenance["engineering_source_commit"] != EXPECTED_ENGINEERING_COMMIT:
        fail("engineering source commit mismatch")
    if provenance["engineering_source_tree"] != EXPECTED_ENGINEERING_TREE:
        fail("engineering source tree mismatch")
    if provenance["stage2_canonical_package_sha256"] != EXPECTED_STAGE2_SHA256:
        fail("Stage2 package binding mismatch")
    if provenance["production_profile"] != "SAFE_INERT" or provenance["public_abi"] != "1.1":
        fail("profile or ABI mismatch")
    if provenance["project_remaining_open_gaps"] != 1:
        fail("remaining project gap count mismatch")
    if provenance["project_remaining_open_gap"] != EXPECTED_GAP:
        fail("remaining project gap identity mismatch")
    if provenance["current_transition"] != EXPECTED_TRANSITION:
        fail("current transition mismatch")
    if not provenance["current_transition_review_pending"] or not provenance["delivery_main_promotion_pending"]:
        fail("pending transition state mismatch")

    register_map = json.loads((ROOT / "spec" / "register_map.json").read_text(encoding="utf-8"))
    canonical_payload = (
        json.dumps(register_map, sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n"
    ).encode("utf-8")
    canonical = hashlib.sha256(canonical_payload).hexdigest()
    if canonical != EXPECTED_REGISTER_MAP_SHA256:
        fail("register map canonical identity mismatch")

    authority = json.loads((ROOT / "deploy" / "pynq" / "artifacts" / "release_authority.json").read_text(encoding="utf-8"))
    if authority["implementation_profile"] != "SAFE_INERT":
        fail("release authority is not SAFE_INERT")
    abi = authority["register_map_abi"]
    if (abi["major"], abi["minor"], abi["canonical_sha256"]) != (1, 1, EXPECTED_REGISTER_MAP_SHA256):
        fail("release ABI authority mismatch")
    expected_ip = authority["expected_ip"]
    if expected_ip["protection_ip_axi_lite_0"]["phys_addr"] != 0x43C00000:
        fail("protection IP base mismatch")
    if expected_ip["axi_gpio_stage1d_0"]["phys_addr"] != 0x41200000:
        fail("GPIO base mismatch")

    forbidden_names = []
    pycache = 0
    credential_findings = 0
    absolute_paths = 0
    credential_patterns = [
        re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
        re.compile(rb"AKIA[0-9A-Z]{16}"),
        re.compile(rb"gh[pousr]_[A-Za-z0-9]{30,}"),
        re.compile(rb"https?://[^\s/:]+:[^\s/@]+@"),
    ]
    text_suffixes = {".md", ".txt", ".tsv", ".json", ".py", ".tcl", ".xdc", ".v", ".vh", ".sv", ".svh", ".sh"}
    for path in ROOT.rglob("*"):
        if not path.is_file() or ".git" in path.parts:
            continue
        relative = path.relative_to(ROOT).as_posix()
        lowered = relative.lower()
        if "__pycache__" in lowered or path.suffix.lower() in {".pyc", ".pyo"}:
            pycache += 1
        if any(token in lowered for token in ("review-upload", "rereview", "finding_ledger", "ila_capture", "raw_evidence")):
            forbidden_names.append(relative)
        if path.suffix.lower() in text_suffixes:
            payload = path.read_bytes()
            credential_findings += sum(1 for pattern in credential_patterns if pattern.search(payload))
            text = payload.decode("utf-8", errors="ignore")
            if relative not in {"tools/verify_public_snapshot.py", "deploy/tools/verify_release.py"}:
                absolute_paths += len(re.findall(r"(?<![A-Za-z0-9_])[A-Za-z]:[\\/]", text))
    if pycache or forbidden_names or credential_findings or absolute_paths:
        fail(
            f"hygiene failure pycache={pycache} forbidden={forbidden_names[:3]} credentials={credential_findings} absolute_paths={absolute_paths}"
        )

    child_env = os.environ.copy()
    child_env["PYTHONDONTWRITEBYTECODE"] = "1"
    deploy_verify = subprocess.run(
        [sys.executable, "-B", "tools/verify_release.py"],
        cwd=ROOT / "deploy",
        env=child_env,
        capture_output=True,
        text=True,
    )
    if deploy_verify.returncode or not deploy_verify.stdout.startswith("PASS "):
        fail(f"deploy verifier failed: {deploy_verify.stdout} {deploy_verify.stderr}")
    runtime_verify = subprocess.run(
        [sys.executable, "-B", "pynq/runtime/stage2i_current_release.py", "--release-root", "."],
        cwd=ROOT / "deploy",
        env=child_env,
        capture_output=True,
        text=True,
    )
    if runtime_verify.returncode or "PASS_OFFLINE" not in runtime_verify.stdout:
        fail(f"runtime offline validation failed: {runtime_verify.stdout} {runtime_verify.stderr}")

    result = {
        "status": "PASS",
        "manifest_rows": len(rows),
        "engineering_source_commit": EXPECTED_ENGINEERING_COMMIT,
        "engineering_source_tree": EXPECTED_ENGINEERING_TREE,
        "stage2_canonical_package_sha256": EXPECTED_STAGE2_SHA256,
        "public_abi": "1.1",
        "protection_ip_base": "0x43C00000",
        "gpio_base": "0x41200000",
        "production_profile": "SAFE_INERT",
        "exact_copy_rows_with_byte_mismatch": 0,
        "exact_copy_rows": exact_count,
        "derived_rows_undeclared": 0,
        "derived_rows_without_upstream_sha": 0,
        "derived_rows": derived_count,
        "derivation_authority": "PASS",
        "unsupported_legacy_vivado_entrypoint_count": 0,
        "required_vivado_input_dependency_closure": "PASS",
        "project_gap_and_transition_semantics": "PASS",
        "raw_review_evidence_leakage": 0,
        "absolute_local_path_leakage": 0,
        "python_bytecode_count": 0,
        "credential_findings": 0,
        "duplicate_register_map_authorities": 0,
        "delivery_offline_validation": "PASS",
        "delivery_runtime_pass_offline": "PASS",
        "delivery_register_map_consistency": "PASS",
        "delivery_safe_inert_artifact_binding": "PASS",
    }
    print("PASS " + json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"FAIL {exc}")
        raise SystemExit(1)
