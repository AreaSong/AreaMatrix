"""Docs baseline and drift checks for versioned workflow planning."""

from __future__ import annotations

import argparse
import hashlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

from .changes import (
    DraftArtifact,
    as_list,
    collect_changes,
    display_path,
    parse_yaml_subset,
    write_artifacts,
)
from .discussion import discussion_dir, load_decisions


VERSION_ROOT = Path("workflow/versions")
BASELINE_ROOT_NAME = "baseline"
BASELINE_FILE_NAME = "docs.yaml"


@dataclass(frozen=True)
class BaselineEntry:
    file: str
    line_start: int
    line_end: int
    heading: str
    excerpt: str
    sha256: str
    source: str

    @property
    def key(self) -> tuple[str, int, int]:
        return (self.file, self.line_start, self.line_end)


def quote(value: Any) -> str:
    return repr(str(value))


def baseline_root(root: Path, version: str) -> Path:
    return root / VERSION_ROOT / version / BASELINE_ROOT_NAME


def baseline_path(root: Path, version: str) -> Path:
    return baseline_root(root, version) / BASELINE_FILE_NAME


def selected_lines(path: Path, line_start: int, line_end: int) -> str:
    lines = path.read_text(encoding="utf-8").splitlines()
    if line_start < 1 or line_end < line_start or line_end > len(lines):
        return ""
    return "\n".join(lines[line_start - 1 : line_end])


def file_line_count(path: Path) -> int:
    return len(path.read_text(encoding="utf-8").splitlines()) or 1


def digest_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def int_field(value: Any) -> int | None:
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.isdigit():
        return int(value)
    return None


def build_entries_from_changes(root: Path, version: str) -> tuple[list[str], list[BaselineEntry]]:
    errors, records, _ = collect_changes(root, None, version)
    if errors:
        return errors, []
    entries: list[BaselineEntry] = []
    seen: set[tuple[str, int, int]] = set()
    for record in records:
        for index, change in enumerate(as_list(record.feature.get("doc_changes")), start=1):
            if not isinstance(change, dict):
                continue
            file_value = change.get("file")
            start = int_field(change.get("line_start"))
            end = int_field(change.get("line_end"))
            if not isinstance(file_value, str) or start is None or end is None:
                continue
            key = (file_value, start, end)
            if key in seen:
                continue
            seen.add(key)
            path = root / file_value
            if not path.is_file():
                errors.append(f"{record.file}: feature {record.feature_id} doc_changes #{index}: doc file does not exist: {file_value}")
                continue
            selected = selected_lines(path, start, end)
            if not selected:
                errors.append(f"{record.file}: feature {record.feature_id} doc_changes #{index}: line range is outside the file")
                continue
            entries.append(
                BaselineEntry(
                    file=file_value,
                    line_start=start,
                    line_end=end,
                    heading=str(change.get("heading", "")).strip(),
                    excerpt=str(change.get("excerpt", "")).strip(),
                    sha256=digest_text(selected),
                    source=f"changes:{record.feature_id}",
                )
            )
    return errors, entries


def first_non_empty_line(path: Path) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            return line.strip()
    return ""


def build_entries_from_discussion(root: Path, version: str) -> tuple[list[str], list[BaselineEntry]]:
    decisions_path = discussion_dir(root, version) / "decisions.yaml"
    errors, data = load_decisions(decisions_path)
    if errors or data is None:
        return errors, []
    entries: list[BaselineEntry] = []
    for doc in as_list(data.get("exact_docs")):
        if not isinstance(doc, str) or not doc.strip():
            errors.append(f"{display_path(root, decisions_path)}: exact_docs values must be strings")
            continue
        path = root / doc
        if not path.is_file():
            errors.append(f"{display_path(root, decisions_path)}: Exact Docs path does not exist: {doc}")
            continue
        line_end = file_line_count(path)
        selected = selected_lines(path, 1, line_end)
        entries.append(
            BaselineEntry(
                file=doc,
                line_start=1,
                line_end=line_end,
                heading="",
                excerpt=first_non_empty_line(path),
                sha256=digest_text(selected),
                source="discussion:exact_docs",
            )
        )
    return errors, entries


