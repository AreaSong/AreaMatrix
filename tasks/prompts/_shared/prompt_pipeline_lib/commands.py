from __future__ import annotations

import argparse
from pathlib import Path
import sys

from .coverage import core_coverage_stats, page_feature_audit
from .doctor import collect_doctor_findings
from .paths import COPY_READY_ROOT, PROGRESS_PATH, VERIFY_READY_ROOT, label_sort_key, rel
from .phase_rendering import print_phase_verify_prompt
from .rendering import (
    capture_task_prompt,
    clear_phase_export_dir,
    print_copy_prompt,
    print_verify_prompt,
    prompt_export_filename,
)
from .repository import (
    filter_labels,
    load_progress,
    mark_progress,
    ordered_labels,
    ready_for_next,
    save_progress,
    task_status,
)


def command_export(args: argparse.Namespace) -> int:
    errors, warnings, tasks, manifests = collect_doctor_findings()
    if errors:
        return print_command_errors("export: doctor failed", errors, warnings)
    labels = export_labels(args, tasks, manifests)
    if not labels:
        target = "all phases" if args.all else args.phase
        print(f"export: no tasks found for {target}", file=sys.stderr)
        return 1
    phase_dirs = prepare_export_dirs(labels, tasks)
    copy_count, verify_count = write_export_prompts(labels, tasks, manifests, phase_dirs)
    print_export_summary(labels, tasks, copy_count, verify_count, warnings)
    return 0


def print_command_errors(title: str, errors: list[str], warnings: list[str]) -> int:
    print(title)
    for error in errors:
        print(f"- ERROR: {error}")
    for warning in warnings:
        print(f"- WARN: {warning}")
    return 1


def export_labels(args: argparse.Namespace, tasks: dict, manifests: dict) -> list[str]:
    labels = ordered_labels(tasks, manifests)
    return labels if args.all else filter_labels(labels, tasks, args.phase)


def prepare_export_dirs(labels: list[str], tasks: dict) -> dict[tuple[str, str], Path]:
    phase_dirs: dict[tuple[str, str], Path] = {}
    for phase in sorted({tasks[label].phase for label in labels}):
        phase_dirs[("copy", phase)] = clear_phase_export_dir(COPY_READY_ROOT, phase)
        phase_dirs[("verify", phase)] = clear_phase_export_dir(VERIFY_READY_ROOT, phase)
    return phase_dirs


def write_export_prompts(labels: list[str], tasks: dict, manifests: dict, phase_dirs: dict) -> tuple[int, int]:
    copy_count = 0
    verify_count = 0
    for label in labels:
        filename = prompt_export_filename(label)
        task = tasks[label]
        entry = manifests[label]
        write_prompt(phase_dirs[("copy", task.phase)] / filename, task, entry, "copy")
        write_prompt(phase_dirs[("verify", task.phase)] / filename, task, entry, "verify")
        copy_count += 1
        verify_count += 1
    return copy_count, verify_count


def write_prompt(path: Path, task, entry, mode: str) -> None:
    path.write_text(capture_task_prompt(task, entry, mode), encoding="utf-8")


def print_export_summary(labels: list[str], tasks: dict, copy_count: int, verify_count: int, warnings: list[str]) -> None:
    phases = sorted({tasks[label].phase for label in labels})
    print("export: OK")
    print(f"- phases: {', '.join(phases)}")
    print(f"- copy-ready: {copy_count}")
    print(f"- verify-ready: {verify_count}")
    print(f"- copy root: {rel(COPY_READY_ROOT)}")
    print(f"- verify root: {rel(VERIFY_READY_ROOT)}")
    print_warnings(warnings)


def command_doctor(_: argparse.Namespace) -> int:
    errors, warnings, tasks, manifests = collect_doctor_findings()
    if errors:
        return print_command_errors("doctor: FAILED", errors, warnings)
    high_risk = [entry for entry in manifests.values() if entry.risk in {"High", "Mission-Critical"}]
    print("doctor: OK")
    print(f"- tasks: {len(tasks)}")
    print(f"- manifests: {len(manifests)}")
    print(f"- high risk tasks: {len(high_risk)}")
    print_warnings(warnings)
    return 0


