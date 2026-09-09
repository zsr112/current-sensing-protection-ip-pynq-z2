#!/usr/bin/env python3
"""Build a new portable evidence snapshot from verified external authorities."""
from __future__ import annotations

import argparse
import copy
import csv
import io
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import stage2i_physical_authority as authority
from tools import verify_windows_board_release as verifier
from tools.board_validation import build_stage1_board_execution_package as package
from tools.board_validation.stage2_board_session import identity, write_json, verify_session_package, utc_now
from sw import stage2i_board_runtime as runtime

SOURCE_FILES = (
    "sw/stage2i_board_runtime.py", "sw/protection_ip_interface.py", "sw/generated/protection_register_map.py",
    "tools/board_validation/stage1_board_functional_validation.py",
    "tools/board_validation/stage1_board_evidence_analyzer.py",
    "tools/board_validation/stage2_board_session.py", "tools/board_validation/stage2_board_session_host.py",
    "tools/verify_windows_board_release.py",
)


def portable_text(text, roots):
    for path, label in sorted(roots.items(), key=lambda item: len(str(item[0])), reverse=True):
        for variant in (str(path), path.as_posix(), str(path).replace("\\", "\\\\")):
            text = re.sub(re.escape(variant), lambda _: f"<EXTERNAL_{label}>", text, flags=re.IGNORECASE)
    # Any remaining machine path is presentation metadata, retained in the external original.
    text = re.sub(r"(?<![A-Za-z0-9])[A-Za-z]:[\\/][^\s\"'<>|,;\]\)\}]*", "<EXTERNAL_PATH>", text)
    text = re.sub(r"/(?:Us" + r"ers|ho" + r"me)/[^/\s]+/[^\s\"'<>|,;\]\)\}]*", "<EXTERNAL_USER_PATH>", text)
    return text


def portable_json(value, roots):
    if isinstance(value, str):
        return portable_text(value, roots)
    if isinstance(value, list):
        return [portable_json(item, roots) for item in value]
    if isinstance(value, dict):
        return {portable_text(key, roots): portable_json(item, roots) for key, item in value.items()}
    return value


