"""Best-effort local metrics for the high-frequency build feedback loop."""

from __future__ import annotations

import json
import os
import platform
import statistics
import math
import tempfile
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import fcntl


METRICS_SCHEMA_VERSION = 1
METRICS_DIRECTORY = ".build/metrics"
CORE_SDK_METRICS_FILE = "core-sdk.jsonl"
CARGO_LOCK_METRICS_FILE = "cargo-lock.jsonl"
FEEDBACK_METRICS_FILE = "developer-feedback.jsonl"
METRICS_MAX_RECORDS = 2_000
METRICS_RETENTION_DAYS = 30


def _metrics_path(root: Path, filename: str) -> Path:
    return (root / METRICS_DIRECTORY / filename).resolve()


def _record_timestamp(record: object) -> datetime | None:
    if not isinstance(record, dict):
        return None
    value = record.get("recorded_at")
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo is not None else parsed.replace(tzinfo=timezone.utc)


def _retained_lines(lines: list[str], *, now: datetime) -> list[str]:
    cutoff = now - timedelta(days=METRICS_RETENTION_DAYS)
    retained: list[str] = []
    for line in lines:
        try:
            timestamp = _record_timestamp(json.loads(line))
        except json.JSONDecodeError:
            timestamp = None
        if timestamp is None or timestamp >= cutoff:
            retained.append(line)
    return retained[-METRICS_MAX_RECORDS:]


def _replace_metric_file(path: Path, lines: list[str]) -> None:
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            if lines:
                handle.write("\n".join(lines) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary_path, 0o600)
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def record_metric(root: Path, filename: str, payload: dict[str, Any]) -> bool:
    """Append one metric record without making the build depend on metrics IO."""

    now = datetime.now(timezone.utc)
    record = {
        "schema_version": METRICS_SCHEMA_VERSION,
        "recorded_at": now.isoformat().replace("+00:00", "Z"),
        "kind": payload.get("kind", "unknown"),
        "operation": payload.get("operation", "unknown"),
        "status": payload.get("status", "success"),
        "duration_seconds": payload.get("duration_seconds", payload.get("hold_seconds", 0.0)),
        "fingerprint": payload.get("fingerprint", "unknown"),
        "toolchain": payload.get("toolchain", os.environ.get("RUSTUP_TOOLCHAIN", "unknown")),
        "arch": payload.get("arch", platform.machine() or "unknown"),
        **payload,
    }
    path = _metrics_path(root, filename)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        lock_path = path.with_suffix(f"{path.suffix}.lock")
        with lock_path.open("a+", encoding="utf-8") as lock_handle:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
            existing = path.read_text(encoding="utf-8").splitlines() if path.is_file() else []
            encoded = json.dumps(record, ensure_ascii=True, sort_keys=True)
            _replace_metric_file(path, _retained_lines([*existing, encoded], now=now))
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
    except (OSError, UnicodeDecodeError, TypeError, ValueError):
        return False
    return True


def _read_metric_file(path: Path, *, limit: int) -> tuple[list[dict[str, Any]], int]:
    if not path.is_file():
        return [], 0
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return [], 1

    records: list[dict[str, Any]] = []
    invalid = 0
    for line in lines:
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            invalid += 1
            continue
        if not isinstance(value, dict) or value.get("schema_version") != METRICS_SCHEMA_VERSION:
            invalid += 1
            continue
        records.append(value)
    return records[-limit:], invalid


def _as_float(value: object) -> float:
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else 0.0


def _percentage(numerator: int, denominator: int) -> float | None:
    if denominator == 0:
        return None
    return round(numerator / denominator * 100, 2)


def _percentile(values: list[float], percentile: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, math.ceil(len(ordered) * percentile) - 1))
    return round(ordered[index], 3)


def _feedback_sample_summary(samples: list[float], *, comparable: bool) -> dict[str, Any]:
    return {
        "successful_sample_count": len(samples),
        "p50_seconds": round(statistics.median(samples), 3) if samples else None,
        "p95_seconds": _percentile(samples, 0.95),
        "baseline_ready": comparable and len(samples) >= 20,
    }


def feedback_metrics_summary(root: Path, *, limit: int = 200) -> dict[str, Any]:
    if limit <= 0:
        raise ValueError("metrics limit must be positive")
    records, invalid = _read_metric_file(_metrics_path(root, FEEDBACK_METRICS_FILE), limit=limit)
    paths: dict[str, Any] = {}
    for path in ("canvas", "build", "test", "ci"):
        path_records = [
            record for record in records
            if record.get("path") == path and record.get("status") in (0, "success")
        ]
        cohorts: dict[str, list[float]] = {}
        for record in path_records:
            cohort = str(record.get("cohort") or "legacy-mixed")
            cohorts.setdefault(cohort, []).append(_as_float(record.get("duration_seconds")))
        paths[path] = {
            "successful_sample_count": len(path_records),
            "cohorts": {
                cohort: _feedback_sample_summary(samples, comparable=cohort != "legacy-mixed")
                for cohort, samples in sorted(cohorts.items())
            },
            "baseline_ready": any(
                cohort != "legacy-mixed" and len(samples) >= 20
                for cohort, samples in cohorts.items()
            ),
        }
    return {
        "schema_version": METRICS_SCHEMA_VERSION,
        "mode": "feedback_metrics",
        "sample_limit": limit,
        "paths": paths,
        "invalid_record_count": invalid,
        "file": str(_metrics_path(root, FEEDBACK_METRICS_FILE)),
    }


