"""Python implementation of the AreaMatrix copy-ready / verify-ready task loop."""

from __future__ import annotations

import argparse
import atexit
import os
import re
import signal
import shlex
import shutil
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Sequence

from . import git as git_helpers
from . import state


PHASES = ("phase-0", "phase-1", "phase-2", "phase-3", "phase-4")
CODEX_SANDBOX_MODES = {"read-only", "workspace-write", "danger-full-access"}


class TaskLoopError(RuntimeError):
    def __init__(self, message: str, code: int = 1) -> None:
        super().__init__(message)
        self.code = code


class CodexNoOutputTimeout(TaskLoopError):
    pass


class CodexNoOutputTimeoutLimit(TaskLoopError):
    pass


class CodexOrphanError(TaskLoopError):
    pass


@dataclass
class TaskFile:
    phase: str
    task_name: str
    label: str
    copy_file: Path
    verify_file: Path
    risk: str


@dataclass
class RuntimeConfig:
    root_dir: Path
    python_bin: str = "python3"
    model: str = "gpt-5.5"
    model_reasoning_effort: str = "xhigh"
    codex_bin: str = ""
    codex_bin_resolved: str = ""
    codex_exec_sandbox: str = "danger-full-access"
    copy_root: Path = Path()
    verify_root: Path = Path()
    progress_file: Path = Path()
    state_file: Path = Path()
    log_root: Path = Path()
    run_summary_root: Path = Path()
    progress_backup_root: Path = Path()
    lock_dir: Path = Path()
    control_dir: Path = Path()
    git_checkpoint: str = "commit"
    git_branch_policy: str = "auto"
    git_push_remote: str = "origin"
    git_push_set_upstream: bool = True
    max_retries: int = 0
    max_tasks: int = 0
    start_from: str = ""
    stop_after: str = ""
    risk_gate: str = "mission-critical"
    risk_policy: str = "pause"
    target_phases: list[str] = field(default_factory=list)
    failure_context_lines: int = 200
    dry_run: bool = False
    dry_run_copy_preview_lines: int = 80
    dry_run_verify_preview_lines: int = 40
    dry_run_result: str = "PASS"
    dry_run_max_attempts: int = 10
    activity_heartbeat_seconds: int = 30
    no_output_notice_seconds: int = 120
    no_output_timeout_seconds: int = 5400
    no_output_restart_delay_seconds: int = 300
    no_output_restart_limit: int = 2
    orphan_codex_policy: str = "fail"
    run_id: str = ""

    @classmethod
    def from_env(cls) -> "RuntimeConfig":
        root = Path(os.environ.get("ROOT_DIR", Path(__file__).resolve().parents[2])).resolve()
        cfg = cls(root_dir=root)
        cfg.python_bin = os.environ.get("PYTHON_BIN", "python3")
        cfg.model = os.environ.get("MODEL", "gpt-5.5")
        cfg.model_reasoning_effort = os.environ.get("MODEL_REASONING_EFFORT", "xhigh")
        cfg.codex_bin = os.environ.get("CODEX_BIN", "")
        cfg.codex_exec_sandbox = os.environ.get("CODEX_EXEC_SANDBOX", "danger-full-access")
        cfg.copy_root = Path(os.environ.get("COPY_ROOT", root / "tasks/prompts/_shared/copy-ready"))
        cfg.verify_root = Path(os.environ.get("VERIFY_ROOT", root / "tasks/prompts/_shared/verify-ready"))
        cfg.progress_file = Path(os.environ.get("PROGRESS_FILE", root / "tasks/prompts/_shared/progress.json"))
        cfg.state_file = Path(os.environ.get("STATE_FILE", root / ".codex/task-loop-state.txt"))
        cfg.log_root = Path(os.environ.get("LOG_ROOT", root / ".codex/task-loop-logs"))
        cfg.run_summary_root = Path(os.environ.get("RUN_SUMMARY_ROOT", root / ".codex/task-loop-runs"))
        cfg.progress_backup_root = Path(os.environ.get("PROGRESS_BACKUP_ROOT", root / ".codex/task-loop-progress-backups"))
        cfg.lock_dir = Path(os.environ.get("LOCK_DIR", root / ".codex/task-loop-lock"))
        cfg.control_dir = Path(os.environ.get("CONTROL_DIR", root / ".codex/task-loop-control"))
        cfg.git_checkpoint = os.environ.get("GIT_CHECKPOINT", "commit")
        cfg.git_branch_policy = os.environ.get("GIT_BRANCH_POLICY", "auto")
        cfg.git_push_remote = os.environ.get("GIT_PUSH_REMOTE", "origin")
        cfg.git_push_set_upstream = os.environ.get("GIT_PUSH_SET_UPSTREAM", "1") == "1"
        cfg.max_retries = int(os.environ.get("MAX_RETRIES", "1"))
        cfg.max_tasks = int(os.environ.get("MAX_TASKS", "0"))
        cfg.start_from = normalize_task_ref(os.environ.get("START_FROM", ""))
        cfg.stop_after = normalize_task_ref(os.environ.get("STOP_AFTER", ""))
        cfg.risk_gate = os.environ.get("RISK_GATE", "mission-critical")
        cfg.risk_policy = os.environ.get("RISK_POLICY", "pause")
        cfg.failure_context_lines = int(os.environ.get("FAILURE_CONTEXT_LINES", "200"))
        cfg.dry_run = os.environ.get("DRY_RUN", "0") == "1"
        cfg.dry_run_copy_preview_lines = int(os.environ.get("DRY_RUN_COPY_PREVIEW_LINES", "80"))
        cfg.dry_run_verify_preview_lines = int(os.environ.get("DRY_RUN_VERIFY_PREVIEW_LINES", "40"))
        cfg.dry_run_result = os.environ.get("DRY_RUN_RESULT", "PASS")
        cfg.dry_run_max_attempts = int(os.environ.get("DRY_RUN_MAX_ATTEMPTS", "10"))
        cfg.activity_heartbeat_seconds = int(os.environ.get("ACTIVITY_HEARTBEAT_SECONDS", "30"))
        cfg.no_output_notice_seconds = int(os.environ.get("NO_OUTPUT_NOTICE_SECONDS", "120"))
        cfg.no_output_timeout_seconds = int(os.environ.get("NO_OUTPUT_TIMEOUT_SECONDS", "5400"))
        cfg.no_output_restart_delay_seconds = int(os.environ.get("NO_OUTPUT_RESTART_DELAY_SECONDS", "300"))
        cfg.no_output_restart_limit = int(os.environ.get("NO_OUTPUT_RESTART_LIMIT", "2"))
        cfg.orphan_codex_policy = os.environ.get("ORPHAN_CODEX_POLICY", "fail")
        cfg.run_id = os.environ.get("RUN_ID", "")
        return cfg

    @property
    def drain_request_file(self) -> Path:
        return self.control_dir / "drain.request"

    @property
    def default_progress_file(self) -> Path:
        return self.root_dir / "tasks/prompts/_shared/progress.json"

    def selected_phases(self) -> list[str]:
        return self.target_phases or list(PHASES)

    def should_write_progress(self) -> bool:
        return not self.dry_run or self.progress_file.resolve() != self.default_progress_file.resolve()


def timestamp() -> str:
    return datetime.now().strftime("%F %T")


def log_event(level: str, message: str) -> None:
    print(f"[ {timestamp()} ] [{level}] {message}")


def log_live_snapshot(
    *,
    title: str,
    stage: str,
    task: "TaskFile",
    attempt: int,
    pid: int | str,
    elapsed: str,
    prompt_file: Path,
    output_file: Path,
    exec_log_file: Path | None = None,
    heartbeat_seconds: int,
    command_elapsed: str,
    command_text: str,
    no_output_notice: str = "",
) -> None:
    log_event("RUN", title)
    print(
        f"  current task | stage={stage} | task={task.label} | attempt={attempt} | pid={pid} | elapsed={elapsed}",
        flush=True,
    )
    print("  live log:", flush=True)
    print(f"    prompt: {prompt_file}", flush=True)
    print(f"    output: {output_file}", flush=True)
    print(f"    state: {state.log_file_status(str(output_file))}", flush=True)
    if exec_log_file:
        print(f"    exec: {exec_log_file}", flush=True)
        print(f"    exec_state: {state.log_file_status(str(exec_log_file))}", flush=True)
    if no_output_notice:
        print(f"    note: {no_output_notice}", flush=True)
    print(
        f"  current command | heartbeat={heartbeat_seconds}s | command_elapsed={command_elapsed} | command={command_text}",
        flush=True,
    )


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def task_name_to_label(task_name: str) -> str:
    batch = task_name.rsplit("-task-", 1)[0]
    number = task_name.rsplit("-task-", 1)[1]
    return f"{batch}/task-{number}"


