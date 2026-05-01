from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
import re

from .paths import (
    BATCH_RE,
    HIGH_RISK_PATH_PATTERNS,
    LABEL_RE,
    MANIFEST_HEADING_RE,
    MANIFEST_ROOT,
    PHASE_RE,
    PROGRESS_PATH,
    PROMPTS_ROOT,
    ROOT,
    SKILL_DISCOVERY_ROOT,
    SKILL_SOURCE_ROOT,
    TASK_RE,
    ManifestEntry,
    TaskFile,
)


def strip_bullet(line: str) -> str | None:
    stripped = line.strip()
    if not stripped.startswith("- "):
        return None
    value = stripped[2:].strip()
    if value.startswith("`") and value.endswith("`"):
        value = value[1:-1].strip()
    return None if value == "None" else value


def task_title(path: Path) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return path.stem


def scan_task_files() -> dict[str, TaskFile]:
    tasks: dict[str, TaskFile] = {}
    for phase_dir in sorted(PROMPTS_ROOT.glob("phase-*")):
        if phase_dir.is_dir():
            scan_phase_tasks(phase_dir, tasks)
    return tasks


def scan_phase_tasks(phase_dir: Path, tasks: dict[str, TaskFile]) -> None:
    phase_match = PHASE_RE.match(phase_dir.name)
    if not phase_match:
        return
    for task_path in sorted(phase_dir.glob("*/*.md")):
        task = task_from_path(phase_dir, int(phase_match.group(1)), task_path)
        if not task:
            continue
        if task.label in tasks:
            raise ValueError(f"duplicate task label: {task.label}")
        tasks[task.label] = task


def task_from_path(phase_dir: Path, phase_number: int, task_path: Path) -> TaskFile | None:
    task_match = TASK_RE.match(task_path.name)
    batch_match = BATCH_RE.match(task_path.parent.name)
    if not task_match or not batch_match:
        return None
    batch = batch_match.group(1)
    label = f"{batch}/task-{task_match.group(1)}"
    return TaskFile(label, phase_dir.name, phase_number, batch, task_path, task_title(task_path))


def parse_depends(line: str) -> list[str]:
    if "None" in line:
        return []
    return re.findall(r"`([^`]+)`", line)


def parse_manifest(path: Path) -> dict[str, ManifestEntry]:
    text = path.read_text(encoding="utf-8")
    headings = list(MANIFEST_HEADING_RE.finditer(text))
    entries: dict[str, ManifestEntry] = {}
    for index, heading in enumerate(headings):
        entry = parse_manifest_entry(path, text, headings, index, heading)
        entries[entry.label] = entry
    return entries


def parse_manifest_entry(
    path: Path,
    text: str,
    headings: list[re.Match[str]],
    index: int,
    heading: re.Match[str],
) -> ManifestEntry:
    end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
    raw = text[heading.start() : end].rstrip()
    entry = ManifestEntry(heading.group(1).strip(), path, raw=raw)
    parse_manifest_entry_lines(entry, raw.splitlines()[1:])
    return entry


def parse_manifest_entry_lines(entry: ManifestEntry, lines: list[str]) -> None:
    section = ""
    for line in lines:
        if line.startswith("> source task:"):
            values = re.findall(r"`([^`]+)`", line)
            entry.source_task = values[0] if values else ""
            continue
        if line.startswith("> depends:"):
            entry.depends = parse_depends(line)
            continue
        if line.startswith("### "):
            section = line[4:].strip()
            entry.sections.setdefault(section, [])
            continue
        value = strip_bullet(line)
        if value and section:
            entry.sections.setdefault(section, []).append(value)


def load_manifests() -> dict[str, ManifestEntry]:
    entries: dict[str, ManifestEntry] = {}
    for path in sorted(MANIFEST_ROOT.glob("phase-*.md")):
        merge_manifest(entries, parse_manifest(path))
    return entries


