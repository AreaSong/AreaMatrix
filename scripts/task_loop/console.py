"""Interactive and non-interactive console for the AreaMatrix task loop."""

from __future__ import annotations

import argparse
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Sequence

from . import dev_config, state
from .actions import ACTIONS, COMMAND_ALIASES, MENUS, SHORTCUT_ALIASES
from .i18n import normalize_lang_mode, t, t_lines
from .lifecycle import LIFECYCLE_STAGES, LifecycleSnapshot, VersionLifecycle, load_lifecycle_snapshot
from .runner import RuntimeConfig, print_loop_status
from scripts.dev_tools import cli as dev_tools_cli


def package_root() -> Path:
    return Path(__file__).resolve().parents[2]


def env_value(name: str, default: str = "") -> str:
    return os.environ.get(f"DEV_{name}", os.environ.get(f"DEV_SH_{name}", default))


@dataclass
class RunnerCommand:
    argv: list[str]
    env: dict[str, str]
    env_bits: list[str]
    execution_mode: str


@dataclass
class ConsoleConfig:
    runtime: RuntimeConfig
    task_loop_bin: Path
    pipeline: Path
    console_log_root: Path
    color_mode: str = "always"
    lang_mode: str = "mixed"

    @classmethod
    def from_env(cls) -> "ConsoleConfig":
        runtime = RuntimeConfig.from_env()
        root = package_root()
        task_loop_bin = Path(os.environ.get("TASK_LOOP_BIN", root / "task-loop"))
        pipeline = Path(os.environ.get("PIPELINE", runtime.root_dir / "tasks/prompts/_shared/prompt_pipeline.py"))
        console_log_root = Path(os.environ.get("CONSOLE_LOG_ROOT", runtime.root_dir / ".codex/task-loop-console"))
        return cls(runtime=runtime, task_loop_bin=task_loop_bin, pipeline=pipeline, console_log_root=console_log_root)


@dataclass
class DevArgs:
    command_args: list[str]
    color_mode: str
    lang_mode: str | None
    once: bool


class DevArgError(ValueError):
    def __init__(self, key: str, lang_mode: str) -> None:
        self.key = key
        self.lang_mode = lang_mode
        super().__init__(key)


@dataclass
class PromptSnapshot:
    total: int
    completed: int
    pending: int
    first_ready: str
    by_status: dict[str, int]
    by_phase: dict[str, int]
    error: str = ""


@dataclass
class ProcessSnapshot:
    runners: list[str]
    repo_codex: list[str]
    host_codex: list[str]
    unavailable_reason: str = ""


@dataclass
class DashboardSnapshot:
    lifecycle: LifecycleSnapshot
    prompt: PromptSnapshot
    progress_counts: dict[str, int]
    process: ProcessSnapshot
    lock: dict[str, Any]
    stale_count: int
    drain_requested: bool
    latest_log_dir: Path | None
    latest_run: dict[str, Any] | None
    latest_verify_result: str
    latest_verify_log: Path | None
    interesting_task: tuple[str, dict[str, Any]] | None
    git_dirty: bool
    captured_at: datetime


def timestamp() -> str:
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def normalize_color_mode(value: str) -> str:
    return value if value in {"always", "never", "auto"} else "always"


def color_enabled(mode: str = "always") -> bool:
    if os.environ.get("NO_COLOR"):
        return False
    if mode == "never":
        return False
    if mode == "auto":
        return sys.stdout.isatty() and bool(os.environ.get("TERM"))
    return True


def supports_color(force_no_color: bool = False, mode: str = "always") -> bool:
    if force_no_color:
        return False
    if os.environ.get("DEV_NO_COLOR"):
        return False
    return color_enabled(mode)


def ansi(text: str, code: str, color: bool) -> str:
    return f"\033[{code}m{text}\033[0m" if color else text


def bold(text: str, color: bool) -> str:
    return ansi(text, "1", color)


def green(text: str, color: bool) -> str:
    return ansi(text, "32", color)


def yellow(text: str, color: bool) -> str:
    return ansi(text, "33", color)


def red(text: str, color: bool) -> str:
    return ansi(text, "31", color)


def cyan(text: str, color: bool) -> str:
    return ansi(text, "36", color)


def dim(text: str, color: bool) -> str:
    return ansi(text, "2", color)


def status_badge(text: str, color_name: str, color: bool) -> str:
    code = {"green": "1;32", "yellow": "1;33", "red": "1;31", "cyan": "1;36", "dim": "2"}.get(color_name, "1")
    return ansi(f" {text} ", code, color)


def tr(cfg: ConsoleConfig, key: str, **params: Any) -> str:
    return t(cfg.lang_mode, key, **params)


def tr_lines(cfg: ConsoleConfig, key: str, **params: Any) -> list[str]:
    return t_lines(cfg.lang_mode, key, **params)


def print_lines(cfg: ConsoleConfig, key: str, **params: Any) -> None:
    print("\n".join(tr_lines(cfg, key, **params)))


def rel_path(root: Path, path: Path | str | None) -> str:
    if not path:
        return "none"
    value = Path(path)
    try:
        return str(value.resolve().relative_to(root.resolve()))
    except (OSError, ValueError):
        return str(path)


def parse_global_args(args: Sequence[str]) -> DevArgs:
    remaining = list(args)
    color_mode = normalize_color_mode(os.environ.get("DEV_COLOR", "always"))
    lang_mode: str | None = None
    error_lang = normalize_lang_mode(os.environ.get("DEV_LANG", "mixed"))
    once = False
    command_args: list[str] = []
    index = 0
    while index < len(remaining):
        value = remaining[index]
        if value == "--once":
            once = True
            index += 1
            continue
        if value == "--no-color":
            color_mode = "never"
            index += 1
            continue
        if value == "--color":
            if index + 1 >= len(remaining):
                raise DevArgError("color_requires", lang_mode or error_lang)
            color_mode = normalize_color_mode(remaining[index + 1])
            index += 2
            continue
        if value.startswith("--color="):
            color_mode = normalize_color_mode(value.split("=", 1)[1])
            index += 1
            continue
        if value == "--lang":
            if index + 1 >= len(remaining):
                raise DevArgError("lang_requires", lang_mode or error_lang)
            lang_mode = normalize_lang_mode(remaining[index + 1])
            index += 2
            continue
        if value.startswith("--lang="):
            lang_mode = normalize_lang_mode(value.split("=", 1)[1])
            index += 1
            continue
        command_args.extend(remaining[index:])
        break
    return DevArgs(command_args=command_args, color_mode=color_mode, lang_mode=lang_mode, once=once)


def resolve_lang_mode(root: Path, cli_lang: str | None) -> str:
    if cli_lang:
        return normalize_lang_mode(cli_lang)
    env_lang = os.environ.get("DEV_LANG")
    if env_lang:
        return normalize_lang_mode(env_lang)
    return dev_config.saved_lang_mode(root)


def banner_lang(cfg: ConsoleConfig | None = None) -> str:
    if cfg:
        return cfg.lang_mode
    return normalize_lang_mode(os.environ.get("DEV_LANG", "mixed"))


def print_banner(cfg: ConsoleConfig | None = None) -> None:
    if sys.stdout.isatty() and os.environ.get("TERM"):
        subprocess.run(["clear"], check=False)
    print("============================================================")
    print(f"        {t(banner_lang(cfg), 'banner.title')}")
    print("============================================================")


def pause(cfg: ConsoleConfig) -> None:
    if not sys.stdin.isatty():
        return
    input(tr(cfg, "pause.return"))


def confirm(cfg: ConsoleConfig, prompt: str) -> bool:
    if env_value("CONFIRM") == "1":
        return True
    if not sys.stdin.isatty():
        return False
    answer = input(tr(cfg, "confirm.suffix", prompt=prompt)).strip().lower()
    return answer in {"y", "yes"}