def command_plan(args: argparse.Namespace) -> int:
    errors, warnings, tasks, manifests = collect_doctor_findings()
    if errors:
        print("plan: doctor failed; run doctor for details", file=sys.stderr)
        return 1
    for label in export_labels(args, tasks, manifests):
        print_plan_item(label, tasks[label], manifests[label])
    print_warnings(warnings)
    return 0


def print_plan_item(label: str, task, entry) -> None:
    deps = ", ".join(entry.depends) if entry.depends else "None"
    print(f"{label} [{task.phase}] {task.title}")
    print(f"  risk: {entry.risk}; depends: {deps}")


def command_next(_: argparse.Namespace) -> int:
    errors, _, tasks, manifests = collect_doctor_findings()
    if errors:
        print("next: doctor failed; run doctor for details", file=sys.stderr)
        return 1
    return print_next_task(tasks, manifests)


def print_next_task(tasks: dict, manifests: dict) -> int:
    progress = load_progress()
    for label in ordered_labels(tasks, manifests):
        status = task_status(progress, label)
        if status != "completed" and ready_for_next(label, manifests, progress):
            print_next_task_details(label, tasks[label], manifests[label], status)
            return 0
    print("No ready pending task.")
    return 0


def print_next_task_details(label: str, task, entry, status: str) -> None:
    print(f"{label} [{task.phase}] {task.title}")
    print(f"risk: {entry.risk}")
    print(f"status: {status}")
    print(f"render: python3 tasks/prompts/_shared/prompt_pipeline.py render --task {label}")
    print(f"verify: python3 tasks/prompts/_shared/prompt_pipeline.py verify --task {label}")


def command_render(args: argparse.Namespace) -> int:
    errors, _, tasks, manifests = collect_doctor_findings()
    if errors:
        print("render: doctor failed; run doctor for details", file=sys.stderr)
        return 1
    if args.task not in tasks:
        print(f"unknown task: {args.task}", file=sys.stderr)
        return 1
    task = tasks[args.task]
    entry = manifests[args.task]
    print_verify_prompt(task, entry) if args.mode == "verify" else print_copy_prompt(task, entry)
    return 0


def command_verify(args: argparse.Namespace) -> int:
    errors, _, tasks, manifests = collect_doctor_findings()
    if errors:
        print("verify: doctor failed; run doctor for details", file=sys.stderr)
        return 1
    if args.phase:
        return print_phase_verify_prompt(args.phase, tasks, manifests)
    args.mode = "verify"
    return command_render(args)


def command_mark(args: argparse.Namespace) -> int:
    errors, _, tasks, manifests = collect_doctor_findings()
    if errors:
        print("mark: doctor failed; run doctor for details", file=sys.stderr)
        return 1
    if args.task not in tasks:
        print(f"unknown task: {args.task}", file=sys.stderr)
        return 1
    if not mark_dependencies_satisfied(args, manifests):
        return 1
    return write_mark(args)


def mark_dependencies_satisfied(args: argparse.Namespace, manifests: dict) -> bool:
    if args.status != "completed":
        return True
    progress = load_progress()
    missing = [dep for dep in manifests[args.task].depends if task_status(progress, dep) != "completed"]
    if missing and not args.force:
        print(f"cannot mark completed; dependencies are not completed: {', '.join(missing)}", file=sys.stderr)
        print("use --force only if this is intentional", file=sys.stderr)
        return False
    return True


def write_mark(args: argparse.Namespace) -> int:
    progress = load_progress()
    task_map = progress.setdefault("tasks", {})
    if not isinstance(task_map, dict):
        print("invalid progress file: tasks must be an object", file=sys.stderr)
        return 1
    mark_progress(task_map, args.task, args.status, args.note or "")
    save_progress(progress)
    print(f"marked {args.task} as {args.status}")
    return 0


