"""Markdown renderers for Codex Operating System reports."""

from __future__ import annotations

from typing import Any

from .codex_os_state import BUCKETS


def _top_projects(snapshot: dict[str, Any], limit: int = 10) -> list[tuple[str, int, int]]:
    rows = [
        (cwd, data["total"], data["unarchived"])
        for cwd, data in snapshot["project_counts"].items()
    ]
    return sorted(rows, key=lambda row: (row[2], row[1]), reverse=True)[:limit]


def render_thread_health(snapshot: dict[str, Any], *, limit: int = 20) -> str:
    lines = ["Codex thread health", ""]
    lines.append(f"- generated_at: {snapshot['generated_at']}")
    lines.append(f"- state_db: {snapshot['state_db']}")
    lines.append(f"- project_filter: {snapshot['project_filter'] or '(all projects)'}")
    lines.append(f"- total_threads: {snapshot['total_threads']}")
    lines.append(f"- unarchived_threads: {snapshot['unarchived_threads']}")
    lines.append("")
    for bucket in BUCKETS:
        lines.append(f"{bucket}: {snapshot['bucket_counts'].get(bucket, 0)}")
        shown = 0
        for item in snapshot["threads"]:
            if item.bucket != bucket or shown >= limit:
                continue
            lines.append(f"- {item.thread.updated_iso} | {item.age_days}d | {item.reason} | {item.thread.display_title}")
            shown += 1
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def render_dashboard(snapshot: dict[str, Any], registry: dict[str, Any] | None = None) -> str:
    lines = ["# Codex OS Dashboard", ""]
    lines.append(f"- Generated: {snapshot['generated_at']}")
    lines.append(f"- State DB: `{snapshot['state_db']}`")
    lines.append(f"- Project filter: `{snapshot['project_filter'] or 'all'}`")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append(f"- Total threads in scope: {snapshot['total_threads']}")
    lines.append(f"- Unarchived threads in scope: {snapshot['unarchived_threads']}")
    for bucket in BUCKETS:
        lines.append(f"- {bucket}: {snapshot['bucket_counts'].get(bucket, 0)}")
    lines.append("")
    lines.append("## Top Projects")
    lines.append("")
    lines.append("| Project | Total | Unarchived |")
    lines.append("|---|---:|---:|")
    for cwd, total, unarchived in _top_projects(snapshot):
        lines.append(f"| `{cwd}` | {total} | {unarchived} |")
    lines.append("")
    lines.append("## Task Registry")
    lines.append("")
    tasks = registry.get("tasks", []) if registry else []
    lines.append(f"- Registered tasks: {len(tasks)}")
    if tasks:
        lines.append("")
        lines.append("| Task | Lane | Status | Next Action |")
        lines.append("|---|---|---|---|")
        for task in tasks[:20]:
            lines.append(
                f"| `{task.get('task_id', '')}` | {task.get('lane', '')} | "
                f"{task.get('status', '')} | {task.get('next_action', '')} |"
            )
    lines.append("")
    lines.append("## Recommended Next Actions")
    lines.append("")
    lines.append("1. Review Active and Risk Review threads before archiving anything.")
    lines.append("2. Use `./dev codex-os thread-health --limit 50` to inspect candidates.")
    lines.append("3. Keep task state in the registry or a handoff file, not only in chat history.")
    lines.append("4. Archive only after closeout evidence exists or the thread is clearly disposable.")
    return "\n".join(lines).rstrip() + "\n"


