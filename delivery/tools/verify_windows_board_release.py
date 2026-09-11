#!/usr/bin/env python3
"""Verify a portable Windows engineering/board evidence snapshot without Git."""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path, PurePosixPath

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tools.board_validation import stage2_board_session_host as host
from tools.path_safety import canonical, path_below_root, regular_files
from tools.board_validation.stage2_board_session import ACTIONS, SCENARIOS, EXTRA_SCENARIOS, identity
from sw import stage2i_board_runtime as runtime

SCHEMA = "windows-board-evidence-release-v1"
PRIVATE_PATH = re.compile(rb"(?<![A-Za-z0-9])[A-Za-z]:[\\/]|/(?:Us" + rb"ers|ho" + rb"me)/[^/\s]+/")
MANIFEST = "RELEASE_MANIFEST.json"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, f"Duplicate JSON key: {key}")
            result[key] = value
        return result
    return json.loads(Path(path).read_text(encoding="utf-8"), object_pairs_hook=unique)


def safe_file(root, relative):
    require(isinstance(relative, str) and relative and "\\" not in relative,
            "Invalid relative path")
    path = PurePosixPath(relative)
    require(not path.is_absolute() and ".." not in path.parts and ":" not in relative,
            f"Unsafe relative path: {relative}")
    return path_below_root(canonical(root, strict=True), relative)


def verify_files(root, expected, excluded=()):
    actual = set(regular_files(root))
    require(actual - set(excluded) == set(expected), "File inventory differs")
    for relative, record in expected.items():
        require(identity(safe_file(root, relative)) == record, f"File identity differs: {relative}")


def physical_findings(reports):
    findings = {}
    for report in ("drc", "methodology"):
        text = (reports / f"{report}.rpt").read_text(encoding="utf-8")
        rows = re.findall(r"(?m)^\|\s*([A-Z]+-\d+)\s*\|\s*(\w+)\s*\|[^|]+\|\s*(\d+)\s*\|", text)
        require(rows, f"Missing {report} finding summary")
        findings[report] = {rule: {"severity": severity, "count": int(count)} for rule, severity, count in rows}
    cdc = (reports / "cdc.rpt").read_text(encoding="utf-8")
    rows = re.findall(r"(?m)^(CDC-\d+)\s+(\w+)\s+(\d+)\s", cdc)
    require(rows, "Missing CDC summary")
    findings["cdc"] = {rule: {"severity": severity, "count": int(count)} for rule, severity, count in rows}
    timing = (reports / "timing_summary.rpt").read_text(encoding="utf-8")
    table = timing.split("WNS(ns)", 1)[1]
    row = next((line.split() for line in table.splitlines() if len(line.split()) == 12 and
                re.fullmatch(r"-?\d+\.\d+", line.split()[0])), None)
    require(row is not None, "Missing timing summary")
    findings["timing"] = {"wns_ns": float(row[0]), "whs_ns": float(row[4]), "wpws_ns": float(row[8]),
                          "setup_failing_endpoints": int(row[2]), "hold_failing_endpoints": int(row[6]),
                          "pulse_width_failing_endpoints": int(row[10])}
    checks = (reports / "check_timing.rpt").read_text(encoding="utf-8")
    findings["constraint_checks"] = {name: int(count) for name, count in
                                      re.findall(r"checking (\w+) \((\d+)\)", checks)}
    return findings


def verify_board(root, original_records=None):
    receipt = load(root / "board_verification_receipt.json")
    require(receipt["status"] == "PASS" and receipt["evidence_state"] == "BOARD_VERIFIED",
            "Board campaign did not pass")
    execution = receipt["execution_id"]
    expected_scenarios = set(SCENARIOS + EXTRA_SCENARIOS)
    require(set(receipt["scenarios"]) == expected_scenarios, "Board scenario inventory differs")
    for relative, expected in receipt["files"].items():
        path = safe_file(root, relative)
        if original_records is None:
            require(identity(path) == expected, f"Board evidence changed: {relative}")
        else:
            require(original_records[f"board/{relative}"]["original"] == expected,
                    f"Original board identity differs: {relative}")
    for index, name in enumerate(ACTIONS):
        action_path = root / f"board_action_{index:02d}.http.json"
        action = load(action_path)
        require((action["execution_id"], action["index"], action["action"], action["status"]) ==
                (execution, index, name, "PASS"), f"Board action differs: {index}")
        host_record = load(root / f"host_action_{index:02d}.json")
        original = identity(action_path) if original_records is None else original_records[
            f"board/{action_path.name}"]["original"]
        require(host_record["response_sha256"] == original["sha256"], "HTTP response identity differs")
        require(host_record["request"] == {"action": name, "execution_id": execution},
                "Host action identity differs")
    loaded = load(root / "board_action_00.http.json")["result"]
    require(loaded["loaded"] is True and loaded["clock_mhz"] == {"fclk0": 100.0, "fclk1": 125.0},
            "Overlay or clocks differ")
    require(loaded["identity"]["source_commit"] == receipt["source_commit"] and
            loaded["identity"]["source_tree"] == receipt["source_tree"], "Loaded source differs")
    for name in sorted(expected_scenarios):
        scenario = load(root / name / "scenario_receipt.json")
        require(scenario == receipt["scenarios"][name], f"Scenario receipt differs: {name}")
        require(scenario["status"] == "PASS" and scenario["execution_id"] == execution,
                f"Scenario did not pass: {name}")
        for relative, expected in scenario["files"].items():
            require(receipt["files"][f"{name}/{relative}"] == expected,
                    f"Scenario file identity differs: {name}/{relative}")
        require(load(root / name / "tool_exit.json")["exit_code"] == 0, "Capture tool failed")
        if name != "legacy_c2":
            host.analyze_scenario(root / name, name, execution)
    host.analyzer.analyze(root / "legacy_c2_result.json", {
        "source_stall": root / "source_protocol/source.csv",
        "source_accept": root / "legacy_c2/source.csv",
        "destination_fault": root / "legacy_c2/destination.csv",
    })
    final = load(root / f"board_action_{len(ACTIONS) - 1:02d}.http.json")["result"]
    require(final["status"] == "PASS" and final["state"]["status"]["ctrl"] == 0,
            "Final board cleanup did not pass")
    return receipt, loaded