def command_status(_: argparse.Namespace) -> int:
    errors, warnings, tasks, manifests = collect_doctor_findings()
    if errors:
        return print_command_errors("status: doctor failed", errors, [])
    progress = load_progress()
    by_phase, by_risk, by_status = status_counts(tasks, manifests, progress)
    print_status_summary(tasks, by_phase, by_risk, by_status)
    print(f"- first task: {first_ready_task(tasks, manifests, progress)}")
    print(f"- progress file: {rel(PROGRESS_PATH) if PROGRESS_PATH.exists() else 'not created'}")
    print_warnings(warnings)
    return 0


def status_counts(tasks: dict, manifests: dict, progress: dict) -> tuple[dict[str, int], dict[str, int], dict[str, int]]:
    by_phase: dict[str, int] = {}
    by_risk: dict[str, int] = {}
    by_status: dict[str, int] = {}
    for label, task in tasks.items():
        by_phase[task.phase] = by_phase.get(task.phase, 0) + 1
        risk = manifests[label].risk
        by_risk[risk] = by_risk.get(risk, 0) + 1
        status = task_status(progress, label)
        by_status[status] = by_status.get(status, 0) + 1
    return by_phase, by_risk, by_status


def print_status_summary(tasks: dict, by_phase: dict[str, int], by_risk: dict[str, int], by_status: dict[str, int]) -> None:
    print("Prompt library status")
    print(f"- tasks: {len(tasks)}")
    print_count_group("phases", sorted(by_phase), by_phase)
    print_count_group("risks", ["Low", "Medium", "High", "Mission-Critical", "Unspecified"], by_risk)
    print_count_group("progress", ["pending", "in_progress", "blocked", "failed", "completed"], by_status)


def print_count_group(title: str, keys: list[str], values: dict[str, int]) -> None:
    print(f"- {title}:")
    for key in keys:
        if key in values:
            print(f"  - {key}: {values[key]}")


def first_ready_task(tasks: dict, manifests: dict, progress: dict) -> str:
    for label in ordered_labels(tasks, manifests):
        if task_status(progress, label) != "completed" and ready_for_next(label, manifests, progress):
            return label
    return "None"


def command_audit(args: argparse.Namespace) -> int:
    errors, warnings, tasks, manifests = collect_doctor_findings()
    if errors:
        return print_command_errors("audit: doctor failed", errors, [])
    args.pages = True if not args.pages else args.pages
    if args.pages:
        print_page_audit(tasks, manifests)
    print_core_audit(tasks, manifests)
    print_warnings(warnings)
    return 0


def print_page_audit(tasks: dict, manifests: dict) -> None:
    from .contracts import load_page_contracts

    print("Page Prompt Coverage Audit")
    print("| Page | Feature Tasks | Page Verify | Expected Core | Feature Covered | Missing | Extra | Status |")
    print("|---|---|---|---|---|---|---|---|")
    for contract in load_page_contracts().values():
        print_page_audit_row(contract, tasks, manifests)
    print()


def print_page_audit_row(contract, tasks: dict, manifests: dict) -> None:
    feature_labels, verify_labels, covered, extra, verify_errors = page_feature_audit(contract, tasks, manifests)
    expected = set(contract.capabilities)
    missing = sorted(expected - covered)
    extra_values = sorted(extra)
    status = page_audit_status(expected, verify_labels, missing, extra_values, verify_errors)
    print("| " + " | ".join(page_audit_cells(contract, feature_labels, verify_labels, covered, missing, extra_values, status)) + " |")


def page_audit_status(expected: set[str], verify_labels: list[str], missing: list[str], extra: list[str], verify_errors: list[str]) -> str:
    needs_verify = len(expected) > 1
    return "OK" if not missing and not extra and not verify_errors and (not needs_verify or verify_labels) else "FAILED"


def page_audit_cells(contract, feature_labels, verify_labels, covered, missing, extra_values, status) -> list[str]:
    needs_verify = len(contract.capabilities) > 1
    return [
        contract.page_id,
        ", ".join(f"`{label}`" for label in feature_labels) or "None",
        ", ".join(f"`{label}`" for label in verify_labels) or ("Not required" if not needs_verify else "Missing"),
        ", ".join(contract.capabilities) or "None",
        ", ".join(sorted(covered)) or "None",
        ", ".join(missing) or "None",
        ", ".join(extra_values) or "None",
        status,
    ]


