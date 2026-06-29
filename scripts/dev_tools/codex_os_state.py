"""Read-only Codex state loading and thread health classification."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import sqlite3
from typing import Any

from .common import ToolError


RUNTIME_ROOT = Path(".codex/runtime/codex-os")
REGISTRY_NAME = "task-registry.json"
THREAD_HEALTH_NAME = "thread-health.json"
DASHBOARD_NAME = "dashboard.md"
HEALTH_REPORT_NAME = "health-report.md"

LANES = {"Quick", "Change", "Mission-Critical", "Explore", "Review", "Ops"}
TASK_STATUSES = {
    "Backlog",
    "Ready",
    "Running",
    "Waiting Confirmation",
    "Blocked",
    "Verifying",
    "Done",
    "Archived",
    "Abandoned",
}
BUCKETS = ("Active", "Warm", "Cold", "Archive Candidate", "Risk Review", "Archived")

ARCHIVE_TITLE_PATTERNS = (
    "",
    "你好",
    "ni",
    "referenced pasted text files",
    "/goal referenced pasted text files",
    "copy-ready prompt",
    "verify-ready prompt",
    "回应问候",
)
PROMPT_HISTORY_PATTERNS = (
    "copy-ready prompt",
    "verify-ready prompt",
)
RISK_TITLE_PATTERNS = (
    "mission-critical",
    "auth",
    "authorization",
    "permission",
    "migration",
    "rollback",
    "reindex",
    "staging",
    "delete",
    "secret",
    "key lifecycle",
    "用户文件",
    "权限",
    "密钥",
    "迁移",
    "删除",
    "回滚",
    "接管",
)
FINAL_JOB_STATUSES = {"completed", "complete", "done", "failed", "cancelled", "canceled"}


@dataclass(frozen=True)
class ThreadRecord:
    id: str
    title: str
    cwd: str
    created_at: int
    updated_at: int
    archived: bool
    preview: str
    has_open_edge: bool
    has_active_job: bool

    @property
    def updated_iso(self) -> str:
        return format_timestamp(self.updated_at)

    @property
    def display_title(self) -> str:
        title = " ".join(self.title.split())
        return title[:120] if title else "(empty title)"


@dataclass(frozen=True)
class ThreadHealth:
    thread: ThreadRecord
    bucket: str
    age_days: int
    reason: str


def default_state_db() -> Path:
    return Path.home() / ".codex" / "state_5.sqlite"


def default_runtime_dir(root: Path) -> Path:
    return root / RUNTIME_ROOT


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def format_timestamp(value: int) -> str:
    if value <= 0:
        return "unknown"
    return datetime.fromtimestamp(value, timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")


def iso_now() -> str:
    return utc_now().strftime("%Y-%m-%dT%H:%M:%SZ")


def _normalize(text: str) -> str:
    return " ".join(text.lower().split())


def _connect_state_db(path: Path) -> sqlite3.Connection:
    if not path.is_file():
        raise ToolError(f"Codex state database not found: {path}", code=1)
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA query_only=ON")
    return conn


def _table_exists(conn: sqlite3.Connection, name: str) -> bool:
    row = conn.execute(
        "select 1 from sqlite_master where type = 'table' and name = ?",
        (name,),
    ).fetchone()
    return row is not None


def _active_job_thread_ids(conn: sqlite3.Connection) -> set[str]:
    if not _table_exists(conn, "agent_job_items"):
        return set()
    rows = conn.execute(
        "select assigned_thread_id, status from agent_job_items "
        "where assigned_thread_id is not null and assigned_thread_id <> ''",
    ).fetchall()
    return {str(row["assigned_thread_id"]) for row in rows if str(row["status"]).lower() not in FINAL_JOB_STATUSES}


def _open_edge_thread_ids(conn: sqlite3.Connection) -> set[str]:
    if not _table_exists(conn, "thread_spawn_edges"):
        return set()
    rows = conn.execute(
        "select parent_thread_id, child_thread_id from thread_spawn_edges where status = 'open'",
    ).fetchall()
    ids: set[str] = set()
    for row in rows:
        ids.add(str(row["parent_thread_id"]))
        ids.add(str(row["child_thread_id"]))
    return ids


def load_threads(state_db: Path) -> list[ThreadRecord]:
    with _connect_state_db(state_db) as conn:
        conn.execute("BEGIN")
        if not _table_exists(conn, "threads"):
            raise ToolError(f"Codex state database has no threads table: {state_db}", code=1)
        active_job_ids = _active_job_thread_ids(conn)
        open_edge_ids = _open_edge_thread_ids(conn)
        rows = conn.execute(
            "select id, title, cwd, created_at, updated_at, archived, preview "
            "from threads order by updated_at desc, id desc",
        ).fetchall()
        conn.execute("COMMIT")
    return [
        ThreadRecord(
            id=str(row["id"]),
            title=str(row["title"] or ""),
            cwd=str(row["cwd"] or ""),
            created_at=int(row["created_at"] or 0),
            updated_at=int(row["updated_at"] or 0),
            archived=bool(row["archived"]),
            preview=str(row["preview"] or ""),
            has_open_edge=str(row["id"]) in open_edge_ids,
            has_active_job=str(row["id"]) in active_job_ids,
        )
        for row in rows
    ]


def load_agent_job_counts(state_db: Path) -> dict[str, int]:
    with _connect_state_db(state_db) as conn:
        conn.execute("BEGIN")
        if not _table_exists(conn, "agent_jobs"):
            conn.execute("COMMIT")
            return {}
        rows = conn.execute("select status, count(*) as count from agent_jobs group by status").fetchall()
        conn.execute("COMMIT")
    return {str(row["status"]): int(row["count"]) for row in rows}


def classify_thread(thread: ThreadRecord, now: datetime | None = None) -> ThreadHealth:
    now = now or utc_now()
    updated = datetime.fromtimestamp(thread.updated_at, timezone.utc) if thread.updated_at > 0 else now
    age_days = max(0, (now - updated).days)
    title = _normalize(thread.title)
    archive_signal = title in ARCHIVE_TITLE_PATTERNS or any(pattern in title for pattern in ARCHIVE_TITLE_PATTERNS if pattern)
    prompt_history_signal = any(pattern in title for pattern in PROMPT_HISTORY_PATTERNS)
    risk_signal = any(pattern in title for pattern in RISK_TITLE_PATTERNS)

    if thread.archived:
        return ThreadHealth(thread, "Archived", age_days, "already archived")
    if thread.has_open_edge:
        return ThreadHealth(thread, "Active", age_days, "open subagent/thread edge")
    if thread.has_active_job:
        return ThreadHealth(thread, "Active", age_days, "active agent job item")
    if age_days <= 3:
        return ThreadHealth(thread, "Active", age_days, "updated within 3 days")
    if age_days <= 30:
        return ThreadHealth(thread, "Warm", age_days, "updated within 30 days")
    if prompt_history_signal:
        return ThreadHealth(thread, "Archive Candidate", age_days, "stale historical prompt title")
    if risk_signal:
        return ThreadHealth(thread, "Risk Review", age_days, "risk keyword in title")
    if archive_signal and age_days >= 7:
        return ThreadHealth(thread, "Archive Candidate", age_days, "stale low-signal title")
    if age_days >= 120 and archive_signal:
        return ThreadHealth(thread, "Archive Candidate", age_days, "very old low-signal title")
    return ThreadHealth(thread, "Cold", age_days, "stale but not obviously disposable")


def build_snapshot(state_db: Path, project: str | None = None) -> dict[str, Any]:
    threads = load_threads(state_db)
    health = [classify_thread(thread) for thread in threads]
    visible = [item for item in health if project is None or item.thread.cwd == project]
    counts = {bucket: 0 for bucket in BUCKETS}
    for item in visible:
        counts[item.bucket] = counts.get(item.bucket, 0) + 1
    project_counts: dict[str, dict[str, int]] = {}
    for item in health:
        cwd = item.thread.cwd or "(unknown)"
        entry = project_counts.setdefault(cwd, {"total": 0, "unarchived": 0})
        entry["total"] += 1
        if not item.thread.archived:
            entry["unarchived"] += 1
    return {
        "generated_at": iso_now(),
        "state_db": str(state_db),
        "project_filter": project,
        "total_threads": len(visible),
        "unarchived_threads": sum(1 for item in visible if not item.thread.archived),
        "bucket_counts": counts,
        "agent_job_counts": load_agent_job_counts(state_db),
        "project_counts": project_counts,
        "threads": visible,
    }


def thread_to_json(item: ThreadHealth) -> dict[str, Any]:
    thread = item.thread
    return {
        "id": thread.id,
        "title": thread.display_title,
        "cwd": thread.cwd,
        "updated_at": thread.updated_iso,
        "archived": thread.archived,
        "bucket": item.bucket,
        "age_days": item.age_days,
        "reason": item.reason,
        "has_open_edge": thread.has_open_edge,
        "has_active_job": thread.has_active_job,
    }


def snapshot_to_json(snapshot: dict[str, Any], *, limit: int = 50) -> dict[str, Any]:
    by_bucket: dict[str, list[dict[str, Any]]] = {bucket: [] for bucket in BUCKETS}
    for item in snapshot["threads"]:
        rows = by_bucket.setdefault(item.bucket, [])
        if len(rows) < limit:
            rows.append(thread_to_json(item))
    return {
        "generated_at": snapshot["generated_at"],
        "state_db": snapshot["state_db"],
        "project_filter": snapshot["project_filter"],
        "total_threads": snapshot["total_threads"],
        "unarchived_threads": snapshot["unarchived_threads"],
        "bucket_counts": snapshot["bucket_counts"],
        "agent_job_counts": snapshot["agent_job_counts"],
        "threads_by_bucket": by_bucket,
    }
