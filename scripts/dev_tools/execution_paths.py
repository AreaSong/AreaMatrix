"""Version-local execution path helpers for AreaMatrix task runtime."""

from __future__ import annotations

import os
from pathlib import Path


DEFAULT_EXECUTION_VERSION = "v1-mvp"
EXECUTION_VERSION_ENV = "AREAMATRIX_EXECUTION_VERSION"
EXECUTION_ROOT_ENV = "AREAMATRIX_EXECUTION_ROOT"
VERSION_ROOT = Path("workflow/versions")


def project_root(start: Path | None = None) -> Path:
    current = (start or Path(__file__)).resolve()
    if current.is_file():
        current = current.parent
    for candidate in [current, *current.parents]:
        if (candidate / ".git").exists() or (
            (candidate / "AGENTS.md").is_file() and (candidate / "workflow").is_dir()
        ):
            return candidate
    return Path(__file__).resolve().parents[2]


def default_execution_version() -> str:
    return os.environ.get(EXECUTION_VERSION_ENV, DEFAULT_EXECUTION_VERSION)


def execution_root(root: Path | None = None, version: str | None = None) -> Path:
    base = (root or project_root()).resolve()
    override = os.environ.get(EXECUTION_ROOT_ENV)
    if override:
        path = Path(override)
        return path if path.is_absolute() else base / path
    version_id = version or default_execution_version()
    return base / VERSION_ROOT / version_id / "execution"


def shared_root(root: Path | None = None, version: str | None = None) -> Path:
    return execution_root(root, version) / "_shared"


def prompt_pipeline_path(root: Path | None = None, version: str | None = None) -> Path:
    return shared_root(root, version) / "prompt_pipeline.py"


def progress_path(root: Path | None = None, version: str | None = None) -> Path:
    return shared_root(root, version) / "progress.json"


def copy_ready_root(root: Path | None = None, version: str | None = None) -> Path:
    return shared_root(root, version) / "copy-ready"


def verify_ready_root(root: Path | None = None, version: str | None = None) -> Path:
    return shared_root(root, version) / "verify-ready"


def manifest_root(root: Path | None = None, version: str | None = None) -> Path:
    return shared_root(root, version) / "manifests"


def task_root(root: Path | None = None, version: str | None = None) -> Path:
    return execution_root(root, version)


def repo_relative(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()