def verify(root):
    root = root.resolve(strict=True)
    manifest = load(root / MANIFEST)
    require(manifest["schema"] == SCHEMA, "Release schema differs")
    verify_files(root, manifest["files"], (MANIFEST,))
    for path in root.rglob("*"):
        if path.is_file():
            require(PRIVATE_PATH.search(path.read_bytes()) is None,
                    f"Machine-private path found: {path.relative_to(root)}")
    version = load(root / "VERSION.json")
    require(version["schema"] == SCHEMA and version["formal_acceptance"] == "NOT_FORMALLY_ACCEPTED",
            "Unsupported acceptance claim")
    require(version["evidence_states"] == ["REBUILT", "BOARD_VERIFIED"], "Evidence states differ")
    require(version["implementation_profile"] == runtime.READY_AWARE, "Implementation profile differs")
    provenance = load(root / "EVIDENCE_PROVENANCE.json")
    records = provenance["records"]
    for label, record in records.items():
        require(identity(safe_file(root, record["delivery_path"])) == record["delivered"],
                f"Portable evidence identity differs: {label}")
        if record["representation"] == "ORIGINAL_BYTES":
            require(record["original"] == record["delivered"], "Original bytes were modified")
        else:
            require(record["representation"] == "PORTABLE_DERIVATIVE", "Unknown evidence representation")
    receipt, loaded = verify_board(root / "evidence/board", records)
    for field, value in (("board_execution_id", receipt["execution_id"]),
                         ("physical_execution_id", receipt["physical_execution_id"]),
                         ("physical_source_commit", receipt["source_commit"]),
                         ("physical_source_tree", receipt["source_tree"]),
                         ("board_tooling_commit", receipt["tooling_commit"])):
        require(version[field] == value, f"Release identity differs: {field}")
    session = load(root / "evidence/session/session_manifest.json")
    require(receipt["package_manifest"] == records["session/session_manifest.json"]["original"],
            "Original session manifest differs")
    for relative, expected in session["files"].items():
        if f"session/{relative}" in records:
            require(records[f"session/{relative}"]["original"] == expected, "Session input differs")
    profile = runtime.load_profile(root, runtime.READY_AWARE)
    runtime.validate_package(root, expected_profile=runtime.READY_AWARE)
    require(profile["artifacts"] == loaded["identity"]["artifact_identities"], "Loaded artifacts differ")
    for name in SCENARIOS + EXTRA_SCENARIOS:
        for role in ("source", "destination"):
            require(records[f"board/{name}/{role}.csv"]["representation"] == "ORIGINAL_BYTES",
                    "ILA CSV must remain byte-exact")
    source_inputs = load(root / "evidence/session/provenance/source_inputs.json")
    require(source_inputs["source_commit"] == receipt["source_commit"] and
            source_inputs["source_tree"] == receipt["source_tree"], "Physical source inputs differ")
    for relative, record in provenance["selected_sources"].items():
        require(identity(safe_file(root, relative)) == record["identity"], "Selected source changed")
        if record["basis"] == "PHYSICAL_SOURCE":
            require(source_inputs["files"][record["source_path"]] == record["identity"],
                    "Selected physical source differs from build input")
    rebuilt = load(root / "evidence/session/provenance/rebuilt_evidence.json")
    for key, label in (("terminal_result", "physical/vivado-output/terminal_result.json"),
                       ("vivado_result", "physical/vivado-output/vivado_result.json"),
                       ("artifact_manifest", "physical/vivado-output/artifacts/artifact-manifest.tsv")):
        require(rebuilt[key] == records[label]["original"], f"Physical evidence differs: {key}")
    physical = load(root / "evidence/physical/vivado-output/vivado_result.json")
    require(physical["route_completed"] and physical["execution_id"] == receipt["physical_execution_id"],
            "Physical implementation did not complete")
    terminal = load(root / "evidence/physical/vivado-output/terminal_result.json")
    require(terminal["process_exit_code"] == "0" and terminal["acceptance_state"] == "NOT_FORMALLY_ACCEPTED",
            "Physical exit or acceptance state differs")
    review = load(root / "evidence/physical/cdc4_review_receipt.json")
    require(review["status"] == "PASS" and review["raw_critical_count"] == 1 and
            review["payload_paths_checked"] == 456 and review["raw_rule"] == "CDC-4",
            "CDC review differs")
    findings = physical_findings(root / "evidence/physical/vivado-output/reports")
    require(findings["drc"] == {"PDCN-1569": {"severity": "Warning", "count": 3},
                                "RTSTAT-10": {"severity": "Warning", "count": 1}}, "Unreviewed DRC findings")
    require(findings["methodology"] == {"LUTAR-1": {"severity": "Warning", "count": 4},
                                        "TIMING-9": {"severity": "Warning", "count": 1},
                                        "XDCB-5": {"severity": "Warning", "count": 4}}, "Unreviewed methodology findings")
    require(findings["cdc"] == {"CDC-3": {"severity": "Info", "count": 54},
                                "CDC-4": {"severity": "Critical", "count": 1},
                                "CDC-6": {"severity": "Warning", "count": 13},
                                "CDC-9": {"severity": "Info", "count": 3},
                                "CDC-15": {"severity": "Warning", "count": 65}}, "Unreviewed CDC findings")
    require(all(value >= 0 for key, value in findings["timing"].items() if key.endswith("_ns")) and
            all(value == 0 for key, value in findings["timing"].items() if key.endswith("endpoints")), "Timing failed")
    require(findings["constraint_checks"].get("unconstrained_internal_endpoints") == 0, "Unconstrained internal endpoints")
    checks = load(root / "evidence/verification/verification_receipt.json")
    required_checks = {"full_digital_regression", "python_engineering_tests", "software_tests", "producer_tests", "board_plan_rtl",
                       "stage1_board_ila_binding_fixture_tests", "stage1_board_ila_capture_configuration_fixture_tests",
                       "stage1_board_ila_attempt03_ltx_binding_fixture_tests"}
    require(set(checks["checks"]) == required_checks and checks["status"] == "PASS" and
            all(c["exit_code"] == 0 for c in checks["checks"].values()),
            "Final verification did not pass")
    require(checks["source_commit"] == version["release_source_commit"] and checks["source_tree"] == version["release_source_tree"],
            "Final verification source identity differs")
    require(checks["board_receipt"] == records["board/board_verification_receipt.json"]["original"],
            "Final verification board identity differs")
    summary = (root / "evidence/verification/digital/runner_summary.txt").read_text()
    for marker in ("STAGE2G_FUNCTIONAL_RTL_RUNNER=PASS", "CANONICAL_REGRESSION=PASS", "RANDOM_EPISODES=PASS_1000",
                   "FULL_PRIOR_STAGE_REGRESSION=PASS", "STAGE2D_DEDICATED_XSIM=PASS", "SOFTWARE_INTERFACE_TESTS=PASS"):
        require(marker in summary.splitlines(), f"Full regression marker absent: {marker}")
    for relative, expected in checks["files"].items():
        require(records[f"verification/{relative}"]["original"] == expected, "Verification log differs")
    annex = load(root / "EVIDENCE_ANNEX.json")
    require(annex["board_receipt"] == identity(root / "evidence/board/board_verification_receipt.json") and
            annex["board_verification"] == "PASS", "Annex identity differs")
    require(annex["physical_findings"] == findings, "Annex physical findings differ")
    with (root / "provenance/artifact-manifest.tsv").open(newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream, delimiter="\t"):
            require(row["execution_id"] == receipt["physical_execution_id"] and row["source_commit"] == receipt["source_commit"]
                    and row["source_tree"] == receipt["source_tree"], "Portable artifact manifest source differs")
            expected = {"bytes": int(row["bytes"]), "sha256": row["sha256"]}
            if row["role"] == "XSA":
                require(expected == {key: profile["artifacts"]["xsa"][key] for key in expected}, "External XSA differs")
            else:
                require(identity(safe_file(root, row["canonical_path"])) == expected,
                        f"Portable artifact/report manifest differs: {row['role']}")
    return {"status": "PASS", "release_id": version["release_id"], "board_scenarios": 8,
            "supporting_scenarios": 2, "raw_ila_csv_count": 20, "private_path_findings": 0,
            "formal_acceptance": "NOT_FORMALLY_ACCEPTED", "manifest": identity(root / MANIFEST)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("release_root", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.release_root), sort_keys=True))
    except (OSError, ValueError, KeyError, RuntimeError) as exc:
        print(json.dumps({"status": "FAIL", "reason": str(exc)}))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
