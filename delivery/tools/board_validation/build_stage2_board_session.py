#!/usr/bin/env python3
"""Package a fresh physical build with separately identified board test tooling."""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools import stage2i_physical_authority as authority
from tools.board_validation import build_stage1_board_execution_package as package
from tools.board_validation.stage2_board_session import identity, write_json, verify_session_package
from sw import stage2i_board_runtime as runtime
from tools.source_export import verify as verify_export


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def checked_source(root):
    if (root / 'SOURCE_MANIFEST.json').is_file():
        exported = verify_export(root)
        return {**exported['origin'], 'basis': 'HASH_VERIFIED_EXPORT',
                'files': list(exported['files']), 'manifest': identity(root / 'SOURCE_MANIFEST.json')}
    if not (root / '.git').exists() or git(root, 'status', '--porcelain', '--untracked-files=all'):
        raise RuntimeError('Source must be a verified export or a clean Git checkout')
    return {'commit': git(root, 'rev-parse', 'HEAD'), 'tree': git(root, 'rev-parse', 'HEAD^{tree}'),
            'basis': 'EXACT_CLEAN_WINDOWS_CHECKOUT_FILE_BYTES',
            'files': subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z']).decode().split('\0')}


def query_version(executable):
    result = subprocess.run([str(executable), "-version"], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False, timeout=30)
    # The Windows 2024.1 launcher can return 1 after printing a valid version.
    # Preserve that exit code; identify the tool from its explicit banner/build.
    if not re.search(r"(?im)^vivado v2024\.1 \(64-bit\)$", result.stdout) or not re.search(
        r"(?m)^SW Build 5076996 on ", result.stdout
    ) or "ERROR:" in result.stdout or result.returncode not in (0, 1):
        raise RuntimeError(f"Vivado version could not be verified (exit={result.returncode}): {result.stdout}")
    return {"stdout": result.stdout.strip(), "query_exit_code": result.returncode,
            "version": "2024.1", "build": "5076996"}


def build(args):
    source = args.source_repo.resolve(strict=True)
    manifest = authority.load_artifact_manifest(args.artifact_manifest, expected_profile=runtime.READY_AWARE)
    physical_source = checked_source(source)
    tooling_source = checked_source(ROOT)
    if physical_source['commit'] != manifest.source_commit or physical_source['tree'] != manifest.source_tree:
        raise RuntimeError("Physical source identity differs from the actual build")
    if physical_source['basis'] == 'HASH_VERIFIED_EXPORT':
        request = runtime.load_json(args.artifact_manifest.parent.parent.parent / 'request.json')
        actual_result = runtime.load_json(args.artifact_manifest.parent.parent / 'vivado_result.json')
        if request['source']['export_manifest_sha256'] != physical_source['manifest']['sha256'] or request['request_identity'] != actual_result['request_identity']:
            raise RuntimeError('Source export is not bound to the physical execution request')
    physical_hardware = {name: identity(source / name) for name in physical_source['files']
                         if name.startswith(('rtl/', 'fpga/', 'sw/'))}
    tooling_hardware = {name: identity(ROOT / name) for name in tooling_source['files']
                        if name.startswith(('rtl/', 'fpga/', 'sw/'))}
    if physical_hardware != tooling_hardware:
        raise RuntimeError("Hardware or board runtime inputs changed since physical build")
    output = args.output_root.resolve()
    output.mkdir(parents=True, exist_ok=False)
    for src, dst in package.SOURCE_FILES.items():
        path = output / dst
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / src, path)
    for filename in ("stage2_board_session.py",):
        shutil.copyfile(ROOT / "tools/board_validation" / filename, output / "runtime" / filename)
    for filename in ("stage2_board_capture_pair.tcl", "stage2_board_session_host.py"):
        shutil.copyfile(ROOT / "tools/board_validation" / filename, output / "host" / filename)
    for key, dst in package.ARTIFACT_PACKAGE_PATHS.items():
        path = output / dst
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(manifest.artifacts[key].path, path)
    (output / "provenance").mkdir()
    shutil.copyfile(manifest.manifest_path, output / package.ARTIFACT_MANIFEST_PACKAGE_PATH)
    write_json(output / runtime.PROFILE_FILENAME, package.build_profile(manifest))
    source_files = physical_source['files']
    source_inputs = {name: identity(source / name) for name in source_files if name}
    write_json(output / "provenance/source_inputs.json", {
        "source_commit": manifest.source_commit, "source_tree": manifest.source_tree,
        "hash_basis": physical_source['basis'], "files": source_inputs,
    })
    terminal = runtime.load_json(args.artifact_manifest.parent.parent / "terminal_result.json")
    result = runtime.load_json(args.artifact_manifest.parent.parent / "vivado_result.json")
    if terminal["process_exit_code"] != "0" or result["result_state"] != "COMPLETED" or not result["route_completed"]:
        raise RuntimeError("Physical build did not complete")
    for field, value in (("execution_id", manifest.execution_id), ("source_commit", manifest.source_commit), ("source_tree", manifest.source_tree)):
        if result[field] != value:
            raise RuntimeError(f"Physical result differs: {field}")
    for artifact in result["artifact_inventory"]:
        if identity(Path(artifact["path"])) != {"bytes": artifact["bytes"], "sha256": artifact["sha256"]}:
            raise RuntimeError("Physical result artifact changed")
    version = query_version(args.vivado)
    write_json(output / "provenance/rebuilt_evidence.json", {
        "evidence_state": "REBUILT", "formal_acceptance": "NOT_FORMALLY_ACCEPTED",
        "board_verification": "NOT_RUN", "physical_execution_id": manifest.execution_id,
        "board_execution_id": args.execution_id, "source_commit": manifest.source_commit,
        "source_tree": manifest.source_tree, "source_inputs": identity(output / "provenance/source_inputs.json"),
        "tool_version": version, "terminal_result": identity(args.artifact_manifest.parent.parent / "terminal_result.json"),
        "vivado_result": identity(args.artifact_manifest.parent.parent / "vivado_result.json"),
        "artifact_manifest": identity(manifest.manifest_path), "artifacts": package.build_profile(manifest)["artifacts"],
    })
    offline = runtime.validate_package(output, expected_profile=runtime.READY_AWARE)
    write_json(output / "OFFLINE_VALIDATION.json", offline)
    files = {p.relative_to(output).as_posix(): identity(p) for p in sorted(output.rglob("*")) if p.is_file()}
    write_json(output / "session_manifest.json", {
        "schema": "stage2-board-session-package-v1", "execution_id": args.execution_id,
        "physical_execution_id": manifest.execution_id,
        "tooling_commit": tooling_source['commit'], "tooling_tree": tooling_source['tree'],
        "tooling_source_basis": tooling_source['basis'],
        "physical_source_commit": manifest.source_commit, "physical_source_tree": manifest.source_tree,
        "files": files,
    })
    verify_session_package(output)
    archive = output.with_suffix(".zip")
    package.write_deterministic_zip(output, archive)
    print(json.dumps({"status": "PASS", "execution_id": args.execution_id, "package": str(archive), **identity(archive)}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-repo", type=Path, required=True)
    parser.add_argument("--artifact-manifest", type=Path, required=True)
    parser.add_argument("--vivado", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--execution-id", required=True)
    build(parser.parse_args())


if __name__ == "__main__":
    main()
