"""Shared helpers for AreaMatrix developer tools."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Mapping, Sequence


class ToolError(RuntimeError):
    """Raised when a developer tool cannot continue."""

    def __init__(self, message: str, code: int = 1) -> None:
        super().__init__(message)
        self.code = code


def project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def fail(message: str, code: int = 1) -> None:
    raise ToolError(message, code)


def default_env(extra: Mapping[str, str] | None = None) -> dict[str, str]:
    env = os.environ.copy()
    env.setdefault("PYTHONPYCACHEPREFIX", str(Path(os.environ.get("TMPDIR", "/tmp")) / "areamatrix-pycache"))
    if extra:
        env.update(extra)
    return env


def command_text(argv: Sequence[str]) -> str:
    import shlex

    return shlex.join([str(part) for part in argv])


def run_step(
    argv: Sequence[str | Path],
    *,
    cwd: Path | None = None,
    env: Mapping[str, str] | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    printable = [str(part) for part in argv]
    print()
    print(f"==> {command_text(printable)}", flush=True)
    proc = subprocess.run(printable, cwd=cwd, env=default_env(env), check=False)
    if check and proc.returncode != 0:
        fail(f"command failed ({proc.returncode}): {command_text(printable)}", proc.returncode)
    return proc


def require_command(command_name: str) -> None:
    if shutil.which(command_name) is None:
        fail(f"missing required command '{command_name}'.", 127)


def require_file(path: Path, description: str) -> None:
    if not path.is_file():
        fail(f"{description} not found at {path}.")


def require_dir(path: Path, description: str) -> None:
    if not path.is_dir():
        fail(f"{description} not found at {path}.")


def resolve_project_path(root: Path, input_path: str | Path) -> Path:
    path = Path(input_path)
    return path if path.is_absolute() else root / path


def print_error(exc: BaseException) -> int:
    if isinstance(exc, ToolError):
        print(f"error: {exc}", file=sys.stderr)
        return exc.code
    print(f"error: {exc}", file=sys.stderr)
    return 1
