#!/usr/bin/env python3
"""Run JSON-generated Stage 2F profiles through default-parameter RTL."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
from pathlib import Path
import random
import re
import shutil
import subprocess
import sys

try:
    from tools.generate_stage2f_adc_profile import generate
    from tools.stage2f_normalization_reference import load_profile, normalize_code
except ModuleNotFoundError:
    from generate_stage2f_adc_profile import generate  # type: ignore[no-redef]
    from stage2f_normalization_reference import (  # type: ignore[no-redef]
        load_profile,
        normalize_code,
    )


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.runtime_config import resolve_vivado_bin
SCHEMA = ROOT / "spec/stage2f_adc_source_profile.schema.json"
PRODUCTION = ROOT / "spec/stage2f_adc_source_profile_unconfigured.json"
PRODUCTION_INCLUDE = ROOT / "rtl/generated/stage2f_adc_source_profile.svh"
NORMALIZER = ROOT / "rtl/adc_sample_code_normalizer.sv"
TESTBENCH = ROOT / "tb/stage2f/tb_stage2f_generated_profile_vectors.sv"
PROFILES = tuple(sorted((ROOT / "spec/stage2f_profiles").glob("*.json")))
WIDTH_WARNING = re.compile(
    r"(?:\bport\b[^\n]*(?:expects|width)|\bpadding\b|\bpruning\b|width mismatch|actual bit length)", re.IGNORECASE
)


def has_width_warning(text: str) -> bool:
    # Inspect diagnostic messages, not filenames in source-location continuations.
    for line in text.splitlines():
        match = re.search(r'\bwarning\s*:\s*(.*)', line, re.IGNORECASE)
        if match and WIDTH_WARNING.search(match.group(1)):
            return True
    return False


@dataclass(frozen=True)
class CaseArtifacts:
    identity: str
    profile_path: Path
    rtl_root: Path
    normalizer: Path
    header: Path
    vector_include: Path
    vectors: Path
    metadata: Path
    profile_sha256: str
    header_sha256: str
    vector_sha256: str
    row_count: int


@dataclass(frozen=True)
class SimulatorResult:
    simulator: str
    compile_returncode: int
    elaborate_returncode: int
    run_returncode: int
    compile_text: str
    elaborate_text: str
    run_text: str

    @property
    def passed(self) -> bool:
        return (
            self.compile_returncode == 0
            and self.elaborate_returncode == 0
            and self.run_returncode == 0
        )

    @property
    def build_passed(self) -> bool:
        return self.compile_returncode == 0 and self.elaborate_returncode == 0


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_process(
    arguments: list[str], working_directory: Path, log_path: Path
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        arguments,
        cwd=working_directory,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    log_path.write_text(result.stdout, encoding="utf-8", newline="\n")
    return result


def _stimuli(identity: str, zero_code: int | None) -> list[tuple[int, int, int, int, int]]:
    rows: list[tuple[int, int, int, int, int]] = [
        (0, 0, 0, 0, 0),
        (0, 1, 1, 0x800, 0x7FF),
        (1, 0, 2, 0, 0),
    ]
    boundaries = [0, 1, 0x7FF, 0x800, 0x801, 0xFFE, 0xFFF]
    if zero_code is not None:
        boundaries.extend(
            max(0, min(0xFFF, value))
            for value in (zero_code - 1, zero_code, zero_code + 1)
        )
    sequence = 0x1000
    for index, raw in enumerate(boundaries):
        rows.append((1, 1, sequence, raw, boundaries[-index - 1]))
        sequence += 1
    for index in range(12):
        raw = (index * 0x137) & 0xFFF
        rows.append((1, 1, sequence, raw, raw if index % 3 else 0x800))
        sequence += 1
    repeated = (0x5A5, 0x5A5)
    rows.extend((1, 1, sequence + index, *repeated) for index in range(3))
    sequence += 3
    rng = random.Random(0x2F000000 + sum(identity.encode("ascii")))
    for _ in range(64):
        valid = 0 if rng.randrange(4) == 0 else 1
        ch1 = rng.randrange(4096)
        ch2 = ch1 if rng.randrange(5) == 0 else rng.randrange(4096)
        rows.append((1, valid, sequence, ch1, ch2))
        if valid:
            sequence += 1
    rows.extend(
        (
            (1, 1, sequence, 0x801, 0x7FF),
            (0, 0, 0, 0, 0),
            (0, 1, 0xFFFFFFFF, 0xFFF, 0x800),
            (1, 1, 0xA5A55A5A, 0x800, 0x801),
            (1, 0, 0, 0, 0),
            (1, 1, 0xA5A55A5B, 0x7FF, 0x800),
            (1, 0, 0, 0, 0),
        )
    )
    return rows


def write_reference_vectors(profile_path: Path, destination: Path) -> int:
    profile = load_profile(profile_path)
    held_sequence = 0
    held_ch1 = 0
    held_ch2 = 0
    output: list[str] = []
    for cycle, stimulus in enumerate(_stimuli(profile.identity, profile.zero_code)):
        reset_n, raw_valid, sequence, raw_ch1, raw_ch2 = stimulus
        expected_valid = 0
        if not reset_n:
            held_sequence = 0
            held_ch1 = 0
            held_ch2 = 0
        elif raw_valid:
            ch1 = normalize_code(raw_ch1, profile, 1)
            ch2 = normalize_code(raw_ch2, profile, 2)
            if ch1 is None or ch2 is None:
                raise RuntimeError(f"configured profile produced no value: {profile.identity}")
            expected_valid = 1
            held_sequence = sequence
            held_ch1 = ch1
            held_ch2 = ch2
        output.append(
            " ".join(
                str(value)
                for value in (
                    cycle,
                    reset_n,
                    raw_valid,
                    sequence,
                    raw_ch1,
                    raw_ch2,
                    expected_valid,
                    held_sequence,
                    held_ch1,
                    held_ch2,
                )
            )
        )
    destination.write_text("\n".join(output) + "\n", encoding="ascii", newline="\n")
    return len(output)


def prepare_profile_case(profile_path: Path, case_root: Path) -> CaseArtifacts:
    if case_root.exists():
        raise RuntimeError(f"profile case output already exists: {case_root}")
    rtl_root = case_root / "rtl"
    generated = rtl_root / "generated"
    generated.mkdir(parents=True)
    normalizer = rtl_root / NORMALIZER.name
    header = generated / "stage2f_adc_source_profile.svh"
    vector_include = generated / "stage2f_reference_vectors.svh"
    vectors = case_root / "reference_vectors.txt"
    metadata = case_root / "profile_vector_provenance.txt"
    shutil.copy2(NORMALIZER, normalizer)
    generate(SCHEMA, profile_path, header, False)
    row_count = write_reference_vectors(profile_path, vectors)
    vector_include.write_text(
        "// Generated for an isolated Stage 2F reference-vector simulation.\n"
        f'`define STAGE2F_REFERENCE_VECTOR_FILE "{vectors.as_posix()}"\n',
        encoding="utf-8",
        newline="\n",
    )
    profile_sha = sha256_file(profile_path)
    header_sha = sha256_file(header)
    vector_sha = sha256_file(vectors)
    metadata.write_text(
        "\n".join(
            (
                f"PROFILE_IDENTITY={profile_path.stem}",
                f"PROFILE_JSON={profile_path.resolve()}",
                f"PROFILE_JSON_SHA256={profile_sha}",
                f"GENERATED_HEADER_SHA256={header_sha}",
                f"REFERENCE_VECTOR_SHA256={vector_sha}",
                f"REFERENCE_VECTOR_ROWS={row_count}",
                "REFERENCE_AUTHORITY=PYTHON_INTEGER_MODEL",
            )
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return CaseArtifacts(
        identity=profile_path.stem,
        profile_path=profile_path,
        rtl_root=rtl_root,
        normalizer=normalizer,
        header=header,
        vector_include=vector_include,
        vectors=vectors,
        metadata=metadata,
        profile_sha256=profile_sha,
        header_sha256=header_sha,
        vector_sha256=vector_sha,
        row_count=row_count,
    )


def _icarus(case: CaseArtifacts, output: Path) -> SimulatorResult:
    output.mkdir(parents=True, exist_ok=True)
    iverilog = shutil.which("iverilog") or shutil.which("iverilog.exe")
    vvp = shutil.which("vvp") or shutil.which("vvp.exe")
    if not iverilog or not vvp:
        raise RuntimeError("Icarus tools are required")
    image = output / "generated_profile.vvp"
    compile_result = run_process(
        [
            iverilog,
            "-g2012",
            "-Wall",
            "-I",
            str(case.rtl_root),
            "-s",
            TESTBENCH.stem,
            "-o",
            str(image),
            str(case.normalizer),
            str(TESTBENCH),
        ],
        output,
        output / "compile.log",
    )
    if compile_result.returncode != 0:
        return SimulatorResult(
            "ICARUS", compile_result.returncode, 1, 1, compile_result.stdout, "", ""
        )
    run_result = run_process(
        [vvp, str(image)],
        output,
        output / "run.log",
    )
    return SimulatorResult(
        "ICARUS", 0, 0, run_result.returncode, compile_result.stdout, "", run_result.stdout
    )


def _xsim(case: CaseArtifacts, output: Path) -> SimulatorResult:
    output.mkdir(parents=True, exist_ok=True)
    vivado = resolve_vivado_bin(ROOT)
    if vivado is None:
        raise RuntimeError('Vivado/XSim tools are required')
    xvlog = vivado / "xvlog.bat"
    xelab = vivado / "xelab.bat"
    xsim = vivado / "xsim.bat"
    if not all(path.is_file() for path in (xvlog, xelab, xsim)):
        raise RuntimeError("Vivado/XSim tools are required")
    compile_result = run_process(
        [
            str(xvlog),
            "--sv",
            "-i",
            str(case.rtl_root),
            "--log",
            str(output / "xvlog.log"),
            str(case.normalizer),
            str(TESTBENCH),
        ],
        output,
        output / "xvlog.console.log",
    )
    if compile_result.returncode != 0:
        return SimulatorResult(
            "XSIM", compile_result.returncode, 1, 1, compile_result.stdout, "", ""
        )
    snapshot = "generated_profile_snapshot"
    elaborate_result = run_process(
        [
            str(xelab),
            f"work.{TESTBENCH.stem}",
            "-s",
            snapshot,
            "--timescale",
            "1ns/1ps",
            "--log",
            str(output / "xelab.log"),
        ],
        output,
        output / "xelab.console.log",
    )
    if elaborate_result.returncode != 0:
        return SimulatorResult(
            "XSIM",
            0,
            elaborate_result.returncode,
            1,
            compile_result.stdout,
            elaborate_result.stdout,
            "",
        )
    run_result = run_process(
        [
            str(xsim),
            snapshot,
            "-runall",
            "--onerror",
            "quit",
            "--onfinish",
            "quit",
            "--log",
            str(output / "xsim.log"),
        ],
        output,
        output / "xsim.console.log",
    )
    return SimulatorResult(
        "XSIM",
        0,
        0,
        run_result.returncode,
        compile_result.stdout,
        elaborate_result.stdout,
        run_result.stdout,
    )


def run_simulator(simulator: str, case: CaseArtifacts, output: Path) -> SimulatorResult:
    if simulator == "ICARUS":
        return _icarus(case, output)
    if simulator == "XSIM":
        return _xsim(case, output)
    raise ValueError(f"unsupported simulator: {simulator}")


def require_passing_result(result: SimulatorResult, case: CaseArtifacts) -> None:
    marker = f"STAGE2F_GENERATED_PROFILE_RTL=PASS PROFILE={case.identity}"
    identity = f"STAGE2F_GENERATED_PROFILE_IDENTITY={case.identity}"
    profile_hash = f"STAGE2F_GENERATED_PROFILE_SHA256={case.profile_sha256}"
    if not result.passed or marker not in result.run_text:
        raise RuntimeError(f"{result.simulator} generated profile failed: {case.identity}")
    if identity not in result.run_text or profile_hash not in result.run_text:
        raise RuntimeError(
            f"{result.simulator} generated profile provenance mismatch: {case.identity}"
        )
    compile_text = result.compile_text + "\n" + result.elaborate_text
    if has_width_warning(compile_text):
        raise RuntimeError(
            f"{result.simulator} width warning in generated profile: {case.identity}"
        )


def run_matrix(output: Path, include_xsim: bool) -> tuple[int, list[str]]:
    if output.exists():
        raise RuntimeError(f"output already exists: {output}")
    output.mkdir(parents=True)
    if len(PROFILES) != 6:
        raise RuntimeError(f"expected six validation profiles, found {len(PROFILES)}")
    production_before = sha256_file(PRODUCTION_INCLUDE)
    results: list[str] = []
    for profile_path in PROFILES:
        case_root = output / profile_path.stem
        case = prepare_profile_case(profile_path, case_root)
        simulators = ("ICARUS", "XSIM") if include_xsim else ("ICARUS",)
        simulator_status: list[str] = []
        for simulator in simulators:
            result = run_simulator(simulator, case, case_root / simulator.lower())
            require_passing_result(result, case)
            simulator_status.append(f"{simulator}=PASS")
        results.append(
            " ".join(
                (
                    f"PROFILE={case.identity}",
                    f"PROFILE_JSON_SHA256={case.profile_sha256}",
                    f"GENERATED_HEADER_SHA256={case.header_sha256}",
                    f"REFERENCE_VECTOR_SHA256={case.vector_sha256}",
                    f"REFERENCE_VECTOR_ROWS={case.row_count}",
                    *simulator_status,
                )
            )
        )
    if not generate(SCHEMA, PRODUCTION, PRODUCTION_INCLUDE, True):
        raise RuntimeError("checked-in production include is stale")
    if sha256_file(PRODUCTION_INCLUDE) != production_before:
        raise RuntimeError("checked-in production include changed during matrix")
    matrix_marker = (
        "GENERATED_PROFILE_RTL_MATRIX=PASS_6_OF_6_ICARUS_AND_XSIM"
        if include_xsim
        else "GENERATED_PROFILE_RTL_MATRIX=PASS_6_OF_6_ICARUS"
    )
    summary = [
        matrix_marker,
        "PYTHON_REFERENCE_TO_RTL_COMPARISON=PASS",
        "PRODUCTION_INCLUDE_CURRENT=PASS",
        *results,
    ]
    (output / "generated_profile_rtl_matrix.txt").write_text(
        "\n".join(summary) + "\n", encoding="utf-8", newline="\n"
    )
    (output / "python_reference_to_rtl_results.txt").write_text(
        "\n".join(
            (
                "PYTHON_REFERENCE_TO_RTL_COMPARISON=PASS",
                "SIMULATORS=ICARUS,XSIM" if include_xsim else "SIMULATORS=ICARUS",
                "PROFILE_COUNT=6",
                *(
                    " ".join(part for part in line.split() if "VECTOR" in part or part.startswith("PROFILE="))
                    for line in results
                ),
            )
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return len(results), summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--xsim", action="store_true")
    args = parser.parse_args(argv)
    try:
        count, summary = run_matrix(args.output.resolve(), args.xsim)
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"STAGE2F_GENERATED_PROFILE_RTL=FAIL: {exc}", file=sys.stderr)
        return 1
    for line in summary[:3]:
        print(line)
    print(f"GENERATED_PROFILE_CASE_COUNT={count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
