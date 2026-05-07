"""Workflow result projection and closeout checks."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

from .changes import DraftArtifact, as_list, display_path, parse_yaml_subset, write_artifacts
from .workflow_baseline import validate_baseline
from .workflow_states import ARTIFACT_STATUSES, status_list
from tasks.prompts._shared.prompt_pipeline_lib.repository import load_manifests
from scripts.task_loop.state import progress_data, verify_result


VERSION_ROOT = Path("workflow/versions")
PROJECTION_ROOT_NAME = "projection"
CLOSEOUT_ROOT_NAME = "closeout"
PROMOTION_ROOT_NAME = "promotion"
PROGRESS_FILE = Path("tasks/prompts/_shared/progress.json")
TEMPLATE_REFERENCE_VERSION = "v-template"


@dataclass(frozen=True)
class ProjectedTask:
    semantic_id: str
    live_label: str
    feature: str
    task_key: str
    status: str
    verify: str
    checkpoint: str
    trace_ok: bool


def projection_root(root: Path, version: str) -> Path:
    return root / VERSION_ROOT / version / PROJECTION_ROOT_NAME


def projection_path(root: Path, version: str) -> Path:
    return projection_root(root, version) / "projection.yaml"


def closeout_root(root: Path, version: str) -> Path:
    return root / VERSION_ROOT / version / CLOSEOUT_ROOT_NAME


def closeout_path(root: Path, version: str) -> Path:
    return closeout_root(root, version) / "closeout.yaml"


def promotion_path(root: Path, version: str) -> Path:
    return root / VERSION_ROOT / version / PROMOTION_ROOT_NAME / "promotion.yaml"


def read_yaml(path: Path) -> tuple[list[str], dict[str, Any] | None]:
    try:
        data = parse_yaml_subset(path.read_text(encoding="utf-8"), path)
    except ValueError as exc:
        return [str(exc)], None
    if not isinstance(data, dict):
        return [f"{path}: top-level YAML must be a mapping"], None
    return [], data


def load_promotion(root: Path, version: str) -> tuple[list[str], dict[str, Any] | None]:
    path = promotion_path(root, version)
    if not path.is_file():
        return [f"missing promotion preview: {display_path(root, path)}"], None
    return read_yaml(path)


def progress_entry(root: Path, label: str) -> dict[str, Any]:
    progress_file = root / PROGRESS_FILE
    if not progress_file.is_file():
        return {}
    data = progress_data(progress_file)
    entry = data.get("tasks", {}).get(label, {})
    return entry if isinstance(entry, dict) else {}


def manifest_trace_ok(label: str, semantic_id: str) -> bool:
    try:
        manifests = load_manifests()
    except Exception:
        return False
    entry = manifests.get(label)
    return bool(entry and entry.source_task == f"workflow:{semantic_id}")


def projected_status(entry: dict[str, Any], verify: str, checkpoint: str) -> str:
    if entry.get("status") == "completed" and verify == "pass" and checkpoint == "committed":
        return "done"
    if entry.get("status") in {"failed", "blocked"} or verify == "fail":
        return "blocked"
    if entry:
        return "promoted"
    return "draft"


def collect_projected_tasks(root: Path, version: str) -> tuple[list[str], list[ProjectedTask], dict[str, Any] | None]:
    errors, promotion = load_promotion(root, version)
    if errors or promotion is None:
        return errors, [], promotion
    tasks: list[ProjectedTask] = []
    for index, item in enumerate(as_list(promotion.get("tasks")), start=1):
        if not isinstance(item, dict):
            errors.append(f"{display_path(root, promotion_path(root, version))}: tasks #{index}: must be a mapping")
            continue
        semantic_id = str(item.get("semantic_id", "")).strip()
        live_label = str(item.get("live_label", "")).strip()
        feature = str(item.get("feature", "")).strip()
        task_key = str(item.get("task_key", "")).strip()
        if not semantic_id or not live_label:
            errors.append(f"{display_path(root, promotion_path(root, version))}: tasks #{index}: semantic_id and live_label are required")
            continue
        entry = progress_entry(root, live_label)
        verify = verify_result(entry.get("verify_log"))
        checkpoint = str(entry.get("git_checkpoint_status", "missing") or "missing")
        status = projected_status(entry, verify, checkpoint)
        tasks.append(
            ProjectedTask(
                semantic_id=semantic_id,
                live_label=live_label,
                feature=feature,
                task_key=task_key,
                status=status,
                verify=verify,
                checkpoint=checkpoint,
                trace_ok=manifest_trace_ok(live_label, semantic_id),
            )
        )
    return errors, tasks, promotion


def projection_decision(tasks: Sequence[ProjectedTask], promotion: dict[str, Any] | None) -> str:
    if not tasks:
        return "blocked"
    if promotion and promotion.get("blocked") is True:
        return "blocked"
    if all(task.status == "done" and task.trace_ok for task in tasks):
        return "done"
    if any(task.status in {"promoted", "done"} for task in tasks):
        return "promoted"
    return "blocked"


def projection_content(version: str, tasks: Sequence[ProjectedTask], decision: str) -> str:
    lines = [
        f"version: {version}",
        f"status: {decision}",
        "kind: result-projection",
        "source: tasks/prompts/_shared/progress.json",
        "tasks:",
    ]
    for task in tasks:
        lines.extend(
            [
                f"  - semantic_id: {task.semantic_id}",
                f"    live_label: {task.live_label}",
                f"    feature: {task.feature}",
                f"    task_key: {task.task_key}",
                f"    status: {task.status}",
                f"    verify: {task.verify}",
                f"    checkpoint: {task.checkpoint}",
                f"    trace_ok: {'true' if task.trace_ok else 'false'}",
                "    trace:",
                f"      promotion_mapping: workflow/versions/{version}/promotion/promotion.yaml",
                f"      queue_candidate: workflow/versions/{version}/queue/{task.feature}/queue.yaml",
                f"      draft_id: workflow/versions/{version}/drafts/{task.feature}/{task.task_key}.copy.md",
                f"      plan_item: workflow/versions/{version}/plans/{task.feature}.plan.md",
                f"      change_id: workflow/versions/{version}/changes",
                f"      middle_layer_entry: workflow/versions/{version}/middle-layer/{task.feature}.yaml",
                f"      docs_discussion: workflow/versions/{version}/discussion/docs-discussion.md",
            ]
        )
    return "\n".join(lines).rstrip() + "\n"


def projection_artifact(root: Path, version: str) -> tuple[list[str], DraftArtifact | None, list[ProjectedTask], str]:
    errors, tasks, promotion = collect_projected_tasks(root, version)
    decision = projection_decision(tasks, promotion)
    if errors:
        return errors, None, tasks, decision
    artifact = DraftArtifact(projection_path(root, version), projection_content(version, tasks, decision))
    return [], artifact, tasks, decision


def validate_projection(root: Path, version: str, require_file: bool) -> tuple[list[str], dict[str, Any] | None]:
    path = projection_path(root, version)
    if not path.is_file():
        if require_file:
            return [f"missing workflow projection: {display_path(root, path)}"], None
        return [], None
    errors, data = read_yaml(path)
    if errors or data is None:
        return errors, data
    if data.get("version") != version:
        errors.append(f"{display_path(root, path)}: version must be {version}")
    if data.get("status") not in ARTIFACT_STATUSES:
        errors.append(f"{display_path(root, path)}: status must be one of {status_list(ARTIFACT_STATUSES)}")
    if data.get("status") not in {"blocked", "promoted", "done"}:
        errors.append(f"{display_path(root, path)}: projection status must be blocked, promoted, or done")
    if data.get("kind") != "result-projection":
        errors.append(f"{display_path(root, path)}: kind must be result-projection")
    for index, item in enumerate(as_list(data.get("tasks")), start=1):
        prefix = f"{display_path(root, path)}: tasks #{index}"
        if not isinstance(item, dict):
            errors.append(f"{prefix}: must be a mapping")
            continue
        for key in ["semantic_id", "live_label", "status", "verify", "checkpoint", "trace_ok"]:
            if key not in item:
                errors.append(f"{prefix}: missing field: {key}")
        trace = item.get("trace")
        if not isinstance(trace, dict):
            errors.append(f"{prefix}: trace must be a mapping")
        else:
            for key in ["promotion_mapping", "queue_candidate", "draft_id", "plan_item", "change_id", "middle_layer_entry", "docs_discussion"]:
                if key not in trace:
                    errors.append(f"{prefix}: trace missing {key}")
        if item.get("status") == "done":
            if item.get("verify") != "pass":
                errors.append(f"{prefix}: done task must have verify=pass")
            if item.get("checkpoint") != "committed":
                errors.append(f"{prefix}: done task must have checkpoint=committed")
            if item.get("trace_ok") is not True:
                errors.append(f"{prefix}: done task must have trace_ok=true")
    return errors, data


def closeout_content(version: str, projection_status: str, decision: str, blockers: Sequence[str]) -> str:
    lines = [
        f"version: {version}",
        f"status: {decision}",
        "kind: closeout-audit",
        f"projection_status: {projection_status}",
        "blockers:",
    ]
    if blockers:
        for blocker in blockers:
            lines.append(f"  - {blocker}")
    else:
        lines.append("  - None")
    lines.extend(
        [
            "evidence:",
            f"  projection: workflow/versions/{version}/projection/projection.yaml",
            f"  promotion: workflow/versions/{version}/promotion/promotion.yaml",
            "  progress: tasks/prompts/_shared/progress.json",
            "  verify: required-for-done",
            "  checkpoint: required-for-done",
            "remaining_risks:",
        ]
    )
    if blockers:
        for blocker in blockers:
            lines.append(f"  - {blocker}")
    else:
        lines.append("  - None")
    lines.append("archive_readiness: " + ("ready" if decision == "done" else "blocked"))
    return "\n".join(lines).rstrip() + "\n"


def closeout_artifact(root: Path, version: str) -> tuple[list[str], DraftArtifact | None, str]:
    errors, projection = validate_projection(root, version, require_file=True)
    baseline_errors, _ = validate_baseline(root, version, require_file=True)
    errors.extend(baseline_errors)
    projection_status = str(projection.get("status", "blocked")) if projection else "blocked"
    blockers = list(errors)
    if projection_status != "done":
        blockers.append(f"projection status is {projection_status}, expected done")
    decision = "done" if not blockers else "blocked"
    artifact = DraftArtifact(closeout_path(root, version), closeout_content(version, projection_status, decision, blockers))
    return [], artifact, decision


def validate_closeout(root: Path, version: str, require_file: bool) -> tuple[list[str], dict[str, Any] | None]:
    path = closeout_path(root, version)
    if not path.is_file():
        if require_file:
            return [f"missing workflow closeout: {display_path(root, path)}"], None
        return [], None
    errors, data = read_yaml(path)
    if errors or data is None:
        return errors, data
    if data.get("version") != version:
        errors.append(f"{display_path(root, path)}: version must be {version}")
    if data.get("status") not in ARTIFACT_STATUSES:
        errors.append(f"{display_path(root, path)}: status must be one of {status_list(ARTIFACT_STATUSES)}")
    if data.get("status") not in {"blocked", "done", "superseded"}:
        errors.append(f"{display_path(root, path)}: closeout status must be blocked, done, or superseded")
    if data.get("kind") != "closeout-audit":
        errors.append(f"{display_path(root, path)}: kind must be closeout-audit")
    if data.get("status") == "done":
        projection_errors, projection = validate_projection(root, version, require_file=True)
        errors.extend(projection_errors)
        if not projection or projection.get("status") != "done":
            errors.append(f"{display_path(root, path)}: done closeout requires done projection")
    return errors, data


def print_projection(root: Path, artifact: DraftArtifact, tasks: Sequence[ProjectedTask], decision: str) -> None:
    print("Workflow result projection")
    print("- mode: preview only; no files written")
    print("- live queue: not modified")
    print(f"- status: {decision}")
    print(f"- tasks: {len(tasks)}")
    print()
    print(f"--- {display_path(root, artifact.path)} ---")
    print(artifact.content.rstrip())


def run_workflow_project(root: Path, args: argparse.Namespace) -> int:
    command = args.project_command
    if command == "doctor":
        errors, data = validate_projection(root, args.version, require_file=True)
        if errors:
            print("workflow project doctor: FAILED")
            for error in errors:
                print(f"- {error}")
            return 1
        print("workflow project doctor: OK")
        print(f"- version: {args.version}")
        print(f"- status: {data.get('status') if data else 'unknown'}")
        if args.version == TEMPLATE_REFERENCE_VERSION and data and data.get("status") == "blocked":
            print("- note: blocked as expected for template reference; no live task-loop verify/checkpoint evidence is required or claimed.")
        return 0
    errors, artifact, tasks, decision = projection_artifact(root, args.version)
    if errors or artifact is None:
        print(f"workflow project {command}: FAILED")
        for error in errors:
            print(f"- {error}")
        return 1
    if command == "preview":
        print_projection(root, artifact, tasks, decision)
        return 0
    if command == "write":
        try:
            written = write_artifacts([artifact], force=args.force, label="workflow projection file")
        except FileExistsError as exc:
            print(f"workflow project write: {exc}")
            return 1
        print("workflow project write: wrote files")
        for path in written:
            print(f"  - {path}")
        return 0
    print(f"workflow project: unsupported command {command}")
    return 2


def run_workflow_closeout(root: Path, args: argparse.Namespace) -> int:
    command = args.closeout_command
    if command == "doctor":
        errors, data = validate_closeout(root, args.version, require_file=True)
        if errors:
            print("workflow closeout doctor: FAILED")
            for error in errors:
                print(f"- {error}")
            return 1
        print("workflow closeout doctor: OK")
        print(f"- version: {args.version}")
        print(f"- status: {data.get('status') if data else 'unknown'}")
        if args.version == TEMPLATE_REFERENCE_VERSION and data and data.get("status") == "blocked":
            print("- note: blocked as expected for template reference; no live task-loop verify/checkpoint evidence is required or claimed.")
        return 0
    errors, artifact, decision = closeout_artifact(root, args.version)
    if errors or artifact is None:
        print(f"workflow closeout {command}: FAILED")
        for error in errors:
            print(f"- {error}")
        return 1
    if command == "preview":
        print("Workflow closeout")
        print("- mode: preview only; no files written")
        print(f"- status: {decision}")
        print()
        print(f"--- {display_path(root, artifact.path)} ---")
        print(artifact.content.rstrip())
        return 0
    if command == "write":
        try:
            written = write_artifacts([artifact], force=args.force, label="workflow closeout file")
        except FileExistsError as exc:
            print(f"workflow closeout write: {exc}")
            return 1
        print("workflow closeout write: wrote files")
        for path in written:
            print(f"  - {path}")
        return 0
    print(f"workflow closeout: unsupported command {command}")
    return 2
