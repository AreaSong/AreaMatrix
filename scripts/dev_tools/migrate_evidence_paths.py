"""Rewrite tracked task-loop evidence JSON to repo-relative paths."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def path_for_git(root: Path, path: Path) -> str | None:
    candidate = path if path.is_absolute() else (root / path)
    try:
        return str(candidate.resolve().relative_to(root.resolve()))
    except ValueError:
        return None

PATH_KEYS = {
    "copy_log",
    "verify_log",
    "summary_file",
    "root_dir",
    "progress_file",
    "log_root",
    "copy_root",
    "verify_root",
    "codex_bin",
}


def sanitize_codex_bin(root: Path, value: str) -> str:
    if not value:
        return value
    path = Path(value)
    if path.is_absolute():
        if str(path).startswith("/Applications/") or "Codex.app" in str(path):
            return path.name or "codex"
        rel = path_for_git(root, path)
        if rel:
            return rel
    return value


def sanitize_value(root: Path, key: str, value: object) -> object:
    if not isinstance(value, str):
        return value
    if key == "codex_bin":
        return sanitize_codex_bin(root, value)
    if key in PATH_KEYS or (value.startswith(str(root)) or "/Users/" in value):
        if value.startswith(str(root)):
            path = Path(value)
        elif value.startswith("/"):
            path = Path(value)
            rel = path_for_git(root, path)
            return rel or value
        else:
            return value
        rel = path_for_git(root, path)
        return rel or value
    return value


def walk_json(root: Path, data: object) -> tuple[object, int]:
    changed = 0
    if isinstance(data, dict):
        out: dict[str, object] = {}
        for key, value in data.items():
            if isinstance(value, (dict, list)):
                sanitized, sub = walk_json(root, value)
                changed += sub
                out[key] = sanitized
            else:
                new_value = sanitize_value(root, key, value)
                if new_value != value:
                    changed += 1
                out[key] = new_value
        return out, changed
    if isinstance(data, list):
        out_list: list[object] = []
        for item in data:
            sanitized, sub = walk_json(root, item)
            changed += sub
            out_list.append(sanitized)
        return out_list, changed
    return data, 0


def migrate_file(root: Path, path: Path) -> int:
    data = json.loads(path.read_text(encoding="utf-8"))
    sanitized, changed = walk_json(root, data)
    if changed:
        path.write_text(json.dumps(sanitized, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return changed


def targets(root: Path) -> list[Path]:
    files = [root / "tasks/prompts/_shared/progress.json", root / ".codex/task-loop-runs/index.json"]
    files += sorted((root / ".codex/task-loop-runs").glob("*/summary.json"))
    return [path for path in files if path.is_file()]


def main() -> int:
    root = ROOT.resolve()
    total = 0
    for path in targets(root):
        count = migrate_file(root, path)
        if count:
            print(f"migrated {path.relative_to(root)} ({count} field(s))")
            total += count
    if total == 0:
        print("no path fields needed migration")
    else:
        print(f"done: {total} field(s) rewritten")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