def render_health_report(snapshot: dict[str, Any], registry: dict[str, Any] | None = None) -> str:
    warnings: list[str] = []
    if snapshot["unarchived_threads"] > 100:
        warnings.append("unarchived thread count is high; use Archive Candidate review.")
    if snapshot["bucket_counts"].get("Risk Review", 0) > 0:
        warnings.append("risk-review threads need manual triage before cleanup.")
    if registry is None:
        warnings.append("task registry is missing; run `./dev codex-os registry init --write`.")
    else:
        done_without_evidence = [
            task.get("task_id", "")
            for task in registry.get("tasks", [])
            if task.get("status") == "Done"
            and not (task.get("evidence_file") or task.get("closeout_file") or task.get("evidence_note") or task.get("closeout_note"))
        ]
        if done_without_evidence:
            warnings.append(f"Done task(s) without evidence/closeout reference: {', '.join(done_without_evidence[:10])}.")
    lines = ["# Codex OS Health Report", ""]
    lines.append(f"- Generated: {snapshot['generated_at']}")
    lines.append(f"- Status: {'WARN' if warnings else 'OK'}")
    lines.append("")
    lines.append("## Checks")
    lines.append("")
    lines.append(f"- Codex state readable: OK (`{snapshot['state_db']}`)")
    lines.append(f"- Runtime thread classification: OK ({snapshot['total_threads']} threads in scope)")
    lines.append(f"- Task registry: {'OK' if registry is not None else 'WARN'}")
    lines.append("- Destructive operations: none performed")
    if warnings:
        lines.append("")
        lines.append("## Warnings")
        lines.append("")
        for warning in warnings:
            lines.append(f"- {warning}")
    return "\n".join(lines).rstrip() + "\n"


def render_task_detail(task: dict[str, Any]) -> str:
    lines = ["Codex OS task", ""]
    for key in (
        "task_id",
        "project",
        "lane",
        "status",
        "risk_level",
        "confirmation_status",
        "validation_status",
        "automation_scope",
        "owner_thread",
        "handoff_file",
        "evidence_file",
        "closeout_file",
        "evidence_note",
        "closeout_note",
        "next_action",
        "validation",
        "archive_recommendation",
        "updated_at",
        "finished_at",
    ):
        value = task.get(key)
        if value:
            lines.append(f"- {key}: {value}")
    return "\n".join(lines).rstrip() + "\n"


def render_preflight_report(report: dict[str, Any]) -> str:
    lines = ["Codex OS preflight", ""]
    lines.append(f"- generated_at: {report['generated_at']}")
    lines.append(f"- task_id: {report.get('task_id') or '(none)'}")
    lines.append(f"- strict: {report.get('strict')}")
    lines.append(f"- result: {report['result']}")
    lines.append("")
    lines.append("Checks")
    lines.append("")
    for check in report["checks"]:
        detail = f" - {check['detail']}" if check.get("detail") else ""
        lines.append(f"- {check['status']}: {check['name']}{detail}")
    if report.get("recommended_commands"):
        lines.append("")
        lines.append("Recommended Commands")
        lines.append("")
        for command in report["recommended_commands"]:
            lines.append(f"- `{command}`")
    if report.get("manual_confirmations"):
        lines.append("")
        lines.append("Manual Confirmations")
        lines.append("")
        for item in report["manual_confirmations"]:
            lines.append(f"- {item}")
    return "\n".join(lines).rstrip() + "\n"


def render_finish_summary(summary: dict[str, Any]) -> str:
    lines = ["Codex OS finish", ""]
    lines.append(f"- generated_at: {summary['generated_at']}")
    lines.append(f"- task_id: {summary['task_id']}")
    lines.append(f"- status: {summary['status']}")
    lines.append(f"- write: {summary['write']}")
    lines.append(f"- result: {summary['result']}")
    if summary.get("updated_path"):
        lines.append(f"- registry: {summary['updated_path']}")
    if summary.get("archive_recommendation"):
        lines.append(f"- archive_recommendation: {summary['archive_recommendation']} (recommendation only)")
    if summary.get("warnings"):
        lines.append("")
        lines.append("Warnings")
        lines.append("")
        for warning in summary["warnings"]:
            lines.append(f"- {warning}")
    if summary.get("task"):
        lines.append("")
        lines.append(render_task_detail(summary["task"]).rstrip())
    return "\n".join(lines).rstrip() + "\n"
