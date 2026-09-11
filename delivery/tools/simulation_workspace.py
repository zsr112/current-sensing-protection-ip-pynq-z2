"""Run simulator file I/O in an ASCII-only temporary workspace."""
from __future__ import annotations

from contextlib import contextmanager
import json
import hashlib
import shutil
import tempfile
from pathlib import Path

try:
    from tools.runtime_config import configured
except ModuleNotFoundError:
    from runtime_config import configured


@contextmanager
def ascii_simulation_workspace(project_root: Path, evidence: Path, label: str):
    """Copy a fresh private ASCII workspace to the requested evidence directory."""
    if evidence.exists():
        raise ValueError("Simulation evidence already exists: " + str(evidence))
    selected = configured(project_root, "sim_scratch_root")
    parent = (
        Path(selected).expanduser().resolve()
        if selected
        else Path(tempfile.gettempdir()).resolve()
    )
    root = project_root.resolve()
    evidence = evidence.resolve()
    if evidence.is_relative_to(root) or root.is_relative_to(evidence):
        raise ValueError('Simulation evidence must be disjoint from source')
    if parent.is_relative_to(root):
        raise ValueError('Simulator scratch must be outside source')
    if not str(parent).isascii():
        raise ValueError(
            "Simulator scratch path must be ASCII; set CSIP_SIM_SCRATCH_ROOT "
            "or sim_scratch_root in the toolchain configuration"
        )
    parent.mkdir(parents=True, exist_ok=True)
    scratch = Path(tempfile.mkdtemp(prefix="csip-sim-", dir=parent))
    status = "FAIL"
    try:
        yield scratch
        status = "PASS"
    finally:
        (scratch / "workspace_receipt.json").write_text(
            json.dumps(
                {
                    "schema": "csip-ascii-simulation-workspace-v1",
                    "label": label,
                    "status": status,
                    "hdl_file_io_path": "ASCII_PRIVATE_TEMPORARY",
                    "evidence_copied_to_requested_output": True,
                    "caller_output": str(evidence),
                    "scratch_path": str(scratch),
                    "vector_sha256": hashlib.sha256((scratch / 'vectors.txt').read_bytes()).hexdigest() if (scratch / 'vectors.txt').is_file() else None,
                },
                sort_keys=True,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
            newline="\n",
        )
        evidence.parent.mkdir(parents=True, exist_ok=True)
        try:
            shutil.copytree(scratch, evidence)
        except Exception:
            print("SIMULATION_SCRATCH_PRESERVED=" + str(scratch))
            raise
        else:
            shutil.rmtree(scratch)