def build_baseline_entries(root: Path, version: str) -> tuple[list[str], list[BaselineEntry]]:
    errors, entries = build_entries_from_changes(root, version)
    if entries or not any(error.startswith(f"no {version} change files") for error in errors):
        return errors, entries
    discussion_errors, discussion_entries = build_entries_from_discussion(root, version)
    return discussion_errors, discussion_entries


def baseline_content(version: str, entries: Sequence[BaselineEntry]) -> str:
    lines = [
        f"version: {version}",
        "status: ready",
        "docs:",
    ]
    for entry in entries:
        lines.extend(
            [
                f"  - file: {quote(entry.file)}",
                f"    line_start: {entry.line_start}",
                f"    line_end: {entry.line_end}",
                f"    heading: {quote(entry.heading)}",
                f"    excerpt: {quote(entry.excerpt)}",
                f"    sha256: {quote(entry.sha256)}",
                f"    source: {quote(entry.source)}",
            ]
        )
    return "\n".join(lines).rstrip() + "\n"


def baseline_artifact(root: Path, version: str) -> tuple[list[str], DraftArtifact | None, list[BaselineEntry]]:
    errors, entries = build_baseline_entries(root, version)
    if errors:
        return errors, None, entries
    if not entries:
        return [f"{VERSION_ROOT / version}: no docs available for baseline"], None, entries
    artifact = DraftArtifact(baseline_path(root, version), baseline_content(version, entries))
    return [], artifact, entries


def load_baseline(path: Path) -> tuple[list[str], dict[str, Any] | None]:
    try:
        data = parse_yaml_subset(path.read_text(encoding="utf-8"), path)
    except ValueError as exc:
        return [str(exc)], None
    if not isinstance(data, dict):
        return [f"{path}: top-level YAML must be a mapping"], None
    return [], data


def baseline_entries_from_data(root: Path, version: str, data: dict[str, Any], path: Path) -> tuple[list[str], list[BaselineEntry]]:
    errors: list[str] = []
    entries: list[BaselineEntry] = []
    prefix = display_path(root, path)
    if data.get("version") != version:
        errors.append(f"{prefix}: version must be {version}")
    if data.get("status") not in {"ready", "blocked"}:
        errors.append(f"{prefix}: status must be ready or blocked")
    docs = data.get("docs")
    if not isinstance(docs, list) or not docs:
        errors.append(f"{prefix}: docs must be a non-empty list")
        return errors, entries
    for index, item in enumerate(docs, start=1):
        item_prefix = f"{prefix}: docs #{index}"
        if not isinstance(item, dict):
            errors.append(f"{item_prefix}: must be a mapping")
            continue
        file_value = item.get("file")
        start = int_field(item.get("line_start"))
        end = int_field(item.get("line_end"))
        sha = str(item.get("sha256", "")).strip()
        for key in ["file", "line_start", "line_end", "sha256", "source"]:
            if key not in item:
                errors.append(f"{item_prefix}: missing field: {key}")
        if not isinstance(file_value, str) or not file_value.strip():
            errors.append(f"{item_prefix}: file must be a non-empty string")
            continue
        if start is None or end is None:
            errors.append(f"{item_prefix}: line_start and line_end must be integers")
            continue
        entries.append(
            BaselineEntry(
                file=file_value,
                line_start=start,
                line_end=end,
                heading=str(item.get("heading", "")).strip(),
                excerpt=str(item.get("excerpt", "")).strip(),
                sha256=sha,
                source=str(item.get("source", "")).strip(),
            )
        )
    return errors, entries


def validate_entry_drift(root: Path, entry: BaselineEntry, prefix: str) -> list[str]:
    errors: list[str] = []
    path = root / entry.file
    if not path.is_file():
        return [f"{prefix}: doc file does not exist: {entry.file}"]
    selected = selected_lines(path, entry.line_start, entry.line_end)
    if not selected:
        return [f"{prefix}: line range is outside the file: {entry.file}:{entry.line_start}-{entry.line_end}"]
    if digest_text(selected) != entry.sha256:
        errors.append(f"{prefix}: docs drift detected for {entry.file}:{entry.line_start}-{entry.line_end}")
    if entry.heading and entry.heading not in selected:
        errors.append(f"{prefix}: heading not found in selected range: {entry.heading}")
    if entry.excerpt and entry.excerpt not in selected:
        errors.append(f"{prefix}: excerpt not found in selected range: {entry.excerpt}")
    if not entry.source:
        errors.append(f"{prefix}: source must be a non-empty string")
    return errors


