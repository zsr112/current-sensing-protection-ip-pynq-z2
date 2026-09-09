#!/usr/bin/env python3
"""Kill connected Stage 2F top-level width and sequence boundary mutations."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
from pathlib import Path
import sys

try:
    from tools.run_stage2f_width_sequence_boundary import (
        PASS_MARKER,
        ROOT,
        prepare_rtl_root,
        require_pass,
        run_case,
    )
except ModuleNotFoundError:
    from run_stage2f_width_sequence_boundary import (  # type: ignore[no-redef]
        PASS_MARKER,
        ROOT,
        prepare_rtl_root,
        require_pass,
        run_case,
    )


TOP = ROOT / "rtl/protection_ip_top_async_adc_axi_lite.v"


@dataclass(frozen=True)
class Mutation:
    name: str
    old: str
    new: str
    expected_stage: str


MUTATIONS = (
    Mutation(
        "width_gate_removed",
        "if (DATA_WIDTH == 12) begin : g_stage2f_normalization_supported",
        "if (1'b1) begin : g_stage2f_normalization_supported",
        "COMPILE_OR_ELABORATE",
    ),
    Mutation(
        "unsupported_tie_bypassed",
        "assign normalized_sample_valid = 1'b0;",
        "assign normalized_sample_valid = dst_sample_valid;",
        "SIMULATION_ORACLE",
    ),
    Mutation(
        "sequence_binding_truncated",
        ".RAW_WIDTH(DATA_WIDTH),\n                .SEQUENCE_WIDTH(OBS_SEQUENCE_WIDTH),\n                .NORMALIZED_WIDTH(13)",
        ".RAW_WIDTH(DATA_WIDTH),\n                .SEQUENCE_WIDTH(16),\n                .NORMALIZED_WIDTH(13)",
        "SIMULATION_ORACLE",
    ),
)


def apply_mutation(text: str, mutation: Mutation) -> str:
    if text.count(mutation.old) != 1:
        raise RuntimeError(f"mutation anchor count is not one: {mutation.name}")
    return text.replace(mutation.old, mutation.new, 1)


def run(output: Path, include_xsim: bool) -> list[str]:
    if output.exists():
        raise RuntimeError(f"output already exists: {output}")
    output.mkdir(parents=True)
    simulators = ("ICARUS", "XSIM") if include_xsim else ("ICARUS",)
    baseline_root = prepare_rtl_root(output / "control")
    for simulator in simulators:
        result = run_case(
            simulator, baseline_root, output / "control" / simulator.lower()
        )
        require_pass(result)

    source = TOP.read_text(encoding="utf-8")
    results: list[str] = []
    for mutation in MUTATIONS:
        mutant = apply_mutation(source, mutation)
        digest = hashlib.sha256(mutant.encode("utf-8")).hexdigest()
        case_root = output / mutation.name
        rtl_root = prepare_rtl_root(case_root, mutant)
        for simulator in simulators:
            result = run_case(
                simulator, rtl_root, case_root / simulator.lower()
            )
            if mutation.expected_stage == "COMPILE_OR_ELABORATE":
                killed = not result.build_passed
            else:
                killed = (
                    result.build_passed
                    and PASS_MARKER not in result.run_text
                    and "WIDTH SEQUENCE BOUNDARY FAIL" in result.run_text
                )
            if not killed:
                raise RuntimeError(
                    f"{simulator} boundary mutant survived or died at wrong stage: "
                    f"{mutation.name}"
                )
            results.append(
                " ".join(
                    (
                        f"MUTANT={mutation.name}",
                        f"SIMULATOR={simulator}",
                        "STATUS=KILLED",
                        f"KILL_STAGE={mutation.expected_stage}",
                        f"MUTANT_SOURCE_SHA256={digest}",
                    )
                )
            )
    marker = f"NEW_BOUNDARY_MUTATION_FIXTURES=PASS_{len(results)}_OF_{len(results)}"
    (output / "boundary_mutation_results.txt").write_text(
        marker + "\n" + "\n".join(results) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--xsim", action="store_true")
    args = parser.parse_args(argv)
    try:
        results = run(args.output.resolve(), args.xsim)
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"NEW_BOUNDARY_MUTATION_FIXTURES=FAIL: {exc}", file=sys.stderr)
        return 1
    print(f"NEW_BOUNDARY_MUTATION_FIXTURES=PASS_{len(results)}_OF_{len(results)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
