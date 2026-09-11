#!/usr/bin/env python3
"""Run the focused A2-2 connected width matrix and RTL mutation set."""

from __future__ import annotations

import argparse
import hashlib
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"
TB = ROOT / "tb/stage2g"
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import run_stage2g_mutations as stage2g


class VerificationError(RuntimeError):
    """A focused A2-2 verification oracle did not hold."""


@dataclass(frozen=True)
class A2Mutation:
    name: str
    target: Path
    fixture: str
    top: str
    coverage: str
    transform: object


def replace_exact(text: str, old: str, new: str, label: str, *, expected: int = 1) -> str:
    count = text.count(old)
    if count != expected:
        raise VerificationError(
            f"{label}: source anchor count={count}, expected={expected}"
        )
    return text.replace(old, new)


def production_sources() -> tuple[Path, ...]:
    return tuple(stage2g.PRODUCTION_SOURCES)


def fixture(top: str, *, strict: bool = False) -> stage2g.Fixture:
    return stage2g.Fixture(
        top,
        production_sources(),
        "STAGE2G_PRODUCTION_PATH=PASS",
        strict,
    )


def bank_replacement(old: str, new: str, label: str):
    return stage2g.module_replacement(
        "protection_reg_bank", old, new, label
    )


def controller_replacement(old: str, new: str, label: str, *, expected: int = 1):
    return stage2g.module_replacement(
        "stage2g_fault_episode_controller",
        old,
        new,
        label,
        expected=expected,
    )


def mutations() -> tuple[A2Mutation, ...]:
    bank = RTL / "protection_reg_bank.v"
    controller = RTL / "protection_fsm.v"
    return (
        A2Mutation(
            "ABI_MAGIC_DRIFT",
            bank,
            "default",
            "tb_stage2g_production_path",
            "explicit version magic must remain exact",
            bank_replacement(
                "rd_data = `PROTECTION_REGISTER_MAP_VERSION_VALUE;",
                "rd_data = `PROTECTION_REGISTER_MAP_VERSION_VALUE ^ 32'h0000_0001;",
                "ABI magic drift",
            ),
        ),
        A2Mutation(
            "CAPABILITIES_RESERVED_BIT_ADVERTISED",
            bank,
            "default",
            "tb_stage2g_production_path",
            "reserved capability bits must remain zero",
            bank_replacement(
                "rd_data = `PROTECTION_CAPABILITIES_0_ABI_1_1_VALUE;",
                "rd_data = `PROTECTION_CAPABILITIES_0_ABI_1_1_VALUE | 32'h0000_0080;",
                "reserved capability bit",
            ),
        ),
        A2Mutation(
            "CAPABILITIES_SEQUENCE_WIDTH_HARDCODED",
            bank,
            "width16",
            "tb_stage2h_abi_1_1_width16",
            "CAPABILITIES_1 must report the implemented width",
            bank_replacement(
                "`PROTECTION_CAPABILITIES_1_VALUE(OBS_SEQUENCE_WIDTH);",
                "`PROTECTION_CAPABILITIES_1_VALUE(32);",
                "sequence width metadata",
            ),
        ),
        A2Mutation(
            "POLICY_STATE_CROSSWIRE",
            bank,
            "default",
            "tb_stage2g_production_path",
            "ARMED_READY must decode ST_ARMED",
            bank_replacement(
                "(fsm_state == `PROTECTION_POLICY_STATE_ST_ARMED)",
                "(fsm_state == `PROTECTION_POLICY_STATE_ST_FAULT_LATCHED)",
                "policy state cross-wire",
            ),
        ),
        A2Mutation(
            "CLEAR_LEVEL_CROSSWIRE",
            bank,
            "default",
            "tb_stage2g_production_path",
            "CLEAR_PENDING must use its exact source level",
            bank_replacement(
                "rd_data[`PROTECTION_POLICY_STATUS_CLEAR_PENDING_LSB] =\n                        clear_pending;",
                "rd_data[`PROTECTION_POLICY_STATUS_CLEAR_PENDING_LSB] =\n                        post_clear_recovery_pending;",
                "clear level cross-wire",
            ),
        ),
        A2Mutation(
            "FIRST_BITMAP_SOURCE_CROSSWIRE",
            bank,
            "default",
            "tb_stage2g_production_path",
            "FIRST bitmap must use the first-cause source",
            bank_replacement(
                "rd_data = {{26{1'b0}}, first_fault_bitmap};",
                "rd_data = {{26{1'b0}}, live_fault_bitmap};",
                "first bitmap source",
            ),
        ),
        A2Mutation(
            "BITMAP_UPPER_BITS_LEAK",
            bank,
            "default",
            "tb_stage2g_production_path",
            "bitmap bits above cause width must read zero",
            bank_replacement(
                "rd_data = {{26{1'b0}}, first_fault_bitmap};",
                "rd_data = {26'h3FFFFFF, first_fault_bitmap};",
                "bitmap upper bits",
            ),
        ),
        A2Mutation(
            "FIRST_BITMAP_OVERWRITTEN_ON_LATER_RETIREMENT",
            controller,
            "default",
            "tb_stage2g_production_path",
            "FIRST bitmap must remain immutable in an episode",
            controller_replacement(
                "live_fault_bitmap <= fault_eval_bitmap;\n"
                "                            fault_seen_bitmap <= fault_seen_bitmap |\n"
                "                                                 fault_eval_bitmap;",
                "first_fault_bitmap <= fault_eval_bitmap;\n"
                "                            live_fault_bitmap <= fault_eval_bitmap;\n"
                "                            fault_seen_bitmap <= fault_seen_bitmap |\n"
                "                                                 fault_eval_bitmap;",
                "first bitmap later-retirement overwrite",
                expected=2,
            ),
        ),
        A2Mutation(
            "SEEN_BITMAP_NOT_MONOTONIC",
            controller,
            "default",
            "tb_stage2g_production_path",
            "SEEN bitmap must OR each clean cause set",
            controller_replacement(
                "fault_seen_bitmap <= fault_seen_bitmap |\n"
                "                                                 fault_eval_bitmap;",
                "fault_seen_bitmap <= fault_eval_bitmap;",
                "seen bitmap assignment",
                expected=2,
            ),
        ),
        A2Mutation(
            "POLICY_IDENTITY_IDLE_WIRE",
            bank,
            "default",
            "tb_stage2g_production_path",
            "identity must hold across idle cycles",
            bank_replacement(
                "rd_data = policy_evaluation_sequence;",
                "rd_data = fault_eval_sequence;",
                "idle-cleared identity wire",
            ),
        ),
        A2Mutation(
            "POLICY_IDENTITY_SIGN_EXTENDED",
            bank,
            "width16",
            "tb_stage2h_abi_1_1_width16",
            "identity source must be zero extended",
            bank_replacement(
                "{{(32-OBS_SEQUENCE_WIDTH){1'b0}}, fault_eval_sequence};",
                "{{(32-OBS_SEQUENCE_WIDTH){fault_eval_sequence[OBS_SEQUENCE_WIDTH-1]}}, fault_eval_sequence};",
                "identity zero extension",
            ),
        ),
        A2Mutation(
            "POLICY_IDENTITY_VALID_CAPTURE_DISABLED",
            bank,
            "default",
            "tb_stage2g_production_path",
            "valid nonclean retirements must still be captured",
            bank_replacement(
                "if (fault_eval_valid)",
                "if (fault_eval_valid && 1'b0)",
                "identity valid capture",
            ),
        ),
    )