def print_core_audit(tasks: dict, manifests: dict) -> None:
    stats = core_coverage_stats(tasks, manifests)
    print("Core Prompt Coverage Audit")
    print("| Metric | Count |")
    print("|---|---:|")
    for key, label in core_audit_rows():
        print(f"| {label} | {stats[key]} |")


def core_audit_rows() -> list[tuple[str, str]]:
    return [
        ("capabilities", "capabilities"),
        ("capability_without_task", "capability_without_task"),
        ("bad_c1_groups", "bad_c1_groups"),
        ("bad_c234_groups", "bad_c2_c3_c4_groups"),
        ("core_integration_verify", "core_integration_verify"),
        ("core_verify_misclassified", "core_verify_misclassified"),
        ("core_verify_secondary_blocking", "core_verify_secondary_blocking"),
    ]


def print_warnings(warnings: list[str]) -> None:
    if warnings:
        print("- warnings:")
        for warning in warnings:
            print(f"  - {warning}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manual prompt runner for AreaMatrix.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    add_simple_parsers(subparsers)
    add_plan_parser(subparsers)
    add_render_parser(subparsers)
    add_verify_parser(subparsers)
    add_export_parser(subparsers)
    add_mark_parser(subparsers)
    add_audit_parser(subparsers)
    return parser


def add_simple_parsers(subparsers) -> None:
    subparsers.add_parser("doctor", help="Validate prompt library health.")
    subparsers.add_parser("next", help="Print the next dependency-ready task.")
    subparsers.add_parser("status", help="Print prompt library summary.")


def add_plan_parser(subparsers) -> None:
    parser = subparsers.add_parser("plan", help="Print execution plan.")
    parser.add_argument("--phase", help="Filter to a phase, for example phase-0 or 0.")
    parser.add_argument("--all", action="store_true", help="Print all phases.")


def add_render_parser(subparsers) -> None:
    parser = subparsers.add_parser("render", help="Render a copy-ready or verify-ready prompt.")
    parser.add_argument("--task", required=True, help="Task label, for example 0-1/task-01.")
    parser.add_argument("--mode", choices=["copy", "verify"], default="copy", help="Prompt mode.")


def add_verify_parser(subparsers) -> None:
    parser = subparsers.add_parser("verify", help="Render a task or phase verify-ready prompt.")
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--task", help="Task label, for example 0-1/task-01.")
    target.add_argument("--phase", help="Phase label, for example phase-0 or 0.")


def add_export_parser(subparsers) -> None:
    parser = subparsers.add_parser("export", help="Export copy-ready and verify-ready prompts to files.")
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--all", action="store_true", help="Export prompts for all phases.")
    target.add_argument("--phase", help="Export prompts for one phase, for example phase-0 or 0.")


def add_mark_parser(subparsers) -> None:
    parser = subparsers.add_parser("mark", help="Record manual task progress.")
    parser.add_argument("--task", required=True, help="Task label, for example 0-1/task-01.")
    parser.add_argument("--status", required=True, choices=["pending", "in_progress", "blocked", "failed", "completed"])
    parser.add_argument("--note", default="", help="Optional progress note.")
    parser.add_argument("--force", action="store_true", help="Allow completion before dependencies are completed.")


def add_audit_parser(subparsers) -> None:
    parser = subparsers.add_parser("audit", help="Print prompt coverage audit reports.")
    parser.add_argument("--pages", action="store_true", help="Audit page to Core capability coverage.")


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    commands = command_map()
    if args.command in commands:
        return commands[args.command](args)
    parser.error(f"unknown command: {args.command}")
    return 2


def command_map() -> dict[str, object]:
    return {
        "doctor": command_doctor,
        "plan": command_plan,
        "next": command_next,
        "render": command_render,
        "verify": command_verify,
        "export": command_export,
        "mark": command_mark,
        "status": command_status,
        "audit": command_audit,
    }
