"""Portable resolution of tools, paths, and optional Git identity."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path


CONFIG_NAME = "toolchain.json"


def load_config(root: Path) -> dict[str, str]:
    selected = os.environ.get("CSIP_CONFIG")
    path = Path(selected).expanduser().resolve() if selected else root / "config" / CONFIG_NAME
    if not path.is_file():
        if selected:
            raise ValueError(f"Configuration file does not exist: {path}")
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ValueError(f"Invalid configuration: {path}: {error}") from error
    if not isinstance(payload, dict) or any(not isinstance(value, str) for value in payload.values()):
        raise ValueError("Toolchain configuration must be an object of string values")
    result = {}
    for key, value in payload.items():
        if value:
            expanded = Path(value).expanduser()
            if not expanded.is_absolute() and (key in ('build_root', 'board_repo', 'vivado_bin', 'sim_scratch_root') or "/" in value or "\\" in value):
                value = str((path.parent / expanded).resolve())
            result[key] = value
    return result


def configured(root: Path, name: str, argument: str | Path | None = None) -> str | None:
    if argument is not None and str(argument):
        return str(argument)
    env_name = f"CSIP_{name.upper()}"
    if os.environ.get(env_name):
        return os.environ[env_name]
    return load_config(root).get(name)


def resolve_tool(
    root: Path,
    name: str,
    argument: str | Path | None = None,
    aliases: tuple[str, ...] = (),
) -> Path | None:
    explicit = configured(root, name, argument)
    candidates = [explicit] if explicit else [name, *aliases]
    for candidate in candidates:
        if not candidate:
            continue
        path = Path(candidate)
        if path.is_file():
            return path.resolve()
        found = shutil.which(str(candidate))
        if found:
            return Path(found).resolve()
    if explicit:
        raise ValueError(f"Configured {name} executable was not found: {explicit}")
    return None


def resolve_directory(
    root: Path,
    name: str,
    argument: str | Path | None = None,
    *,
    required: bool = False,
) -> Path | None:
    value = configured(root, name, argument)
    if not value:
        if required:
            raise ValueError(f"{name} requires a command-line option or CSIP_{name.upper()}")
        return None
    path = Path(value).expanduser().resolve()
    if required and not path.is_dir():
        raise ValueError(f"configured {name} directory does not exist: {path}")
    return path


def optional_git_identity(root: Path) -> dict[str, str] | None:
    """Return local identity when Git is available, otherwise leave it absent."""
    if not (root / ".git").exists():
        return None
    try:
        values = {}
        for key, args in (
            ("branch", ("branch", "--show-current")),
            ("commit", ("rev-parse", "HEAD")),
            ("tree", ("rev-parse", "HEAD^{tree}")),
        ):
            result = subprocess.run(
                ["git", "-C", str(root), *args],
                check=True,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
            )
            values[key] = result.stdout.strip()
        return values
    except (OSError, subprocess.CalledProcessError):
        return None


def resolve_vivado_bin(root: Path, argument: str | Path | None = None) -> Path | None:
    directory = resolve_directory(root, "vivado_bin", argument)
    if directory is not None:
        launcher = directory / ('vivado.bat' if os.name == 'nt' else 'vivado')
        if not launcher.is_file():
            raise ValueError(f'Configured vivado_bin has no Vivado executable: {directory}')
        return directory
    executable = resolve_tool(root, "vivado", aliases=("vivado.bat", "vivado.exe"))
    return executable.parent if executable is not None else None