def run_control(output: Path, name: str, top: str) -> None:
    item = fixture(top, strict=top.endswith("width16"))
    work = output / "controls" / name
    image = stage2g.compile_icarus(item, list(item.sources), work)
    result = stage2g.run_icarus(image, work)
    stage2g.assert_control(result, item, f"control {name}")


def run_mutation(output: Path, item: A2Mutation) -> str:
    source_text = item.target.read_text(encoding="utf-8")
    mutant_text = item.transform(source_text)
    digest = hashlib.sha256(mutant_text.encode("utf-8")).hexdigest()
    case_root = output / "mutants" / item.name.lower()
    mutant_source = case_root / "source" / item.target.name
    mutant_source.parent.mkdir(parents=True, exist_ok=True)
    mutant_source.write_text(mutant_text, encoding="utf-8", newline="\n")
    selected = fixture(item.top, strict=item.top.endswith("width16"))
    sources = stage2g.replace_source(selected.sources, item.target, mutant_source)
    work = case_root / "icarus"
    try:
        image = stage2g.compile_icarus(selected, sources, work)
    except stage2g.MutationError:
        return f"KILLED_COMPILE\t{digest}"
    result = stage2g.run_icarus(image, work)
    try:
        stage2g.assert_killed(result, selected, f"A2-2 {item.name}")
    except stage2g.MutationError as exc:
        raise VerificationError(str(exc)) from exc
    return f"KILLED_RUNTIME\t{digest}"


def run(output: Path) -> tuple[int, Path]:
    if output.exists():
        raise VerificationError(f"output must not already exist: {output}")
    output.mkdir(parents=True)

    run_control(output, "production_width32", "tb_stage2g_production_path")
    run_control(output, "production_width16", "tb_stage2h_abi_1_1_width16")
    run_control(output, "production_width24", "tb_stage2h_abi_1_1_width24")
    run_control(output, "production_width32_explicit", "tb_stage2h_abi_1_1_width32")

    items = mutations()
    names = [item.name for item in items]
    if len(names) != len(set(names)):
        raise VerificationError("A2-2 mutation names are not unique")
    rows = ["NAME\tTARGET\tCOVERAGE\tSTATUS\tSHA256"]
    for item in items:
        status, digest = run_mutation(output, item).split("\t", 1)
        rows.append(
            "\t".join(
                (
                    item.name,
                    item.target.relative_to(ROOT).as_posix(),
                    item.coverage,
                    status,
                    digest,
                )
            )
        )
    inventory = output / "mutation_inventory.tsv"
    inventory.write_text("\n".join(rows) + "\n", encoding="utf-8", newline="\n")
    summary = output / "verification_summary.txt"
    summary.write_text(
        "\n".join(
            (
                "STAGE2H_A2_2_CONNECTED_VERIFICATION=PASS",
                "A2_2_WIDTH_MATRIX=PASS_16_24_32",
                f"A2_2_CONNECTED_MUTATIONS=PASS_{len(items)}_OF_{len(items)}",
                "LEGACY_AXI_ADDITIVE_ACCESS=PASS",
                f"A2_2_MUTATION_INVENTORY={inventory}",
            )
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(summary.read_text(encoding="utf-8"), end="")
    return len(items), inventory


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        run(args.output.resolve())
    except (OSError, VerificationError, stage2g.MutationError) as exc:
        print(f"STAGE2H_A2_2_CONNECTED_VERIFICATION=FAIL: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
