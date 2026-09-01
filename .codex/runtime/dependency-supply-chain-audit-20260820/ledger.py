#!/usr/bin/env python3
"""Resumable JSONL ledger operations for the read-only supply-chain audit."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parent
ALLOWED = {"PENDING", "IN_PROGRESS", "PASS", "FINDING", "NOT_APPLICABLE", "BLOCKED"}


def now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def read_jsonl(name: str) -> list[dict[str, object]]:
    path = ROOT / name
    if not path.exists() or not path.read_text(encoding="utf-8"):
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write_jsonl(name: str, rows: list[dict[str, object]]) -> None:
    path = ROOT / name
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )
    temporary.replace(path)


def mark(args: argparse.Namespace) -> None:
    rows = read_jsonl("coverage.jsonl")
    target_paths = set(args.path or [])
    if args.prefix:
        target_paths.update(row["path"] for row in rows if str(row["path"]).startswith(args.prefix))
    if not target_paths:
        raise SystemExit("mark requires --path or --prefix")
    missing = target_paths - {row["path"] for row in rows}
    if missing:
        raise SystemExit(f"paths not in frozen scope: {sorted(missing)}")
    if args.status not in ALLOWED:
        raise SystemExit(f"invalid status: {args.status}")
    changed = 0
    for row in rows:
        if row["path"] not in target_paths:
            continue
        row["status"] = args.status
        row["reviewer"] = args.reviewer
        if args.status == "IN_PROGRESS" and not row.get("started_at"):
            row["started_at"] = now()
        if args.status in {"PASS", "FINDING", "NOT_APPLICABLE", "BLOCKED"}:
            row["completed_at"] = now()
        if args.evidence:
            row.setdefault("evidence", []).extend(args.evidence)
        if args.notes:
            row["notes"] = args.notes
        changed += 1
    write_jsonl("coverage.jsonl", rows)
    print(json.dumps({"changed": changed, "status": args.status}, ensure_ascii=False))


def append_record(name: str, record: dict[str, object]) -> None:
    rows = read_jsonl(name)
    rows.append(record)
    write_jsonl(name, rows)


def append_json(args: argparse.Namespace) -> None:
    try:
        record = json.loads(args.record)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid JSON: {exc}") from exc
    if not isinstance(record, dict):
        raise SystemExit("record must be an object")
    record.setdefault("recorded_at", now())
    append_record(args.file, record)


def stats(_: argparse.Namespace) -> None:
    rows = read_jsonl("coverage.jsonl")
    counts: dict[str, int] = {}
    for row in rows:
        status = str(row.get("status"))
        counts[status] = counts.get(status, 0) + 1
    print(json.dumps({"total": len(rows), "counts": counts}, ensure_ascii=False, sort_keys=True))


def validate(_: argparse.Namespace) -> None:
    rows = read_jsonl("coverage.jsonl")
    paths = [str(row.get("path")) for row in rows]
    bad_status = [row for row in rows if row.get("status") not in ALLOWED]
    duplicate_paths = sorted({path for path in paths if paths.count(path) > 1})
    pending = [row["path"] for row in rows if row.get("status") in {"PENDING", "IN_PROGRESS"}]
    result = {
        "total": len(rows),
        "unique_paths": len(set(paths)),
        "duplicate_paths": duplicate_paths,
        "bad_status_count": len(bad_status),
        "pending_or_in_progress_count": len(pending),
        "counts": {status: sum(row.get("status") == status for row in rows) for status in sorted(ALLOWED)},
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    if duplicate_paths or bad_status or len(paths) != len(set(paths)):
        raise SystemExit(2)


parser = argparse.ArgumentParser()
subparsers = parser.add_subparsers(dest="command", required=True)

mark_parser = subparsers.add_parser("mark")
mark_parser.add_argument("--status", required=True)
mark_parser.add_argument("--path", action="append")
mark_parser.add_argument("--prefix")
mark_parser.add_argument("--reviewer", default="primary")
mark_parser.add_argument("--evidence", action="append")
mark_parser.add_argument("--notes")
mark_parser.set_defaults(function=mark)

append_parser = subparsers.add_parser("append")
append_parser.add_argument("--file", choices=["dependency-ledger.jsonl", "license-ledger.jsonl", "findings.jsonl"], required=True)
append_parser.add_argument("--record", required=True)
append_parser.set_defaults(function=append_json)

stats_parser = subparsers.add_parser("stats")
stats_parser.set_defaults(function=stats)

validate_parser = subparsers.add_parser("validate")
validate_parser.set_defaults(function=validate)

args = parser.parse_args()
args.function(args)