def record_feedback_metric(
    root: Path,
    *,
    path: str,
    cohort: str,
    duration_seconds: float,
    note: str = "",
) -> bool:
    normalized_cohort = cohort.strip()
    if path not in {"canvas", "build", "test", "ci"} or duration_seconds <= 0 or not normalized_cohort:
        raise ValueError("feedback metric requires canvas/build/test/ci, a cohort, and a positive duration")
    return record_metric(root, FEEDBACK_METRICS_FILE, {
        "kind": "developer_feedback",
        "operation": path,
        "path": path,
        "cohort": normalized_cohort,
        "status": "success",
        "duration_seconds": duration_seconds,
        "note": note,
    })


def run_feedback_metrics(root: Path, *, limit: int, json_output: bool) -> int:
    summary = feedback_metrics_summary(root, limit=limit)
    if json_output:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 0
    for path, values in summary["paths"].items():
        print(f"{path}: samples={values['successful_sample_count']} ready={values['baseline_ready']}")
        for cohort, cohort_values in values["cohorts"].items():
            print(
                f"  {cohort}: samples={cohort_values['successful_sample_count']} "
                f"p50={cohort_values['p50_seconds']} p95={cohort_values['p95_seconds']} "
                f"ready={cohort_values['baseline_ready']}"
            )
    return 0


def build_metrics_summary(root: Path, *, limit: int = 200) -> dict[str, Any]:
    """Summarize recent CoreSDK and Cargo lock samples for local diagnostics."""

    if limit <= 0:
        raise ValueError("metrics limit must be positive")
    core_records, core_invalid = _read_metric_file(
        _metrics_path(root, CORE_SDK_METRICS_FILE), limit=limit
    )
    lock_records, lock_invalid = _read_metric_file(
        _metrics_path(root, CARGO_LOCK_METRICS_FILE), limit=limit
    )

    build_records = [record for record in core_records if record.get("operation", "build") == "build"]
    cache_counts = Counter(str(record.get("cache", "unknown")) for record in build_records)
    successful_builds = [record for record in build_records if record.get("status") == 0]
    hit_count = cache_counts.get("hit", 0) + cache_counts.get("hit-after-wait", 0)
    miss_count = cache_counts.get("miss", 0)
    wait_values = [_as_float(record.get("wait_seconds")) for record in lock_records]
    contended_waits = [value for value in wait_values if value > 0.001]

    core_summary = {
        "sample_count": len(build_records),
        "successful_sample_count": len(successful_builds),
        "cache_counts": dict(sorted(cache_counts.items())),
        "cache_hit_count": hit_count,
        "cache_miss_count": miss_count,
        "cache_hit_rate_percent": _percentage(hit_count, hit_count + miss_count),
        "lock_wait_seconds_total": round(
            sum(_as_float(record.get("lock_wait_seconds")) for record in build_records), 3
        ),
        "lock_wait_seconds_max": round(
            max((_as_float(record.get("lock_wait_seconds")) for record in build_records), default=0.0),
            3,
        ),
    }
    lock_summary = {
        "sample_count": len(lock_records),
        "contended_sample_count": len(contended_waits),
        "contention_rate_percent": _percentage(len(contended_waits), len(lock_records)),
        "wait_seconds_total": round(sum(wait_values), 3),
        "wait_seconds_max": round(max(wait_values, default=0.0), 3),
    }
    return {
        "schema_version": METRICS_SCHEMA_VERSION,
        "mode": "build_metrics",
        "sample_limit": limit,
        "core_sdk": core_summary,
        "cargo_lock": lock_summary,
        "invalid_record_count": core_invalid + lock_invalid,
        "files": {
            "core_sdk": str(_metrics_path(root, CORE_SDK_METRICS_FILE)),
            "cargo_lock": str(_metrics_path(root, CARGO_LOCK_METRICS_FILE)),
        },
    }


def run_build_metrics(
    root: Path,
    *,
    limit: int = 200,
    json_output: bool = False,
    strict: bool = False,
) -> int:
    """Print a read-only build feedback summary."""

    summary = build_metrics_summary(root, limit=limit)
    if json_output:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 1 if strict and summary["invalid_record_count"] else 0

    core = summary["core_sdk"]
    locks = summary["cargo_lock"]
    hit_rate = core["cache_hit_rate_percent"]
    contention_rate = locks["contention_rate_percent"]
    print(
        "Build metrics: "
        f"CoreSDK samples={core['sample_count']} "
        f"cache_hit_rate={hit_rate if hit_rate is not None else 'n/a'}% "
        f"lock_wait_seconds={core['lock_wait_seconds_total']:.3f}"
    )
    print(
        "Cargo lock metrics: "
        f"samples={locks['sample_count']} "
        f"contention_rate={contention_rate if contention_rate is not None else 'n/a'}% "
        f"wait_seconds_total={locks['wait_seconds_total']:.3f} "
        f"wait_seconds_max={locks['wait_seconds_max']:.3f}"
    )
    if summary["invalid_record_count"]:
        print(f"Build metrics: WARNING invalid_record_count={summary['invalid_record_count']}")
    return 1 if strict and summary["invalid_record_count"] else 0
