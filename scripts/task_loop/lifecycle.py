"""Read-only lifecycle snapshot for the AreaMatrix dev console."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any


VERSION_ROOT = Path("workflow/versions")
LIFECYCLE_STAGES = ("discussion", "changes", "plans", "drafts", "queue", "promotion", "live", "archive")


@dataclass(frozen=True)
class VersionLifecycle:
    version_id: str
    title: str
    status: str
    depends_on: tuple[str, ...]
    gate: str
    promotion: str
    discussion: str
    local_queue: str
    live_mapping: str
    live_queue: str
    changes_count: int
    plans_count: int
    drafts_count: int
    queue_count: int
    promotion_count: int
    stage_statuses: dict[str, str]


@dataclass(frozen=True)
class LifecycleSnapshot:
    versions: tuple[VersionLifecycle, ...]
    active_version: str
    live_version: str
    planning_versions: int
    promotion_blockers: tuple[str, ...]


def _read_yaml(path: Path) -> dict[str, Any]:
    try:
        import yaml

        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception:
        return _read_simple_yaml(path)
    return data if isinstance(data, dict) else {}


def _scalar(value: str) -> Any:
    value = value.strip()
    if value in {'""', "''"}:
        return ""
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    if value == "true":
        return True
    if value == "false":
        return False
    if value == "[]":
        return []
    try:
        return int(value)
    except ValueError:
        return value


def _read_simple_yaml(path: Path) -> dict[str, Any]:
    result: dict[str, Any] = {}
    current_key = ""
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue
        indent = len(raw_line) - len(raw_line.lstrip(" "))
        line = raw_line.strip()
        if indent == 0:
            key, sep, value = line.partition(":")
            if not sep:
                continue
            key = key.strip()
            value = value.strip()
            if value:
                result[key] = _scalar(value)
                current_key = ""
            else:
                result[key] = {}
                current_key = key
            continue
        if indent == 2 and current_key:
            if line.startswith("- "):
                items = result.setdefault(current_key, [])
                if isinstance(items, list):
                    items.append(_scalar(line[2:]))
                continue
            key, sep, value = line.partition(":")
            if sep:
                current = result.setdefault(current_key, {})
                if isinstance(current, dict):
                    current[key.strip()] = _scalar(value)
    return result


def _count_files(path: Path, suffixes: tuple[str, ...]) -> int:
    if not path.exists():
        return 0
    return sum(1 for item in path.rglob("*") if item.is_file() and item.suffix in suffixes and item.name != "README.md")


def _as_tuple(value: Any) -> tuple[str, ...]:
    if isinstance(value, list):
        return tuple(str(item) for item in value)
    if isinstance(value, str) and value:
        return (value,)
    return ()


def _discussion_status(data: dict[str, Any]) -> str:
    discussion = data.get("discussion")
    if not isinstance(discussion, dict):
        return "missing"
    if discussion.get("required") is False:
        return str(discussion.get("status") or "skipped")
    return str(discussion.get("status") or "required")


def _local_queue_label(data: dict[str, Any]) -> str:
    queue = data.get("local_queue")
    if not isinstance(queue, dict):
        return "already-live" if data.get("promotion") == "already-live" else "missing"
    return f"{queue.get('phase', 'unknown')}/{queue.get('batch', 'unknown')}/task-{int(queue.get('start_task') or 1):02d}"


def _live_mapping_label(data: dict[str, Any]) -> str:
    if data.get("promotion") == "already-live":
        return "already-live"
    config = data.get("promotion_preview")
    if not isinstance(config, dict):
        return "missing"
    if config.get("live_mapping") == "pending":
        return "pending"
    return f"configured ({config.get('phase', 'unknown')}/{config.get('batch', 'unknown')})"


def _stage_statuses(data: dict[str, Any], version_dir: Path, counts: dict[str, int]) -> dict[str, str]:
    status = str(data.get("status") or "unknown")
    promotion = str(data.get("promotion") or "missing")
    live_queue = str(data.get("live_queue") or "")
    archive_policy = str(data.get("archive_policy") or "missing")
    return {
        "discussion": _discussion_status(data),
        "changes": "ready" if counts["changes"] else "empty",
        "plans": "ready" if counts["plans"] else "empty",
        "drafts": "ready" if counts["drafts"] else "empty",
        "queue": "ready" if counts["queue"] else "empty",
        "promotion": promotion,
        "live": "live-running" if live_queue else status,
        "archive": archive_policy,
    }


def _sort_version_key(version: str) -> tuple[int, str]:
    if version == "v1-mvp":
        return (1, version)
    if version.startswith("v") and version[1:].isdigit():
        return (int(version[1:]), version)
    return (9999, version)


def load_lifecycle_snapshot(root: Path) -> LifecycleSnapshot:
    version_root = root / VERSION_ROOT
    versions: list[VersionLifecycle] = []
    for version_file in sorted(version_root.glob("*/version.yaml"), key=lambda path: _sort_version_key(path.parent.name)):
        data = _read_yaml(version_file)
        version_dir = version_file.parent
        counts = {
            "changes": _count_files(version_dir / "changes", (".yaml", ".yml")),
            "plans": _count_files(version_dir / "plans", (".md",)),
            "drafts": _count_files(version_dir / "drafts", (".md", ".yaml", ".yml")),
            "queue": _count_files(version_dir / "queue", (".md", ".yaml", ".yml")),
            "promotion": _count_files(version_dir / "promotion", (".md", ".yaml", ".yml")),
        }
        version_id = str(data.get("id") or version_dir.name)
        versions.append(
            VersionLifecycle(
                version_id=version_id,
                title=str(data.get("title") or version_id),
                status=str(data.get("status") or "unknown"),
                depends_on=_as_tuple(data.get("depends_on")),
                gate=str(data.get("gate") or "none"),
                promotion=str(data.get("promotion") or "missing"),
                discussion=_discussion_status(data),
                local_queue=_local_queue_label(data),
                live_mapping=_live_mapping_label(data),
                live_queue=str(data.get("live_queue") or ""),
                changes_count=counts["changes"],
                plans_count=counts["plans"],
                drafts_count=counts["drafts"],
                queue_count=counts["queue"],
                promotion_count=counts["promotion"],
                stage_statuses=_stage_statuses(data, version_dir, counts),
            )
        )
    live = next((item.version_id for item in versions if item.status == "live-running"), "none")
    active = next((item.version_id for item in versions if item.status == "planning"), live)
    blockers = tuple(
        f"{item.version_id}: {item.gate}" for item in versions if item.gate == "queue-only-until-v1-complete" and live == "v1-mvp"
    )
    return LifecycleSnapshot(
        versions=tuple(versions),
        active_version=active,
        live_version=live,
        planning_versions=sum(1 for item in versions if item.status == "planning"),
        promotion_blockers=blockers,
    )


def validate_lifecycle_snapshot(root: Path) -> list[str]:
    errors: list[str] = []
    snapshot = load_lifecycle_snapshot(root)
    if not snapshot.versions:
        errors.append("lifecycle: no workflow versions found")
        return errors
    ids = {item.version_id for item in snapshot.versions}
    if "v1-mvp" not in ids:
        errors.append("lifecycle: missing v1-mvp")
    if "v2" not in ids:
        errors.append("lifecycle: missing v2")
    v1 = next((item for item in snapshot.versions if item.version_id == "v1-mvp"), None)
    if v1 and v1.status != "live-running":
        errors.append("lifecycle: v1-mvp must be live-running")
    v2 = next((item for item in snapshot.versions if item.version_id == "v2"), None)
    if v2:
        if v2.status != "planning":
            errors.append("lifecycle: v2 must be planning")
        if v2.live_mapping == "missing":
            errors.append("lifecycle: v2 live mapping missing")
    if not snapshot.promotion_blockers:
        errors.append("lifecycle: expected v1 live promotion blocker")
    return errors
