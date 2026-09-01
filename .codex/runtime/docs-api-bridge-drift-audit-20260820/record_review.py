#!/usr/bin/env python3
"""Record hash-bound manual review decisions without touching repository sources."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from datetime import datetime
from pathlib import Path


AUDIT_DIR = Path(__file__).resolve().parent
ROOT = AUDIT_DIR.parents[2]
DECISIONS = AUDIT_DIR / "review-decisions.jsonl"


def sha256(path: Path) -> str:
    if path.is_symlink():
        return hashlib.sha256(os.fsencode(os.readlink(path))).hexdigest()
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def line_count(path: Path) -> int | None:
    data = path.read_bytes()
    if b"\0" in data:
        return None
    try:
        data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return None
    return data.count(b"\n") + (1 if data and not data.endswith(b"\n") else 0)


def load() -> dict[str, dict[str, object]]:
    if not DECISIONS.exists():
        return {}
    rows = [json.loads(line) for line in DECISIONS.read_text(encoding="utf-8").splitlines() if line.strip()]
    return {str(row["path"]): row for row in rows}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+")
    parser.add_argument("--status", required=True)
    parser.add_argument("--auditor", default="root")
    parser.add_argument("--auditor-role", default="primary_manual_auditor")
    parser.add_argument("--reviewer", default="root")
    parser.add_argument("--reviewer-role", default="audit_owner_recheck")
    parser.add_argument("--started-at")
    parser.add_argument("--completed-at")
    parser.add_argument("--evidence", action="append", required=True)
    parser.add_argument("--notes", required=True)
    args = parser.parse_args()

    decisions = load()
    now = datetime.now().astimezone().isoformat(timespec="seconds")
    started_at = args.started_at or now
    completed_at = args.completed_at or now
    for relative in args.paths:
        absolute = ROOT / relative
        if not absolute.exists() and not absolute.is_symlink():
            raise FileNotFoundError(relative)
        lines = line_count(absolute)
        decisions[relative] = {
            "path": relative,
            "status": args.status,
            "auditor": args.auditor,
            "auditor_role": args.auditor_role,
            "reviewer": args.reviewer,
            "reviewer_role": args.reviewer_role,
            "started_at": started_at,
            "completed_at": completed_at,
            "reviewed_sha256": sha256(absolute),
            "reviewed_line_ranges": [[1, lines]] if lines else [],
            "evidence": args.evidence,
            "notes": args.notes,
        }

    DECISIONS.write_text(
        "".join(json.dumps(decisions[path], ensure_ascii=False, sort_keys=True) + "\n" for path in sorted(decisions)),
        encoding="utf-8",
    )
    print(json.dumps({"recorded": len(args.paths), "decision_total": len(decisions)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