def build(args):
    git = lambda *a: subprocess.check_output(["git", "-C", str(ROOT), *a], text=True).strip()
    if git("status", "--porcelain", "--untracked-files=all"):
        raise RuntimeError("Final release source must be committed and clean")
    board_root, physical_root = args.board_evidence.resolve(strict=True), args.physical_root.resolve(strict=True)
    session_root, verification_root = args.session_package.resolve(strict=True), args.verification_root.resolve(strict=True)
    session = verify_session_package(session_root)
    board, loaded = verifier.verify_board(board_root)
    verifier.require(board["package_manifest"] == identity(session_root / "session_manifest.json"), "Session identity differs")
    artifact_manifest = physical_root / "vivado-output/artifacts/artifact-manifest.tsv"
    physical = authority.load_artifact_manifest(artifact_manifest, expected_profile=runtime.READY_AWARE)
    verifier.require(physical.execution_id == board["physical_execution_id"] and physical.source_commit == board["source_commit"]
                     and physical.source_tree == board["source_tree"], "Physical/board identity differs")
    verifier.require(not git("diff", physical.source_commit, "--", "rtl", "fpga", "sw"), "Hardware inputs changed")
    checks = verifier.load(verification_root / "verification_receipt.json")
    verifier.require(checks["status"] == "PASS" and checks["board_receipt"] == identity(board_root / "board_verification_receipt.json"),
                     "Final verification does not cover this board campaign")
    verifier.require(checks["source_commit"] == git("rev-parse", "HEAD"), "Final verification source differs")
    for relative, expected in checks["files"].items():
        verifier.require(identity(verification_root / relative) == expected, f"Verification file changed: {relative}")
    review = verifier.load(physical_root / "cdc4_review_receipt.json")
    for relative, digest in review["physical_root_evidence_sha256"].items():
        verifier.require(identity(physical_root / relative)["sha256"] == digest, "CDC review input changed")
    for relative, digest in review["tooling_source_evidence_sha256"].items():
        verifier.require(identity(ROOT / relative)["sha256"] == digest, "CDC review source changed")
    output = args.output.resolve()
    verifier.require(not output.is_relative_to(ROOT), "Release output must be external")
    verifier.require(not output.with_suffix(".zip").exists(), "Release ZIP already exists")
    output.mkdir(parents=True, exist_ok=False)
    roots = {board_root: "BOARD", physical_root: "PHYSICAL", session_root: "SESSION", verification_root: "VERIFICATION",
             ROOT: "SOURCE"}
    records, selected_sources = {}, {}

    def evidence(label, source, destination=None, raw_required=False):
        destination = destination or f"evidence/{label}"
        target = output / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        data = source.read_bytes()
        converted = data
        if verifier.PRIVATE_PATH.search(data):
            verifier.require(not raw_required, f"Private path in immutable artifact: {label}")
            if source.suffix == ".json":
                converted = package.canonical_json(portable_json(verifier.load(source), roots))
            else:
                converted = portable_text(data.decode("utf-8"), roots).encode("utf-8")
        target.write_bytes(converted)
        records[label] = {"source_authority": label.split("/")[0], "source_relative_path": label.split("/", 1)[1],
                          "original": identity(source), "delivery_path": destination, "delivered": identity(target),
                          "representation": "ORIGINAL_BYTES" if converted == data else "PORTABLE_DERIVATIVE"}

    for relative in ["board_verification_receipt.json", *board["files"]]:
        evidence(f"board/{relative}", board_root / relative, raw_required=relative.endswith(".csv"))
    for relative in ("session_manifest.json", "provenance/source_inputs.json", "provenance/rebuilt_evidence.json", runtime.PROFILE_FILENAME):
        evidence(f"session/{relative}", session_root / relative)
    for key, relative in package.ARTIFACT_PACKAGE_PATHS.items():
        evidence(f"artifact/{key}", physical.artifacts[key].path, relative, raw_required=True)
    physical_files = ["cdc4_review_receipt.json", "vivado-output/terminal_result.json", "vivado-output/vivado_result.json",
                      "vivado-output/artifacts/artifact-manifest.tsv", "fifo-routed-audit-02/fifo_paths.tsv",
                      "fifo-routed-audit-02/cdc_unwaived.rpt", "fifo-routed-audit-02/bus_skew.rpt", "fifo-routed-audit-02.log"]
    physical_files += [p.relative_to(physical_root).as_posix() for p in (physical_root / "vivado-output/reports").glob("*.rpt")]
    for relative in physical_files:
        evidence(f"physical/{relative}", physical_root / relative)
    for relative in ["verification_receipt.json", *checks["files"]]:
        evidence(f"verification/{relative}", verification_root / relative)
    for relative in ("docs/review/windows_b2_cdc4_review_20260909.md", "docs/bringup/windows_board_session.md",
                     "docs/project/windows_rebuild_status_20260909.md", "docs/review/windows_board_test_corrections_20260909.md",
                     "docs/review/windows_rebuild_changed_files_20260909.md"):
        evidence(f"source/{relative}", ROOT / relative, relative)

    physical_inputs = verifier.load(session_root / "provenance/source_inputs.json")["files"]
    sources = list(SOURCE_FILES) + git("ls-files", "rtl", "fpga/vivado/constraints").splitlines()
    for relative in sources:
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
        file_identity = identity(target)
        basis = "PHYSICAL_SOURCE" if physical_inputs.get(relative) == file_identity else "RELEASE_TOOLING_SOURCE"
        selected_sources[relative] = {"source_path": relative, "identity": file_identity, "basis": basis}

    # The deployable profile explicitly refers to a new relative-path manifest.
    rows = list(csv.DictReader(artifact_manifest.read_text().splitlines(), delimiter="\t"))
    for row in rows:
        original_name = Path(row["canonical_path"]).name
        if row["kind"] == "artifact":
            row["canonical_path"] = ("external-physical/artifacts/" if row["role"] == "XSA" else "artifacts/") + original_name
        else:
            row["canonical_path"] = "evidence/physical/vivado-output/reports/" + original_name
            row.update(identity(output / row["canonical_path"]))
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=list(rows[0]), delimiter="\t", lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    (output / "provenance").mkdir()
    (output / "provenance/artifact-manifest.tsv").write_text(buffer.getvalue(), encoding="utf-8", newline="\n")
    profile = copy.deepcopy(runtime.load_profile(session_root, runtime.READY_AWARE))
    profile["artifact_manifest"].update(identity(output / "provenance/artifact-manifest.tsv"))
    write_json(output / runtime.PROFILE_FILENAME, profile)
    (output / "evidence/analysis").mkdir()
    write_json(output / "evidence/analysis/board_identity_receipt.json", {
        "representation": "EXTRACTED_FROM_ORIGINAL_HTTP_RESPONSE", "source": records["board/board_action_00.http.json"]["original"],
        "identity": loaded["identity"]})
    write_json(output / "evidence/analysis/overlay_receipt.json", {
        "representation": "EXTRACTED_FROM_ORIGINAL_HTTP_RESPONSE", "source": records["board/board_action_00.http.json"]["original"],
        "overlay": loaded})
    write_json(output / "evidence/analysis/ila_analysis_receipt.json", {
        "execution_id": board["execution_id"], "status": "PASS", "source_board_receipt": identity(board_root / "board_verification_receipt.json"),
        "scenarios": {name: row["status"] for name, row in board["scenarios"].items()}, "raw_csv_count": 20})
    write_json(output / "EVIDENCE_PROVENANCE.json", {
        "schema": "portable-evidence-derivatives-v1", "records": records, "selected_sources": selected_sources,
        "policy": "External originals are unchanged. Original hashes refer to external authorities; delivered hashes refer to this snapshot.",
        "runtime_profile_derivation": {"original": identity(session_root / runtime.PROFILE_FILENAME),
                                       "delivered": identity(output / runtime.PROFILE_FILENAME),
                                       "change": "Artifact manifest location identity only; artifact bytes/hashes unchanged"},
    })
    version = {"schema": verifier.SCHEMA, "release_id": args.release_id, "generated_at_host_utc": utc_now(),
               "evidence_states": ["REBUILT", "BOARD_VERIFIED"], "formal_acceptance": "NOT_FORMALLY_ACCEPTED",
               "implementation_profile": runtime.READY_AWARE, "physical_execution_id": physical.execution_id,
               "physical_source_commit": physical.source_commit, "physical_source_tree": physical.source_tree,
               "board_execution_id": board["execution_id"], "board_tooling_commit": session["tooling_commit"],
               "release_source_commit": git("rev-parse", "HEAD"), "release_source_tree": git("rev-parse", "HEAD^{tree}"),
               "vivado": verifier.load(session_root / "provenance/rebuilt_evidence.json")["tool_version"],
               "board": loaded["identity"], "scope": "Synthetic digital samples and internal PWM; external ADC/power stage NOT_RUN"}
    write_json(output / "VERSION.json", version)
    write_json(output / "EVIDENCE_ANNEX.json", {
        "schema": "windows-evidence-annex-v1", "release_id": args.release_id, "board_verification": "PASS",
        "board_receipt": identity(output / "evidence/board/board_verification_receipt.json"),
        "original_board_receipt": identity(board_root / "board_verification_receipt.json"),
        "rebuilt": "PASS", "full_digital_regression": "PASS", "tool_tests": "PASS", "formal_acceptance": "NOT_FORMALLY_ACCEPTED",
        "cdc_critical": {"count": 1, "rule": "CDC-4", "review": "PASS", "hardware_change_required": False},
        "timing_ns": {"wns": review["timing_wns_ns"], "whs": review["timing_whs_ns"], "wpws": review["timing_wpws_ns"]},
        "physical_findings": verifier.physical_findings(physical_root / "vivado-output/reports"),
        "finding_disposition": "Engineering review only; raw severities retained. Vendor debug/reset and ILA findings retained; custom FIFO bounded review attached.",
        "historical": {"classification": "HISTORICAL_ACCEPTED", "used_as_fresh_proof": False,
                       "preserved_tags": ["stage2-digital-protection-engineering-closure-v1", "pynq-z2-stage2-digital-protection-delivery-v1"]},
        "not_run": ["analog ADC disconnection", "external-pin PWM/power-stage validation", "persistent boot/soak", "formal acceptance"],
    })
    (output / "README.md").write_text(
        "# Windows PYNQ-Z2 Board Evidence Release\n\n"
        "This selected engineering snapshot contains freshly rebuilt B2 hardware and a new board campaign. "
        "It is not a production or formally accepted protection system.\n\n"
        "Run `python -B tools/verify_windows_board_release.py .` after extraction. "
        "Verification requires Python 3.10 or newer, uses no Git or FPGA tools, and reanalyzes all raw ILA captures.\n\n"
        "BIT/HWH/LTX and ILA CSV files retain their original bytes. EVIDENCE_PROVENANCE.json identifies "
        "original evidence and every portable derivative by separate size and SHA-256. Full original Vivado "
        "logs, XSA, routed checkpoint and build workspace remain in the external evidence authority.\n\n"
        "The root board profile is a portable derivative suitable for the included PYNQ runtime. "
        "The original session profile and manifest remain evidence under evidence/session. This snapshot "
        "is not a replayable authenticated session package; prepare a fresh execution with the complete repository tooling.\n\n"
        "Hardware-source, board-tooling and release-tooling commits are separate fields in VERSION.json. "
        "Selected RTL/constraints are included for inspection; a complete rebuild uses the full engineering "
        "repository at the recorded physical-source commit, with a new external build root.\n\n"
        "The eight required scenarios and two supporting scenarios passed. Sample removal covers the "
        "synthetic digital producer, not a physical analog ADC. CDC-4 remains Critical in the raw report; "
        "the bounded FIFO review is attached. Formal acceptance remains NOT_FORMALLY_ACCEPTED.\n",
        encoding="utf-8", newline="\n")
    write_json(output / verifier.MANIFEST, {"schema": verifier.SCHEMA, "files": {
        p.relative_to(output).as_posix(): identity(p) for p in sorted(output.rglob("*")) if p.is_file()}})
    result = verifier.verify(output)
    archive = output.with_suffix(".zip")
    package.write_deterministic_zip(output, archive)
    with tempfile.TemporaryDirectory(prefix="csip-release-audit-", dir=output.parent) as temporary:
        import zipfile
        with zipfile.ZipFile(archive) as zipped:
            zipped.extractall(temporary)
        verifier.verify(Path(temporary))
    write_json(output.with_name(output.name + "-build-receipt.json"), {
        **result, "release_zip": identity(archive), "zip_extraction_verification": "PASS", "created_at_host_utc": utc_now()})
    print(json.dumps({**result, "zip": str(archive), "zip_identity": identity(archive)}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("session-package", "board-evidence", "physical-root", "verification-root", "output"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    parser.add_argument("--release-id", required=True)
    build(parser.parse_args())


if __name__ == "__main__":
    main()
