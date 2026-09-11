#!/usr/bin/env python3
"""Build the authoritative Stage2I current-use PYNQ-Z2 release subtree."""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

try:
    from tools import stage2i_physical_authority as physical_authority
    from tools import verify_current_release as release_verifier
except ModuleNotFoundError:  # Direct execution as python tools/build_current_release.py.
    import stage2i_physical_authority as physical_authority  # type: ignore
    import verify_current_release as release_verifier  # type: ignore

try:
    from tools.runtime_config import configured, optional_git_identity, resolve_directory
except ModuleNotFoundError:
    from runtime_config import configured, optional_git_identity, resolve_directory  # type: ignore


BUILDER_VERSION = "2.0"
AUTHORITY_SCHEMA = "stage2i-current-release-authority-v1"
PERSISTENT_DEPLOYMENT_CLAIM = "NOT_CLAIMED"
EXPECTED_IP = {
    "axi_gpio_stage1d_0": {"phys_addr": 0x41200000, "addr_range": 0x10000},
    "protection_ip_axi_lite_0": {"phys_addr": 0x43C00000, "addr_range": 0x1000},
}
ACTIVE_WORKTREE_PACKAGE_SOURCES = {
    "fpga/pynq/deployment/stage1g/stage2i_current_release.py": (
        "pynq/runtime/stage2i_current_release.py"
    ),
    "sw/protection_ip_interface.py": "pynq/runtime/protection_ip_interface.py",
    "sw/generated/protection_register_map.py": (
        "pynq/runtime/generated/protection_register_map.py"
    ),
}
DEPLOY_ARTIFACT_PATHS = {
    "bit": "pynq/artifacts/protection_system.bit",
    "hwh": "pynq/artifacts/protection_system.hwh",
}


class ReleaseBuildError(RuntimeError):
    """The deterministic release build could not close."""


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def canonical_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=True, allow_nan=False, indent=2, sort_keys=True)
        + "\n"
    ).encode("utf-8")


def run_git(repo_root: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo_root), *args],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.stdout.strip()


def verify_git_gate(
    repo_root: Path, require_clean: bool = True, require_main: bool = True
) -> tuple[str, str]:
    try:
        branch = run_git(repo_root, "branch", "--show-current")
        head = run_git(repo_root, "rev-parse", "HEAD")
        tree = run_git(repo_root, "rev-parse", "HEAD^{tree}")
    except (OSError, subprocess.CalledProcessError):
        if require_clean:
            raise ReleaseBuildError("--require-clean needs a working Git checkout")
        return "UNAVAILABLE", "UNAVAILABLE"
    if require_clean:
        status = run_git(repo_root, "status", "--porcelain", "--untracked-files=all")
        if status:
            raise ReleaseBuildError("Git gate failed: worktree is not clean")
    if require_main:
        main = run_git(repo_root, "rev-parse", "main")
        origin = run_git(repo_root, "rev-parse", "origin/main")
        if branch != "main" or not (head == main == origin):
            raise ReleaseBuildError("Git gate failed: main must be clean and equal to origin/main")
    return head, tree


def _literal_assignments(path: Path) -> dict[str, Any]:
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    except (OSError, UnicodeError, SyntaxError) as exc:
        raise ReleaseBuildError(f"cannot parse generated register map: {exc}") from exc
    result: dict[str, Any] = {}
    for node in tree.body:
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        try:
            value = ast.literal_eval(node.value)
        except (ValueError, TypeError):
            continue
        for target in targets:
            if isinstance(target, ast.Name):
                result[target.id] = value
    return result


def current_register_map_abi(repo_root: Path) -> dict[str, Any]:
    values = _literal_assignments(
        repo_root / "sw" / "generated" / "protection_register_map.py"
    )
    abi = {
        "major": values.get("REGISTER_MAP_VERSION_ABI_MAJOR_RESET"),
        "minor": values.get("REGISTER_MAP_VERSION_ABI_MINOR_RESET"),
        "schema_version": values.get("REGISTER_MAP_SCHEMA_VERSION"),
        "canonical_sha256": values.get("REGISTER_MAP_CANONICAL_SHA256"),
    }
    if (
        abi["major"] != 1
        or abi["minor"] != 1
        or abi["schema_version"] != "1.1.0"
        or not isinstance(abi["canonical_sha256"], str)
        or len(abi["canonical_sha256"]) != 64
    ):
        raise ReleaseBuildError(f"current generated register-map ABI differs: {abi}")
    return abi