def label_to_task_ref(label: str) -> str:
    batch = label.split("/task-", 1)[0]
    number = label.split("/task-", 1)[1]
    phase_number = batch.split("-", 1)[0]
    return f"phase-{phase_number}/{batch}-task-{number}"


def normalize_task_ref(value: str) -> str:
    if not value:
        return ""
    if re.match(r"^phase-[0-9]/.*-task-[0-9]+$", value):
        return task_name_to_label(value.split("/", 1)[1])
    if re.match(r"^[0-9]+-[0-9]+/task-[0-9]+$", value):
        return value
    if re.match(r"^[0-9]+-[0-9]+-task-[0-9]+$", value):
        return task_name_to_label(value)
    return value


def natural_task_key(path: Path) -> tuple[int, int, int, str]:
    return state.task_key(task_name_to_label(path.stem))


def bool_text(value: bool) -> str:
    return "yes" if value else "no"


@dataclass
class CodexExecProcess:
    pid: int
    ppid: int
    pgid: int
    state: str
    elapsed: str
    command: str


def parse_ps_line(line: str) -> CodexExecProcess | None:
    parts = line.strip().split(None, 5)
    if len(parts) < 6:
        return None
    try:
        pid = int(parts[0])
        ppid = int(parts[1])
        pgid = int(parts[2])
    except ValueError:
        return None
    return CodexExecProcess(pid=pid, ppid=ppid, pgid=pgid, state=parts[3], elapsed=parts[4], command=parts[5])