def read_ps_lines() -> tuple[list[str], str]:
    try:
        proc = subprocess.run(
            ["ps", "-axo", "pid=,ppid=,stat=,command="],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as error:
        reason = error.strerror or str(error)
        return [], f"ps unavailable: {reason}"
    if proc.returncode != 0:
        reason = (proc.stderr or "").strip() or f"exit {proc.returncode}"
        return [], f"ps unavailable: {reason}"
    return [line for line in proc.stdout.splitlines() if line.strip()], ""


def ps_lines() -> list[str]:
    lines, _ = read_ps_lines()
    return lines


def runner_processes_from_lines(cfg: ConsoleConfig, process_lines: Sequence[str]) -> list[str]:
    root = str(cfg.runtime.root_dir)
    lines = []
    for line in process_lines:
        if "codex exec" in line:
            continue
        if "task-loop" in line and (" run" in line or " resume-" in line) and root in line:
            lines.append(line)
    return lines


def codex_processes_from_lines(process_lines: Sequence[str]) -> list[str]:
    return [line for line in process_lines if "codex exec" in line]


def runner_processes(cfg: ConsoleConfig) -> list[str]:
    return runner_processes_from_lines(cfg, ps_lines())


def codex_processes() -> list[str]:
    return codex_processes_from_lines(ps_lines())


def repo_codex_processes(cfg: ConsoleConfig) -> list[str]:
    root = str(cfg.runtime.root_dir)
    return [line for line in codex_processes() if root in line]


def process_snapshot(cfg: ConsoleConfig) -> ProcessSnapshot:
    lines, unavailable_reason = read_ps_lines()
    codex_lines = codex_processes_from_lines(lines)
    root = str(cfg.runtime.root_dir)
    return ProcessSnapshot(
        runners=runner_processes_from_lines(cfg, lines),
        repo_codex=[line for line in codex_lines if root in line],
        host_codex=codex_lines,
        unavailable_reason=unavailable_reason,
    )


def live_runner_active(cfg: ConsoleConfig) -> bool:
    lock = state.lock_info(cfg.runtime.lock_dir)
    return bool(lock["exists"] and lock["alive"] and lock.get("operation") == "run")


def status_output(cfg: ConsoleConfig) -> str:
    return state.status_fragment(
        cfg.runtime.progress_file,
        cfg.runtime.lock_dir,
        cfg.runtime.log_root,
        cfg.runtime.drain_request_file,
    )


def print_status_compact(cfg: ConsoleConfig) -> None:
    wanted = (
        "- lock:",
        "- lock_alive:",
        "- lock_pid:",
        "- lock_run_id:",
        "- lock_command:",
        "- live_activity:",
        "- live_activity_started_at:",
        "- live_activity_elapsed:",
        "- live_activity_pid:",
        "- live_activity_prompt:",
        "- live_activity_log:",
        "- live_activity_log_state:",
        "- live_activity_no_output_elapsed:",
        "- live_activity_no_output_timeout:",
        "- live_activity_codex_idle_timeout:",
        "- live_activity_validation_child_running:",
        "- live_activity_validation_child_count:",
        "- live_activity_validation_child:",
        "- live_activity_validation_scan_reason:",
        "- live_activity_meaningful_activity:",
        "- live_activity_exec_activity_events:",
        "- live_activity_command:",
        "- drain_requested:",
        "- latest_log_dir:",
        "- completed:",
        "- in_progress:",
        "- failed:",
        "- blocked:",
        "- stale_in_progress:",
        "- recent_in_progress:",
        "- recent_failed:",
        "- recent_blocked:",
        "- recent_stale_in_progress:",
    )
    for line in status_output(cfg).splitlines():
        if line.startswith(wanted):
            print(line)


def show_processes(cfg: ConsoleConfig) -> None:
    snapshot = process_snapshot(cfg)
    runners = snapshot.runners
    repo_codex = snapshot.repo_codex
    host_codex = snapshot.host_codex
    print(tr(cfg, "processes.title"))
    if snapshot.unavailable_reason:
        print(f"- {snapshot.unavailable_reason}")
    print(tr(cfg, "processes.runner", count=len(runners)))
    print(tr(cfg, "processes.area_codex", count=len(repo_codex)))
    print(tr(cfg, "processes.host_codex", count=len(host_codex)))
    if runners:
        print(tr(cfg, "processes.runner_title"))
        print("\n".join(runners))
    if repo_codex:
        print(tr(cfg, "processes.area_codex_title"))
        print("\n".join(repo_codex))
    if host_codex:
        print(tr(cfg, "processes.host_codex_title"))
        print("\n".join(host_codex))


def summarize_process_line(line: str, root: Path) -> str:
    parts = line.split()
    pid = parts[0] if parts else "?"
    cwd_match = re.search(r"--cd\s+(\S+)", line)
    cwd = cwd_match.group(1) if cwd_match else ""
    out_match = re.search(r"-o\s+(\S+)", line)
    out_path = out_match.group(1) if out_match else ""
    cwd_name = Path(cwd).name if cwd else "unknown"
    out_name = Path(out_path).name if out_path else "no-log"
    if cwd and root.as_posix() in cwd:
        cwd_name = "AreaMatrix"
    return f"pid={pid} {cwd_name} {out_name}"


def process_summary_line(cfg: ConsoleConfig, snapshot: ProcessSnapshot, *, detailed: bool = True) -> str:
    if snapshot.unavailable_reason:
        return snapshot.unavailable_reason
    other = [line for line in snapshot.host_codex if line not in snapshot.repo_codex]
    summary = (
        f"runner={len(snapshot.runners)} | "
        f"AreaMatrix codex={len(snapshot.repo_codex)} | "
        f"other codex={len(other)}"
    )
    if not detailed:
        return summary
    examples: list[str] = []
    for line in [*snapshot.runners[:1], *snapshot.repo_codex[:1], *other[:1]]:
        examples.append(summarize_process_line(line, cfg.runtime.root_dir))
    if examples:
        summary += ": " + " ; ".join(examples)
    return summary


def read_json(path: Path, default: object) -> object:
    try:
        import json

        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def show_latest_task_details(cfg: ConsoleConfig) -> None:
    data = read_json(cfg.runtime.progress_file, {"tasks": {}})
    tasks = data.get("tasks", {}) if isinstance(data, dict) else {}
    interesting: list[tuple[str, str, dict[str, object]]] = []
    for label, value in tasks.items():
        if isinstance(value, dict) and value.get("status") in {"in_progress", "failed", "blocked"}:
            interesting.append((str(value.get("updated_at", "")), label, value))
    interesting.sort(reverse=True)

    print(tr(cfg, "task_details.title"))
    if interesting:
        _, label, entry = interesting[0]
        print(f"- label: {label}")
        print(f"- status: {entry.get('status', 'unknown')}")
        print(f"- attempts: {entry.get('attempts', 0)}")
        print(f"- note: {entry.get('note', '')}")
        for key in ["copy_log", "verify_log", "git_checkpoint_status", "git_push_status"]:
            if entry.get(key):
                print(f"- {key}: {entry[key]}")
    else:
        print(tr(cfg, "task_details.none"))

    index = read_json(cfg.runtime.run_summary_root / "index.json", {"runs": []})
    runs = index.get("runs", []) if isinstance(index, dict) else []
    print(tr(cfg, "task_details.recent_run"))
    for item in [run for run in runs if isinstance(run, dict)][:5]:
        print(
            f"- {item.get('run_id', 'unknown')} "
            f"status={item.get('status', '')} "
            f"completed={item.get('completed', 0)} "
            f"retries={item.get('retries', 0)} "
            f"start_from={item.get('start_from', '')} "
            f"stop_after={item.get('stop_after', '')}"
        )


def latest_verify_log(log_root: Path) -> Path | None:
    if not log_root.exists():
        return None
    logs = sorted(log_root.rglob("*-verify-attempt-*.log"))
    return logs[-1] if logs else None


def latest_verify_result(path: Path | None) -> str:
    if not path:
        return "missing"
    return state.verify_result(str(path))


def show_latest_failure_summary(cfg: ConsoleConfig) -> None:
    print(tr(cfg, "verify_summary.title"))
    latest = latest_verify_log(cfg.runtime.log_root)
    if not latest:
        print(tr(cfg, "verify_summary.none"))
        return
    print(tr(cfg, "verify_summary.log", path=latest))
    lines = latest.read_text(encoding="utf-8", errors="replace").splitlines()
    for line in lines[-60:-5][-40:]:
        if "VERIFY_RESULT:" not in line:
            print(line)
    for line in lines[-5:]:
        if "VERIFY_RESULT:" in line:
            print(line)


def git_dirty(root: Path) -> bool:
    proc = subprocess.run(["git", "status", "--short"], cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
    return bool(proc.stdout.strip())


def load_prompt_snapshot(cfg: ConsoleConfig) -> PromptSnapshot:
    try:
        from tasks.prompts._shared.prompt_pipeline_lib.repository import (
            load_manifests,
            load_progress,
            ordered_labels,
            ready_for_next,
            scan_task_files,
            task_status,
        )

        tasks = scan_task_files()
        manifests = load_manifests()
        progress = load_progress()
        labels = ordered_labels(tasks, manifests)
        by_status: dict[str, int] = {}
        by_phase: dict[str, int] = {}
        first_ready = "None"
        for label in labels:
            if label not in manifests:
                continue
            task = tasks[label]
            by_phase[task.phase] = by_phase.get(task.phase, 0) + 1
            status_name = task_status(progress, label)
            by_status[status_name] = by_status.get(status_name, 0) + 1
            if first_ready == "None" and status_name != "completed" and ready_for_next(label, manifests, progress):
                first_ready = label
        total = len(tasks)
        completed = by_status.get("completed", 0)
        return PromptSnapshot(
            total=total,
            completed=completed,
            pending=max(total - completed, 0),
            first_ready=first_ready,
            by_status=by_status,
            by_phase=by_phase,
        )
    except Exception as exc:
        data = read_json(cfg.runtime.progress_file, {"tasks": {}})
        tasks = data.get("tasks", {}) if isinstance(data, dict) else {}
        completed = sum(1 for value in tasks.values() if isinstance(value, dict) and value.get("status") == "completed") if isinstance(tasks, dict) else 0
        return PromptSnapshot(
            total=completed,
            completed=completed,
            pending=0,
            first_ready="unknown",
            by_status={"completed": completed},
            by_phase={},
            error=str(exc),
        )


def latest_log_dir(log_root: Path) -> Path | None:
    if not log_root.is_dir():
        return None
    logs = sorted(path for path in log_root.iterdir() if path.is_dir() and path.name.startswith("20"))
    return logs[-1] if logs else None


def latest_run(cfg: ConsoleConfig) -> dict[str, Any] | None:
    index = read_json(cfg.runtime.run_summary_root / "index.json", {"runs": []})
    runs = index.get("runs", []) if isinstance(index, dict) else []
    for item in runs:
        if isinstance(item, dict):
            return item
    return None


def current_interesting_task(cfg: ConsoleConfig) -> tuple[str, dict[str, Any]] | None:
    data = read_json(cfg.runtime.progress_file, {"tasks": {}})
    tasks = data.get("tasks", {}) if isinstance(data, dict) else {}
    interesting: list[tuple[str, str, dict[str, Any]]] = []
    if isinstance(tasks, dict):
        for label, value in tasks.items():
            if isinstance(value, dict) and value.get("status") in {"in_progress", "failed", "blocked"}:
                interesting.append((str(value.get("updated_at", "")), str(label), value))
    if not interesting:
        return None
    _, label, entry = sorted(interesting, reverse=True)[0]
    return label, entry


def runtime_progress_counts(cfg: ConsoleConfig) -> dict[str, int]:
    data = read_json(cfg.runtime.progress_file, {"tasks": {}})
    tasks = data.get("tasks", {}) if isinstance(data, dict) else {}
    counts: dict[str, int] = {}
    if isinstance(tasks, dict):
        for value in tasks.values():
            if not isinstance(value, dict):
                continue
            status_name = str(value.get("status", "pending"))
            counts[status_name] = counts.get(status_name, 0) + 1
    return counts


def dashboard_snapshot(cfg: ConsoleConfig) -> DashboardSnapshot:
    lock = state.lock_info(cfg.runtime.lock_dir)
    latest_verify = latest_verify_log(cfg.runtime.log_root)
    return DashboardSnapshot(
        lifecycle=load_lifecycle_snapshot(cfg.runtime.root_dir),
        prompt=load_prompt_snapshot(cfg),
        progress_counts=runtime_progress_counts(cfg),
        process=process_snapshot(cfg),
        lock=lock,
        stale_count=len(state.stale_tasks(cfg.runtime.progress_file, cfg.runtime.lock_dir)),
        drain_requested=bool(state.read_control_file(cfg.runtime.drain_request_file)),
        latest_log_dir=latest_log_dir(cfg.runtime.log_root),
        latest_run=latest_run(cfg),
        latest_verify_result=latest_verify_result(latest_verify),
        latest_verify_log=latest_verify,
        interesting_task=current_interesting_task(cfg),
        git_dirty=git_dirty(cfg.runtime.root_dir),
        captured_at=datetime.now(),
    )


def show_recovery_hints(cfg: ConsoleConfig) -> None:
    output = status_output(cfg)
    print(tr(cfg, "recovery.hint.title"))
    if re.search(r"stale_in_progress: [1-9]", output):
        print(tr(cfg, "recovery.hint.stale"))
    if re.search(r"^- failed: ", output, flags=re.MULTILINE):
        print(tr(cfg, "recovery.hint.failed"))
    if re.search(r"^- blocked: ", output, flags=re.MULTILINE):
        print(tr(cfg, "recovery.hint.blocked"))
    if live_runner_active(cfg):
        print(tr(cfg, "recovery.hint.live"))
    if git_dirty(cfg.runtime.root_dir):
        print(tr(cfg, "recovery.hint.dirty"))


def runner_state(snapshot: DashboardSnapshot) -> tuple[str, str]:
    lock = snapshot.lock
    if lock["exists"] and lock["alive"]:
        if snapshot.drain_requested:
            return "draining", "yellow"
        return "running", "green"
    if snapshot.stale_count:
        return "stale", "red"
    if snapshot.progress_counts.get("failed", 0):
        return "failed", "red"
    if snapshot.progress_counts.get("blocked", 0):
        return "blocked", "yellow"
    if snapshot.git_dirty:
        return "dirty", "yellow"
    return "idle", "cyan"


def state_text(cfg: ConsoleConfig, state_name: str) -> str:
    return tr(cfg, f"state.{state_name}")


def recommended_action(cfg: ConsoleConfig, snapshot: DashboardSnapshot) -> tuple[str, str]:
    if snapshot.lock["exists"] and snapshot.lock["alive"]:
        if snapshot.drain_requested:
            return tr(cfg, "action.wait_drain"), "./dev status"
        return tr(cfg, "action.request_drain"), "./dev drain"
    if snapshot.git_dirty and env_value("GIT_CHECKPOINT", cfg.runtime.git_checkpoint) != "off":
        return tr(cfg, "action.handle_dirty"), "git status --short"
    if snapshot.stale_count:
        return tr(cfg, "action.resume_stale"), "./dev resume-stale"
    if snapshot.progress_counts.get("failed", 0):
        return tr(cfg, "action.resume_failed"), "./dev resume-failed"
    if snapshot.progress_counts.get("blocked", 0):
        return tr(cfg, "action.continue_blocked"), "RISK_POLICY=allow START_FROM=<label> ./task-loop run"
    if snapshot.lifecycle.promotion_blockers:
        return tr(cfg, "action.review_workflow"), "./dev workflow status"
    return tr(cfg, "action.continue_queue"), "RISK_POLICY=allow MAX_RETRIES=1 ./task-loop run"


def blocker_lines(cfg: ConsoleConfig, snapshot: DashboardSnapshot) -> list[str]:
    lines: list[str] = []
    if snapshot.git_dirty:
        lines.append(tr(cfg, "blocker.dirty"))
    if snapshot.stale_count:
        lines.append(tr(cfg, "blocker.stale"))
    for blocker in snapshot.lifecycle.promotion_blockers:
        lines.append(tr(cfg, "blocker.promotion", blocker=blocker))
    return lines


def verify_text(result: str, color: bool) -> str:
    if result == "pass":
        return green("PASS", color)
    if result == "fail":
        return red("FAIL", color)
    if result == "unfinished":
        return yellow("unfinished", color)
    return dim(result, color)


def render_progress_bar(completed: int, total: int, color: bool, width: int = 28) -> str:
    if total <= 0:
        return dim("[" + "-" * width + "]", color)
    filled = int(round(width * min(completed, total) / total))
    bar = "#" * filled + "-" * (width - filled)
    return green(f"[{bar}]", color)


def progress_text(cfg: ConsoleConfig, prompt: PromptSnapshot, percent: float) -> str:
    return tr(cfg, "progress.text", completed=prompt.completed, total=prompt.total, pending=prompt.pending, percent=percent)


def lifecycle_summary_text(cfg: ConsoleConfig, lifecycle: LifecycleSnapshot) -> str:
    return tr(
        cfg,
        "lifecycle.summary",
        count=len(lifecycle.versions),
        live=lifecycle.live_version,
        active=lifecycle.active_version,
        planning=lifecycle.planning_versions,
    )


def lifecycle_version_line(cfg: ConsoleConfig, version: VersionLifecycle) -> str:
    parts = [
        f"{version.version_id} {version.status}",
        f"discussion={version.discussion}",
        f"changes={version.changes_count}",
        f"plans={version.plans_count}",
        f"drafts={version.drafts_count}",
        f"queue={version.queue_count}",
        f"promotion={version.promotion}",
    ]
    if version.live_queue:
        parts.append(f"live={version.live_queue}")
    if version.gate and version.gate != "none":
        parts.append(f"gate={version.gate}")
    return " | ".join(parts)


def current_task_parts(snapshot: DashboardSnapshot) -> tuple[str, str, int]:
    if not snapshot.interesting_task:
        return "none", "none", 0
    task_label, entry = snapshot.interesting_task
    return task_label, str(entry.get("status", "unknown")), int(entry.get("attempts", 0) or 0)


def safety_issue_labels(cfg: ConsoleConfig, snapshot: DashboardSnapshot) -> list[str]:
    issues: list[str] = []
    if snapshot.lock["exists"] and snapshot.lock["alive"]:
        issues.append(tr(cfg, "situation.issue.running"))
    if snapshot.git_dirty and env_value("GIT_CHECKPOINT", cfg.runtime.git_checkpoint) != "off":
        issues.append(tr(cfg, "situation.issue.dirty"))
    if snapshot.stale_count:
        issues.append(tr(cfg, "situation.issue.stale"))
    if snapshot.progress_counts.get("failed", 0):
        issues.append(tr(cfg, "situation.issue.failed"))
    if snapshot.progress_counts.get("blocked", 0):
        issues.append(tr(cfg, "situation.issue.blocked"))
    if snapshot.lifecycle.promotion_blockers:
        issues.append(tr(cfg, "situation.issue.promotion"))
    return issues


def situation_reason_lines(cfg: ConsoleConfig, snapshot: DashboardSnapshot) -> list[str]:
    task_label, _, attempts = current_task_parts(snapshot)
    lines: list[str] = []
    if snapshot.git_dirty and env_value("GIT_CHECKPOINT", cfg.runtime.git_checkpoint) != "off":
        lines.append(tr(cfg, "situation.reason.dirty"))
    if snapshot.stale_count:
        lines.append(tr(cfg, "situation.reason.stale", task=task_label, attempts=attempts))
    if snapshot.progress_counts.get("failed", 0):
        lines.append(tr(cfg, "situation.reason.failed"))
    if snapshot.progress_counts.get("blocked", 0):
        lines.append(tr(cfg, "situation.reason.blocked"))
    if snapshot.lock["exists"] and snapshot.lock["alive"]:
        lines.append(tr(cfg, "situation.reason.running"))
    for blocker in snapshot.lifecycle.promotion_blockers:
        lines.append(tr(cfg, "situation.reason.promotion", blocker=blocker))
    return lines or [tr(cfg, "situation.reason.none")]


def situation_lines(cfg: ConsoleConfig, snapshot: DashboardSnapshot, color: bool) -> list[str]:
    state_name, state_color = runner_state(snapshot)
    task_label, task_status, attempts = current_task_parts(snapshot)
    issues = safety_issue_labels(cfg, snapshot)
    summary = (
        tr(cfg, "situation.summary.unsafe", issues=" + ".join(issues))
        if issues
        else tr(cfg, "situation.summary.safe")
    )
    lines = [
        bold(tr(cfg, "situation.title"), color),
        f"{status_badge(state_text(cfg, state_name), state_color, color)} {summary}",
        tr(cfg, "situation.current_task", task=task_label, status=task_status, attempts=attempts),
        tr(cfg, "situation.reasons"),
    ]
    lines.extend(f"- {line}" for line in situation_reason_lines(cfg, snapshot))
    return lines


def recommended_chain_steps(cfg: ConsoleConfig, snapshot: DashboardSnapshot) -> list[str]:
    dirty_blocks_checkpoint = snapshot.git_dirty and env_value("GIT_CHECKPOINT", cfg.runtime.git_checkpoint) != "off"
    if snapshot.lock["exists"] and snapshot.lock["alive"]:
        if snapshot.drain_requested:
            return [tr(cfg, "guide.step.status"), tr(cfg, "guide.step.wait_drain")]
        return [tr(cfg, "guide.step.drain"), tr(cfg, "guide.step.status")]
    if dirty_blocks_checkpoint:
        if snapshot.stale_count:
            final_step = tr(cfg, "guide.step.resume_stale")
        elif snapshot.progress_counts.get("failed", 0):
            final_step = tr(cfg, "guide.step.resume_failed")
        else:
            final_step = tr(cfg, "guide.step.run_queue")
        return [tr(cfg, "guide.step.git_status"), tr(cfg, "guide.step.save_worktree"), final_step]
    if snapshot.stale_count:
        return [tr(cfg, "guide.step.resume_stale")]
    if snapshot.progress_counts.get("failed", 0):
        return [tr(cfg, "guide.step.resume_failed")]
    if snapshot.progress_counts.get("blocked", 0):
        return [tr(cfg, "guide.step.review_blocked")]
    if snapshot.lifecycle.promotion_blockers:
        return [tr(cfg, "guide.step.workflow_status")]
    return [tr(cfg, "guide.step.run_queue")]


def recommended_chain_lines(cfg: ConsoleConfig, snapshot: DashboardSnapshot, color: bool) -> list[str]:
    lines = [bold(tr(cfg, "guide.title"), color)]
    for index, step in enumerate(recommended_chain_steps(cfg, snapshot), start=1):
        lines.append(f"{index}. {step}")
    lines.append(tr(cfg, "guide.after"))
    return lines


def progress_overview_lines(cfg: ConsoleConfig, snapshot: DashboardSnapshot, color: bool) -> list[str]:
    prompt = snapshot.prompt
    percent = (prompt.completed / prompt.total * 100) if prompt.total else 0.0
    task_label, _, _ = current_task_parts(snapshot)
    task_marker = task_label if snapshot.stale_count else prompt.first_ready
    v1 = next((item for item in snapshot.lifecycle.versions if item.version_id == "v1-mvp"), None)
    template = next((item for item in snapshot.lifecycle.versions if item.version_id == "v-template"), None)
    promotion_state = (
        tr(cfg, "progress_overview.promotion_blocked")
        if snapshot.lifecycle.promotion_blockers
        else (template.promotion if template else "none")
    )
    lines = [bold(tr(cfg, "progress_overview.title"), color)]
    lines.append(
        tr(
            cfg,
            "progress_overview.v1",
            version=v1.version_id if v1 else "v1-mvp",
            completed=prompt.completed,
            total=prompt.total,
            percent=percent,
            status=runner_state(snapshot)[0],
            task=task_marker,
        )
    )
    if template:
        lines.append(
            tr(
                cfg,
                "progress_overview.template",
                version=template.version_id,
                changes=template.changes_count,
                plans=template.plans_count,
                drafts=template.drafts_count,
                queue=template.queue_count,
                promotion=promotion_state,
            )
        )
    return lines


def dashboard_lines(cfg: ConsoleConfig, snapshot: DashboardSnapshot, *, color: bool, realtime: bool) -> list[str]:
    mode_value = tr(cfg, "dashboard.mode.realtime_5s" if realtime else "dashboard.mode.snapshot")

    lines = [
        bold(tr(cfg, "dashboard.title"), color),
        f"{dim(tr(cfg, 'dashboard.lang'), color)} {cfg.lang_mode} | "
        f"{mode_value} {snapshot.captured_at.strftime('%Y-%m-%d %H:%M:%S')} | "
        f"{dim(tr(cfg, 'dashboard.exit'), color)} Ctrl+C",
        "",
        *situation_lines(cfg, snapshot, color),
        "",
        *recommended_chain_lines(cfg, snapshot, color),
        "",
        *progress_overview_lines(cfg, snapshot, color),
    ]
    if snapshot.prompt.error:
        lines.append(f"{bold(tr(cfg, 'dashboard.prompt_status'), color)} {yellow('fallback', color)} {snapshot.prompt.error}")
    return lines


def render_status_dashboard(cfg: ConsoleConfig, *, color: bool, realtime: bool) -> None:
    snapshot = dashboard_snapshot(cfg)
    print("\n".join(dashboard_lines(cfg, snapshot, color=color, realtime=realtime)))


def show_status_dashboard(cfg: ConsoleConfig, *, refresh_seconds: float = 5.0, once: bool = False, no_color: bool = False) -> int:
    color = supports_color(no_color, cfg.color_mode)
    realtime = sys.stdout.isatty() and not once
    if not realtime:
        render_status_dashboard(cfg, color=color, realtime=False)
        return 0
    try:
        while True:
            print("\033[2J\033[H", end="")
            render_status_dashboard(cfg, color=color, realtime=True)
            sys.stdout.flush()
            time.sleep(refresh_seconds)
    except KeyboardInterrupt:
        print()
        return 0


def show_preflight(cfg: ConsoleConfig) -> int:
    print_banner(cfg)
    print(tr(cfg, "preflight.title"))
    print(tr(cfg, "preflight.root", root=cfg.runtime.root_dir))
    branch = subprocess.run(["git", "branch", "--show-current"], cwd=cfg.runtime.root_dir, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
    remote = subprocess.run(["git", "remote", "get-url", "origin"], cwd=cfg.runtime.root_dir, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
    print(tr(cfg, "preflight.branch", branch=branch.stdout.strip() or "unknown"))
    print(tr(cfg, "preflight.remote", remote=remote.stdout.strip() or "none"))
    if git_dirty(cfg.runtime.root_dir):
        print(tr(cfg, "preflight.worktree_dirty"))
        status = subprocess.run(["git", "status", "--short"], cwd=cfg.runtime.root_dir, text=True, stdout=subprocess.PIPE, check=False)
        print("\n".join(status.stdout.splitlines()[:20]))
    else:
        print(tr(cfg, "preflight.worktree_clean"))
    print()
    print_status_compact(cfg)
    show_processes(cfg)
    show_recovery_hints(cfg)
    return 0


def show_status_verbose(cfg: ConsoleConfig) -> int:
    print_banner(cfg)
    print_loop_status(cfg.runtime)
    show_processes(cfg)
    show_latest_task_details(cfg)
    show_latest_failure_summary(cfg)
    show_recovery_hints(cfg)
    return 0


def guard_no_live_runner(cfg: ConsoleConfig) -> bool:
    if not live_runner_active(cfg):
        return True
    print_banner(cfg)
    print(tr(cfg, "guard.live.line1"))
    print_status_compact(cfg)
    show_processes(cfg)
    print(tr(cfg, "guard.live.options"))
    print(tr(cfg, "guard.live.option_drain"))
    print(tr(cfg, "guard.live.option_status"))
    return False


def choose_execution_mode(cfg: ConsoleConfig) -> str:
    value = env_value("EXECUTION_MODE")
    if value in {"foreground", "background"}:
        return value
    if not sys.stdin.isatty():
        return "background"
    print("\n".join(tr_lines(cfg, "choose.execution.lines")))
    answer = input(tr(cfg, "prompt.selection")).strip()
    return "foreground" if answer in {"2", "foreground"} else "background"


def choose_git_mode(cfg: ConsoleConfig) -> str:
    value = env_value("GIT_CHECKPOINT")
    if value:
        return value
    if not sys.stdin.isatty():
        return "commit"
    print("\n".join(tr_lines(cfg, "choose.git.lines")))
    answer = input(tr(cfg, "prompt.selection")).strip()
    if answer in {"2", "push"}:
        return "push"
    if answer in {"3", "off"}:
        return "off"
    return "commit"


def choose_max_tasks(cfg: ConsoleConfig) -> str:
    value = env_value("MAX_TASKS")
    if value:
        return value
    if not sys.stdin.isatty():
        return "0"
    print("\n".join(tr_lines(cfg, "choose.max_tasks.lines")))
    answer = input(tr(cfg, "prompt.selection")).strip()
    if answer == "2":
        return "1"
    if answer == "3":
        return "5"
    if answer == "4":
        return "20"
    if answer == "5":
        custom = input(tr(cfg, "prompt.custom_n")).strip()
        return custom if custom.isdigit() else "0"
    return "0"


def choose_max_retries(cfg: ConsoleConfig) -> str:
    value = env_value("MAX_RETRIES")
    if value:
        return value
    if not sys.stdin.isatty():
        return "1"
    print("\n".join(tr_lines(cfg, "choose.max_retries.lines")))
    answer = input(tr(cfg, "prompt.selection")).strip().lower()
    if answer == "2":
        return "2"
    if answer in {"3", "0", "infinite", "forever"}:
        return "0"
    if answer == "4":
        custom = input(tr(cfg, "prompt.custom_n")).strip()
        return custom if custom.isdigit() else "1"
    return "1"


def choose_stop_target(cfg: ConsoleConfig) -> tuple[str, str]:
    phase = env_value("PHASE")
    stop_after = env_value("STOP_AFTER")
    if phase or stop_after or not sys.stdin.isatty():
        return phase, stop_after
    print("\n".join(tr_lines(cfg, "choose.stop.lines")))
    answer = input(tr(cfg, "prompt.selection")).strip()
    if answer == "2":
        return input(tr(cfg, "prompt.phase")).strip(), ""
    if answer == "3":
        return "", input(tr(cfg, "prompt.task_label")).strip()
    return "", ""


def base_env(cfg: ConsoleConfig, git_mode: str, max_retries: str | None = None) -> tuple[dict[str, str], list[str]]:
    values = {
        "RISK_POLICY": "allow",
        "MAX_RETRIES": max_retries if max_retries is not None else env_value("MAX_RETRIES", "1"),
        "GIT_CHECKPOINT": git_mode,
        "CODEX_EXEC_SANDBOX": env_value("CODEX_EXEC_SANDBOX", cfg.runtime.codex_exec_sandbox),
        "PROGRESS_FILE": str(cfg.runtime.progress_file),
        "LOG_ROOT": str(cfg.runtime.log_root),
        "RUN_SUMMARY_ROOT": str(cfg.runtime.run_summary_root),
        "PROGRESS_BACKUP_ROOT": str(cfg.runtime.progress_backup_root),
        "LOCK_DIR": str(cfg.runtime.lock_dir),
        "CONTROL_DIR": str(cfg.runtime.control_dir),
        "ROOT_DIR": str(cfg.runtime.root_dir),
    }
    env = os.environ.copy()
    env.update(values)
    return env, [f"{key}={value}" for key, value in values.items()]


def build_runner_command(cfg: ConsoleConfig, subcommand: str, extra_args: Sequence[str]) -> RunnerCommand:
    execution_mode = choose_execution_mode(cfg)
    git_mode = choose_git_mode(cfg)
    max_tasks = choose_max_tasks(cfg)
    max_retries = choose_max_retries(cfg)
    phase, stop_after = choose_stop_target(cfg)
    env, env_bits = base_env(cfg, git_mode, max_retries)
    argv = [str(cfg.task_loop_bin), subcommand]
    if env_value("DRY_RUN", "0") == "1":
        argv.append("--dry-run")
        env["DRY_RUN_RESULT"] = env_value("DRY_RUN_RESULT", "PASS")
        env_bits.append(f"DRY_RUN_RESULT={env['DRY_RUN_RESULT']}")
    if max_tasks != "0":
        argv.extend(["--max-tasks", max_tasks])
    if phase:
        argv.extend(["--phase", phase])
    if stop_after:
        argv.extend(["--stop-after", stop_after])
    argv.extend(extra_args)
    return RunnerCommand(argv=argv, env=env, env_bits=env_bits, execution_mode=execution_mode)


def print_command_preview(cfg: ConsoleConfig, command: RunnerCommand) -> None:
    print(tr(cfg, "command_preview.prefix", command=shlex.join(["env", *command.env_bits, *command.argv])))
    print(tr(cfg, "command_preview.execution_mode", mode=command.execution_mode))


def run_runner_command(cfg: ConsoleConfig, command: RunnerCommand) -> int:
    cfg.console_log_root.mkdir(parents=True, exist_ok=True)
    print_command_preview(cfg, command)
    if command.execution_mode == "foreground":
        return subprocess.run(command.argv, env=command.env, check=False).returncode
    log_file = cfg.console_log_root / f"task-loop-{timestamp()}.log"
    with log_file.open("w", encoding="utf-8") as stream:
        proc = subprocess.Popen(command.argv, env=command.env, stdout=stream, stderr=subprocess.STDOUT)
    (cfg.console_log_root / "last-task-loop.pid").write_text(f"{proc.pid}\n", encoding="utf-8")
    print(tr(cfg, "runner.background.started", pid=proc.pid))
    print(tr(cfg, "runner.console_log", path=log_file))
    print(tr(cfg, "runner.task_logs"))
    return 0


def start_with_wizard(cfg: ConsoleConfig, subcommand: str) -> int:
    if not guard_no_live_runner(cfg):
        return 1
    return run_runner_command(cfg, build_runner_command(cfg, subcommand, []))


def preview_with_wizard(cfg: ConsoleConfig) -> int:
    command = build_runner_command(cfg, "run", [])
    print_command_preview(cfg, command)
    if live_runner_active(cfg):
        print(tr(cfg, "preview.live_runner"))
    print(tr(cfg, "preview.not_executed"))
    return 0


def run_temp_dry_run(cfg: ConsoleConfig) -> int:
    with tempfile.TemporaryDirectory(prefix="areamatrix-task-loop-") as tmp:
        tmp_dir = Path(tmp)
        print(tr(cfg, "dry_run.temp_dir", path=tmp_dir))
        env = os.environ.copy()
        env.update(
            {
                "ROOT_DIR": str(cfg.runtime.root_dir),
                "PROGRESS_FILE": str(tmp_dir / "progress.json"),
                "LOG_ROOT": str(tmp_dir / "logs"),
                "RUN_SUMMARY_ROOT": str(tmp_dir / "runs"),
                "PROGRESS_BACKUP_ROOT": str(tmp_dir / "backups"),
                "LOCK_DIR": str(tmp_dir / "lock"),
                "CONTROL_DIR": str(tmp_dir / "control"),
                "GIT_CHECKPOINT": "off",
                "CODEX_EXEC_SANDBOX": env_value("CODEX_EXEC_SANDBOX", cfg.runtime.codex_exec_sandbox),
                "RISK_POLICY": "allow",
                "MAX_RETRIES": env_value("MAX_RETRIES", "1"),
                "DRY_RUN_RESULT": env_value("DRY_RUN_RESULT", "PASS"),
            }
        )
        max_tasks = env_value("MAX_TASKS", "1")
        argv = [str(cfg.task_loop_bin), "run", "--dry-run", "--max-tasks", max_tasks]
        if env_value("PHASE"):
            argv.extend(["--phase", env_value("PHASE")])
        rc = subprocess.run(argv, env=env, check=False).returncode
        if rc == 0:
            print(tr(cfg, "dry_run.done"))
        return rc


def request_drain(cfg: ConsoleConfig) -> int:
    if not live_runner_active(cfg):
        print(tr(cfg, "drain.no_runner"))
        return 1
    env, _ = base_env(cfg, cfg.runtime.git_checkpoint)
    return subprocess.run([str(cfg.task_loop_bin), "drain"], env=env, check=False).returncode


def run_health_checks(cfg: ConsoleConfig) -> int:
    return dev_tools_cli.main(["check"])


def lang_from_status_args(args: Sequence[str], default: str) -> str:
    values = list(args)
    for index, value in enumerate(values):
        if value == "--lang" and index + 1 < len(values):
            return normalize_lang_mode(values[index + 1])
        if value.startswith("--lang="):
            return normalize_lang_mode(value.split("=", 1)[1])
    return default


def parse_status_args(args: Sequence[str], default_lang: str) -> argparse.Namespace:
    lang = lang_from_status_args(args, default_lang)
    if "-h" in args or "--help" in args:
        print("\n".join(t_lines(lang, "status_help.lines")))
        raise SystemExit(0)
    parser = argparse.ArgumentParser(prog="./dev status", add_help=False)
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--refresh", type=float, default=5.0)
    parser.add_argument("--color", choices=["always", "never", "auto"])
    parser.add_argument("--lang", choices=["mixed", "zh", "en"])
    parser.add_argument("--no-color", action="store_true")
    return parser.parse_args(list(args))


def show_latest_console_log(cfg: ConsoleConfig) -> int:
    print_banner(cfg)
    logs = sorted(cfg.console_log_root.glob("*.log")) if cfg.console_log_root.exists() else []
    if not logs:
        print(tr(cfg, "logs.none"))
        return 0
    latest = logs[-1]
    print(tr(cfg, "logs.latest", path=latest))
    print("\n".join(latest.read_text(encoding="utf-8", errors="replace").splitlines()[-100:]))
    return 0


def clear_stale(cfg: ConsoleConfig) -> int:
    if not confirm(cfg, tr(cfg, "clear_stale.confirm")):
        print(tr(cfg, "error.cancelled"))
        return 1
    env, _ = base_env(cfg, cfg.runtime.git_checkpoint)
    return subprocess.run([str(cfg.task_loop_bin), "clear-stale"], env=env, check=False).returncode


def reset_progress(cfg: ConsoleConfig) -> int:
    print(tr(cfg, "reset.warning"))
    if env_value("RESET_CONFIRM") != "RESET" and (not sys.stdin.isatty() or input(tr(cfg, "reset.confirm")).strip() != "RESET"):
        print(tr(cfg, "error.cancelled"))
        return 1
    env, _ = base_env(cfg, cfg.runtime.git_checkpoint)
    return subprocess.run([str(cfg.task_loop_bin), "reset-progress"], env=env, check=False).returncode


def clear_screen() -> None:
    if sys.stdout.isatty() and os.environ.get("TERM"):
        print("\033[2J\033[H", end="")


def action_label(cfg: ConsoleConfig, action_id: str) -> str:
    return tr(cfg, ACTIONS[action_id].label_key)


def action_note(cfg: ConsoleConfig, action_id: str) -> str:
    return tr(cfg, ACTIONS[action_id].note_key)


def home_action_key(action_id: str) -> str:
    spec = ACTIONS[action_id]
    return spec.shortcuts[0] if spec.shortcuts else spec.command


def home_action_lines(cfg: ConsoleConfig, color: bool) -> list[str]:
    actions = [(home_action_key(action_id), action_label(cfg, action_id), action_note(cfg, action_id)) for action_id in MENUS["home"].action_ids]
    lines = [bold(tr(cfg, "home.title"), color)]
    width = max(24, *(len(command) for _, command, _ in actions))
    for key, command, note in actions:
        lines.append(f"  {cyan(key, color)}  {command:<{width}}  {dim(note, color)}")
    lines.append("")
    lines.append(dim(tr(cfg, "home.footer"), color))
    lines.append(dim(tr(cfg, "home.meta", mode=cfg.lang_mode), color))
    return lines


def show_recommended_guide(cfg: ConsoleConfig) -> int:
    print_banner(cfg)
    color = color_enabled(cfg.color_mode)
    snapshot = dashboard_snapshot(cfg)
    print("\n".join(situation_lines(cfg, snapshot, color)))
    print("")
    print("\n".join(recommended_chain_lines(cfg, snapshot, color)))
    print("")
    print(dim(tr(cfg, "guide.not_executed"), color))
    return 0


def menu_key(action_id: str, index: int) -> str:
    if action_id == "maintenance-menu":
        return "m"
    if action_id == "new-version-preview":
        return "n"
    spec = ACTIONS[action_id]
    return spec.shortcuts[0] if spec.shortcuts else str(index)


def submenu_rows(cfg: ConsoleConfig, menu_id: str) -> list[tuple[str, str, str, str]]:
    rows: list[tuple[str, str, str, str]] = []
    for index, action_id in enumerate(MENUS[menu_id].action_ids, start=1):
        rows.append((menu_key(action_id, index), action_id, action_label(cfg, action_id), action_note(cfg, action_id)))
    return rows


def submenu_lines(cfg: ConsoleConfig, menu_id: str, color: bool) -> list[str]:
    title = tr(cfg, MENUS[menu_id].title_key)
    items = submenu_rows(cfg, menu_id)
    back_label = tr(cfg, "submenu.back.label")
    back_note = tr(cfg, "submenu.back.note")
    lines = [bold(title, color)]
    for key, _, command, note in items:
        lines.append(f"  {cyan(key, color)}  {command:<18} {dim(note, color)}")
    lines.append(f"  {cyan('?', color)}  {action_label(cfg, 'shortcuts-help'):<18} {dim(action_note(cfg, 'shortcuts-help'), color)}")
    lines.append(f"  {cyan('lang', color)}  {action_label(cfg, 'language-menu'):<18} {dim(action_note(cfg, 'language-menu'), color)}")
    lines.append(f"  {cyan('0', color)}  {back_label:<18} {dim(back_note, color)}")
    return lines


def print_menu(cfg: ConsoleConfig) -> None:
    color = color_enabled(cfg.color_mode)
    clear_screen()
    snapshot = dashboard_snapshot(cfg)
    print("\n".join(dashboard_lines(cfg, snapshot, color=color, realtime=False)))
    print()
    print("\n".join(home_action_lines(cfg, color)))


def print_lifecycle_versions(cfg: ConsoleConfig, snapshot: LifecycleSnapshot, color: bool) -> None:
    print(bold(tr(cfg, "lifecycle.title"), color))
    print(lifecycle_summary_text(cfg, snapshot))
    if snapshot.promotion_blockers:
        print(tr(cfg, "lifecycle.blockers"))
        for blocker in snapshot.promotion_blockers:
            print(f"- {blocker}")
    print()
    for index, version in enumerate(snapshot.versions, start=1):
        print(f"  {cyan(str(index), color)}  {lifecycle_version_line(cfg, version)}")


def version_lifecycle_lines(cfg: ConsoleConfig, version: VersionLifecycle, color: bool) -> list[str]:
    lines = [
        bold(tr(cfg, "lifecycle.version_title", version=version.version_id), color),
        tr(cfg, "lifecycle.version_status", status=version.status, title=version.title),
        tr(cfg, "lifecycle.version_queue", local=version.local_queue, live=version.live_queue or "none", mapping=version.live_mapping),
        "",
        tr(cfg, "lifecycle.stages"),
    ]
    for stage in LIFECYCLE_STAGES:
        lines.append(f"  - {stage}: {version.stage_statuses.get(stage, 'unknown')}")
    lines.extend(
        [
            "",
            tr(cfg, "lifecycle.safe_actions"),
            "  1  ./dev workflow status",
            "  2  ./dev workflow doctor",
            f"  3  ./dev workflow discuss --version {version.version_id} preview",
            f"  4  ./dev workflow plan --version {version.version_id}",
            f"  5  ./dev workflow queue --version {version.version_id}",
            f"  6  ./dev workflow promote --version {version.version_id} --preview",
            f"  7  ./dev workflow init --version <vN>",
            "",
            dim(tr(cfg, "lifecycle.safe_note"), color),
        ]
    )
    return lines


def run_lifecycle_command(cfg: ConsoleConfig, version: VersionLifecycle, choice: str) -> int:
    commands = {
        "1": ["workflow", "status"],
        "2": ["workflow", "doctor"],
        "3": ["workflow", "discuss", "--version", version.version_id, "preview"],
        "4": ["workflow", "plan", "--version", version.version_id],
        "5": ["workflow", "queue", "--version", version.version_id],
        "6": ["workflow", "promote", "--version", version.version_id, "--preview"],
    }
    command = commands.get(choice)
    if command:
        return dev_tools_cli.main(command)
    if choice == "7":
        if not sys.stdin.isatty():
            print(tr(cfg, "lifecycle.init_hint"))
            return 0
        version_id = input(tr(cfg, "lifecycle.version_prompt")).strip()
        if not version_id:
            return 0
        return dev_tools_cli.main(["workflow", "init", "--version", version_id])
    print(tr(cfg, "error.unknown_option", choice=choice))
    return 1


def show_version_lifecycle(cfg: ConsoleConfig, version: VersionLifecycle) -> int:
    color = color_enabled(cfg.color_mode)
    if not sys.stdin.isatty():
        print("\n".join(version_lifecycle_lines(cfg, version, color)))
        return 0
    while True:
        print_banner(cfg)
        print("\n".join(version_lifecycle_lines(cfg, version, color)))
        choice = input("\n" + tr(cfg, "prompt.selection")).strip()
        if choice in {"0", "q", "back"}:
            return 0
        run_lifecycle_command(cfg, version, choice)
        pause(cfg)


def show_lifecycle_menu(cfg: ConsoleConfig) -> int:
    color = color_enabled(cfg.color_mode)
    snapshot = load_lifecycle_snapshot(cfg.runtime.root_dir)
    if not sys.stdin.isatty():
        print_lifecycle_versions(cfg, snapshot, color)
        print("")
        print(tr(cfg, "lifecycle.noninteractive_hint"))
        return 0
    while True:
        print_banner(cfg)
        print_lifecycle_versions(cfg, snapshot, color)
        print(f"  {cyan('n', color)}  {tr(cfg, 'lifecycle.new_version')}")
        print(f"  {cyan('0', color)}  {tr(cfg, 'submenu.back.label')}")
        choice = input("\n" + tr(cfg, "prompt.selection")).strip()
        if choice in {"0", "q", "back"}:
            return 0
        if choice == "n":
            run_lifecycle_command(cfg, snapshot.versions[0] if snapshot.versions else VersionLifecycle("", "", "", (), "", "", "", "", "", "", 0, 0, 0, 0, 0, {}), "7")
            pause(cfg)
            continue
        if choice.isdigit() and 1 <= int(choice) <= len(snapshot.versions):
            show_version_lifecycle(cfg, snapshot.versions[int(choice) - 1])
            snapshot = load_lifecycle_snapshot(cfg.runtime.root_dir)
            continue
        print(tr(cfg, "error.unknown_option", choice=choice))
        pause(cfg)


def print_help(cfg: ConsoleConfig | None = None) -> None:
    print_banner(cfg)
    lang = cfg.lang_mode if cfg else banner_lang()
    print("\n".join(t_lines(lang, "help.lines")))


def quick_continue(cfg: ConsoleConfig) -> int:
    snapshot = dashboard_snapshot(cfg)
    if snapshot.lock["exists"] and snapshot.lock["alive"]:
        print_banner(cfg)
        print(tr(cfg, "guard.quick_live.line1"))
        print(tr(cfg, "guard.quick_live.line2"))
        return 1
    if snapshot.git_dirty and env_value("GIT_CHECKPOINT", cfg.runtime.git_checkpoint) != "off":
        print_banner(cfg)
        print(tr(cfg, "dirty_continue.line1"))
        print(tr(cfg, "dirty_continue.line2"))
        print(tr(cfg, "dirty_continue.line3"))
        print(tr(cfg, "dirty_continue.line4"))
        if snapshot.stale_count:
            print(tr(cfg, "dirty_continue.stale"))
        elif snapshot.progress_counts.get("failed", 0):
            print(tr(cfg, "dirty_continue.failed"))
        else:
            print(tr(cfg, "dirty_continue.run"))
        return 1
    if snapshot.stale_count:
        return start_with_wizard(cfg, "resume-stale")
    if snapshot.progress_counts.get("failed", 0):
        return start_with_wizard(cfg, "resume-failed")
    return start_with_wizard(cfg, "run")


def show_interruption_recovery(cfg: ConsoleConfig) -> int:
    print_banner(cfg)
    print_lines(cfg, "recovery.interruption.lines")
    print_status_compact(cfg)
    return 0


def shortcut_key_text(shortcuts: Sequence[str]) -> str:
    return ", ".join("Enter" if item == "" else item for item in shortcuts)


def show_shortcuts_help(cfg: ConsoleConfig) -> int:
    print_banner(cfg)
    color = color_enabled(cfg.color_mode)
    rows = [
        (shortcut_key_text(spec.shortcuts), action_label(cfg, action_id), action_note(cfg, action_id))
        for action_id, spec in ACTIONS.items()
        if spec.shortcuts
    ]
    width = max(12, *(len(keys) for keys, _, _ in rows))
    print(bold(tr(cfg, "shortcuts.title"), color))
    for keys, label, note in rows:
        print(f"  {cyan(keys, color):<{width}}  {label:<24} {dim(note, color)}")
    print("")
    print(dim(tr(cfg, "shortcuts.footer", mode=cfg.lang_mode), color))
    return 0


def show_language_menu(cfg: ConsoleConfig) -> int:
    color = color_enabled(cfg.color_mode)
    options = [("1", "mixed", tr(cfg, "language.option.mixed")), ("2", "zh", tr(cfg, "language.option.zh")), ("3", "en", tr(cfg, "language.option.en"))]
    if not sys.stdin.isatty():
        print_banner(cfg)
        print(tr(cfg, "language.current", mode=cfg.lang_mode))
        print(tr(cfg, "language.config_path", path=dev_config.config_path(cfg.runtime.root_dir)))
        for key, lang, note in options:
            print(f"  {key}  {lang:<5} {note}")
        print(tr(cfg, "language.command_hint"))
        return 0
    while True:
        print_banner(cfg)
        print(bold(tr(cfg, "language.title"), color))
        print(tr(cfg, "language.current", mode=cfg.lang_mode))
        for key, lang, note in options:
            print(f"  {cyan(key, color)}  {lang:<5} {dim(note, color)}")
        choice = input("\n" + tr(cfg, "prompt.selection")).strip()
        if choice in {"0", "q", "back"}:
            return 0
        selected = {"1": "mixed", "2": "zh", "3": "en", "mixed": "mixed", "zh": "zh", "en": "en"}.get(choice)
        if not selected:
            print(tr(cfg, "error.unknown_option", choice=choice))
            pause(cfg)
            continue
        cfg.lang_mode = selected
        dev_config.save_lang_mode(cfg.runtime.root_dir, selected)
        print(tr(cfg, "language.saved", mode=cfg.lang_mode, path=dev_config.config_path(cfg.runtime.root_dir)))
        return 0


def run_action(cfg: ConsoleConfig, action_id: str, args: Sequence[str] = ()) -> int:
    if action_id == "full-status":
        return show_status_verbose(cfg)
    if action_id == "recommended-next":
        return show_recommended_guide(cfg)
    if action_id == "lifecycle-menu":
        return show_lifecycle_menu(cfg)
    if action_id == "live-queue-menu":
        return submenu_loop(cfg, "live_queue")
    if action_id == "quick-continue":
        return quick_continue(cfg)
    if action_id == "tools-menu":
        return submenu_loop(cfg, "tools")
    if action_id == "language-menu":
        return show_language_menu(cfg)
    if action_id == "shortcuts-help":
        return show_shortcuts_help(cfg)
    if action_id == "help":
        print_help(cfg)
        return 0
    if action_id == "quit":
        return 0
    if action_id == "start":
        return start_with_wizard(cfg, "run")
    if action_id == "resume-stale":
        return start_with_wizard(cfg, "resume-stale")
    if action_id == "resume-failed":
        return start_with_wizard(cfg, "resume-failed")
    if action_id == "drain":
        return request_drain(cfg)
    if action_id == "logs":
        return show_latest_console_log(cfg)
    if action_id == "verify-summary":
        print_banner(cfg)
        show_latest_failure_summary(cfg)
        return 0
    if action_id == "preflight":
        return show_preflight(cfg)
    if action_id == "preview":
        return preview_with_wizard(cfg)
    if action_id == "dry-run":
        return run_temp_dry_run(cfg)
    if action_id == "processes":
        show_processes(cfg)
        return 0
    if action_id == "compact":
        print_banner(cfg)
        print_status_compact(cfg)
        show_processes(cfg)
        return 0
    if action_id == "clear-stale":
        return clear_stale(cfg)
    if action_id == "reset-progress":
        return reset_progress(cfg)
    if action_id == "interrupted-help":
        return show_interruption_recovery(cfg)
    if action_id == "maintenance-menu":
        return submenu_loop(cfg, "maintenance")
    if action_id == "new-version-preview":
        return dev_tools_cli.main(["workflow", "init", "--version", "v3"])
    if action_id == "workflow-status":
        return dev_tools_cli.main(["workflow", "status"])
    if action_id == "workflow-doctor":
        return dev_tools_cli.main(["workflow", "doctor"])
    if action_id == "changes-preview":
        return dev_tools_cli.main(["changes", "preview"])
    spec = ACTIONS[action_id]
    if spec.passthrough:
        return dev_tools_cli.main([spec.command, *args])
    raise KeyError(f"unhandled action: {action_id}")


def submenu_loop(cfg: ConsoleConfig, menu_id: str) -> int:
    color = color_enabled(cfg.color_mode)
    if not sys.stdin.isatty():
        print("\n".join(submenu_lines(cfg, menu_id, color)))
        return 0
    while True:
        print_banner(cfg)
        print("\n".join(submenu_lines(cfg, menu_id, color)))
        choice = input("\n" + tr(cfg, "prompt.selection")).strip()
        if choice in {"0", "q", "back"}:
            return 0
        if choice == "?":
            show_shortcuts_help(cfg)
            pause(cfg)
            continue
        if choice == "lang":
            show_language_menu(cfg)
            continue
        action_ids = MENUS[menu_id].action_ids
        keyed = {menu_key(action_id, index): action_id for index, action_id in enumerate(action_ids, start=1)}
        action_id = keyed.get(choice)
        if not action_id:
            shortcut_action = SHORTCUT_ALIASES.get(choice)
            if shortcut_action in action_ids:
                action_id = shortcut_action
        if not action_id:
            print(tr(cfg, "error.unknown_option", choice=choice))
            pause(cfg)
            continue
        return run_action(cfg, action_id)


def interactive_loop(cfg: ConsoleConfig) -> int:
    if not sys.stdin.isatty():
        print_menu(cfg)
        return 0
    while True:
        print_menu(cfg)
        choice = input("\n" + tr(cfg, "prompt.selection")).strip()
        action_id = SHORTCUT_ALIASES.get(choice)
        if action_id == "quit":
            return 0
        if action_id:
            run_action(cfg, action_id)
        else:
            print(tr(cfg, "error.unknown_option", choice=choice))
        pause(cfg)


def main(argv: Sequence[str] | None = None) -> int:
    try:
        parsed = parse_global_args(list(argv or sys.argv[1:]))
    except DevArgError as exc:
        message = t(exc.lang_mode, f"error.{exc.key}")
        print(t(exc.lang_mode, "error.prefix", message=message), file=sys.stderr)
        return 2
    except ValueError as exc:
        lang = normalize_lang_mode(os.environ.get("DEV_LANG", "mixed"))
        print(t(lang, "error.prefix", message=str(exc)), file=sys.stderr)
        return 2
    args = parsed.command_args
    command = args[0] if args else "menu"
    cfg = ConsoleConfig.from_env()
    cfg.color_mode = parsed.color_mode
    cfg.lang_mode = resolve_lang_mode(cfg.runtime.root_dir, parsed.lang_mode)
    if command in {"", "menu"}:
        if parsed.once:
            print_menu(cfg)
            return 0
        return interactive_loop(cfg)
    action_id = COMMAND_ALIASES.get(command)
    if action_id == "status":
        status_args = parse_status_args(args[1:], cfg.lang_mode)
        if status_args.color:
            cfg.color_mode = status_args.color
        if status_args.lang:
            cfg.lang_mode = status_args.lang
        if status_args.verbose:
            return show_status_verbose(cfg)
        return show_status_dashboard(
            cfg,
            refresh_seconds=max(status_args.refresh, 0.5),
            once=status_args.once or parsed.once,
            no_color=status_args.no_color,
        )
    if action_id:
        return run_action(cfg, action_id, args[1:])
    print(tr(cfg, "error.unknown_command", command=command), file=sys.stderr)
    print_help(cfg)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