def runtime_source_records(repo_root: Path) -> dict[str, dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {}
    for source_relative, release_relative in ACTIVE_WORKTREE_PACKAGE_SOURCES.items():
        source = repo_root / Path(source_relative)
        if not source.is_file():
            raise ReleaseBuildError(f"current runtime source is missing: {source_relative}")
        payload = source.read_bytes()
        records[release_relative] = {
            "source_relative_path": source_relative,
            "bytes": len(payload),
            "sha256": sha256_bytes(payload),
        }
    if set(records) != set(ACTIVE_WORKTREE_PACKAGE_SOURCES.values()):
        raise ReleaseBuildError("current runtime source inventory is not singular")
    return records


def release_authority_record(
    authority: physical_authority.PhysicalAuthority,
    commit: str,
    tree: str,
    abi: dict[str, Any],
    runtime_sources: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    if authority.implementation_profile != physical_authority.PRODUCTION_PROFILE:
        raise ReleaseBuildError("physical authority is not SAFE_INERT")
    if authority.source_tree != tree:
        raise ReleaseBuildError("physical artifact source tree differs from final main tree")
    return {
        "schema_version": AUTHORITY_SCHEMA,
        "implementation_profile": authority.implementation_profile,
        "engineering_main_commit": commit,
        "engineering_main_tree": tree,
        "physical_artifact_source_commit": authority.source_commit,
        "physical_artifact_source_tree": authority.source_tree,
        "physical_artifact_execution_id": authority.execution_id,
        "physical_artifact_request_identity": authority.request_identity,
        "physical_authority_receipt_sha256": authority.receipt_sha256,
        "artifact_manifest": {
            "bytes": authority.artifact_manifest_bytes,
            "sha256": authority.artifact_manifest_sha256,
            "project_identity": authority.project_identity,
            "design_identity": authority.design_identity,
        },
        "artifacts": {
            key: {
                "role": artifact.role,
                "bytes": artifact.bytes,
                "sha256": artifact.sha256,
                "delivery_policy": artifact.delivery_policy,
            }
            for key, artifact in authority.artifacts.items()
        },
        "expected_ip": EXPECTED_IP,
        "register_map_abi": abi,
        "runtime_sources": runtime_sources,
        "persistent_deployment_claim": PERSISTENT_DEPLOYMENT_CLAIM,
        "tree_equivalence": "PASS",
    }


def proof_boundary() -> dict[str, list[str]]:
    return {
        "proved": [
            "external immutable SAFE_INERT B1 artifact authority validated",
            "physical artifact source tree equals final authoritative main tree",
            "BIT and HWH are the sole packaged hardware artifacts",
            "LTX and XSA identities are retained as provenance-only required artifacts",
            "packaged runtime and software are bound to the current ABI 1.1 sources",
            "offline HWH IP and address metadata validation",
        ],
        "not_proved": [
            "PYNQ Overlay loading on physical hardware",
            "board MMIO execution",
            "Hardware Manager target access or ILA capture",
            "persistent systemd or reboot deployment",
            "power-stage load or analog current scaling",
        ],
    }


def read_only_example() -> str:
    return '''#!/usr/bin/env python3
"""Read the current ABI 1.1 status without loading an Overlay or writing MMIO."""
import argparse
import json
import sys
from pathlib import Path

from pynq import MMIO

RUNTIME_ROOT = Path(__file__).resolve().parents[1] / "pynq" / "runtime"
sys.path.insert(0, str(RUNTIME_ROOT))

from protection_ip_interface import (  # noqa: E402
    read_capabilities,
    read_observability,
    read_policy_status,
    read_register_map_version,
    read_status,
)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--base-address", type=lambda value: int(value, 0), default=0x43C00000)
args = parser.parse_args()
mmio = MMIO(args.base_address, 0x1000)
version = read_register_map_version(mmio)
capabilities = read_capabilities(mmio)
status = read_status(mmio)
policy = read_policy_status(mmio)
observability = read_observability(mmio)
print(json.dumps({
    "register_map_version": {"raw": version.raw_value, "major": version.major, "minor": version.minor},
    "capabilities": {
        "raw_capabilities_0": capabilities.raw_capabilities_0,
        "raw_capabilities_1": capabilities.raw_capabilities_1,
    },
    "status": {"ctrl": status.ctrl, "status": status.status, "fault_code": status.fault_code},
    "policy_status": policy.raw_value,
    "observability": {
        "source_accept_count": observability.source_accept_count,
        "destination_delivery_count": observability.destination_delivery_count,
        "backpressure_cycle_count": observability.backpressure_cycle_count,
    },
}, indent=2, sort_keys=True))
'''


def render_documents(
    commit: str,
    tree: str,
    release_id: str,
    authority: physical_authority.PhysicalAuthority,
) -> dict[str, str]:
    identity = (
        f"Engineering main commit: `{commit}` (tree `{tree}`). Physical artifact source "
        f"commit: `{authority.source_commit}` (tree `{authority.source_tree}`), execution "
        f"`{authority.execution_id}`. The two trees are equal."
    )
    return {
        "README.md": f"""# Current-Sensing Protection IP Release

This is the Stage2I current-use PYNQ-Z2 release. {identity}

The release packages one SAFE_INERT BIT/HWH pair and the current one-shot ABI 1.1 runtime. LTX and XSA are
required physical-provenance artifacts but are intentionally not deployment payloads. Persistent deployment is
explicitly `NOT_CLAIMED`.

Run `python tools/verify_release.py` before use. Offline validation is:

`python pynq/runtime/stage2i_current_release.py --release-root .`

Physical Overlay loading is opt-in only through `--execute` and remains a separately authorized board action.
""",
        "QUICK_START.md": """# Quick Start

1. Run `python tools/verify_release.py` from the expanded release root.
2. Review `PROOF_BOUNDARY.md` and `docs/recovery_safety.md`.
3. Run `python pynq/runtime/stage2i_current_release.py --release-root .` for offline HWH and ABI validation.
4. Use `--execute` only in an explicitly authorized physical-board gate.

There is no systemd unit, boot installer, reboot action, or persistent-deployment claim in this release.
""",
        "RELEASE_NOTES.md": f"""# Release Notes

Release ID: `{release_id}`.

{identity}

Included: SAFE_INERT BIT/HWH, external physical authority record, one-shot current runtime, current software
interface, generated ABI 1.1 map, read-only example, documentation, provenance, manifest, and self-verifier.

Excluded: LTX/XSA deployment copies, systemd/reboot payload, Vivado workspaces, board evidence, credentials,
historical Stage1 runtime, and physical-board execution claims.
""",
        "PROOF_BOUNDARY.md": """# Proof Boundary

The release proves exact physical-source/final-main tree equivalence, immutable B1 artifact identity, current
runtime/software source identity, ABI 1.1 binding, and offline HWH metadata compatibility.

It does not prove Overlay loading, MMIO, ILA capture, persistent deployment, analog scaling, or power-stage use.
Those are separate physical execution boundaries.
""",
        "docs/recovery_safety.md": """# Recovery Safety

The formal recovery sequence is `disable -> clear-only -> verify -> separate enable`. Clear while a live fault
is present must not release protection. Read-only status inspection must not write CTRL, thresholds, PWM, or
reserved registers. This release does not authorize physical fault injection or recovery execution.
""",
    }


def write_release_tree(
    root: Path,
    repo_root: Path,
    commit: str,
    tree: str,
    generated_at: str,
    authority: physical_authority.PhysicalAuthority,
) -> dict[str, Any]:
    release_id = f"current-sensing-protection-ip-{commit[:12]}-pynq-z2-stage2i"
    abi = current_register_map_abi(repo_root)
    runtime_sources = runtime_source_records(repo_root)
    release_authority = release_authority_record(
        authority, commit, tree, abi, runtime_sources
    )
    records: dict[str, dict[str, Any]] = {}

    def add(
        relative: str,
        payload: bytes,
        component: str,
        source_authority: str,
        source_identity: str,
        source_relative: str,
        validation_status: str,
        notes: str,
    ) -> None:
        path = root / Path(relative)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        records[relative] = {
            "logical_component": component,
            "release_relative_path": relative,
            "source_authority": source_authority,
            "source_path_or_commit": source_identity,
            "source_relative_path": source_relative,
            "bytes": len(payload),
            "sha256": sha256_bytes(payload),
            "validation_status": validation_status,
            "notes": notes,
        }

    for source_relative, release_relative in ACTIVE_WORKTREE_PACKAGE_SOURCES.items():
        payload = (repo_root / Path(source_relative)).read_bytes()
        record = runtime_sources[release_relative]
        if len(payload) != record["bytes"] or sha256_bytes(payload) != record["sha256"]:
            raise ReleaseBuildError(f"runtime source changed during build: {source_relative}")
        add(
            release_relative,
            payload,
            "current_runtime_software",
            "engineering_main_git",
            commit,
            source_relative,
            "CURRENT_ABI_1_1_SOURCE_BOUND",
            "Packaged from the exact clean authoritative main tree.",
        )

    for key, release_relative in DEPLOY_ARTIFACT_PATHS.items():
        artifact = authority.artifacts[key]
        add(
            release_relative,
            artifact.path.read_bytes(),
            f"stage2i_b1_{key}",
            "external_stage2i_physical_authority",
            authority.execution_id,
            artifact.role,
            "EXTERNAL_RECEIPT_IDENTITY_VERIFIED",
            "Deploy-required artifact from the accepted SAFE_INERT B1 authority.",
        )

    authority_payload = canonical_json(release_authority)
    add(
        "pynq/artifacts/release_authority.json",
        authority_payload,
        "release_authority",
        "external_stage2i_physical_authority_and_engineering_main",
        authority.receipt_sha256,
        "stage2i-current-release-authority-v1",
        "TREE_EQUIVALENCE_AND_RUNTIME_CONVERGENCE_PASS",
        "LTX/XSA identities are retained here without packaging deployment copies.",
    )

    generated = {"examples/read_only_status.py": read_only_example()}
    generated.update(render_documents(commit, tree, release_id, authority))
    for relative, content in generated.items():
        add(
            relative,
            content.encode("utf-8"),
            "documentation" if relative.endswith(".md") else "release_tool",
            "engineering_main_git",
            commit,
            "tools/build_current_release.py",
            "NON_PHYSICAL_RELEASE_SUPPORT",
            "Generated deterministically by the current release builder.",
        )

    register_map = (repo_root / "docs" / "implementation" / "register_map.md").read_bytes()
    add(
        "docs/register_map.md",
        register_map,
        "interface_documentation",
        "engineering_main_git",
        commit,
        "docs/implementation/register_map.md",
        "CURRENT_ABI_1_1_DOCUMENTATION",
        "Current register and recovery contract.",
    )
    verifier_source = (repo_root / "tools" / "verify_current_release.py").read_bytes()
    add(
        "tools/verify_release.py",
        verifier_source,
        "release_self_verifier",
        "engineering_main_git",
        commit,
        "tools/verify_current_release.py",
        "READ_ONLY_INDEPENDENT_VERIFIER",
        "Standard-library verifier packaged with the release.",
    )

    version = {
        "release_id": release_id,
        "release_status": "CURRENT_USE_AND_DELIVERY",
        "generated_at_utc": generated_at,
        "engineering_main_commit": commit,
        "engineering_main_tree": tree,
        "physical_artifact_source_commit": authority.source_commit,
        "physical_artifact_source_tree": authority.source_tree,
        "physical_artifact_execution_id": authority.execution_id,
        "physical_authority_receipt_sha256": authority.receipt_sha256,
        "implementation_profile": authority.implementation_profile,
        "target_board": "PYNQ-Z2",
        "pynq_version": "3.1.1",
        "register_map_abi": abi,
        "persistent_deployment_claim": PERSISTENT_DEPLOYMENT_CLAIM,
        "artifact_delivery_policy": {
            key: artifact.delivery_policy for key, artifact in authority.artifacts.items()
        },
        "release_manifest_sha256": release_verifier.MANIFEST_SELF_REFERENCE,
        "proof_boundary": proof_boundary(),
        "release_builder_version": BUILDER_VERSION,
    }
    add(
        "VERSION.json",
        canonical_json(version),
        "release_identity",
        "builder_generated",
        commit,
        "tools/build_current_release.py",
        "TREE_EQUIVALENCE_PASS",
        "Commit identities are distinct; physical and final-main trees are equal.",
    )

    provenance = {
        "schema_version": 2,
        "engineering_main_commit": commit,
        "engineering_main_tree": tree,
        "physical_artifact_source_commit": authority.source_commit,
        "physical_artifact_source_tree": authority.source_tree,
        "physical_artifact_execution_id": authority.execution_id,
        "physical_authority_receipt_sha256": authority.receipt_sha256,
        "tree_equivalence": "PASS",
        "entries": [records[path] for path in sorted(records)],
    }
    provenance_payload = canonical_json(provenance)
    (root / release_verifier.PROVENANCE_NAME).write_bytes(provenance_payload)
    records[release_verifier.PROVENANCE_NAME] = {
        "logical_component": "source_provenance",
        "release_relative_path": release_verifier.PROVENANCE_NAME,
        "source_authority": "builder_generated",
        "source_path_or_commit": commit,
        "source_relative_path": "tools/build_current_release.py",
        "bytes": len(provenance_payload),
        "sha256": sha256_bytes(provenance_payload),
        "validation_status": "TREE_EQUIVALENCE_PASS",
        "notes": "The manifest supplies the provenance self-entry identity.",
    }

    lines = ["relative_path\tbytes\tsha256\tcomponent\tsource_authority\n"]
    for relative in sorted(records):
        record = records[relative]
        lines.append(
            f"{relative}\t{record['bytes']}\t{record['sha256']}\t"
            f"{record['logical_component']}\t{record['source_authority']}\n"
        )
    (root / release_verifier.MANIFEST_NAME).write_text(
        "".join(lines), encoding="utf-8", newline="\n"
    )
    return {
        "release_id": release_id,
        "engineering_main_commit": commit,
        "engineering_main_tree": tree,
        "physical_artifact_source_commit": authority.source_commit,
        "physical_artifact_source_tree": authority.source_tree,
        "physical_artifact_execution_id": authority.execution_id,
        "physical_authority_receipt_sha256": authority.receipt_sha256,
        "tree_equivalence": "PASS",
        "persistent_deployment_claim": PERSISTENT_DEPLOYMENT_CLAIM,
    }


def atomic_build(
    output: Path,
    populate: Callable[[Path], dict[str, Any]],
    validate: Callable[[Path], dict[str, Any]] = release_verifier.verify_release,
) -> dict[str, Any]:
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        if not output.is_dir() or any(output.iterdir()):
            raise ReleaseBuildError(f"existing release target requires review: {output}")
        output.rmdir()
    staging = Path(tempfile.mkdtemp(prefix=f".{output.name}.staging-", dir=output.parent))
    published = False
    try:
        build_result = populate(staging)
        prepublish = validate(staging)
        os.replace(staging, output)
        published = True
        final = validate(output)
        return {
            **build_result,
            "prepublish_verification": prepublish,
            "final_verification": final,
        }
    finally:
        if not published and staging.exists():
            shutil.rmtree(staging)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--physical-authority-receipt", type=Path, required=True)
    parser.add_argument("--generated-at-utc")
    parser.add_argument("--require-clean", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    repo_root = args.repo_root.resolve()
    generated_at = args.generated_at_utc or datetime.now(timezone.utc).isoformat(
        timespec="seconds"
    ).replace("+00:00", "Z")
    try:
        output = args.output or configured(repo_root, "output_root")
        if not output:
            raise ReleaseBuildError("release output requires --output or CSIP_OUTPUT_ROOT/config/toolchain.json")
        commit, tree = verify_git_gate(repo_root, args.require_clean, require_main=False)
        authority = physical_authority.load_physical_authority(
            args.physical_authority_receipt,
            expected_profile=physical_authority.PRODUCTION_PROFILE,
            expected_tree=tree,
        )
        result = atomic_build(
            Path(output),
            lambda staging: write_release_tree(
                staging, repo_root, commit, tree, generated_at, authority
            ),
        )
    except (
        OSError,
        ValueError,
        json.JSONDecodeError,
        subprocess.CalledProcessError,
        ReleaseBuildError,
        physical_authority.PhysicalAuthorityError,
        release_verifier.ReleaseVerificationError,
    ) as exc:
        print(f"FAIL {exc}")
        return 1
    print("PASS " + json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