def scan_task_loop_codex_exec_processes(root_dir: Path, log_root: Path) -> list[CodexExecProcess]:
    proc = subprocess.run(
        ["ps", "-axo", "pid=,ppid=,pgid=,stat=,etime=,command="],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return task_loop_codex_exec_processes_from_ps(proc.stdout.splitlines(), root_dir, log_root)


def task_loop_codex_exec_processes_from_ps(
    lines: Sequence[str],
    root_dir: Path,
    log_root: Path,
) -> list[CodexExecProcess]:
    root_marker = f"--cd {root_dir}"
    log_marker = str(log_root)
    processes: list[CodexExecProcess] = []
    for line in lines:
        if "codex exec" not in line:
            continue
        if root_marker not in line or log_marker not in line:
            continue
        parsed = parse_ps_line(line)
        if parsed and parsed.pid != os.getpid():
            processes.append(parsed)
    return processes


def terminate_process_group_by_pgid(pgid: int, sig: signal.Signals) -> None:
    try:
        os.killpg(pgid, sig)
    except OSError:
        pass


class TaskLoopRunner:
    def __init__(self, cfg: RuntimeConfig, original_command: str = "") -> None:
        self.cfg = cfg
        self.original_command = original_command or "./task-loop run"
        self.session_log_root = Path()
        self.summary_file = Path()
        self.lock_acquired = False
        self.done_tasks = 0
        self.retry_total = 0
        self.total_tasks = 0
        self.run_final_status = ""
        self.git_active_branch = ""
        self.current_child: subprocess.Popen[str] | None = None
        self.cleanup_registered = False
        self._terminating = False

    def ensure_run_id(self) -> None:
        if self.cfg.run_id:
            return
        base = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.cfg.run_id = base
        if (self.cfg.log_root / base).exists() or (self.cfg.run_summary_root / base).exists():
            self.cfg.run_id = f"{base}_{os.getpid()}"

    def init_run_paths(self) -> None:
        self.ensure_run_id()
        self.cfg.progress_file.parent.mkdir(parents=True, exist_ok=True)
        self.cfg.log_root.mkdir(parents=True, exist_ok=True)
        self.cfg.run_summary_root.mkdir(parents=True, exist_ok=True)
        self.session_log_root = self.cfg.log_root / self.cfg.run_id
        self.summary_file = self.cfg.run_summary_root / self.cfg.run_id / "summary.json"
        self.session_log_root.mkdir(parents=True, exist_ok=True)
        self.summary_file.parent.mkdir(parents=True, exist_ok=True)

    def validate_runtime_options(self) -> None:
        if self.cfg.risk_gate not in {"high", "mission-critical", "none"}:
            raise TaskLoopError("RISK_GATE must be high, mission-critical, or none")
        if self.cfg.risk_policy not in {"pause", "skip", "allow"}:
            raise TaskLoopError("RISK_POLICY must be pause, skip, or allow")
        if self.cfg.git_checkpoint not in {"off", "commit", "push"}:
            raise TaskLoopError("GIT_CHECKPOINT must be off, commit, or push")
        if self.cfg.git_branch_policy not in {"auto", "require-task-branch", "current"}:
            raise TaskLoopError("GIT_BRANCH_POLICY must be auto, require-task-branch, or current")
        if self.cfg.codex_exec_sandbox not in CODEX_SANDBOX_MODES:
            raise TaskLoopError("CODEX_EXEC_SANDBOX must be read-only, workspace-write, or danger-full-access")
        if self.cfg.dry_run_result not in {"PASS", "FAIL"}:
            raise TaskLoopError("DRY_RUN_RESULT must be PASS or FAIL")
        if self.cfg.activity_heartbeat_seconds < 1:
            raise TaskLoopError("ACTIVITY_HEARTBEAT_SECONDS must be >= 1")
        if self.cfg.no_output_notice_seconds < 1:
            raise TaskLoopError("NO_OUTPUT_NOTICE_SECONDS must be >= 1")
        if self.cfg.no_output_timeout_seconds < 0:
            raise TaskLoopError("NO_OUTPUT_TIMEOUT_SECONDS must be >= 0")
        if self.cfg.no_output_restart_delay_seconds < 0:
            raise TaskLoopError("NO_OUTPUT_RESTART_DELAY_SECONDS must be >= 0")
        if self.cfg.no_output_restart_limit < 0:
            raise TaskLoopError("NO_OUTPUT_RESTART_LIMIT must be >= 0")
        if self.cfg.orphan_codex_policy not in {"fail", "terminate", "ignore"}:
            raise TaskLoopError("ORPHAN_CODEX_POLICY must be fail, terminate, or ignore")
        for phase in self.cfg.selected_phases():
            if phase not in PHASES:
                raise TaskLoopError(f"invalid phase: {phase}")

    def acquire_lock(self, operation: str) -> None:
        self.ensure_run_id()
        self.cfg.lock_dir.parent.mkdir(parents=True, exist_ok=True)
        try:
            self.cfg.lock_dir.mkdir()
            self.lock_acquired = True
        except FileExistsError:
            lock = state.lock_info(self.cfg.lock_dir)
            if lock["alive"]:
                raise TaskLoopError(
                    f"task loop lock is held by live pid={lock['pid']}\nlock_dir={self.cfg.lock_dir}",
                    9,
                )
            log_event("WARN", f"removing stale task loop lock: {self.cfg.lock_dir}")
            shutil.rmtree(self.cfg.lock_dir)
            self.cfg.lock_dir.mkdir()
            self.lock_acquired = True

        (self.cfg.lock_dir / "pid").write_text(f"{os.getpid()}\n", encoding="utf-8")
        (self.cfg.lock_dir / "run_id").write_text(f"{self.cfg.run_id}\n", encoding="utf-8")
        (self.cfg.lock_dir / "operation").write_text(f"{operation}\n", encoding="utf-8")
        (self.cfg.lock_dir / "started_at").write_text(datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ") + "\n", encoding="utf-8")
        (self.cfg.lock_dir / "command").write_text(f"{self.original_command}\n", encoding="utf-8")
        state.clear_lock_activity(self.cfg.lock_dir)

    def release_lock(self) -> None:
        if not self.lock_acquired:
            return
        lock = state.lock_info(self.cfg.lock_dir)
        if lock.get("pid") == str(os.getpid()):
            shutil.rmtree(self.cfg.lock_dir, ignore_errors=True)
        self.lock_acquired = False

    def register_cleanup_handlers(self) -> None:
        if self.cleanup_registered:
            return
        self.cleanup_registered = True
        atexit.register(self.cleanup_current_child)

        def handle_signal(signum: int, _frame: object) -> None:
            if self._terminating:
                raise SystemExit(128 + signum)
            self._terminating = True
            log_event("WARN", f"received signal {signum}; terminate active codex exec child")
            self.cleanup_current_child()
            raise SystemExit(128 + signum)

        signal.signal(signal.SIGTERM, handle_signal)
        signal.signal(signal.SIGINT, handle_signal)

    def cleanup_current_child(self) -> None:
        proc = self.current_child
        if proc is None or proc.poll() is not None:
            return
        terminate_process_group(proc, signal.SIGTERM)
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            terminate_process_group(proc, signal.SIGKILL)
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                log_event("WARN", f"active codex exec child did not exit after SIGKILL pid={proc.pid}")

    def clear_stale_drain_request_for_new_run(self) -> None:
        request_file = self.cfg.drain_request_file
        if not request_file.exists():
            return
        values = state.read_control_file(request_file)
        if values.get("lock_run_id") != self.cfg.run_id:
            log_event("WARN", f"clear stale drain request before new run: {request_file}")
            request_file.unlink(missing_ok=True)

    def handle_orphan_codex_exec_processes(self) -> None:
        if self.cfg.dry_run or self.cfg.orphan_codex_policy == "ignore":
            return
        orphaned = [proc for proc in scan_task_loop_codex_exec_processes(self.cfg.root_dir, self.cfg.log_root) if proc.ppid == 1]
        if not orphaned:
            return
        details = "\n".join(
            f"- pid={proc.pid} pgid={proc.pgid} elapsed={proc.elapsed} command={proc.command}" for proc in orphaned
        )
        if self.cfg.orphan_codex_policy == "fail":
            raise CodexOrphanError(
                "found orphaned codex exec task-loop children for this workspace; "
                "clean them up before starting another live child, or set ORPHAN_CODEX_POLICY=terminate:\n"
                f"{details}",
                10,
            )
        log_event("WARN", f"terminate orphaned codex exec task-loop children:\n{details}")
        for proc in orphaned:
            terminate_process_group_by_pgid(proc.pgid, signal.SIGTERM)
        time.sleep(2)
        still_alive = [
            proc
            for proc in scan_task_loop_codex_exec_processes(self.cfg.root_dir, self.cfg.log_root)
            if proc.pid in {item.pid for item in orphaned}
        ]
        for proc in still_alive:
            terminate_process_group_by_pgid(proc.pgid, signal.SIGKILL)
        if still_alive:
            time.sleep(1)
        remaining = [
            proc
            for proc in scan_task_loop_codex_exec_processes(self.cfg.root_dir, self.cfg.log_root)
            if proc.pid in {item.pid for item in orphaned}
        ]
        if remaining:
            details = "\n".join(f"- pid={proc.pid} pgid={proc.pgid} elapsed={proc.elapsed}" for proc in remaining)
            raise CodexOrphanError(f"failed to terminate orphaned codex exec children:\n{details}", 10)

    def request_drain(self) -> int:
        self.ensure_run_id()
        self.cfg.control_dir.mkdir(parents=True, exist_ok=True)
        lock = state.lock_info(self.cfg.lock_dir)
        if not lock["exists"]:
            raise TaskLoopError("no live task loop lock found; nothing to drain")
        if not lock["alive"]:
            raise TaskLoopError("task loop lock exists but pid is not alive; use status and recovery commands instead")
        if lock.get("operation") != "run":
            raise TaskLoopError(f"live task loop operation is {lock.get('operation') or 'unknown'}, not run; drain request refused")
        log_event("INFO", f"request drain for live runner pid={lock['pid']} run_id={lock.get('run_id') or 'unknown'}")
        self.cfg.drain_request_file.write_text(
            "\n".join(
                [
                    f"requested_at={datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')}",
                    f"requested_by_pid={os.getpid()}",
                    "target=after_current_task",
                    f"lock_run_id={lock.get('run_id') or ''}",
                    f"lock_operation={lock.get('operation') or ''}",
                    "",
                ]
            ),
            encoding="utf-8",
        )
        log_event("INFO", f"drain_request_file={self.cfg.drain_request_file}")
        return 0

    def drain_requested(self) -> bool:
        return self.cfg.drain_request_file.exists()

    def clear_drain_request(self) -> None:
        self.cfg.drain_request_file.unlink(missing_ok=True)

    def resolve_codex_bin(self) -> None:
        if self.cfg.codex_bin:
            path = Path(self.cfg.codex_bin)
            if path.exists() and os.access(path, os.X_OK):
                self.cfg.codex_bin_resolved = str(path)
                return
            raise TaskLoopError(f"CODEX_BIN is not executable: {self.cfg.codex_bin}")
        found = shutil.which("codex")
        if found:
            self.cfg.codex_bin_resolved = found
            return
        app_bin = Path("/Applications/Codex.app/Contents/Resources/codex")
        if app_bin.exists() and os.access(app_bin, os.X_OK):
            self.cfg.codex_bin_resolved = str(app_bin)
            return
        raise TaskLoopError("Codex CLI not found. Install it, add it to PATH, or set CODEX_BIN=/path/to/codex.")

    def run_git_preflight(self) -> None:
        if self.cfg.git_checkpoint == "off" or self.cfg.dry_run:
            proc = subprocess.run(["git", "branch", "--show-current"], cwd=self.cfg.root_dir, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            self.git_active_branch = proc.stdout.strip()
            return
        output = git_helpers.preflight(
            self.cfg.root_dir,
            self.cfg.git_checkpoint,
            self.cfg.git_branch_policy,
            self.cfg.git_push_remote,
            self.cfg.git_push_set_upstream,
            self.cfg.run_id,
            dry_run=self.cfg.dry_run,
        )
        log_event("GIT", json_dumps(output))
        proc = subprocess.run(["git", "branch", "--show-current"], cwd=self.cfg.root_dir, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.git_active_branch = proc.stdout.strip()

    def run_git_checkpoint(self, task: TaskFile, attempt: int, copy_log: Path, verify_log: Path) -> None:
        if self.cfg.dry_run:
            log_event("GIT", f"dry-run: skip Git checkpoint for {task.label}")
            return
        if self.cfg.git_checkpoint == "off":
            log_event("GIT", f"GIT_CHECKPOINT=off: skip Git checkpoint for {task.label}")
            return
        try:
            output = git_helpers.checkpoint(
                self.cfg.root_dir,
                self.cfg.git_checkpoint,
                self.cfg.git_push_remote,
                self.cfg.git_push_set_upstream,
                task.label,
                task.phase,
                task.task_name,
                attempt,
                self.cfg.run_id,
                str(copy_log),
                str(verify_log),
                self.cfg.progress_file,
                self.summary_file,
            )
        except git_helpers.GitError as exc:
            log_event("GIT", str(exc))
            log_event("ERROR", f"Git checkpoint failed for {task.label}; fix Git state, then resume from this task.")
            raise TaskLoopError(str(exc), exc.returncode)
        log_event("GIT", json_dumps(output))

    def run_git_run_summary_checkpoint(self) -> int:
        if self.cfg.dry_run or self.cfg.git_checkpoint == "off" or not self.summary_file.exists():
            return 0
        try:
            output = git_helpers.commit_run_summary(
                self.cfg.root_dir,
                self.cfg.git_checkpoint,
                self.cfg.git_push_remote,
                self.cfg.git_push_set_upstream,
                self.cfg.run_id,
                self.summary_file,
                self.cfg.run_summary_root,
            )
            log_event("GIT", json_dumps(output))
            return 0
        except git_helpers.GitError as exc:
            log_event("GIT", str(exc))
            log_event("ERROR", f"Git run-summary checkpoint failed for run_id={self.cfg.run_id}")
            return exc.returncode

    def init_summary(self) -> None:
        state.init_summary(
            self.summary_file,
            {
                "run_id": self.cfg.run_id,
                "root_dir": str(self.cfg.root_dir),
                "model": self.cfg.model,
                "model_reasoning_effort": self.cfg.model_reasoning_effort,
                "dry_run": self.cfg.dry_run,
                "codex_bin": self.cfg.codex_bin_resolved,
                "codex_exec_sandbox": self.cfg.codex_exec_sandbox,
                "risk_gate": self.cfg.risk_gate,
                "risk_policy": self.cfg.risk_policy,
                "max_retries": self.cfg.max_retries,
                "max_tasks": self.cfg.max_tasks,
                "start_from": self.cfg.start_from,
                "stop_after": self.cfg.stop_after,
                "progress_file": str(self.cfg.progress_file),
                "log_root": str(self.session_log_root),
                "copy_root": str(self.cfg.copy_root),
                "verify_root": str(self.cfg.verify_root),
                "phases": self.cfg.selected_phases(),
                "total_tasks": self.total_tasks,
                "git": {
                    "checkpoint": self.cfg.git_checkpoint,
                    "branch_policy": self.cfg.git_branch_policy,
                    "push_remote": self.cfg.git_push_remote,
                    "push_set_upstream": "1" if self.cfg.git_push_set_upstream else "0",
                    "active_branch": self.git_active_branch,
                },
            },
        )

    def finalize_summary(self, status_name: str, exit_code: int, note: str = "") -> None:
        if self.summary_file.exists():
            state.finalize_summary(
                self.summary_file,
                self.cfg.run_summary_root,
                status_name,
                exit_code,
                self.done_tasks,
                self.retry_total,
                note,
            )

    def update_run_index(self) -> None:
        if self.summary_file.exists():
            state.update_index(self.cfg.run_summary_root, self.summary_file)

    def record_task_summary(
        self,
        task: TaskFile,
        status_name: str,
        attempt: int,
        copy_log: Path,
        verify_log: Path,
        note: str,
    ) -> None:
        if not self.summary_file:
            return
        state.record_summary(
            self.summary_file,
            task.label,
            task.phase,
            task.task_name,
            status_name,
            attempt,
            task.risk,
            str(copy_log),
            str(verify_log),
            note,
            self.done_tasks,
            self.retry_total,
        )

    def mark_progress(self, task: TaskFile, status_name: str, note: str, copy_log: Path | None, verify_log: Path | None, attempts: int) -> None:
        if not self.cfg.should_write_progress():
            return
        state.mark_progress(
            self.cfg.progress_file,
            task.label,
            status_name,
            note,
            str(copy_log or ""),
            str(verify_log or ""),
            attempts,
            task.risk,
            self.cfg.run_id,
        )

    def prompt_status(self, label: str) -> str:
        task_ref = label_to_task_ref(label)
        phase = task_ref.split("/", 1)[0]
        if phase not in self.cfg.selected_phases():
            return f"phase-not-selected:{phase}"
        copy_file = self.cfg.copy_root / f"{task_ref}.md"
        verify_file = self.cfg.verify_root / f"{task_ref}.md"
        if not copy_file.exists():
            return f"copy-missing:{copy_file}"
        if not verify_file.exists():
            return f"verify-missing:{verify_file}"
        return "ok"

    def validate_task_targets(self) -> None:
        if self.cfg.start_from:
            status = self.prompt_status(self.cfg.start_from)
            if status != "ok":
                raise TaskLoopError(f"START_FROM label is not runnable in selected phases: {self.cfg.start_from} ({status})")
        if self.cfg.stop_after:
            status = self.prompt_status(self.cfg.stop_after)
            if status != "ok":
                raise TaskLoopError(f"STOP_AFTER label is not runnable in selected phases: {self.cfg.stop_after} ({status})")

    def task_files(self) -> list[TaskFile]:
        tasks: list[TaskFile] = []
        for phase in self.cfg.selected_phases():
            copy_dir = self.cfg.copy_root / phase
            verify_dir = self.cfg.verify_root / phase
            if not copy_dir.is_dir() or not verify_dir.is_dir():
                continue
            for copy_file in sorted(copy_dir.glob("*.md"), key=natural_task_key):
                task_name = copy_file.stem
                verify_file = verify_dir / f"{task_name}.md"
                if not verify_file.exists():
                    continue
                tasks.append(
                    TaskFile(
                        phase=phase,
                        task_name=task_name,
                        label=task_name_to_label(task_name),
                        copy_file=copy_file,
                        verify_file=verify_file,
                        risk=self.task_risk(copy_file),
                    )
                )
        return tasks

    def bootstrap_counts(self) -> None:
        self.total_tasks = len(self.task_files())
        if self.cfg.max_tasks > 0 and self.cfg.max_tasks < self.total_tasks:
            self.total_tasks = self.cfg.max_tasks

    def task_risk(self, prompt_file: Path) -> str:
        text = prompt_file.read_text(encoding="utf-8", errors="replace")
        match = re.search(r"风险等级：`([^`]+)`", text)
        return match.group(1) if match else "Unspecified"

    def risk_matches_gate(self, risk: str) -> bool:
        if self.cfg.risk_gate == "none":
            return False
        if self.cfg.risk_gate == "mission-critical":
            return risk == "Mission-Critical"
        return risk in {"High", "Mission-Critical"}

    def handle_risk_gate(self, task: TaskFile) -> int:
        if not self.risk_matches_gate(task.risk):
            return 0
        if self.cfg.risk_policy == "allow":
            log_event("RISK", f"{task.label} risk={task.risk} allowed by RISK_POLICY=allow")
            return 0
        if self.cfg.risk_policy == "skip":
            log_event("RISK", f"{task.label} risk={task.risk} skipped by RISK_POLICY=skip")
            self.mark_progress(task, "blocked", f"风险门禁跳过：risk={task.risk} gate={self.cfg.risk_gate} policy=skip", None, None, 0)
            return 2
        log_event("RISK", f"{task.label} risk={task.risk} paused by RISK_POLICY=pause")
        self.mark_progress(
            task,
            "blocked",
            f"风险门禁暂停：risk={task.risk} gate={self.cfg.risk_gate} policy=pause；确认后可用 RISK_POLICY=allow 继续",
            None,
            None,
            0,
        )
        return 3

    def is_task_done(self, label: str) -> bool:
        if state.task_status(self.cfg.progress_file, label) == "completed":
            return True
        if self.cfg.state_file.exists():
            task_ref = label_to_task_ref(label)
            lines = set(self.cfg.state_file.read_text(encoding="utf-8", errors="replace").splitlines())
            return label in lines or task_ref in lines
        return False

    def print_launch_header(self) -> None:
        log_event("INFO", "AreaMatrix task loop start")
        log_event("INFO", f"MODEL={self.cfg.model} MODEL_REASONING_EFFORT={self.cfg.model_reasoning_effort}")
        if self.cfg.codex_bin_resolved:
            log_event("INFO", f"CODEX_BIN={self.cfg.codex_bin_resolved}")
        log_event("INFO", f"CODEX_EXEC_SANDBOX={self.cfg.codex_exec_sandbox}")
        log_event("INFO", f"DRY_RUN={1 if self.cfg.dry_run else 0}")
        if self.cfg.dry_run:
            log_event("INFO", f"DRY_RUN_RESULT={self.cfg.dry_run_result}")
        log_event("INFO", f"ACTIVITY_HEARTBEAT_SECONDS={self.cfg.activity_heartbeat_seconds}")
        log_event("INFO", f"NO_OUTPUT_NOTICE_SECONDS={self.cfg.no_output_notice_seconds}")
        log_event("INFO", f"NO_OUTPUT_TIMEOUT_SECONDS={self.cfg.no_output_timeout_seconds}")
        log_event("INFO", f"NO_OUTPUT_RESTART_DELAY_SECONDS={self.cfg.no_output_restart_delay_seconds}")
        log_event("INFO", f"NO_OUTPUT_RESTART_LIMIT={self.cfg.no_output_restart_limit}")
        log_event("INFO", f"ROOT_DIR={self.cfg.root_dir}")
        log_event("INFO", f"COPY_ROOT={self.cfg.copy_root}")
        log_event("INFO", f"VERIFY_ROOT={self.cfg.verify_root}")
        log_event("INFO", f"PROGRESS_FILE={self.cfg.progress_file}")
        log_event("INFO", f"LEGACY_STATE_FILE={self.cfg.state_file}")
        log_event("INFO", f"LOG_ROOT={self.session_log_root}")
        log_event("INFO", f"RUN_SUMMARY_FILE={self.summary_file}")
        log_event("INFO", f"LOCK_DIR={self.cfg.lock_dir}")
        log_event("INFO", f"CONTROL_DIR={self.cfg.control_dir}")
        log_event("INFO", f"RISK_GATE={self.cfg.risk_gate} RISK_POLICY={self.cfg.risk_policy}")
        log_event("INFO", f"GIT_CHECKPOINT={self.cfg.git_checkpoint} GIT_BRANCH_POLICY={self.cfg.git_branch_policy}")
        if self.git_active_branch:
            log_event("INFO", f"GIT_ACTIVE_BRANCH={self.git_active_branch}")
        log_event("INFO", f"PHASES={' '.join(self.cfg.selected_phases())}")
        log_event("INFO", f"TOTAL_TASKS={self.total_tasks}")
        if self.cfg.start_from:
            log_event("INFO", f"START_FROM={self.cfg.start_from}")
        if self.cfg.stop_after:
            log_event("INFO", f"STOP_AFTER={self.cfg.stop_after}")
        if self.cfg.max_tasks > 0:
            log_event("INFO", f"MAX_TASKS={self.cfg.max_tasks}")

    def print_task_progress(self, status_name: str, task: TaskFile, attempt: int, copy_log: Path, verify_log: Path) -> None:
        remain_count = self.total_tasks - self.done_tasks
        percent = self.done_tasks * 100 // self.total_tasks if self.total_tasks > 0 else 0
        log_event(status_name, f"task={task.label} attempt={attempt}")
        log_event(status_name, f"done={self.done_tasks} total={self.total_tasks} remain={remain_count} complete={percent}%")
        log_event(status_name, f"copy_log={copy_log}")
        log_event(status_name, f"verify_log={verify_log}")

    def dry_run_stub(self, prompt_file: Path, output_file: Path, stage: str, extra_prompt: str, preview_lines: int, task: TaskFile, attempt: int) -> None:
        output_file.parent.mkdir(parents=True, exist_ok=True)
        prompt_lines = prompt_file.read_text(encoding="utf-8", errors="replace").splitlines()[:preview_lines]
        lines = [
            "DRY RUN OUTPUT (command not executed)",
            f"label: {task.label}",
            f"phase: {task.phase}",
            f"stage: {stage}",
            f"sandbox: {self.cfg.codex_exec_sandbox}",
            f"model: {self.cfg.model}",
            f"reasoning_effort: {self.cfg.model_reasoning_effort}",
            f"prompt_file: {prompt_file}",
            f"attempt: {attempt}",
            "",
        ]
        if extra_prompt:
            lines.extend(["--- injected_retry_prompt ---", extra_prompt, ""])
        lines.append(f"--- prompt_head ({preview_lines} lines) ---")
        lines.extend(prompt_lines)
        if stage == "verify":
            lines.extend(["", f"VERIFY_RESULT: {self.cfg.dry_run_result}"])
        output_file.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def run_codex(self, prompt_file: Path, output_file: Path, stage: str, extra_prompt: str, task: TaskFile, attempt: int) -> None:
        output_file.parent.mkdir(parents=True, exist_ok=True)
        preview_lines = self.cfg.dry_run_verify_preview_lines if stage == "verify" else self.cfg.dry_run_copy_preview_lines
        if self.cfg.dry_run:
            log_event("DRY", f"simulating codex exec for {prompt_file} -> {output_file}")
            self.dry_run_stub(prompt_file, output_file, stage, extra_prompt, preview_lines, task, attempt)
            return
        exec_log_file = output_file.with_suffix(".exec.log")
        prompt_text = prompt_file.read_text(encoding="utf-8")
        if extra_prompt:
            prompt_text = f"{prompt_text}\n\n{extra_prompt}\n"
        command = [
            self.cfg.codex_bin_resolved,
            "exec",
            "-m",
            self.cfg.model,
            "-c",
            f"model_reasoning_effort={self.cfg.model_reasoning_effort}",
            "--full-auto",
            "-s",
            self.cfg.codex_exec_sandbox,
            "--cd",
            str(self.cfg.root_dir),
            "-o",
            str(output_file),
            "-",
        ]
        command_text = shlex.join([str(part) for part in command])
        restarts = 0
        while True:
            try:
                self.run_codex_child(
                    command,
                    command_text,
                    prompt_text,
                    prompt_file,
                    output_file,
                    exec_log_file,
                    stage,
                    task,
                    attempt,
                    restart_index=restarts,
                )
                return
            except CodexNoOutputTimeout as exc:
                if restarts >= self.cfg.no_output_restart_limit:
                    raise CodexNoOutputTimeoutLimit(
                        f"{exc}; restart limit reached ({self.cfg.no_output_restart_limit})",
                        124,
                    ) from exc
                restarts += 1
                delay = self.cfg.no_output_restart_delay_seconds
                log_event(
                    "WARN",
                    f"codex exec no-output timeout; restart {stage} task={task.label} "
                    f"attempt={attempt} child_restart={restarts}/{self.cfg.no_output_restart_limit} "
                    f"after {state.human_duration(delay)}",
                )
                state.write_lock_activity(
                    self.cfg.lock_dir,
                    {
                        "status": "restart_wait",
                        "child_restart": restarts,
                        "child_restart_limit": self.cfg.no_output_restart_limit,
                        "restart_delay_seconds": delay,
                    },
                )
                sleep_with_drain_notice(delay)

    def run_codex_child(
        self,
        command: list[str],
        command_text: str,
        prompt_text: str,
        prompt_file: Path,
        output_file: Path,
        exec_log_file: Path,
        stage: str,
        task: TaskFile,
        attempt: int,
        *,
        restart_index: int,
    ) -> None:
        state.replace_lock_activity(
            self.cfg.lock_dir,
            {
                "status": "starting",
                "stage": stage,
                "task_label": task.label,
                "task_name": task.task_name,
                "attempt": attempt,
                "prompt_file": str(prompt_file),
                "output_file": str(output_file),
                "exec_log_file": str(exec_log_file),
                "command": command_text,
                "started_at": utc_now(),
                "child_restart": restart_index,
                "child_restart_limit": self.cfg.no_output_restart_limit,
                "pid": "",
            },
        )
        log_live_snapshot(
            title="live activity started",
            stage=stage,
            task=task,
            attempt=attempt,
            pid=f"starting restart={restart_index}",
            elapsed="0s",
            prompt_file=prompt_file,
            output_file=output_file,
            exec_log_file=exec_log_file,
            heartbeat_seconds=self.cfg.activity_heartbeat_seconds,
            command_elapsed="0s",
            command_text=command_text,
        )
        exec_log_file.parent.mkdir(parents=True, exist_ok=True)
        exec_log = exec_log_file.open("a", encoding="utf-8", errors="replace")
        exec_log.write(f"[{utc_now()}] start {stage} task={task.label} attempt={attempt} restart={restart_index}\n")
        exec_log.flush()
        proc = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=exec_log,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
        )
        self.current_child = proc
        start_monotonic = time.monotonic()
        last_output_signature = (output_file_signature(output_file), output_file_signature(exec_log_file))
        last_output_change_monotonic = start_monotonic
        state.write_lock_activity(self.cfg.lock_dir, {"status": "running", "pid": proc.pid, "child_restart": restart_index})
        log_live_snapshot(
            title="live activity running",
            stage=stage,
            task=task,
            attempt=attempt,
            pid=proc.pid,
            elapsed="0s",
            prompt_file=prompt_file,
            output_file=output_file,
            exec_log_file=exec_log_file,
            heartbeat_seconds=self.cfg.activity_heartbeat_seconds,
            command_elapsed="0s",
            command_text=command_text,
        )
        communicate_error: list[BaseException] = []
        timeout_error = ""

        def communicate_with_child() -> None:
            try:
                proc.communicate(prompt_text)
            except BaseException as exc:  # pragma: no cover - defensive handoff from worker thread
                communicate_error.append(exc)

        worker = threading.Thread(target=communicate_with_child, daemon=True)
        worker.start()
        try:
            while worker.is_alive():
                time.sleep(self.cfg.activity_heartbeat_seconds)
                if not worker.is_alive():
                    break
                now = time.monotonic()
                current_signature = (output_file_signature(output_file), output_file_signature(exec_log_file))
                if current_signature != last_output_signature:
                    last_output_signature = current_signature
                    last_output_change_monotonic = now
                no_output_elapsed_seconds = int(now - last_output_change_monotonic)
                elapsed = state.human_duration(now - start_monotonic)
                log_state = state.log_file_status(str(output_file))
                no_output_notice = ""
                if no_output_elapsed_seconds >= self.cfg.no_output_notice_seconds:
                    no_output_notice = (
                        "codex exec child is running but final output / exec stream have not made progress; "
                        "this is a no-output wait, not proof that validation commands are progressing."
                    )
                state.write_lock_activity(
                    self.cfg.lock_dir,
                    {
                        "status": "running",
                        "log_state": log_state,
                        "exec_log_state": state.log_file_status(str(exec_log_file)),
                        "no_output_elapsed_seconds": no_output_elapsed_seconds,
                        "no_output_timeout_seconds": self.cfg.no_output_timeout_seconds,
                        "child_restart": restart_index,
                        "child_restart_limit": self.cfg.no_output_restart_limit,
                    },
                )
                if (
                    self.cfg.no_output_timeout_seconds > 0
                    and no_output_elapsed_seconds >= self.cfg.no_output_timeout_seconds
                ):
                    timeout_error = (
                        f"codex exec no-output timeout for {stage} {task.label} attempt={attempt}: "
                        f"no output log progress for {state.human_duration(no_output_elapsed_seconds)} "
                        f"(timeout={state.human_duration(self.cfg.no_output_timeout_seconds)}; "
                        f"log_state={log_state})"
                    )
                    state.write_lock_activity(
                        self.cfg.lock_dir,
                        {
                            "status": "no_output_timeout",
                            "no_output_elapsed_seconds": no_output_elapsed_seconds,
                            "no_output_timeout_seconds": self.cfg.no_output_timeout_seconds,
                            "child_restart": restart_index,
                            "child_restart_limit": self.cfg.no_output_restart_limit,
                            "log_state": log_state,
                        },
                    )
                    log_live_snapshot(
                        title="live activity no-output timeout",
                        stage=stage,
                        task=task,
                        attempt=attempt,
                        pid=proc.pid,
                        elapsed=elapsed,
                        prompt_file=prompt_file,
                        output_file=output_file,
                        exec_log_file=exec_log_file,
                        heartbeat_seconds=self.cfg.activity_heartbeat_seconds,
                        command_elapsed=elapsed,
                        command_text=command_text,
                        no_output_notice=timeout_error,
                    )
                    terminate_child(proc, worker)
                    break
                log_live_snapshot(
                    title="live activity heartbeat",
                    stage=stage,
                    task=task,
                    attempt=attempt,
                    pid=proc.pid,
                    elapsed=elapsed,
                    prompt_file=prompt_file,
                    output_file=output_file,
                    exec_log_file=exec_log_file,
                    heartbeat_seconds=self.cfg.activity_heartbeat_seconds,
                    command_elapsed=elapsed,
                    command_text=command_text,
                    no_output_notice=no_output_notice,
                )
            worker.join(timeout=5)
        finally:
            if self.current_child is proc:
                self.current_child = None
            exec_log.write(f"[{utc_now()}] finish returncode={proc.returncode}\n")
            exec_log.close()
            state.write_lock_activity(
                self.cfg.lock_dir,
                {
                    "status": "no_output_timeout" if timeout_error else "finished",
                    "finished_at": utc_now(),
                    "returncode": proc.returncode,
                },
            )
        if timeout_error:
            raise CodexNoOutputTimeout(timeout_error, 124)
        if communicate_error:
            raise TaskLoopError(f"codex exec communication failed for {prompt_file}: {communicate_error[0]}", 1)
        if proc.returncode != 0:
            raise TaskLoopError(f"codex exec failed for {prompt_file}: exit={proc.returncode}", proc.returncode)

    def is_verify_pass(self, verify_log: Path) -> bool:
        if not verify_log.exists():
            return False
        return bool(state.VERIFY_PASS_RE.search(verify_log.read_text(encoding="utf-8", errors="replace")))

    def extract_verify_feedback(self, verify_log: Path) -> str:
        if not verify_log.exists():
            return "验收未通过，但 verify 日志缺失。请严格对照该任务 copy-ready 与 verify-ready 的要求重新实现并重试。"
        lines = verify_log.read_text(encoding="utf-8", errors="replace").splitlines()[-self.cfg.failure_context_lines :]
        feedback = [line for line in lines if "VERIFY_RESULT:" not in line and line.strip()]
        if not feedback:
            return "验收未通过，但 verify 日志未给出明确失败细节。请严格对照该任务 copy-ready 与 verify-ready 的要求重新实现并重试。"
        return "\n".join(feedback)

    def build_copy_retry_prompt(self, task: TaskFile, attempt: int, verify_log: Path) -> str:
        feedback = self.extract_verify_feedback(verify_log)
        return f"""你正在对同一个任务进行 repair retry（修复重试，第 {attempt} 次尝试）。任务标签：{task.label}（文件：{task.task_name}.md）。
本次重试只允许修复上一次验收失败问题，不要改写任务目标外的范围。
本次重试必须同时修复本 task 范围内的功能失败、验收证据失败和工程质量失败；重新读取工程质量规则与编码规范。
本次重试不会改变验证等级：仍以当前 task manifest 的 `Validation` 为上限。
除非当前 task manifest 明确列出 `./dev check all`、`./dev check core` 或 `cargo test --workspace`，否则不要因为 retry、证据不足、上一次 verify 失败或 `core/**` 改动而升级到这些宽门禁。
若上一次验收日志声称 manifest 要求更宽门禁，必须先回到当前 task manifest 核对；以 manifest 原文为准。
以下是上一次验收日志里的失败摘要（请只修复这些本 task 范围内的问题）：

{feedback}

修复完成后，重新执行当前 task manifest `Validation` 中列出的检查，再进入该任务验收。"""

    def build_silent_approval_prompt(self, task: TaskFile) -> str:
        if self.cfg.risk_policy != "allow":
            return ""
        return f"""自动执行授权上下文：
- 用户已明确授权 AreaMatrix task loop 静默执行当前任务，当前任务标签：{task.label}，风险等级：{task.risk}。
- 对 High / Mission-Critical task，仍需在日志中说明影响、风险、验证和回滚，但不要停下来等待人工确认。
- 允许在仓库内修改、创建和运行当前 task 完成所需的文件与验证命令。
- 若验收失败指出 task 直接相关的 Exact Docs、Core API、UDL、manifest 或 README 存在源事实漂移，可在不实现相邻能力、不触碰 Forbidden Touches 的前提下同步修复，并在报告中列出。
- 本授权不允许删除、移动、覆盖真实用户原文件；命中用户文件破坏性操作时仍必须停止并报告。"""

    def build_copy_context_prompt(self, task: TaskFile, attempt: int, previous_verify_log: Path | None) -> str:
        parts = [part for part in [self.build_silent_approval_prompt(task)] if part]
        if attempt > 1 and previous_verify_log:
            parts.append(self.build_copy_retry_prompt(task, attempt, previous_verify_log))
        return "\n\n".join(parts)

    def verify_suffix(self) -> str:
        return f"""自动任务循环输出要求：
- 保留简明验收报告，尤其是不通过时的失败摘要、阻塞项、文件路径和验证缺口。
- 工程质量不达标时必须写清楚本 task 范围内的质量阻塞点，供下一轮 repair retry 精准修复。
- 验证边界不随 retry 次数变化；普通 task 的 retry 仍以当前 task manifest 的 `Validation` 为上限。
- 除非当前 task manifest 明确要求宽门禁，否则不要把失败、证据不足或 `core/**` 改动解释成必须运行
  `./dev check all`、`./dev check core` 或 `cargo test --workspace`。
- 当前验收发生在 runner 写入 completed progress 和 Git checkpoint 之前；不要因为 `progress.json`
  仍是 `in_progress`、新增文件尚未被 `git add`、或 `git_checkpoint_status` 尚未写入而判定不通过。
- 你仍需检查当前工作区是否有与本 task 无关、危险或无法解释的脏改动；真实功能、验证命令、
  Forbidden Touches、代码质量、安全/隐私/依赖/CI/review blocker 仍必须按规则严格阻断。
- 若本轮验收输出 `VERIFY_RESULT: PASS`，runner 随后会按 `GIT_CHECKPOINT={self.cfg.git_checkpoint}` 执行
  progress / summary / Git checkpoint 收口；若该收口失败，应归因给 runner checkpoint 阶段，而不是本
  verify 阶段。
- 最后一行必须单独输出 VERIFY_RESULT: PASS 或 VERIFY_RESULT: FAIL。
- 不要在最后一行之后输出任何内容。"""

    def run_loop(self, resume_failed: bool = False, resume_stale: bool = False) -> int:
        self.register_cleanup_handlers()
        self.validate_runtime_options()
        self.acquire_lock("run")
        try:
            self.clear_stale_drain_request_for_new_run()
            if resume_failed:
                failed_label = state.first_failed(self.cfg.progress_file)
                if not failed_label:
                    raise TaskLoopError(f"no failed task found in {self.cfg.progress_file}")
                self.cfg.start_from = failed_label
                log_event("INFO", f"resume failed task: {self.cfg.start_from}")
            if resume_stale:
                stale_label = state.first_stale(self.cfg.progress_file, self.cfg.lock_dir)
                if not stale_label:
                    raise TaskLoopError(f"no stale in_progress task found in {self.cfg.progress_file}")
                self.cfg.start_from = stale_label
                log_event("INFO", f"resume stale task: {self.cfg.start_from}")
            self.validate_task_targets()
            if not self.cfg.dry_run:
                self.resolve_codex_bin()
            self.handle_orphan_codex_exec_processes()
            self.run_git_preflight()
            self.init_run_paths()
            self.bootstrap_counts()
            self.init_summary()
            self.print_launch_header()
            exit_code = self._execute_tasks()
            final_status = self.run_final_status or "completed"
            self.finalize_summary(final_status, exit_code)
            summary_rc = self.run_git_run_summary_checkpoint() if exit_code == 0 else 0
            return summary_rc or exit_code
        except TaskLoopError as exc:
            log_event("ERROR", str(exc))
            if self.summary_file and self.summary_file.exists():
                self.finalize_summary("failed", exc.code)
            return exc.code
        finally:
            self.release_lock()

    def _execute_tasks(self) -> int:
        should_start = not bool(self.cfg.start_from)
        for task in self.task_files():
            if not should_start:
                if task.label == self.cfg.start_from:
                    should_start = True
                else:
                    continue
            if self.is_task_done(task.label):
                log_event("SKIP", f"{task.label} already completed")
                continue
            if self.cfg.max_tasks > 0 and self.done_tasks >= self.cfg.max_tasks:
                log_event("INFO", f"reach max tasks cap: {self.cfg.max_tasks}")
                log_event("INFO", "stop execution")
                log_event("INFO", f"Done tasks done. completed={self.done_tasks} total={self.total_tasks} retries={self.retry_total}")
                return 0
            gate_result = self.handle_risk_gate(task)
            if gate_result == 2:
                self.record_task_summary(task, "blocked", 0, Path(), Path(), "风险门禁跳过")
                continue
            if gate_result == 3:
                self.record_task_summary(task, "blocked", 0, Path(), Path(), "风险门禁暂停")
                raise TaskLoopError("risk gate paused", 2)
            self._execute_single_task(task)
            if self.run_final_status in {"stopped", "drained"}:
                return 0
        log_event("INFO", f"All tasks done. completed={self.done_tasks} total={self.total_tasks} retries={self.retry_total}")
        return 0

    def _execute_single_task(self, task: TaskFile) -> None:
        attempt = 0
        while True:
            attempt += 1
            copy_log = self.session_log_root / task.phase / f"{task.task_name}-copy-attempt-{attempt}.log"
            verify_log = self.session_log_root / task.phase / f"{task.task_name}-verify-attempt-{attempt}.log"
            if attempt > 1:
                log_event("REPAIR", f"repair retry {task.label} attempt={attempt}")
                progress_note = f"修复重试中：attempt={attempt} risk={task.risk}"
            else:
                log_event("TASK", f"start {task.label}")
                progress_note = f"执行中：attempt={attempt} risk={task.risk}"
            log_event("TASK", f"copy prompt -> {copy_log}")
            self.mark_progress(task, "in_progress", progress_note, copy_log, verify_log, attempt)
            self.record_task_summary(task, "in_progress", attempt, copy_log, verify_log, progress_note)
            previous_verify_log = self.session_log_root / task.phase / f"{task.task_name}-verify-attempt-{attempt - 1}.log" if attempt > 1 else None
            try:
                self.run_codex(task.copy_file, copy_log, "copy", self.build_copy_context_prompt(task, attempt, previous_verify_log), task, attempt)
                log_event("TASK", f"verify prompt -> {verify_log}")
                self.run_codex(task.verify_file, verify_log, "verify", self.verify_suffix(), task, attempt)
            except CodexNoOutputTimeoutLimit as exc:
                note = f"codex exec no-output timeout：{exc}"
                self.mark_progress(task, "failed", note, copy_log, verify_log, attempt)
                self.record_task_summary(task, "failed", attempt, copy_log, verify_log, note)
                raise
            if self.is_verify_pass(verify_log):
                self.mark_progress(task, "completed", f"自动执行验收通过：attempt={attempt}", copy_log, verify_log, attempt)
                self.done_tasks += 1
                self.record_task_summary(task, "completed", attempt, copy_log, verify_log, "自动执行验收通过")
                self.update_run_index()
                self.run_git_checkpoint(task, attempt, copy_log, verify_log)
                self.print_task_progress("PASS", task, attempt, copy_log, verify_log)
                if self.cfg.stop_after and task.label == self.cfg.stop_after:
                    log_event("STOP", f"stop-after reached; stop after completed task={task.label}")
                    self.run_final_status = "stopped"
                    return
                if self.drain_requested():
                    log_event("DRAIN", f"drain requested; stop after completed task={task.label}")
                    self.clear_drain_request()
                    self.run_final_status = "drained"
                    return
                return
            self.retry_total += 1
            log_event("RETRY", f"{task.label} failed verify, entering repair retry...")
            self.record_task_summary(task, "retrying", attempt, copy_log, verify_log, "验收失败，下一轮按本 task Validation 上限精准修复")
            self.print_task_progress("RETRY", task, attempt, copy_log, verify_log)
            if self.cfg.max_retries > 0 and attempt >= self.cfg.max_retries:
                self.mark_progress(task, "failed", f"达到最大重试次数：MAX_RETRIES={self.cfg.max_retries}", copy_log, verify_log, attempt)
                self.record_task_summary(task, "failed", attempt, copy_log, verify_log, f"达到最大重试次数：MAX_RETRIES={self.cfg.max_retries}")
                raise TaskLoopError(f"{task.label} reached max retries ({self.cfg.max_retries})", 1)
            if self.cfg.dry_run and self.cfg.dry_run_result == "FAIL" and attempt >= self.cfg.dry_run_max_attempts:
                self.mark_progress(task, "failed", f"dry-run 达到最大重试次数：DRY_RUN_MAX_ATTEMPTS={self.cfg.dry_run_max_attempts}", copy_log, verify_log, attempt)
                self.record_task_summary(task, "failed", attempt, copy_log, verify_log, f"dry-run 达到最大重试次数：DRY_RUN_MAX_ATTEMPTS={self.cfg.dry_run_max_attempts}")
                raise TaskLoopError(f"DRY_RUN stop at max retry attempts: {self.cfg.dry_run_max_attempts}", 1)


def json_dumps(value: object) -> str:
    import json

    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def output_file_signature(path: Path) -> tuple[str, int, int]:
    try:
        stat = path.stat()
    except FileNotFoundError:
        return ("missing", 0, 0)
    except OSError:
        return ("unreadable", 0, 0)
    return ("exists", stat.st_mtime_ns, stat.st_size)


def terminate_child(proc: subprocess.Popen[str], worker: threading.Thread) -> None:
    if proc.poll() is None:
        terminate_process_group(proc, signal.SIGTERM)
    worker.join(timeout=5)
    if worker.is_alive() and proc.poll() is None:
        terminate_process_group(proc, signal.SIGKILL)
    worker.join(timeout=5)


def terminate_process_group(proc: subprocess.Popen[str], sig: signal.Signals) -> None:
    try:
        os.killpg(proc.pid, sig)
    except OSError:
        try:
            if sig == signal.SIGTERM:
                proc.terminate()
            else:
                proc.kill()
        except OSError:
            pass


def sleep_with_drain_notice(seconds: int) -> None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        time.sleep(min(5, max(0, deadline - time.monotonic())))


def print_loop_status(cfg: RuntimeConfig) -> None:
    print("Task loop status")
    print(f"- progress_file: {cfg.progress_file}")
    print(f"- legacy_state_file: {cfg.state_file}")
    legacy_count = len(cfg.state_file.read_text(encoding="utf-8", errors="replace").splitlines()) if cfg.state_file.exists() else 0
    print(f"- legacy_completed_count: {legacy_count}")
    print(state.status_fragment(cfg.progress_file, cfg.lock_dir, cfg.log_root, cfg.drain_request_file), end="")
    print()
    sys.stdout.flush()
    pipeline = cfg.root_dir / "tasks/prompts/_shared/prompt_pipeline.py"
    subprocess.run([cfg.python_bin, str(pipeline), "status"], cwd=cfg.root_dir, check=False)


def reset_progress(cfg: RuntimeConfig) -> int:
    runner = TaskLoopRunner(cfg, "./task-loop reset-progress")
    runner.acquire_lock("reset-progress")
    try:
        for line in state.reset_progress(cfg.progress_file, cfg.progress_backup_root):
            log_event("INFO", line)
        return 0
    finally:
        runner.release_lock()


def clear_stale(cfg: RuntimeConfig) -> int:
    runner = TaskLoopRunner(cfg, "./task-loop clear-stale")
    runner.acquire_lock("clear-stale")
    try:
        for line in state.clear_stale(cfg.progress_file, cfg.lock_dir, cfg.progress_backup_root):
            log_event("INFO", line)
        return 0
    finally:
        runner.release_lock()


def preview_command(cfg: RuntimeConfig, command: str = "run") -> str:
    args = ["./task-loop", command]
    if cfg.dry_run:
        args.append("--dry-run")
    for phase in cfg.target_phases:
        args.extend(["--phase", phase])
    if cfg.max_tasks:
        args.extend(["--max-tasks", str(cfg.max_tasks)])
    if cfg.start_from:
        args.extend(["--start-from", cfg.start_from])
    if cfg.stop_after:
        args.extend(["--stop-after", cfg.stop_after])
    args.extend(["--risk-policy", cfg.risk_policy, "--risk-gate", cfg.risk_gate])
    env_bits = [
        f"MODEL={cfg.model}",
        f"MODEL_REASONING_EFFORT={cfg.model_reasoning_effort}",
        f"CODEX_EXEC_SANDBOX={cfg.codex_exec_sandbox}",
        f"GIT_CHECKPOINT={cfg.git_checkpoint}",
        f"MAX_RETRIES={cfg.max_retries}",
        f"PROGRESS_FILE={cfg.progress_file}",
        f"LOG_ROOT={cfg.log_root}",
        f"RUN_SUMMARY_ROOT={cfg.run_summary_root}",
        f"LOCK_DIR={cfg.lock_dir}",
        f"CONTROL_DIR={cfg.control_dir}",
    ]
    return " ".join(env_bits + args)


def apply_run_args(cfg: RuntimeConfig, args: argparse.Namespace) -> RuntimeConfig:
    if getattr(args, "model", None):
        cfg.model = args.model
    if getattr(args, "model_reasoning_effort", None):
        cfg.model_reasoning_effort = args.model_reasoning_effort
    if getattr(args, "codex_bin", None):
        cfg.codex_bin = args.codex_bin
    if getattr(args, "codex_exec_sandbox", None):
        cfg.codex_exec_sandbox = args.codex_exec_sandbox
    if getattr(args, "git_checkpoint", None):
        cfg.git_checkpoint = args.git_checkpoint
    if getattr(args, "git_branch_policy", None):
        cfg.git_branch_policy = args.git_branch_policy
    if getattr(args, "git_push_remote", None):
        cfg.git_push_remote = args.git_push_remote
    if getattr(args, "no_git_push_set_upstream", False):
        cfg.git_push_set_upstream = False
    if getattr(args, "max_retries", None) is not None:
        cfg.max_retries = args.max_retries
    if getattr(args, "dry_run_result", None):
        cfg.dry_run_result = args.dry_run_result
    if getattr(args, "dry_run_max_attempts", None) is not None:
        cfg.dry_run_max_attempts = args.dry_run_max_attempts
    if getattr(args, "progress_file", None):
        cfg.progress_file = Path(args.progress_file)
    if getattr(args, "log_root", None):
        cfg.log_root = Path(args.log_root)
    if getattr(args, "run_summary_root", None):
        cfg.run_summary_root = Path(args.run_summary_root)
    if getattr(args, "progress_backup_root", None):
        cfg.progress_backup_root = Path(args.progress_backup_root)
    if getattr(args, "lock_dir", None):
        cfg.lock_dir = Path(args.lock_dir)
    if getattr(args, "control_dir", None):
        cfg.control_dir = Path(args.control_dir)
    if getattr(args, "dry_run", False):
        cfg.dry_run = True
    if getattr(args, "phase", None):
        cfg.target_phases = list(args.phase)
    if getattr(args, "max_tasks", None) is not None:
        cfg.max_tasks = args.max_tasks
    if getattr(args, "start_from", None):
        cfg.start_from = normalize_task_ref(args.start_from)
    if getattr(args, "stop_after", None):
        cfg.stop_after = normalize_task_ref(args.stop_after)
    if getattr(args, "risk_gate", None):
        cfg.risk_gate = args.risk_gate
    if getattr(args, "risk_policy", None):
        cfg.risk_policy = args.risk_policy
    return cfg


def add_run_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--dry-run", action="store_true", help="仅模拟执行，不调用 codex")
    parser.add_argument("--phase", action="append", choices=list(PHASES), help="仅运行指定 phase，可重复")
    parser.add_argument("--max-tasks", type=int, help="最多执行 n 个 task（0 表示不限制）")
    parser.add_argument("--max-retries", type=int, help="最多重试次数（0 表示无限）")
    parser.add_argument("--start-from", help="从某个 task 开始，例如 phase-1/1-1-task-01 或 1-1/task-01")
    parser.add_argument("--stop-after", help="在某个 task PASS + checkpoint 后停止")
    parser.add_argument("--risk-gate", choices=["high", "mission-critical", "none"], help="风险门禁范围")
    parser.add_argument("--risk-policy", choices=["pause", "skip", "allow"], help="风险命中策略")
    parser.add_argument("--model", help="Codex model，优先级高于 MODEL")
    parser.add_argument("--model-reasoning-effort", help="Codex reasoning effort，优先级高于 MODEL_REASONING_EFFORT")
    parser.add_argument("--codex-bin", help="Codex CLI 路径，优先级高于 CODEX_BIN")
    parser.add_argument("--codex-exec-sandbox", choices=sorted(CODEX_SANDBOX_MODES), help="Codex exec sandbox 模式，优先级高于 CODEX_EXEC_SANDBOX")
    parser.add_argument("--git-checkpoint", choices=["off", "commit", "push"], help="Git checkpoint 模式")
    parser.add_argument("--git-branch-policy", choices=["auto", "require-task-branch", "current"], help="Git 分支策略")
    parser.add_argument("--git-push-remote", help="Git push remote")
    parser.add_argument("--no-git-push-set-upstream", action="store_true", help="push 时不自动设置 upstream")
    parser.add_argument("--dry-run-result", choices=["PASS", "FAIL"], help="dry-run verify 结果")
    parser.add_argument("--dry-run-max-attempts", type=int, help="dry-run FAIL 最大尝试次数")
    parser.add_argument("--progress-file", help="progress.json 路径，优先级高于 PROGRESS_FILE")
    parser.add_argument("--log-root", help="日志根目录，优先级高于 LOG_ROOT")
    parser.add_argument("--run-summary-root", help="summary 根目录，优先级高于 RUN_SUMMARY_ROOT")
    parser.add_argument("--progress-backup-root", help="progress 备份目录，优先级高于 PROGRESS_BACKUP_ROOT")
    parser.add_argument("--lock-dir", help="lock 目录，优先级高于 LOCK_DIR")
    parser.add_argument("--control-dir", help="control 目录，优先级高于 CONTROL_DIR")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="AreaMatrix task-loop runner")
    subparsers = parser.add_subparsers(dest="command")
    run = subparsers.add_parser("run", help="Run copy-ready / verify-ready loop")
    add_run_options(run)
    preview = subparsers.add_parser("preview", help="Preview run command/config without execution")
    add_run_options(preview)
    subparsers.add_parser("status", help="Show task-loop status")
    subparsers.add_parser("drain", help="Request live runner graceful drain")
    resume_stale = subparsers.add_parser("resume-stale", help="Resume first stale in_progress task")
    add_run_options(resume_stale)
    resume_failed = subparsers.add_parser("resume-failed", help="Resume first failed task")
    add_run_options(resume_failed)
    subparsers.add_parser("clear-stale", help="Clear stale in_progress records")
    subparsers.add_parser("reset-progress", help="Backup and reset progress.json")
    subparsers.add_parser("check", help="Run task-loop self-check")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    from . import self_check

    parser = build_parser()
    args = parser.parse_args(argv)
    command = args.command or "run"
    cfg = RuntimeConfig.from_env()

    try:
        if command == "status":
            print_loop_status(cfg)
            return 0
        if command == "drain":
            return TaskLoopRunner(cfg, "./task-loop drain").request_drain()
        if command == "clear-stale":
            return clear_stale(cfg)
        if command == "reset-progress":
            return reset_progress(cfg)
        if command == "check":
            return self_check.run_check(cfg.root_dir)
        if command == "preview":
            apply_run_args(cfg, args)
            print("即将执行：", preview_command(cfg, "run"))
            print("未执行。")
            return 0
        if command == "resume-stale":
            apply_run_args(cfg, args)
            return TaskLoopRunner(cfg, "./task-loop resume-stale").run_loop(resume_stale=True)
        if command == "resume-failed":
            apply_run_args(cfg, args)
            return TaskLoopRunner(cfg, "./task-loop resume-failed").run_loop(resume_failed=True)
        apply_run_args(cfg, args)
        return TaskLoopRunner(cfg, "./task-loop run").run_loop()
    except TaskLoopError as exc:
        print(str(exc), file=sys.stderr)
        return exc.code


if __name__ == "__main__":
    raise SystemExit(main())
