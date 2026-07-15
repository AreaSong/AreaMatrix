"""Authoring-only AreaFlow compatibility shim for AreaMatrix.

The shim permits local workflow planning artifacts while keeping promotion
apply, execution state, progress, logs, checkpoints, and task execution blocked.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Sequence


PROJECT_KEY = "areamatrix"
DEFAULT_API_BASE = "http://127.0.0.1:3847/api/v1"
LOCAL_SHIM_STATE = "authoring_only_shim"
TASK_LOOP_BLOCKED_COMMANDS = {
    "run",
    "resume-stale",
    "resume-failed",
    "reset-progress",
    "clear-stale",
    "drain",
}
STATUS_BLOCKED_COMMANDS = {
    "./task-loop run",
    "./task-loop resume-stale",
    "./task-loop resume-failed",
    "./task-loop reset-progress",
    "./task-loop clear-stale",
    "./task-loop drain",
    "changes generate --write outside v2 drafts",
    "promotion apply",
    "write execution",
}
WORKFLOW_WRITE_SUBCOMMANDS = {
    ("baseline", "write"),
    ("project", "write"),
    ("closeout", "write"),
}
AUTHORING_WORKFLOW_COMMANDS = {
    "init",
    "discuss",
    "baseline",
    "middle",
    "plan",
    "drafts",
    "queue",
    "promote",
}


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def status_projection_path(root: Path | None = None) -> Path:
    return (root or project_root()) / ".areaflow/status.json"


def load_status_projection(root: Path | None = None) -> tuple[dict[str, Any] | None, str]:
    path = status_projection_path(root)
    if not path.is_file():
        return None, f"missing status projection: {path}"
    try:
        return json.loads(path.read_text(encoding="utf-8")), ""
    except json.JSONDecodeError as exc:
        return None, f"invalid status projection JSON: {exc}"


def area_flow_project_url(status: dict[str, Any] | None) -> str:
    if status:
        value = str(status.get("area_flow_url") or "").strip()
        if value:
            return value
    return "http://127.0.0.1:3847/projects/areamatrix"


def area_flow_api_base(status: dict[str, Any] | None = None) -> str:
    env_value = os.environ.get("AREAFLOW_API_URL", "").strip()
    if env_value:
        return env_value.rstrip("/")
    project_url = area_flow_project_url(status)
    if "/projects/" in project_url:
        return project_url.split("/projects/", 1)[0].rstrip("/") + "/api/v1"
    return DEFAULT_API_BASE


def api_get(path: str, status: dict[str, Any] | None = None) -> tuple[dict[str, Any] | None, str]:
    if os.environ.get("AREAFLOW_SHIM_ALLOW_LOCAL_API") != "1":
        return None, "AreaFlow API disabled by local shim; set AREAFLOW_SHIM_ALLOW_LOCAL_API=1 to opt in"
    url = f"{area_flow_api_base(status)}{path}"
    try:
        with urllib.request.urlopen(url, timeout=1.5) as response:
            payload = response.read().decode("utf-8")
        return json.loads(payload), ""
    except (OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
        return None, f"AreaFlow API unavailable: {exc}"


def areaflow_bin() -> str:
    configured = os.environ.get("AREAFLOW_BIN", "").strip()
    if configured:
        return configured
    return shutil.which("areaflow") or ""


def cli_query(args: Sequence[str]) -> tuple[str, str]:
    binary = areaflow_bin()
    if not binary:
        return "", "AreaFlow CLI unavailable: AREAFLOW_BIN is not set and `areaflow` is not on PATH"
    try:
        proc = subprocess.run(
            [binary, *args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=8,
            check=False,
        )
    except OSError as exc:
        return "", f"AreaFlow CLI unavailable: {exc}"
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout).strip()
        return "", f"AreaFlow CLI query failed: {detail}"
    return proc.stdout.strip(), ""


def _active_version_lines(status: dict[str, Any]) -> list[str]:
    lines: list[str] = []
    versions = status.get("active_versions")
    if not isinstance(versions, list):
        return lines
    for version in versions:
        if not isinstance(version, dict):
            continue
        progress = version.get("rough_progress")
        progress = progress if isinstance(progress, dict) else {}
        lines.append(
            "active_version: "
            f"{version.get('display_label', 'unknown')} "
            f"status={version.get('lifecycle_status', 'unknown')} "
            f"progress={progress.get('percent', 'unknown')}% "
            f"blocked={str(progress.get('blocked', 'unknown')).lower()} "
            f"label={progress.get('label', '')}"
        )
    return lines


def print_status_projection_summary(
    root: Path | None = None,
    *,
    heading: str = "AreaFlow authoring-only shim status",
) -> int:
    status, error = load_status_projection(root)
    print(heading)
    print(f"- local_shim_lifecycle_state: {LOCAL_SHIM_STATE}")
    print("- execution_forwarding: blocked")
    print("- task_loop_run_forwarding: blocked")
    if status is None:
        print(f"- source: unavailable ({error})")
        return 1

    compatibility = status.get("compatibility")
    compatibility = compatibility if isinstance(compatibility, dict) else {}
    print("- source: .areaflow/status.json")
    print(f"- project_id: {status.get('project_id', PROJECT_KEY)}")
    print(f"- area_flow_url: {area_flow_project_url(status)}")
    print(f"- cutover_phase: {status.get('cutover_phase', 'unknown')}")
    print(f"- status_projection_shim_lifecycle_state: {compatibility.get('shim_lifecycle_state', 'unknown')}")
    print(f"- source_snapshot_hash: {status.get('source_snapshot_hash', 'unknown')}")
    for line in _active_version_lines(status):
        print(f"- {line}")
    blocked_commands = compatibility.get("blocked_commands")
    if isinstance(blocked_commands, list):
        for command in blocked_commands:
            print(f"- blocked_command: {command}")
    return 0


def print_json_payload(label: str, payload: dict[str, Any]) -> int:
    print(f"AreaFlow authoring-only shim: {label}")
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


def workflow_status(root: Path | None = None) -> int:
    status, _ = load_status_projection(root)
    payload, api_error = api_get(f"/projects/{PROJECT_KEY}/summary", status)
    if payload is not None:
        return print_json_payload("workflow status from AreaFlow API", payload)
    output, cli_error = cli_query(["project", "summary", PROJECT_KEY, "--json"])
    if output:
        print("AreaFlow authoring-only shim: workflow status from AreaFlow CLI")
        print(output)
        return 0
    rc = print_status_projection_summary(root, heading="AreaFlow authoring-only shim: workflow status fallback")
    print(f"- api_status: {api_error}")
    print(f"- cli_status: {cli_error}")
    return rc


def workflow_doctor(root: Path | None = None) -> int:
    status, error = load_status_projection(root)
    print("AreaFlow authoring-only shim: workflow doctor")
    print(f"- local_shim_lifecycle_state: {LOCAL_SHIM_STATE}")
    print("- native_workflow_doctor: skipped")
    print("- native_workflow_doctor_reason: compatibility projection check only")
    print("- task_loop_run_forwarding: blocked")
    if status is None:
        print(f"- status_projection: fail ({error})")
        return 1
    required = (
        "schema_version",
        "project_id",
        "area_flow_url",
        "cutover_phase",
        "active_versions",
        "source_snapshot_hash",
        "compatibility",
    )
    missing = [key for key in required if key not in status]
    if status.get("project_id") != PROJECT_KEY:
        missing.append("project_id=areamatrix")
    compatibility = status.get("compatibility")
    if not isinstance(compatibility, dict):
        missing.append("compatibility")
    else:
        if compatibility.get("shim_lifecycle_state") != LOCAL_SHIM_STATE:
            missing.append(f"compatibility.shim_lifecycle_state={LOCAL_SHIM_STATE}")
        blocked_commands = compatibility.get("blocked_commands", [])
        blocked_commands = blocked_commands if isinstance(blocked_commands, list) else []
        for command in sorted(STATUS_BLOCKED_COMMANDS):
            if command not in blocked_commands:
                missing.append(f"compatibility.blocked_commands[{command}]")
    if missing:
        print("- status_projection: blocked")
        for key in missing:
            print(f"- missing_or_invalid: {key}")
        return 1
    print("- status_projection: pass")
    print(f"- status_projection_shim_lifecycle_state: {compatibility.get('shim_lifecycle_state', 'unknown')}")
    return 0


def workflow_init(args: Sequence[str], root: Path | None = None) -> int:
    values = list(args)
    version = ""
    for index, value in enumerate(values):
        if value == "--version" and index + 1 < len(values):
            version = values[index + 1]
        elif value.startswith("--version="):
            version = value.split("=", 1)[1]
    if "--write" in values:
        print("AreaFlow authoring-only shim: workflow init blocked")
        print("- reason: Package B does not authorize writing workflow/versions/**")
        print("- command: ./dev workflow init --write")
        print("- next: request a separate AreaFlow authoring/cutover approval")
        return 2
    if not version:
        print("AreaFlow authoring-only shim: workflow init requires --version <version>")
        return 2
    status, _ = load_status_projection(root)
    print("AreaFlow authoring-only shim: workflow init preview")
    print(f"- version: {version}")
    print("- local_write: false")
    print("- workflow_versions_write: blocked")
    print("- execution_write: blocked")
    print(f"- area_flow_url: {area_flow_project_url(status)}")
    print("- note: preview only; no AreaMatrix workflow files were created")
    return 0


def workflow_open(root: Path | None = None) -> int:
    status, _ = load_status_projection(root)
    print("AreaFlow authoring-only shim: workflow open")
    print(f"- area_flow_url: {area_flow_project_url(status)}")
    print("- browser_opened: false")
    print("- note: open the AreaFlow URL manually if the local service is running")
    return 0


def task_loop_status(root: Path | None = None) -> int:
    rc = print_status_projection_summary(root, heading="AreaFlow authoring-only shim: task-loop status")
    print("- legacy_runner_started: false")
    print("- run_command: blocked")
    return rc


def block_task_loop_command(command: str) -> int:
    print(f"AreaFlow authoring-only shim: ./task-loop {command} blocked")
    print("- reason: local cutover authorizes planning artifacts only")
    print("- execution_forwarding: disabled")
    print("- legacy_runner_started: false")
    print("- progress_written: false")
    print("- logs_written: false")
    print("- checkpoint_written: false")
    print("- next: request explicit execution cutover authorization before enabling task-loop run forwarding")
    return 2


def workflow_write_requested(command: str, args: Sequence[str]) -> bool:
    values = list(args)
    if "--write" in values or any(value.startswith("--write=") for value in values):
        return True
    return any(command == parent and child in values for parent, child in WORKFLOW_WRITE_SUBCOMMANDS)


def option_value(args: Sequence[str], option: str) -> str:
    values = list(args)
    for index, value in enumerate(values):
        if value == option and index + 1 < len(values):
            return values[index + 1]
        if value.startswith(f"{option}="):
            return value.split("=", 1)[1]
    return ""


def v2_draft_write_allowed(args: Sequence[str], root: Path) -> bool:
    if option_value(args, "--version") != "v2":
        return False
    configured = option_value(args, "--out-dir")
    target = Path(configured) if configured else root / "workflow/versions/v2/drafts"
    target = target if target.is_absolute() else root / target
    allowed = (root / "workflow/versions/v2/drafts").resolve()
    try:
        target.resolve().relative_to(allowed)
    except ValueError:
        return False
    return True


def block_dev_write_command(surface: str, command: str, args: Sequence[str]) -> int:
    display_args = list(args)
    if display_args[:1] == [command]:
        display_args = display_args[1:]
    printable = " ".join(["./dev", surface, command, *display_args]).strip()
    print("AreaFlow authoring-only shim: dev write command blocked")
    print("- reason: local cutover authorizes planning artifacts only")
    print(f"- command: {printable}")
    print("- local_write: false")
    print("- workflow_versions_write: blocked")
    print("- execution_write: blocked")
    print("- progress_written: false")
    print("- logs_written: false")
    print("- checkpoint_written: false")
    print("- next: request explicit execution cutover authorization")
    return 2


def block_workflow_write_command(command: str, args: Sequence[str]) -> int:
    return block_dev_write_command("workflow", command, args)


def handle_workflow_command(command: str, args: Sequence[str], root: Path | None = None) -> int | None:
    if command == "status":
        return workflow_status(root)
    if command == "open":
        return workflow_open(root)
    values = list(args)
    if command == "promote" and workflow_write_requested(command, values):
        if "approve" in values or "apply" in values:
            return block_workflow_write_command(command, values)
    if workflow_write_requested(command, values) and command not in AUTHORING_WORKFLOW_COMMANDS:
        return block_workflow_write_command(command, args)
    return None


def handle_changes_command(command: str, args: Sequence[str], root: Path | None = None) -> int | None:
    if command == "generate" and workflow_write_requested(command, args):
        resolved_root = (root or project_root()).resolve()
        if v2_draft_write_allowed(args, resolved_root):
            return None
        return block_dev_write_command("changes", command, args)
    return None


def handle_task_loop_command(command: str, root: Path | None = None) -> int | None:
    if command == "status":
        return task_loop_status(root)
    if command in TASK_LOOP_BLOCKED_COMMANDS:
        return block_task_loop_command(command)
    return None
