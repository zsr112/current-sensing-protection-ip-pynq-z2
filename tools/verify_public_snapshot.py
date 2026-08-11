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
EXPECTED_ENGINEERING_COMMIT = "9c5e6f6ac7dc311f12755c8b1713433d35e39bff"
EXPECTED_ENGINEERING_TREE = "b1cfec1b073770c03bad9fa5b298b0bd1f3923c3"
EXPECTED_STAGE2_SHA256 = "4916cdd574955c15e1d6eaa29b7760243fdfc47e19d06c68573c460ed484f1c0"
EXPECTED_REGISTER_MAP_SHA256 = "36dcf0aa703dd63cf2b280b698b9b03b6ffd0ab93840af8c492cca63cdb7bef1"


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


def fail(message: str) -> None:
    raise RuntimeError(message)


def main() -> int:
    rows = list(csv.DictReader(MANIFEST.open(encoding="utf-8", newline=""), delimiter="\t"))
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
    for row in rows:
        path = ROOT / row["relative_path"]
        if int(row["bytes"]) != path.stat().st_size or row["sha256"] != sha256(path):
            fail(f"manifest identity mismatch: {row['relative_path']}")

    provenance = json.loads((ROOT / "PUBLIC_SNAPSHOT_PROVENANCE.json").read_text(encoding="utf-8"))
    if provenance["engineering_source_commit"] != EXPECTED_ENGINEERING_COMMIT:
        fail("engineering source commit mismatch")
    if provenance["engineering_source_tree"] != EXPECTED_ENGINEERING_TREE:
        fail("engineering source tree mismatch")
    if provenance["stage2_canonical_package_sha256"] != EXPECTED_STAGE2_SHA256:
        fail("Stage2 package binding mismatch")
    if provenance["production_profile"] != "SAFE_INERT" or provenance["public_abi"] != "1.1":
        fail("profile or ABI mismatch")

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

    deploy_verify = subprocess.run(
        [sys.executable, "tools/verify_release.py"], cwd=ROOT / "deploy", capture_output=True, text=True
    )
    if deploy_verify.returncode or not deploy_verify.stdout.startswith("PASS "):
        fail(f"deploy verifier failed: {deploy_verify.stdout} {deploy_verify.stderr}")
    runtime_verify = subprocess.run(
        [sys.executable, "pynq/runtime/stage2i_current_release.py", "--release-root", "."],
        cwd=ROOT / "deploy",
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
