#!/usr/bin/env python3
"""Kill generated-profile mutations through the real Stage 2F normalizer."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import sys

try:
    from tools.run_stage2f_generated_profile_rtl import (
        ROOT,
        prepare_profile_case,
        require_passing_result,
        run_simulator,
        sha256_file,
    )
except ModuleNotFoundError:
    from run_stage2f_generated_profile_rtl import (  # type: ignore[no-redef]
        ROOT,
        prepare_profile_case,
        require_passing_result,
        run_simulator,
        sha256_file,
    )


@dataclass(frozen=True)
class Mutation:
    name: str
    profile: str
    replacements: tuple[tuple[str, str], ...]
    expected_stage: str


MUTATIONS = (
    Mutation(
        "encoding_codes_swapped",
        "SIM_UNSIGNED_ZERO_EDGE_0",
        (("`define STAGE2F_PROFILE_ENCODING 2'd1", "`define STAGE2F_PROFILE_ENCODING 2'd2"),),
        "SIMULATION_ORACLE",
    ),
    Mutation(
        "polarity_negative_values_swapped",
        "SIM_UNSIGNED_ZERO_MIDSCALE_CH2_REVERSED",
        (
            (
                "`define STAGE2F_PROFILE_CH1_POLARITY_NEGATIVE 1'b0",
                "`define STAGE2F_PROFILE_CH1_POLARITY_NEGATIVE 1'b1",
            ),
            (
                "`define STAGE2F_PROFILE_CH2_POLARITY_NEGATIVE 1'b1",
                "`define STAGE2F_PROFILE_CH2_POLARITY_NEGATIVE 1'b0",
            ),
        ),
        "SIMULATION_ORACLE",
    ),
    Mutation(
        "configured_forced_zero",
        "SIM_UNSIGNED_ZERO_MIDSCALE_POSITIVE",
        (("`define STAGE2F_PROFILE_CONFIGURED 1'b1", "`define STAGE2F_PROFILE_CONFIGURED 1'b0"),),
        "SIMULATION_ORACLE",
    ),
    Mutation(
        "zero_code_wrong_constant",
        "SIM_UNSIGNED_ZERO_MIDSCALE_POSITIVE",
        (("`define STAGE2F_PROFILE_ZERO_CODE 12'd2048", "`define STAGE2F_PROFILE_ZERO_CODE 12'd2047"),),
        "SIMULATION_ORACLE",
    ),
    Mutation(
        "raw_width_wrong_constant",
        "SIM_TWOS_COMPLEMENT_POSITIVE",
        (("`define STAGE2F_PROFILE_RAW_WIDTH 12", "`define STAGE2F_PROFILE_RAW_WIDTH 11"),),
        "COMPILE_OR_ELABORATE",
    ),
    Mutation(
        "normalized_width_wrong_constant",
        "SIM_TWOS_COMPLEMENT_POSITIVE",
        (("`define STAGE2F_PROFILE_NORMALIZED_WIDTH 13", "`define STAGE2F_PROFILE_NORMALIZED_WIDTH 12"),),
        "COMPILE_OR_ELABORATE",
    ),
)


def mutation_source_sha256(mutation: Mutation) -> str:
    payload = json.dumps(
        {
            "name": mutation.name,
            "profile": mutation.profile,
            "replacements": mutation.replacements,
            "expected_stage": mutation.expected_stage,
        },
        sort_keys=True,
        separators=(",", ":"),
    ).encode("ascii")
    return hashlib.sha256(payload).hexdigest()


def apply_mutation(text: str, mutation: Mutation) -> str:
    result = text
    for old, new in mutation.replacements:
        if result.count(old) != 1:
            raise RuntimeError(
                f"mutation anchor count is not one: {mutation.name}: {old}"
            )
        result = result.replace(old, new, 1)
    if result == text:
        raise RuntimeError(f"mutation did not alter output: {mutation.name}")
    return result


def mutant_is_killed(mutation: Mutation, result_text: str, build_passed: bool, passed: bool) -> bool:
    if mutation.expected_stage == "COMPILE_OR_ELABORATE":
        return not build_passed
    if not build_passed:
        return False
    oracle_markers = (
        "GENERATED PROFILE VECTOR FAIL",
        "generated validation profile is not configured",
        "generated profile status is invalid",
    )
    return not passed and any(marker in result_text for marker in oracle_markers)


def run(output: Path, include_xsim: bool) -> list[str]:
    if output.exists():
        raise RuntimeError(f"output already exists: {output}")
    output.mkdir(parents=True)
    simulators = ("ICARUS", "XSIM") if include_xsim else ("ICARUS",)
    results: list[str] = []
    for mutation in MUTATIONS:
        profile = ROOT / "spec/stage2f_profiles" / f"{mutation.profile}.json"
        case_root = output / mutation.name
        case = prepare_profile_case(profile, case_root)
        baseline_sha = sha256_file(case.header)
        for simulator in simulators:
            baseline = run_simulator(
                simulator, case, case_root / f"baseline_{simulator.lower()}"
            )
            require_passing_result(baseline, case)
        original = case.header.read_text(encoding="utf-8")
        case.header.write_text(
            apply_mutation(original, mutation),
            encoding="utf-8",
            newline="\n",
        )
        mutant_sha = sha256_file(case.header)
        if mutant_sha == baseline_sha:
            raise RuntimeError(f"mutant output hash did not change: {mutation.name}")
        for simulator in simulators:
            result = run_simulator(
                simulator, case, case_root / f"mutant_{simulator.lower()}"
            )
            combined = "\n".join(
                (result.compile_text, result.elaborate_text, result.run_text)
            )
            pass_marker = (
                f"STAGE2F_GENERATED_PROFILE_RTL=PASS PROFILE={case.identity}"
            )
            if not mutant_is_killed(
                mutation,
                combined,
                result.build_passed,
                result.passed and pass_marker in result.run_text,
            ):
                raise RuntimeError(
                    f"{simulator} generator mutant survived or died at wrong stage: "
                    f"{mutation.name}"
                )
            results.append(
                " ".join(
                    (
                        f"MUTANT={mutation.name}",
                        f"SIMULATOR={simulator}",
                        "STATUS=KILLED",
                        f"PROFILE={mutation.profile}",
                        f"PROFILE_JSON_SHA256={case.profile_sha256}",
                        f"MUTANT_SOURCE_SHA256={mutation_source_sha256(mutation)}",
                        f"BASELINE_OUTPUT_SHA256={baseline_sha}",
                        f"MUTANT_OUTPUT_SHA256={mutant_sha}",
                        f"KILL_STAGE={mutation.expected_stage}",
                    )
                )
            )
    marker = f"GENERATOR_TO_RTL_PROFILE_FIXTURES=PASS_{len(results)}_OF_{len(results)}"
    (output / "generator_mutation_results.txt").write_text(
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
        print(f"GENERATOR_TO_RTL_PROFILE_FIXTURES=FAIL: {exc}", file=sys.stderr)
        return 1
    print(f"GENERATOR_TO_RTL_PROFILE_FIXTURES=PASS_{len(results)}_OF_{len(results)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
