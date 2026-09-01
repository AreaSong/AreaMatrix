"""Shared local build-artifact paths for AreaMatrix developer tooling."""

from __future__ import annotations

import fcntl
import json
import os
import time
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator, TextIO

from .metrics import CARGO_LOCK_METRICS_FILE, record_metric


CARGO_ARTIFACT_LANES = ("xcode", "validation", "sdk", "release")
DEFAULT_CARGO_LANE = "sdk"


@dataclass(frozen=True)
class CargoLaneLease:
    """Metadata for one acquired Cargo artifact-lane lock."""

    lane: str
    operation: str
    path: Path
    wait_seconds: float


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _write_lock_metadata(handle: TextIO, metadata: dict[str, object]) -> None:
    handle.seek(0)
    json.dump(metadata, handle, ensure_ascii=True, indent=2, sort_keys=True)
    handle.write("\n")
    handle.truncate()
    handle.flush()
    os.fsync(handle.fileno())


@contextmanager
def cargo_lane_lock(
    root: Path,
    *,
    lane: str,
    operation: str,
    poll_interval: float = 0.05,
) -> Iterator[CargoLaneLease]:
    """Serialize one Cargo-producing workflow within its artifact lane."""

    if lane not in CARGO_ARTIFACT_LANES:
        raise ValueError(f"unsupported Cargo artifact lane: {lane}")
    if not operation:
        raise ValueError("Cargo artifact lock operation must not be empty")
    if poll_interval <= 0:
        raise ValueError("Cargo artifact lock poll interval must be positive")

    lock_path = (root / ".build/locks/cargo" / f"{lane}.lock").resolve()
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    handle = os.fdopen(descriptor, "r+", encoding="utf-8")
    started_at = time.monotonic()
    waiting_reported = False

    try:
        while True:
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if not waiting_reported:
                    print(f"Cargo lock: WAIT lane={lane} operation={operation}", flush=True)
                    waiting_reported = True
                time.sleep(poll_interval)

        wait_seconds = time.monotonic() - started_at
        acquired_at = _utc_now()
        metadata: dict[str, object] = {
            "pid": os.getpid(),
            "lane": lane,
            "operation": operation,
            "state": "acquired",
            "acquired_at": acquired_at,
            "released_at": None,
            "wait_seconds": round(wait_seconds, 6),
        }
        _write_lock_metadata(handle, metadata)
        print(
            f"Cargo lock: ACQUIRED lane={lane} operation={operation} "
            f"wait_seconds={wait_seconds:.3f}",
            flush=True,
        )
        lease = CargoLaneLease(
            lane=lane,
            operation=operation,
            path=lock_path,
            wait_seconds=wait_seconds,
        )
        try:
            yield lease
        finally:
            hold_seconds = time.monotonic() - started_at - wait_seconds
            metadata["state"] = "released"
            metadata["released_at"] = _utc_now()
            try:
                try:
                    _write_lock_metadata(handle, metadata)
                finally:
                    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
            finally:
                record_metric(
                    root,
                    CARGO_LOCK_METRICS_FILE,
                    {
                        "kind": "cargo_lock",
                        "lane": lane,
                        "operation": operation,
                        "status": "success",
                        "wait_seconds": round(wait_seconds, 6),
                        "hold_seconds": round(hold_seconds, 6),
                        "duration_seconds": round(wait_seconds + hold_seconds, 6),
                    },
                )
    finally:
        handle.close()


def resolve_artifact_path(root: Path, value: str | Path) -> Path:
    """Resolve an artifact path without depending on the caller's cwd."""

    path = Path(value).expanduser()
    return path.resolve() if path.is_absolute() else (root / path).resolve()


def cargo_target_dir(
    root: Path,
    *,
    lane: str = DEFAULT_CARGO_LANE,
    configured: str | Path | None = None,
) -> Path:
    """Return the isolated Cargo target directory for one build-purpose lane."""

    if lane not in CARGO_ARTIFACT_LANES:
        raise ValueError(f"unsupported Cargo artifact lane: {lane}")
    override = configured or os.environ.get("AREAMATRIX_CARGO_TARGET_DIR")
    if override:
        return resolve_artifact_path(root, override)
    return (root / ".build/cargo" / lane).resolve()


def macos_derived_data_dir(root: Path, *, configured: str | Path | None = None) -> Path:
    """Return the persistent local DerivedData directory used by ./dev test macos."""

    override = configured or os.environ.get("DERIVED_DATA_PATH")
    if override:
        return resolve_artifact_path(root, override)
    return (root / ".build/derived-data/macos-tests").resolve()
