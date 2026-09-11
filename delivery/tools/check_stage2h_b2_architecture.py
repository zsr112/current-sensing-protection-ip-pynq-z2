#!/usr/bin/env python3
"""Check the three frozen Stage 2H-B2 RTL authority closures."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


class CheckError(RuntimeError):
    pass


def extract_module(text: str, name: str) -> str:
    match = re.search(rf"(?m)^module\s+{re.escape(name)}\b", text)
    if not match:
        raise CheckError(f"missing module {name}")
    end = text.find("endmodule", match.end())
    if end < 0:
        raise CheckError(f"unterminated module {name}")
    return text[match.start() : end + len("endmodule")]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CheckError(message)


def require_regex(text: str, pattern: str, message: str) -> None:
    require(re.search(pattern, text, flags=re.MULTILINE) is not None, message)


def load(root: Path, relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8")


def check(root: Path) -> list[str]:
    source_text = load(root, "rtl/transaction_source_observer.v")
    bridge_text = load(root, "rtl/adc_sample_cdc_bridge.v")
    destination_text = load(root, "rtl/transaction_destination_observer.v")
    core_text = load(root, "rtl/protection_core_top.v")
    reg_text = load(root, "rtl/protection_ip_top_reg_controlled.v")
    axi_text = load(root, "rtl/protection_ip_top_axi_lite.v")
    top_text = load(root, "rtl/protection_ip_top_async_adc_axi_lite.v")
    contract = json.loads(
        load(root, "spec/stage2h_b_rtl_architecture_contract.json")
    )

    decisions = contract["decisions"]
    require(
        decisions["shared_axi_lite_transport"]["decision"] == "APPROVED",
        "B1 shared AXI transport decision changed",
    )
    require(
        decisions["single_destination_sequence_state_authority"]["decision"]
        == "APPROVED",
        "B1 destination sequence decision changed",
    )
    require(
        decisions["single_source_protocol_state_authority"]["decision"]
        == "APPROVED",
        "B1 source protocol decision changed",
    )
    require(
        decisions["aclk_reset_authority"]["decision"] == "KEEP_CURRENT",
        "B1 ACLK reset decision changed",
    )
    require(
        decisions["full_stage2g_file_split_in_b"]["decision"]
        == "NO_DEFER_TO_STAGE2H_C",
        "B1 file-split deferral changed",
    )
    require(
        decisions["adc_cdc_bridge_dedup_in_b"]["decision"] == "DEFERRED",
        "B1 CDC bridge deferral changed",
    )
    require(
        len(contract["b2_recommended_changes"]) == 3,
        "B1 B2 change count is not three",
    )

    transport = extract_module(
        axi_text, "protection_axi_lite_register_transport"
    )
    legacy_axi = extract_module(axi_text, "protection_ip_top_axi_lite")
    stage2g_axi = extract_module(
        axi_text, "stage2g_protection_ip_axi_lite"
    )
    require(
        axi_text.count("module protection_axi_lite_register_transport") == 1,
        "shared AXI transport module count is not one",
    )
    require(
        axi_text.count("reg [1:0] wr_state;") == 1
        and axi_text.count("reg [1:0] rd_state;") == 1,
        "AXI write/read state authority count is not one",
    )
    for token in (
        "aw_hold_valid",
        "w_hold_valid",
        "S_AXI_BVALID",
        "S_AXI_RVALID",
        "S_AXI_RDATA",
        "wr_en",
        "rd_en",
        "wstrb",
    ):
        require(token in transport, f"shared AXI transport omits {token}")
    for name, wrapper in (
        ("legacy", legacy_axi),
        ("Stage2G", stage2g_axi),
    ):
        require(
            wrapper.count("protection_axi_lite_register_transport #(") == 1,
            f"{name} wrapper does not instantiate exactly one shared transport",
        )
        for forbidden in (
            "wr_state",
            "rd_state",
            "aw_hold_valid",
            "w_hold_valid",
            "WR_COLLECT",
            "RD_CAPTURE",
        ):
            require(
                forbidden not in wrapper,
                f"{name} wrapper retains AXI protocol state {forbidden}",
            )
        require(
            wrapper.count("reset_release_sync u_reset_release_sync") == 1,
            f"{name} wrapper reset-release authority changed",
        )
    require(
        "reset_release_sync" not in transport,
        "shared transport incorrectly owns reset release",
    )

    tracker = extract_module(
        destination_text, "destination_sequence_integrity_tracker"
    )
    observer = extract_module(
        destination_text, "transaction_destination_observer"
    )
    core = extract_module(core_text, "stage2g_protection_core")
    require(
        destination_text.count(
            "module destination_sequence_integrity_tracker"
        )
        == 1,
        "destination tracker module count is not one",
    )
    require(
        destination_text.count(
            "reg [SEQUENCE_WIDTH-1:0] expected_sequence;"
        )
        == 1,
        "destination expected-sequence state authority count is not one",
    )
    require(
        destination_text.count("reg has_last_delivery;") == 1,
        "destination has-last state authority count is not one",
    )
    require(
        "output reg  [SEQUENCE_WIDTH-1:0] last_destination_sequence"
        in tracker,
        "destination tracker does not own last delivery state",
    )
    for output_name in (
        "expected_delivery",
        "duplicate_delivery",
        "stale_first_delivery",
        "sequence_gap",
        "reorder_or_stale",
        "sequence_delta",
        "last_destination_sequence",
    ):
        require(
            output_name in tracker,
            f"destination tracker omits classification {output_name}",
        )
    require(
        observer.count("destination_sequence_integrity_tracker #(") == 1,
        "destination observer does not instantiate exactly one tracker",
    )
    for forbidden in (
        "reg [SEQUENCE_WIDTH-1:0] expected_sequence;",
        "reg has_last_delivery;",
    ):
        require(
            forbidden not in observer,
            f"destination observer retains mutable tracker state {forbidden}",
        )
    for forbidden in (
        "expected_sample_sequence",
        "has_last_sample_delivery",
        "last_sample_sequence",
        "stage2e_transaction_sequence_classifier",
        "u_sequence_classifier",
    ):
        require(
            forbidden not in core,
            f"Stage2G core retains destination authority {forbidden}",
        )
    require_regex(
        core,
        r"accepted_integrity_clean\s*<=\s*"
        r"sample_source_integrity_clean\s*&&\s*"
        r"sample_destination_integrity_clean\s*;",
        "Stage2G core does not combine the two direct transaction results",
    )
    require_regex(
        top_text,
        r"\.sample_destination_integrity_clean\s*\(\s*"
        r"destination_expected_delivery\s*\)",
        "production top does not route observer classification to policy",
    )
    for module_name, module in (
        ("Stage2G AXI wrapper", stage2g_axi),
        (
            "Stage2G register-controlled wrapper",
            extract_module(reg_text, "stage2g_protection_ip_reg_controlled"),
        ),
        ("Stage2G core", core),
    ):
        require(
            "sample_destination_integrity_clean" in module,
            f"{module_name} omits direct destination classification",
        )
    require(
        "obs_sticky" not in core and "obs_" not in core,
        "Stage2G core consumes observability telemetry",
    )

    source_observer = extract_module(
        source_text, "transaction_source_observer"
    )
    stage2g_bridge = extract_module(
        bridge_text, "stage2g_adc_sample_cdc_bridge"
    )
    require(
        "module stage2g_source_integrity_tracker" not in source_text,
        "duplicate Stage2G source tracker module remains",
    )
    require(
        source_text.count("reg stall_pending;") == 1,
        "source stall-pending state authority count is not one",
    )
    require(
        source_text.count("reg stall_violation_recorded;") == 1,
        "source violation state authority count is not one",
    )
    require(
        source_text.count(
            "reg [PAYLOAD_WIDTH-1:0] stall_payload_snapshot;"
        )
        == 1,
        "source stalled-payload state authority count is not one",
    )
    require_regex(
        source_observer,
        r"assign\s+transaction_integrity_clean\s*=\s*"
        r"!\(stall_violation_recorded\s*\|\|\s*"
        r"source_protocol_violation_event\)\s*;",
        "source observer integrity result is not derived from its protocol state",
    )
    require(
        stage2g_bridge.count(
            "transaction_source_observer #("
        )
        == 1,
        "Stage2G bridge does not instantiate exactly one source observer",
    )
    require(
        "u_source_integrity_tracker" not in stage2g_bridge
        and "stage2g_source_integrity_tracker" not in stage2g_bridge,
        "Stage2G bridge retains a second source stall tracker",
    )
    require_regex(
        stage2g_bridge,
        r"\.transaction_integrity_clean\s*\(\s*"
        r"source_integrity_clean\s*\)",
        "Stage2G FIFO sideband is not driven by the shared source observer",
    )
    require_regex(
        stage2g_bridge,
        r"assign\s+fifo_write_data\s*=\s*\{\s*"
        r"source_integrity_clean\s*,",
        "Stage2G FIFO payload omits the direct source integrity bit",
    )
    require_regex(
        top_text,
        r"\.sample_source_integrity_clean\s*\(\s*"
        r"dst_sample_integrity_clean\s*\)",
        "production policy source result is not the FIFO sideband",
    )

    return [
        "B2_RECOMMENDED_CHANGE_COUNT=3",
        "AXI_LITE_REGISTER_TRANSPORT_STATE_AUTHORITY_COUNT=1",
        "DESTINATION_SEQUENCE_MUTABLE_STATE_AUTHORITY_COUNT=1",
        "SOURCE_OFFER_PROTOCOL_MUTABLE_STATE_AUTHORITY_COUNT=1",
        "LEGACY_AXI_TRANSPORT_STATE_COPY=0",
        "STAGE2G_AXI_TRANSPORT_STATE_COPY=0",
        "DUPLICATE_DESTINATION_SEQUENCE_STATE_IN_STAGE2G_CORE=NO",
        "DUPLICATE_SOURCE_STALL_STATE_IN_STAGE2G_TRACKER=NO",
        "SECOND_AXI_TRANSPORT_FSM_COPY=NO",
        "POLICY_CONSUMES_TELEMETRY_COUNTERS=NO",
        "POLICY_CONSUMES_STICKY_OBSERVABILITY=NO",
        "ACLK_RESET_AUTHORITY_CHANGED=NO",
        "BUILD_SOURCE_LIST_IMPACT=NONE",
        "STAGE2H_B2_ARCHITECTURE_AUTHORITY_CLOSURE=PASS",
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    args = parser.parse_args()
    try:
        markers = check(args.root.resolve())
    except (CheckError, KeyError, json.JSONDecodeError, OSError) as exc:
        print(f"STAGE2H_B2_ARCHITECTURE_AUTHORITY_CLOSURE=FAIL: {exc}")
        return 1
    print("\n".join(markers))
    return 0


if __name__ == "__main__":
    sys.exit(main())