def change_doc_keys(root: Path, version: str) -> tuple[list[str], set[tuple[str, int, int]]]:
    errors, records, _ = collect_changes(root, None, version)
    if errors:
        if any(error.startswith(f"no {version} change files") for error in errors):
            return [], set()
        return errors, set()
    keys: set[tuple[str, int, int]] = set()
    for record in records:
        for change in as_list(record.feature.get("doc_changes")):
            if not isinstance(change, dict):
                continue
            file_value = change.get("file")
            start = int_field(change.get("line_start"))
            end = int_field(change.get("line_end"))
            if isinstance(file_value, str) and start is not None and end is not None:
                keys.add((file_value, start, end))
    return [], keys


def validate_baseline(root: Path, version: str, require_file: bool = True) -> tuple[list[str], list[BaselineEntry]]:
    path = baseline_path(root, version)
    if not path.is_file():
        if require_file:
            return [f"missing workflow baseline: {display_path(root, path)}"], []
        return [], []
    errors, data = load_baseline(path)
    if errors or data is None:
        return errors, []
    shape_errors, entries = baseline_entries_from_data(root, version, data, path)
    errors.extend(shape_errors)
    seen: set[tuple[str, int, int]] = set()
    for index, entry in enumerate(entries, start=1):
        if entry.key in seen:
            errors.append(f"{display_path(root, path)}: duplicate docs baseline key: {entry.file}:{entry.line_start}-{entry.line_end}")
        seen.add(entry.key)
        errors.extend(validate_entry_drift(root, entry, f"{display_path(root, path)}: docs #{index}"))
    key_errors, expected_keys = change_doc_keys(root, version)
    errors.extend(key_errors)
    missing = sorted(expected_keys - seen)
    for file_value, start, end in missing:
        errors.append(f"{display_path(root, path)}: missing baseline for change doc ref {file_value}:{start}-{end}")
    return errors, entries


def version_has_change_files(root: Path, version: str) -> bool:
    change_dir = root / VERSION_ROOT / version / "changes"
    return change_dir.is_dir() and any(change_dir.glob("*.yaml"))


def validate_required_baselines(root: Path, versions: Sequence[Any]) -> list[str]:
    errors: list[str] = []
    for record in versions:
        version = str(record.version_id)
        if version == "v1-mvp":
            continue
        if version_has_change_files(root, version) or baseline_path(root, version).is_file():
            baseline_errors, _ = validate_baseline(root, version, require_file=True)
            errors.extend(baseline_errors)
    return errors


def print_artifact(root: Path, artifact: DraftArtifact, entries: Sequence[BaselineEntry]) -> None:
    print("Workflow docs baseline")
    print("- mode: preview only; no files written")
    print("- live queue: not modified")
    print(f"- docs: {len(entries)}")
    print()
    print(f"--- {display_path(root, artifact.path)} ---")
    print(artifact.content.rstrip())


def run_workflow_baseline(root: Path, args: argparse.Namespace) -> int:
    command = args.baseline_command
    if command == "doctor":
        errors, entries = validate_baseline(root, args.version, require_file=True)
        if errors:
            print("workflow baseline doctor: FAILED")
            for error in errors:
                print(f"- {error}")
            return 1
        print("workflow baseline doctor: OK")
        print(f"- version: {args.version}")
        print(f"- docs: {len(entries)}")
        print(f"- baseline: {display_path(root, baseline_path(root, args.version))}")
        return 0
    errors, artifact, entries = baseline_artifact(root, args.version)
    if errors or artifact is None:
        print(f"workflow baseline {command}: FAILED")
        for error in errors:
            print(f"- {error}")
        return 1
    if command == "preview":
        print_artifact(root, artifact, entries)
        return 0
    if command == "write":
        try:
            written = write_artifacts([artifact], force=args.force, label="workflow baseline file")
        except FileExistsError as exc:
            print(f"workflow baseline write: {exc}")
            return 1
        print("workflow baseline write: wrote files")
        for path in written:
            print(f"  - {path}")
        return 0
    print(f"workflow baseline: unsupported command {command}")
    return 2
