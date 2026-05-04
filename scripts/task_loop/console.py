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

from . import state
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
    once: bool


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


@dataclass
class DashboardSnapshot:
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
                raise ValueError("--color requires always, never, or auto")
            color_mode = normalize_color_mode(remaining[index + 1])
            index += 2
            continue
        if value.startswith("--color="):
            color_mode = normalize_color_mode(value.split("=", 1)[1])
            index += 1
            continue
        command_args.extend(remaining[index:])
        break
    return DevArgs(command_args=command_args, color_mode=color_mode, once=once)


def print_banner() -> None:
    if sys.stdout.isatty() and os.environ.get("TERM"):
        subprocess.run(["clear"], check=False)
    print(
        """============================================================
        AreaMatrix Task Loop 控制台
============================================================"""
    )


def pause() -> None:
    if not sys.stdin.isatty():
        return
    input("\n按 Enter 返回菜单...")


def confirm(prompt: str) -> bool:
    if env_value("CONFIRM") == "1":
        return True
    if not sys.stdin.isatty():
        return False
    answer = input(f"{prompt} [y/N] ").strip().lower()
    return answer in {"y", "yes"}


def ps_lines() -> list[str]:
    proc = subprocess.run(
        ["ps", "-axo", "pid=,ppid=,stat=,command="],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return [line for line in proc.stdout.splitlines() if line.strip()]


def runner_processes(cfg: ConsoleConfig) -> list[str]:
    root = str(cfg.runtime.root_dir)
    lines = []
    for line in ps_lines():
        if "codex exec" in line:
            continue
        if "task-loop" in line and (" run" in line or " resume-" in line) and root in line:
            lines.append(line)
    return lines


def codex_processes() -> list[str]:
    return [line for line in ps_lines() if "codex exec" in line]


def repo_codex_processes(cfg: ConsoleConfig) -> list[str]:
    root = str(cfg.runtime.root_dir)
    return [line for line in codex_processes() if root in line]


def process_snapshot(cfg: ConsoleConfig) -> ProcessSnapshot:
    return ProcessSnapshot(
        runners=runner_processes(cfg),
        repo_codex=repo_codex_processes(cfg),
        host_codex=codex_processes(),
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
    print("\n进程快照")
    print(f"- task-loop runner: {len(runners)}")
    print(f"- AreaMatrix codex exec: {len(repo_codex)}")
    print(f"- host codex exec: {len(host_codex)}")
    if runners:
        print("\nrunner:")
        print("\n".join(runners))
    if repo_codex:
        print("\nAreaMatrix codex exec:")
        print("\n".join(repo_codex))
    if host_codex:
        print("\nhost codex exec:")
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


def process_summary_line(cfg: ConsoleConfig, snapshot: ProcessSnapshot) -> str:
    other = [line for line in snapshot.host_codex if line not in snapshot.repo_codex]
    summary = (
        f"runner={len(snapshot.runners)} | "
        f"AreaMatrix codex={len(snapshot.repo_codex)} | "
        f"other codex={len(other)}"
    )
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

    print("\n当前任务")
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
        print("- none")

    index = read_json(cfg.runtime.run_summary_root / "index.json", {"runs": []})
    runs = index.get("runs", []) if isinstance(index, dict) else []
    print("\n最近 run")
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
    print("\n最近 verify 摘要")
    latest = latest_verify_log(cfg.runtime.log_root)
    if not latest:
        print("- 暂无 verify 日志。")
        return
    print(f"- log: {latest}")
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
    print("\n恢复建议")
    if re.search(r"stale_in_progress: [1-9]", output):
        print("- 存在 stale：优先选“从 stale 任务继续”或运行 ./dev resume-stale。")
    if re.search(r"^- failed: ", output, flags=re.MULTILINE):
        print("- 存在 failed：先看最近 verify 摘要，再选“从 failed 任务继续”或运行 ./dev resume-failed。")
    if re.search(r"^- blocked: ", output, flags=re.MULTILINE):
        print("- 存在 blocked：检查风险门禁，确认后用 allow 模式从对应 task 继续。")
    if live_runner_active(cfg):
        print("- 当前已有 live runner；不要启动第二个。需要停机请选“一键优雅收尾”或运行 ./dev drain。")
    if git_dirty(cfg.runtime.root_dir):
        print("- 工作区非干净；commit/push checkpoint 模式启动前会被 Git gate 拦截。可先查看 git status。")


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


def dashboard_lines(cfg: ConsoleConfig, snapshot: DashboardSnapshot, *, color: bool, realtime: bool) -> list[str]:
    state_name, state_color = runner_state(snapshot)
    prompt = snapshot.prompt
    percent = (prompt.completed / prompt.total * 100) if prompt.total else 0.0
    latest_run = snapshot.latest_run or {}
    latest_status = latest_run.get("status", "none")
    latest_run_id = latest_run.get("run_id", "")
    latest_completed = latest_run.get("completed", 0)
    latest_retries = latest_run.get("retries", 0)
    task_line = "none"
    if snapshot.interesting_task:
        label, entry = snapshot.interesting_task
        task_line = f"{label} ({entry.get('status', 'unknown')}, attempts={entry.get('attempts', 0)})"

    lines = [
        bold("AreaMatrix Task Loop", color),
        f"{dim('captured', color)} {snapshot.captured_at.strftime('%Y-%m-%d %H:%M:%S')}    "
        f"{dim('mode', color)} {'realtime 5s' if realtime else 'snapshot'}    "
        f"{dim('exit', color)} Ctrl+C",
        "",
        f"{bold('状态', color)} {status_badge(state_name, state_color, color)} "
        f"{process_summary_line(cfg, snapshot.process)}",
        f"{bold('进度', color)} {prompt.completed}/{prompt.total} completed  {prompt.pending} pending  {percent:.1f}%",
        f"      {render_progress_bar(prompt.completed, prompt.total, color)}",
        f"{bold('下一任务', color)} {cyan(prompt.first_ready, color) if prompt.first_ready not in {'None', 'unknown'} else prompt.first_ready}",
        f"{bold('当前任务', color)} {task_line}",
        f"{bold('锁 / stale', color)} lock={'live' if snapshot.lock['exists'] and snapshot.lock['alive'] else 'none'} "
        f"stale={snapshot.stale_count} drain={'yes' if snapshot.drain_requested else 'no'}",
        f"{bold('最近 run', color)} {latest_run_id or 'none'} status={latest_status} completed={latest_completed} retries={latest_retries}",
        f"{bold('最近 verify', color)} {verify_text(snapshot.latest_verify_result, color)} "
        f"{dim(rel_path(cfg.runtime.root_dir, snapshot.latest_verify_log), color)}",
        f"{bold('日志', color)} {rel_path(cfg.runtime.root_dir, snapshot.latest_log_dir)}",
    ]
    if prompt.error:
        lines.append(f"{bold('prompt 状态', color)} {yellow('fallback', color)} {prompt.error}")

    suggestions = dashboard_suggestions(cfg, snapshot)
    lines.append("")
    lines.append(bold("下一步建议", color))
    lines.extend([f"- {item}" for item in suggestions])
    lines.append("")
    lines.append(dim("详细长输出：./dev status --verbose；一次性快照：./dev status --once。", color))
    return lines


def dashboard_suggestions(cfg: ConsoleConfig, snapshot: DashboardSnapshot) -> list[str]:
    suggestions: list[str] = []
    if snapshot.lock["exists"] and snapshot.lock["alive"]:
        suggestions.append("一键优雅收尾：./dev drain  当前 task 完成、验收和 checkpoint 后停止")
    if snapshot.stale_count:
        suggestions.append("从 stale 任务继续：./dev resume-stale")
    if snapshot.progress_counts.get("failed", 0):
        suggestions.append("从 failed 任务继续：./dev resume-failed")
    if snapshot.progress_counts.get("blocked", 0):
        suggestions.append("blocked 授权继续：RISK_POLICY=allow START_FROM=<label> ./task-loop run")
    if snapshot.git_dirty:
        suggestions.append("git status --short  先收口工作区，避免 Git checkpoint gate 拦截")
    if not suggestions:
        suggestions.append("RISK_POLICY=allow MAX_RETRIES=0 ./task-loop run  无限继续当前队列")
    suggestions.append("./dev preflight  启动前检查 Git、锁、进程和恢复建议")
    if snapshot.latest_verify_log:
        suggestions.append("./dev verify-summary  查看最近 verify 摘要")
    return suggestions


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
    print_banner()
    print("Preflight")
    print(f"- root: {cfg.runtime.root_dir}")
    branch = subprocess.run(["git", "branch", "--show-current"], cwd=cfg.runtime.root_dir, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
    remote = subprocess.run(["git", "remote", "get-url", "origin"], cwd=cfg.runtime.root_dir, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
    print(f"- branch: {branch.stdout.strip() or 'unknown'}")
    print(f"- remote: {remote.stdout.strip() or 'none'}")
    if git_dirty(cfg.runtime.root_dir):
        print("- worktree: dirty")
        status = subprocess.run(["git", "status", "--short"], cwd=cfg.runtime.root_dir, text=True, stdout=subprocess.PIPE, check=False)
        print("\n".join(status.stdout.splitlines()[:20]))
    else:
        print("- worktree: clean")
    print()
    print_status_compact(cfg)
    show_processes(cfg)
    show_recovery_hints(cfg)
    return 0


def show_status_verbose(cfg: ConsoleConfig) -> int:
    print_banner()
    print_loop_status(cfg.runtime)
    show_processes(cfg)
    show_latest_task_details(cfg)
    show_latest_failure_summary(cfg)
    show_recovery_hints(cfg)
    return 0


def guard_no_live_runner(cfg: ConsoleConfig) -> bool:
    if not live_runner_active(cfg):
        return True
    print_banner()
    print("已有 live runner，已阻止启动第二个 runner。\n")
    print_status_compact(cfg)
    show_processes(cfg)
    print("\n可选操作：")
    print("  ./dev drain   请求当前 task 完成并 checkpoint 后停止")
    print("  ./dev status  查看详细状态和日志")
    return False


def choose_execution_mode() -> str:
    value = env_value("EXECUTION_MODE")
    if value in {"foreground", "background"}:
        return value
    if not sys.stdin.isatty():
        return "background"
    print("\n执行方式：\n  1) 后台运行\n  2) 前台运行")
    answer = input("> ").strip()
    return "foreground" if answer in {"2", "foreground"} else "background"


def choose_git_mode() -> str:
    value = env_value("GIT_CHECKPOINT")
    if value:
        return value
    if not sys.stdin.isatty():
        return "commit"
    print("\nGit checkpoint：\n  1) 本地 commit（默认）\n  2) commit + push\n  3) off（仅诊断）")
    answer = input("> ").strip()
    if answer in {"2", "push"}:
        return "push"
    if answer in {"3", "off"}:
        return "off"
    return "commit"


def choose_max_tasks() -> str:
    value = env_value("MAX_TASKS")
    if value:
        return value
    if not sys.stdin.isatty():
        return "0"
    print("\n任务数量上限：\n  1) 无限（默认）\n  2) 1 个\n  3) 5 个\n  4) 20 个\n  5) 自定义 N")
    answer = input("> ").strip()
    if answer == "2":
        return "1"
    if answer == "3":
        return "5"
    if answer == "4":
        return "20"
    if answer == "5":
        custom = input("N=").strip()
        return custom if custom.isdigit() else "0"
    return "0"


def choose_stop_target() -> tuple[str, str]:
    phase = env_value("PHASE")
    stop_after = env_value("STOP_AFTER")
    if phase or stop_after or not sys.stdin.isatty():
        return phase, stop_after
    print("\n停止点：\n  1) 不限制（默认）\n  2) 只跑某个 phase\n  3) 跑到某个 task 后停止")
    answer = input("> ").strip()
    if answer == "2":
        return input("phase=").strip(), ""
    if answer == "3":
        return "", input("task label=").strip()
    return "", ""


def base_env(cfg: ConsoleConfig, git_mode: str) -> tuple[dict[str, str], list[str]]:
    values = {
        "RISK_POLICY": "allow",
        "MAX_RETRIES": "0",
        "GIT_CHECKPOINT": git_mode,
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
    execution_mode = choose_execution_mode()
    git_mode = choose_git_mode()
    max_tasks = choose_max_tasks()
    phase, stop_after = choose_stop_target()
    env, env_bits = base_env(cfg, git_mode)
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


def print_command_preview(command: RunnerCommand) -> None:
    print("\n即将执行：" + shlex.join(["env", *command.env_bits, *command.argv]))
    print(f"执行方式：{command.execution_mode}")


def run_runner_command(cfg: ConsoleConfig, command: RunnerCommand) -> int:
    cfg.console_log_root.mkdir(parents=True, exist_ok=True)
    print_command_preview(command)
    if command.execution_mode == "foreground":
        return subprocess.run(command.argv, env=command.env, check=False).returncode
    log_file = cfg.console_log_root / f"task-loop-{timestamp()}.log"
    with log_file.open("w", encoding="utf-8") as stream:
        proc = subprocess.Popen(command.argv, env=command.env, stdout=stream, stderr=subprocess.STDOUT)
    (cfg.console_log_root / "last-task-loop.pid").write_text(f"{proc.pid}\n", encoding="utf-8")
    print(f"已后台启动：pid={proc.pid}")
    print(f"控制台日志：{log_file}")
    print("任务详细日志仍写入 .codex/task-loop-logs/<run_id>/...")
    return 0


def start_with_wizard(cfg: ConsoleConfig, subcommand: str) -> int:
    if not guard_no_live_runner(cfg):
        return 1
    return run_runner_command(cfg, build_runner_command(cfg, subcommand, []))


def preview_with_wizard(cfg: ConsoleConfig) -> int:
    command = build_runner_command(cfg, "run", [])
    print_command_preview(command)
    if live_runner_active(cfg):
        print("注意：当前已有 live runner；这里只是预览，没有启动第二个 runner。")
    print("未执行。")
    return 0


def run_temp_dry_run(cfg: ConsoleConfig) -> int:
    with tempfile.TemporaryDirectory(prefix="areamatrix-task-loop-") as tmp:
        tmp_dir = Path(tmp)
        print(f"临时 dry-run 目录：{tmp_dir}")
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
                "RISK_POLICY": "allow",
                "MAX_RETRIES": "0",
                "DRY_RUN_RESULT": env_value("DRY_RUN_RESULT", "PASS"),
            }
        )
        max_tasks = env_value("MAX_TASKS", "1")
        argv = [str(cfg.task_loop_bin), "run", "--dry-run", "--max-tasks", max_tasks]
        if env_value("PHASE"):
            argv.extend(["--phase", env_value("PHASE")])
        rc = subprocess.run(argv, env=env, check=False).returncode
        if rc == 0:
            print("\n临时 dry-run 完成，真实 progress/logs 未修改。")
        return rc


def request_drain(cfg: ConsoleConfig) -> int:
    if not live_runner_active(cfg):
        print("当前没有 live runner，无法请求优雅收尾。")
        return 1
    env, _ = base_env(cfg, cfg.runtime.git_checkpoint)
    return subprocess.run([str(cfg.task_loop_bin), "drain"], env=env, check=False).returncode


def run_health_checks(cfg: ConsoleConfig) -> int:
    return dev_tools_cli.main(["check"])


def parse_status_args(args: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="./dev status", description="Show AreaMatrix task-loop status")
    parser.add_argument("--verbose", action="store_true", help="Show the full legacy status report")
    parser.add_argument("--once", action="store_true", help="Render one compact dashboard snapshot and exit")
    parser.add_argument("--refresh", type=float, default=5.0, help="TUI refresh interval in seconds")
    parser.add_argument("--color", choices=["always", "never", "auto"], help="Color mode; overrides DEV_COLOR")
    parser.add_argument("--no-color", action="store_true", help="Disable ANSI color")
    return parser.parse_args(list(args))


def show_latest_console_log(cfg: ConsoleConfig) -> int:
    print_banner()
    logs = sorted(cfg.console_log_root.glob("*.log")) if cfg.console_log_root.exists() else []
    if not logs:
        print("暂无控制台后台日志。")
        return 0
    latest = logs[-1]
    print(f"latest: {latest}\n")
    print("\n".join(latest.read_text(encoding="utf-8", errors="replace").splitlines()[-100:]))
    return 0


def clear_stale(cfg: ConsoleConfig) -> int:
    if not confirm("确认只清理 stale in_progress 记录？该操作会先备份 progress.json。"):
        print("已取消。")
        return 1
    env, _ = base_env(cfg, cfg.runtime.git_checkpoint)
    return subprocess.run([str(cfg.task_loop_bin), "clear-stale"], env=env, check=False).returncode


def reset_progress(cfg: ConsoleConfig) -> int:
    print("高风险操作：这会备份并清空 progress.json，从 0 开始。")
    if env_value("RESET_CONFIRM") != "RESET" and (not sys.stdin.isatty() or input("请输入 RESET 确认：").strip() != "RESET"):
        print("已取消。")
        return 1
    env, _ = base_env(cfg, cfg.runtime.git_checkpoint)
    return subprocess.run([str(cfg.task_loop_bin), "reset-progress"], env=env, check=False).returncode


def clear_screen() -> None:
    if sys.stdout.isatty() and os.environ.get("TERM"):
        print("\033[2J\033[H", end="")


def shortcut_lines(color: bool) -> list[str]:
    normal = [
        ("s", "start", "从下一个 pending 继续"),
        ("p", "preflight", "启动前检查"),
        ("v", "preview", "预览命令，不执行"),
        ("d", "dry-run", "临时演练，不写真实 progress"),
        ("r", "resume-stale", "恢复 stale"),
        ("f", "resume-failed", "恢复 failed"),
        ("g", "drain", "优雅收尾"),
        ("l", "logs", "后台日志"),
        ("y", "verify-summary", "最近 verify"),
        ("c", "check", "doctor + task-loop 自检"),
        ("x", "processes", "完整进程"),
        ("h", "help", "帮助"),
        ("q", "quit", "退出"),
    ]
    lines = [bold("快捷键", color)]
    for key, command, note in normal:
        lines.append(f"  {cyan(key, color)}  {command:<15} {dim(note, color)}")
    lines.append("")
    lines.append(red("危险操作", color))
    lines.append(f"  {yellow('clear-stale', color):<15}  清理 stale in_progress（会备份 progress）")
    lines.append(f"  {red('reset-progress', color):<15}  重置 progress 从 0 开始（需输入 RESET）")
    lines.append("")
    lines.append(dim("旧数字键仍可用；完整长状态：./dev status --verbose；关闭颜色：./dev --color never。", color))
    return lines


def print_menu(cfg: ConsoleConfig) -> None:
    color = color_enabled(cfg.color_mode)
    clear_screen()
    snapshot = dashboard_snapshot(cfg)
    print("\n".join(dashboard_lines(cfg, snapshot, color=color, realtime=False)))
    print()
    print("\n".join(shortcut_lines(color)))


def print_help() -> None:
    print_banner()
    print(
        """常用理解：
- ./dev 默认是彩色首页：状态看板 + 快捷键。
- stale 继续：用于关机、强停、断电后恢复半截任务。
- 优雅收尾：用于 runner 正在执行时，请求它做完当前 task、完成 verify 和 Git checkpoint 后停止。
- Git 默认：commit；需要上传时启动向导里选择 commit + push。
- 任务数默认：无限；启动向导可选 1、5、20 或自定义。
- 已有 live runner 时，控制台会阻止启动第二个 runner。
- 颜色默认强制开启；可用 ./dev --color never 或 NO_COLOR=1 关闭。

快捷命令：
  ./dev --once
  ./dev --color always --once
  ./dev --color never --once
  ./dev status
  ./dev status --color always --once
  ./dev status --verbose
  ./dev compact
  ./dev preflight
  ./dev preview
  ./dev dry-run
  ./dev resume-stale
  ./dev resume-failed
  ./dev start
  ./dev drain
  ./dev logs
  ./dev verify-summary
  ./dev check
  ./dev changes doctor
  ./dev changes preview"""
    )


def interactive_loop(cfg: ConsoleConfig) -> int:
    if not sys.stdin.isatty():
        print_menu(cfg)
        return 0
    while True:
        print_menu(cfg)
        choice = input("\n> ").strip()
        if choice in {"1", ""}:
            show_status_verbose(cfg)
        elif choice == "2":
            show_preflight(cfg)
        elif choice == "3":
            preview_with_wizard(cfg)
        elif choice == "4":
            run_temp_dry_run(cfg)
        elif choice == "5":
            start_with_wizard(cfg, "resume-stale")
        elif choice == "6":
            start_with_wizard(cfg, "resume-failed")
        elif choice == "7":
            start_with_wizard(cfg, "run")
        elif choice == "8":
            request_drain(cfg)
        elif choice == "9":
            show_latest_console_log(cfg)
        elif choice == "10":
            print_banner()
            show_latest_failure_summary(cfg)
        elif choice == "11":
            run_health_checks(cfg)
        elif choice == "12":
            clear_stale(cfg)
        elif choice == "13":
            reset_progress(cfg)
        elif choice == "s":
            start_with_wizard(cfg, "run")
        elif choice == "p":
            show_preflight(cfg)
        elif choice == "v":
            preview_with_wizard(cfg)
        elif choice == "d":
            run_temp_dry_run(cfg)
        elif choice == "r":
            start_with_wizard(cfg, "resume-stale")
        elif choice == "f":
            start_with_wizard(cfg, "resume-failed")
        elif choice == "g":
            request_drain(cfg)
        elif choice == "l":
            show_latest_console_log(cfg)
        elif choice == "y":
            print_banner()
            show_latest_failure_summary(cfg)
        elif choice == "c":
            run_health_checks(cfg)
        elif choice == "x":
            print_banner()
            show_processes(cfg)
        elif choice == "clear-stale":
            clear_stale(cfg)
        elif choice == "reset-progress":
            reset_progress(cfg)
        elif choice in {"h", "help"}:
            print_help()
        elif choice in {"q", "quit", "exit", "0"}:
            return 0
        else:
            print(f"未知选项：{choice}")
        pause()


def main(argv: Sequence[str] | None = None) -> int:
    try:
        parsed = parse_global_args(list(argv or sys.argv[1:]))
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    args = parsed.command_args
    command = args[0] if args else "menu"
    cfg = ConsoleConfig.from_env()
    cfg.color_mode = parsed.color_mode
    if command in {"", "menu"}:
        if parsed.once:
            print_menu(cfg)
            return 0
        return interactive_loop(cfg)
    if command == "status":
        status_args = parse_status_args(args[1:])
        if status_args.color:
            cfg.color_mode = status_args.color
        if status_args.verbose:
            return show_status_verbose(cfg)
        return show_status_dashboard(
            cfg,
            refresh_seconds=max(status_args.refresh, 0.5),
            once=status_args.once or parsed.once,
            no_color=status_args.no_color,
        )
    if command == "compact":
        print_banner()
        print_status_compact(cfg)
        show_processes(cfg)
        return 0
    if command == "preflight":
        return show_preflight(cfg)
    if command == "preview":
        return preview_with_wizard(cfg)
    if command == "dry-run":
        return run_temp_dry_run(cfg)
    if command in {"processes", "ps"}:
        show_processes(cfg)
        return 0
    if command == "resume-stale":
        return start_with_wizard(cfg, "resume-stale")
    if command == "resume-failed":
        return start_with_wizard(cfg, "resume-failed")
    if command == "start":
        return start_with_wizard(cfg, "run")
    if command == "drain":
        return request_drain(cfg)
    if command == "logs":
        return show_latest_console_log(cfg)
    if command == "verify-summary":
        print_banner()
        show_latest_failure_summary(cfg)
        return 0
    if command == "check":
        return dev_tools_cli.main(["check", *args[1:]])
    if command in {"build", "test", "bindings", "changes"}:
        return dev_tools_cli.main(args)
    if command in {"help", "-h", "--help"}:
        print_help()
        return 0
    print(f"未知命令：{command}\n", file=sys.stderr)
    print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