def merge_manifest(
    entries: dict[str, ManifestEntry],
    new_entries: dict[str, ManifestEntry],
) -> None:
    for label, entry in new_entries.items():
        if label in entries:
            raise ValueError(f"duplicate manifest label: {label}")
        entries[label] = entry


def is_allowed_new_path(value: str) -> bool:
    from .paths import ALLOWED_NEW_ROOTS

    normalized = value.rstrip("*")
    return any(normalized == root.rstrip("/") or normalized.startswith(root) for root in ALLOWED_NEW_ROOTS)


def looks_high_risk(entry: ManifestEntry) -> bool:
    haystack = " ".join(
        [entry.source_task, *entry.exact_docs, *entry.existing_code, *entry.expected_new_paths]
    ).lower()
    return any(pattern in haystack for pattern in HIGH_RISK_PATH_PATTERNS)


def ordered_labels(tasks: dict[str, TaskFile], manifests: dict[str, ManifestEntry]) -> list[str]:
    result: list[str] = []
    temporary: set[str] = set()
    permanent: set[str] = set()
    for label in sorted(tasks, key=lambda value: label_sort_tuple(value)):
        visit_label(label, tasks, manifests, result, temporary, permanent)
    return result


def label_sort_tuple(label: str) -> tuple[int, int, int]:
    match = LABEL_RE.match(label)
    if not match:
        return (999, 999, 999)
    first, second = match.group(1).split("-")
    return (int(first), int(second), int(match.group(2)))


def visit_label(
    label: str,
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
    result: list[str],
    temporary: set[str],
    permanent: set[str],
) -> None:
    if label in permanent or label not in tasks:
        return
    if label in temporary:
        raise ValueError(f"dependency cycle at {label}")
    temporary.add(label)
    for dep in manifests[label].depends:
        visit_label(dep, tasks, manifests, result, temporary, permanent)
    temporary.remove(label)
    permanent.add(label)
    result.append(label)


def filter_labels(labels: list[str], tasks: dict[str, TaskFile], phase: str | None) -> list[str]:
    if not phase:
        return labels
    normalized = phase if phase.startswith("phase-") else f"phase-{phase}"
    return [label for label in labels if tasks[label].phase == normalized]


def load_progress() -> dict[str, object]:
    if not PROGRESS_PATH.exists():
        return {"version": 1, "tasks": {}}
    return json.loads(PROGRESS_PATH.read_text(encoding="utf-8"))


def save_progress(progress: dict[str, object]) -> None:
    text = json.dumps(progress, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    PROGRESS_PATH.write_text(text, encoding="utf-8")


def task_status(progress: dict[str, object], label: str) -> str:
    tasks = progress.get("tasks", {})
    if not isinstance(tasks, dict):
        return "pending"
    value = tasks.get(label)
    if not isinstance(value, dict):
        return "pending"
    status = value.get("status")
    return status if isinstance(status, str) else "pending"


def ready_for_next(label: str, manifests: dict[str, ManifestEntry], progress: dict[str, object]) -> bool:
    return all(task_status(progress, dep) == "completed" for dep in manifests[label].depends)


def mark_progress(task_map: dict[object, object], task: str, status: str, note: str) -> None:
    task_map[task] = {
        "status": status,
        "note": note,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }


def markdown_section(text: str, heading: str) -> str:
    pattern = re.compile(rf"^##\s+{re.escape(heading)}\s*$", re.M)
    match = pattern.search(text)
    if not match:
        return "未在 task 文件中找到该章节；验收时必须回到 task 正文自行定位。"
    next_match = re.search(r"^##\s+", text[match.end() :], re.M)
    end = match.end() + next_match.start() if next_match else len(text)
    return text[match.end() : end].strip() or "该章节为空。"


def skill_file(name: str) -> Path:
    return SKILL_SOURCE_ROOT / name / "SKILL.md"


def discovery_skill_file(name: str) -> Path:
    return SKILL_DISCOVERY_ROOT / name / "SKILL.md"
