"""CLI dispatcher for the AreaMatrix root ./dev tool surface."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence

from .backlog import run_backlog_command
from .build import run_bindings_update, run_core_build
from .changes import run_changes_doctor, run_changes_generate, run_changes_preview
from .checks import (
    run_all_check,
    run_codex_os_check,
    run_diff_check,
    run_governance_check,
    run_prompts_check,
    run_quality_check,
    run_quick_check,
    run_secrets_check,
    run_skills_check,
    run_task_check,
    run_task_loop_check,
)
from .common import ToolError, print_error, project_root
from .codex_os import run_codex_os_command
from .discussion import run_workflow_discuss
from .macos import run_macos_tests
from .middle_layer import run_workflow_middle
from .release import (
    DEFAULT_READINESS_BUILD_DERIVED_DATA,
    DEFAULT_NOTARY_PROFILE,
    run_release_readiness_build,
    run_release_preflight,
)
from .tasks import TASK_KINDS, TASK_LAYERS, TASK_PRIORITIES, TASK_RISKS, run_tasks_command
from .workflow_baseline import run_workflow_baseline
from .workflow_init import run_workflow_init
from .workflow_projection import run_workflow_closeout, run_workflow_project
from .workflow import (
    DEFAULT_VERSION,
    run_workflow_check_template,
    run_workflow_doctor,
    run_workflow_drafts,
    run_workflow_plan,
    run_workflow_promote,
    run_workflow_queue,
    run_workflow_status,
)
from .wording import run_wording_audit

CODEX_OS_LANES = sorted(["Quick", "Change", "Mission-Critical", "Explore", "Review", "Ops"])
CODEX_OS_STATUSES = sorted(["Backlog", "Ready", "Running", "Waiting Confirmation", "Blocked", "Verifying", "Done", "Archived", "Abandoned"])
CODEX_OS_RISK_LEVELS = sorted(["Low", "Medium", "High", "Mission-Critical"])
CODEX_OS_CONFIRMATION_STATUSES = sorted(["Not Required", "Required", "Granted", "Blocked"])
CODEX_OS_VALIDATION_STATUSES = sorted(["Not Started", "Recommended", "Running", "Pass", "Fail", "Blocked", "Not-Ready", "Skipped"])
CODEX_OS_AUTOMATION_SCOPES = sorted(["observe-only", "registry-write", "validation-run", "manual-confirmation-required"])
CODEX_OS_ARCHIVE_RECOMMENDATIONS = sorted(["keep", "archive", "review"])


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="./dev", description="AreaMatrix developer tools")
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_codex_os_common(target: argparse.ArgumentParser) -> None:
        target.add_argument("--state-db", help="Codex state SQLite path; defaults to ~/.codex/state_5.sqlite")
        target.add_argument("--runtime-dir", help="Output directory; defaults to .codex/runtime/codex-os")
        target.add_argument("--project", help="Limit thread health to an exact cwd/project path")

    def add_codex_os_task_fields(target: argparse.ArgumentParser) -> None:
        target.add_argument("--risk-level", choices=CODEX_OS_RISK_LEVELS)
        target.add_argument("--confirmation-status", choices=CODEX_OS_CONFIRMATION_STATUSES)
        target.add_argument("--evidence-file", help="Evidence file path or local reference")
        target.add_argument("--closeout-file", help="Closeout file path or local reference")
        target.add_argument("--evidence-note", help="Short evidence note when no evidence file exists")
        target.add_argument("--closeout-note", help="Short closeout note when no closeout file exists")
        target.add_argument("--validation-status", choices=CODEX_OS_VALIDATION_STATUSES)
        target.add_argument("--automation-scope", choices=CODEX_OS_AUTOMATION_SCOPES)

    check = subparsers.add_parser("check", help="Run repo health checks")
    check.add_argument(
        "target",
        nargs="?",
        choices=["governance", "skills", "quality", "wording", "task-loop", "prompts", "diff", "secrets", "codex-os", "all", "task"],
    )
    check.add_argument("task_label", nargs="?", help="Task label for './dev check task', for example 4-1/task-15")

    wording = subparsers.add_parser("wording", help="Audit long-term source wording")
    wording_sub = wording.add_subparsers(dest="wording_command", required=True)
    wording_audit = wording_sub.add_parser("audit", help="Scan for staged / delivery-track wording drift")
    wording_audit.add_argument("--show-allowed", action="store_true", help="Print allowed technical, policy, and archive hits")
    wording_audit.add_argument("--max-lines", type=int, default=80, help="Maximum hits to print per group")

    build = subparsers.add_parser("build", help="Build developer artifacts")
    build_sub = build.add_subparsers(dest="build_target", required=True)
    build_core = build_sub.add_parser("core", help="Build Rust core universal staticlib and Swift bindings")
    build_core.add_argument("--profile", choices=["release", "debug"], help="Build profile; overrides BUILD_PROFILE")
    build_core.add_argument("--out-dir", help="Generated output directory; overrides OUT_DIR")
    build_core.add_argument(
        "--deployment-target",
        "--macosx-deployment-target",
        dest="deployment_target",
        help="macOS deployment target; overrides MACOSX_DEPLOYMENT_TARGET",
    )

    test = subparsers.add_parser("test", help="Run developer tests")
    test_sub = test.add_subparsers(dest="test_target", required=True)
    macos = test_sub.add_parser("macos", help="Run macOS XCTest gate with sandbox fallback")
    macos.add_argument("--scheme", help="Xcode scheme; overrides XCODE_SCHEME")
    macos.add_argument("--test-bundle-name", help="XCTest bundle name; overrides XCODE_TEST_BUNDLE_NAME")
    macos.add_argument("--destination", help="Xcode destination; overrides XCODE_DESTINATION")
    macos.add_argument("--derived-data-path", help="DerivedData path; overrides DERIVED_DATA_PATH")
    macos.add_argument("--keep-derived-data", action="store_true", help="Keep temporary DerivedData")
    macos.add_argument("--test-log", help="xcodebuild test log path")
    macos.add_argument("--build-log", help="xcodebuild build-for-testing log path")
    macos.add_argument("--result-bundle-path", help="Optional xcodebuild result bundle path")
    macos.add_argument(
        "--disable-parallel-testing",
        action="store_true",
        help="Pass -parallel-testing-enabled NO to xcodebuild test for CI-stable filesystem integration runs",
    )
    macos.add_argument(
        "--only-testing",
        action="append",
        default=[],
        help="Limit XCTest execution to TARGET/CLASS or TARGET/CLASS/METHOD; may be repeated",
    )

    bindings = subparsers.add_parser("bindings", help="Manage generated language bindings")
    bindings_sub = bindings.add_subparsers(dest="bindings_command", required=True)
    update = bindings_sub.add_parser("update", help="Regenerate Swift bindings from an explicit UDL")
    update.add_argument("--udl", required=True, help="UDL file path")
    update.add_argument("--out-dir", "--output-dir", dest="out_dir", required=True, help="Output directory")

    release = subparsers.add_parser("release", help="Run release distribution checks")
    release_sub = release.add_subparsers(dest="release_command", required=True)
    release_preflight = release_sub.add_parser("preflight", help="Check local release signing/notary prerequisites")
    release_preflight.add_argument(
        "--notary-profile",
        default=DEFAULT_NOTARY_PROFILE,
        help=f"notarytool keychain profile to check; defaults to {DEFAULT_NOTARY_PROFILE}",
    )
    release_readiness_build = release_sub.add_parser(
        "readiness-build",
        help="Build a timestamped ad-hoc signed Release app for local readiness validation",
    )
    release_readiness_build.add_argument("--install", action="store_true", help="Install the built app to /Applications/AreaMatrix.app")
    release_readiness_build.add_argument(
        "--build-number",
        help="Override the generated YYYYMMDDHHMM build number; defaults to the current local time",
    )
    release_readiness_build.add_argument(
        "--derived-data-path",
        default=DEFAULT_READINESS_BUILD_DERIVED_DATA,
        help=f"DerivedData output path; defaults to {DEFAULT_READINESS_BUILD_DERIVED_DATA}",
    )
    release_readiness_build.add_argument(
        "--destination",
        default="platform=macOS,arch=arm64",
        help="xcodebuild destination; defaults to platform=macOS,arch=arm64",
    )
    release_readiness_build.add_argument(
        "--applications-dir",
        default="/Applications",
        help="Applications directory used with --install; defaults to /Applications",
    )

    changes = subparsers.add_parser("changes", help="Validate and preview versioned workflow changes")
    changes_sub = changes.add_subparsers(dest="changes_command", required=True)
    changes_doctor = changes_sub.add_parser("doctor", help="Validate versioned workflow change tracking files")
    changes_doctor.add_argument("--version", default=DEFAULT_VERSION, help=f"Workflow version to inspect; defaults to {DEFAULT_VERSION}")
    changes_doctor.add_argument("--file", help="Validate one change file instead of all version changes")
    changes_preview = changes_sub.add_parser("preview", help="Preview versioned workflow tasks without generating prompts")
    changes_preview.add_argument("--version", default=DEFAULT_VERSION, help=f"Workflow version to preview; defaults to {DEFAULT_VERSION}")
    changes_preview.add_argument("--file", help="Preview one change file instead of all version changes")
    changes_generate = changes_sub.add_parser("generate", help="Generate versioned prompt drafts from change tracking files")
    changes_generate.add_argument("--version", default=DEFAULT_VERSION, help=f"Workflow version to generate; defaults to {DEFAULT_VERSION}")
    changes_generate.add_argument("--file", help="Generate from one change file instead of all version changes")
    changes_generate.add_argument("--feature", help="Generate only one feature id")
    changes_generate.add_argument("--write", action="store_true", help="Write draft files instead of printing a preview")
    changes_generate.add_argument("--out-dir", help="Draft output directory; defaults to workflow/versions/<version>/drafts")
    changes_generate.add_argument("--force", action="store_true", help="Allow overwriting existing draft files when --write is used")

    backlog = subparsers.add_parser("backlog", help="Browse backlog prompt packages without touching the live queue")
    backlog_sub = backlog.add_subparsers(dest="backlog_command", required=True)
    backlog_sub.add_parser("list", help="List backlog prompt packages")
    backlog_show = backlog_sub.add_parser("show", help="Print a backlog package README or one prompt")
    backlog_show.add_argument("package", help="Backlog package slug under tasks/backlog/prompts")
    backlog_show.add_argument("--task", type=int, help="1-based task number inside the package")
    backlog_show.add_argument("--mode", choices=["copy", "verify"], help="Prompt mode to print when --task is provided")

    tasks = subparsers.add_parser("tasks", help="Manage lightweight tasks without touching live queues")
    tasks_sub = tasks.add_subparsers(dest="tasks_command", required=True)
    tasks_sub.add_parser("doctor", help="Validate lightweight task structure")
    tasks_sub.add_parser("status", help="Show active, done, and backlog summary")
    tasks_sub.add_parser("list", help="List lightweight tasks from active and done")
    tasks_create = tasks_sub.add_parser("create", help="Preview or create a lightweight task under tasks/active")
    tasks_create.add_argument("--title", required=True, help="Task title")
    tasks_create.add_argument("--slug", help="Directory slug; defaults to a slug derived from --title")
    tasks_create.add_argument("--priority", choices=sorted(TASK_PRIORITIES), default="p2", help="Task priority")
    tasks_create.add_argument("--kind", choices=sorted(TASK_KINDS), default="feature", help="Task kind")
    tasks_create.add_argument("--risk", choices=sorted(TASK_RISKS), default="low", help="Task risk")
    tasks_create.add_argument("--layer", choices=sorted(TASK_LAYERS), required=True, help="Task layer, such as frontend or scripts")
    tasks_create.add_argument("--area", required=True, help="Task area, such as apps/macos or scripts/dev_tools")
    tasks_create.add_argument("--feature", required=True, help="Feature or component name")
    tasks_create.add_argument("--touch", action="append", default=[], help="Allowed path; may be repeated. Defaults to --area/")
    tasks_create.add_argument("--forbid", action="append", default=[], help="Additional forbidden path; may be repeated")
    tasks_create.add_argument("--validation", action="append", default=[], help="Validation command; may be repeated")
    tasks_create.add_argument("--date", help="Creation date in YYYY-MM-DD format; defaults to today")
    tasks_create.add_argument("--write", action="store_true", help="Create files instead of printing a preview")
    tasks_complete = tasks_sub.add_parser("complete", help="Preview or archive a completed active lightweight task")
    tasks_complete.add_argument("task_id", type=int, help="Active lightweight task id, for example 2")
    tasks_complete.add_argument("--date", help="Completion date in YYYY-MM-DD format; defaults to today")
    tasks_complete.add_argument("--write", action="store_true", help="Move the task from active to done")
    tasks_complete.add_argument(
        "--confirm-pass",
        action="store_true",
        help="Required with --write; records the operator's PASS decision",
    )
    tasks_show = tasks_sub.add_parser("show", help="Show one lightweight task by numeric id")
    tasks_show.add_argument("task_id", type=int, help="Lightweight task id, for example 1")
    tasks_show.add_argument("--task", action="store_true", help="Print only task.md")
    tasks_show.add_argument("--verify", action="store_true", help="Print only verify.md")
    tasks_show.add_argument("--evidence", action="store_true", help="Print only evidence.md")

    codex_os = subparsers.add_parser("codex-os", help="Inspect Codex workspace state without mutating Codex internals")
    add_codex_os_common(codex_os)
    codex_os_sub = codex_os.add_subparsers(dest="codex_os_command", required=True)
    codex_os_status = codex_os_sub.add_parser("status", help="Print a read-only thread health summary")
    add_codex_os_common(codex_os_status)
    codex_os_status.add_argument("--limit", type=int, default=20, help="Rows to print per health bucket")
    codex_os_health = codex_os_sub.add_parser("thread-health", help="Generate thread health and archive candidate data")
    add_codex_os_common(codex_os_health)
    codex_os_health.add_argument("--limit", type=int, default=50, help="Rows to include per health bucket")
    codex_os_health.add_argument("--json", action="store_true", help="Print JSON instead of the human summary")
    codex_os_health.add_argument("--write", action="store_true", help="Write .codex/runtime/codex-os/thread-health.json")
    codex_os_archive = codex_os_sub.add_parser("archive-candidates", help="List archive candidates without archiving")
    add_codex_os_common(codex_os_archive)
    codex_os_archive.add_argument("--limit", type=int, default=50, help="Candidate rows to print")
    codex_os_archive.add_argument("--json", action="store_true", help="Print candidate JSON")
    codex_os_dashboard = codex_os_sub.add_parser("dashboard", help="Render or write dashboard and health report")
    add_codex_os_common(codex_os_dashboard)
    codex_os_dashboard.add_argument("--limit", type=int, default=50, help="Rows to include in thread-health.json when writing")
    codex_os_dashboard.add_argument("--write", action="store_true", help="Write dashboard.md, health-report.md, and thread-health.json")
    codex_os_new = codex_os_sub.add_parser("new", help="Preview or create a Codex OS task in the local registry")
    add_codex_os_common(codex_os_new)
    codex_os_new.add_argument("--title", required=True, help="Human task title")
    codex_os_new.add_argument("--task-id", help="Task id; generated from date/title when omitted")
    codex_os_new.add_argument("--project-name", default="AreaMatrix", help="Project display name")
    codex_os_new.add_argument("--lane", choices=CODEX_OS_LANES, required=True)
    codex_os_new.add_argument("--status", choices=CODEX_OS_STATUSES, default="Ready")
    codex_os_new.add_argument("--owner-thread", help="Owner Codex thread id")
    codex_os_new.add_argument("--handoff-file", help="Handoff file path")
    codex_os_new.add_argument("--next-action", help="Next action text")
    codex_os_new.add_argument("--validation", help="Validation command or summary")
    codex_os_new.add_argument("--path", action="append", default=[], help="Changed or expected path for validation recommendation")
    codex_os_new.add_argument("--recommend-validation", action="store_true", help="Attach recommended validation commands")
    add_codex_os_task_fields(codex_os_new)
    codex_os_new.add_argument("--write", action="store_true", help="Write the task to the registry")
    codex_os_context = codex_os_sub.add_parser("context", help="Render a Codex OS context bundle")
    add_codex_os_common(codex_os_context)
    codex_os_context.add_argument("--task-id", help="Task id to include")
    codex_os_context.add_argument("--json", action="store_true", help="Print JSON instead of Markdown")
    codex_os_context.add_argument("--write", action="store_true", help="Write context.md and context.json")
    codex_os_resume = codex_os_sub.add_parser("resume", help="Show the safest next steps for a registered task")
    add_codex_os_common(codex_os_resume)
    codex_os_resume.add_argument("--task-id", help="Task id to resume; defaults to first non-terminal task")
    codex_os_resume.add_argument("--lane", choices=CODEX_OS_LANES, help="Limit default resume lookup to one lane")
    codex_os_resume.add_argument("--json", action="store_true", help="Print JSON instead of Markdown")
    codex_os_validation = codex_os_sub.add_parser("recommend-validation", help="Recommend the smallest sufficient validation set without running it")
    add_codex_os_common(codex_os_validation)
    codex_os_validation.add_argument("--path", action="append", default=[], help="Changed path; may be repeated")
    codex_os_validation.add_argument("--changed", action="store_true", help="Include current git status paths")
    codex_os_validation.add_argument("--json", action="store_true", help="Print JSON instead of Markdown")
    codex_os_validation.add_argument("--write", action="store_true", help="Write recommend-validation.json")
    codex_os_archive_review = codex_os_sub.add_parser("archive-review", help="Render archive and risk-review recommendations without archiving")
    add_codex_os_common(codex_os_archive_review)
    codex_os_archive_review.add_argument("--limit", type=int, default=50, help="Rows per recommendation group")
    codex_os_archive_review.add_argument("--json", action="store_true", help="Print JSON instead of Markdown")
    codex_os_archive_review.add_argument("--write", action="store_true", help="Write archive-review.md and archive-review.json")
    codex_os_title_suggestions = codex_os_sub.add_parser("title-suggestions", help="Suggest clearer thread titles without changing them")
    add_codex_os_common(codex_os_title_suggestions)
    codex_os_title_suggestions.add_argument("--limit", type=int, default=50, help="Suggestion rows to print")
    codex_os_title_suggestions.add_argument("--json", action="store_true", help="Print JSON instead of Markdown")
    codex_os_title_suggestions.add_argument("--write", action="store_true", help="Write title-suggestions.json")
    codex_os_weekly = codex_os_sub.add_parser("weekly", help="Render a weekly Codex OS operations review")
    add_codex_os_common(codex_os_weekly)
    codex_os_weekly.add_argument("--json", action="store_true", help="Print JSON instead of Markdown")
    codex_os_weekly.add_argument("--write", action="store_true", help="Write weekly.md and weekly.json")
    codex_os_diagnose = codex_os_sub.add_parser("diagnose", help="Diagnose registry, task, and validation readiness")
    add_codex_os_common(codex_os_diagnose)
    codex_os_diagnose.add_argument("--task-id", help="Task id to diagnose")
    codex_os_diagnose.add_argument("--path", action="append", default=[], help="Changed path for validation recommendation")
    codex_os_diagnose.add_argument("--changed", action="store_true", help="Include current git status paths")
    codex_os_diagnose.add_argument("--strict", action="store_true", help="Return non-zero when diagnosis fails")
    codex_os_diagnose.add_argument("--json", action="store_true", help="Print JSON instead of Markdown")
    codex_os_health_score = codex_os_sub.add_parser("health-score", help="Compute a Codex OS health score")
    add_codex_os_common(codex_os_health_score)
    codex_os_health_score.add_argument("--json", action="store_true", help="Print JSON instead of Markdown")
    codex_os_health_score.add_argument("--write", action="store_true", help="Write health-score.json")
    codex_os_runbook = codex_os_sub.add_parser("runbook", help="Print the Codex OS 0-100%% runbook")
    add_codex_os_common(codex_os_runbook)
    codex_os_runbook.add_argument("--write", action="store_true", help="Write runbook.md")
    codex_os_lifecycle = codex_os_sub.add_parser("lifecycle", help="Show allowed next lifecycle commands for a task")
    add_codex_os_common(codex_os_lifecycle)
    codex_os_lifecycle.add_argument("--task-id", required=True)
    codex_os_lifecycle.add_argument("--json", action="store_true", help="Print JSON instead of Markdown")
    codex_os_registry = codex_os_sub.add_parser("registry", help="Manage the repo-local Codex OS task registry")
    add_codex_os_common(codex_os_registry)
    codex_os_registry_sub = codex_os_registry.add_subparsers(dest="registry_command", required=True)
    codex_os_registry_init = codex_os_registry_sub.add_parser("init", help="Preview or create task-registry.json")
    add_codex_os_common(codex_os_registry_init)
    codex_os_registry_init.add_argument("--write", action="store_true", help="Create the registry")
    codex_os_registry_init.add_argument("--force", action="store_true", help="Overwrite an existing registry")
    codex_os_registry_list = codex_os_registry_sub.add_parser("list", help="List registered tasks")
    add_codex_os_common(codex_os_registry_list)
    codex_os_registry_add = codex_os_registry_sub.add_parser("add", help="Preview or add a registered task")
    add_codex_os_common(codex_os_registry_add)
    codex_os_registry_add.add_argument("--task-id", required=True, help="Task id, for example AM-20260629-001")
    codex_os_registry_add.add_argument("--project-name", default="AreaMatrix", help="Project display name")
    codex_os_registry_add.add_argument("--lane", choices=CODEX_OS_LANES, required=True)
    codex_os_registry_add.add_argument(
        "--status",
        choices=CODEX_OS_STATUSES,
        default="Ready",
    )
    codex_os_registry_add.add_argument("--owner-thread", help="Owner Codex thread id")
    codex_os_registry_add.add_argument("--handoff-file", help="Handoff file path")
    codex_os_registry_add.add_argument("--next-action", help="Next action text")
    codex_os_registry_add.add_argument("--validation", help="Validation command or summary")
    codex_os_registry_add.add_argument("--archive-recommendation", choices=CODEX_OS_ARCHIVE_RECOMMENDATIONS, default="keep")
    add_codex_os_task_fields(codex_os_registry_add)
    codex_os_registry_add.add_argument("--write", action="store_true", help="Write the new task")
    codex_os_registry_update = codex_os_registry_sub.add_parser("update", help="Preview or update a registered task")
    add_codex_os_common(codex_os_registry_update)
    codex_os_registry_update.add_argument("--task-id", required=True, help="Task id to update")
    codex_os_registry_update.add_argument("--lane", choices=CODEX_OS_LANES)
    codex_os_registry_update.add_argument(
        "--status",
        choices=CODEX_OS_STATUSES,
    )
    codex_os_registry_update.add_argument("--owner-thread", help="Owner Codex thread id")
    codex_os_registry_update.add_argument("--handoff-file", help="Handoff file path")
    codex_os_registry_update.add_argument("--next-action", help="Next action text")
    codex_os_registry_update.add_argument("--validation", help="Validation command or summary")
    codex_os_registry_update.add_argument("--archive-recommendation", choices=CODEX_OS_ARCHIVE_RECOMMENDATIONS)
    add_codex_os_task_fields(codex_os_registry_update)
    codex_os_registry_update.add_argument("--write", action="store_true", help="Write the update")
    codex_os_registry_status = codex_os_registry_sub.add_parser("status", help="Validate the task registry")
    add_codex_os_common(codex_os_registry_status)
    codex_os_registry_status.add_argument("--strict", action="store_true", help="Return non-zero for WARN or FAIL audit results")
    codex_os_registry_status.add_argument("--json", action="store_true", help="Print JSON instead of Markdown")
    codex_os_intake = codex_os_sub.add_parser("intake", help="Print the task intake template")
    add_codex_os_common(codex_os_intake)
    codex_os_intake.add_argument("--lane", choices=CODEX_OS_LANES)
    codex_os_intake.add_argument("--task-id", help="Replace <task-id> in the intake template")
    codex_os_intake.add_argument("--output", help="Write path; defaults to .codex/runtime/codex-os/intake/")
    codex_os_intake.add_argument("--write", action="store_true", help="Write the rendered template")
    codex_os_handoff = codex_os_sub.add_parser("handoff", help="Print the handoff template")
    add_codex_os_common(codex_os_handoff)
    codex_os_handoff.add_argument("--task-id", help="Replace <task-id> in the handoff template")
    codex_os_handoff.add_argument("--output", help="Write path; defaults to .codex/runtime/codex-os/handoff/")
    codex_os_handoff.add_argument("--write", action="store_true", help="Write the rendered template")
    codex_os_evidence = codex_os_sub.add_parser("evidence", help="Print the evidence template")
    add_codex_os_common(codex_os_evidence)
    codex_os_evidence.add_argument("--task-id", help="Replace <task-id> in the evidence template")
    codex_os_evidence.add_argument("--output", help="Write path; defaults to .codex/runtime/codex-os/evidence/")
    codex_os_evidence.add_argument("--write", action="store_true", help="Write the rendered template")
    codex_os_closeout = codex_os_sub.add_parser("closeout", help="Print the thread closeout template")
    add_codex_os_common(codex_os_closeout)
    codex_os_closeout.add_argument("--task-id", help="Replace <task-id> in the closeout template")
    codex_os_closeout.add_argument("--output", help="Write path; defaults to .codex/runtime/codex-os/closeout/")
    codex_os_closeout.add_argument("--write", action="store_true", help="Write the rendered template")
    codex_os_doctor = codex_os_sub.add_parser("doctor", help="Validate Codex OS docs, templates, registry, and readable state")
    add_codex_os_common(codex_os_doctor)
    codex_os_preflight = codex_os_sub.add_parser("preflight", help="Run Codex OS task preflight without touching Codex internals")
    add_codex_os_common(codex_os_preflight)
    codex_os_preflight.add_argument("--task-id", help="Task id to inspect")
    codex_os_preflight.add_argument("--strict", action="store_true", help="Return non-zero when required lifecycle checks fail")
    codex_os_preflight.add_argument("--json", action="store_true", help="Print JSON instead of the human report")
    codex_os_preflight.add_argument("--write-dashboard", action="store_true", help="Refresh dashboard and health report")
    codex_os_preflight.add_argument("--limit", type=int, default=50, help="Rows to include when --write-dashboard refreshes thread-health.json")
    codex_os_task = codex_os_sub.add_parser("task", help="Manage a Codex OS task lifecycle wrapper")
    add_codex_os_common(codex_os_task)
    codex_os_task_sub = codex_os_task.add_subparsers(dest="task_command", required=True)
    codex_os_task_list = codex_os_task_sub.add_parser("list", help="List registered Codex OS tasks")
    add_codex_os_common(codex_os_task_list)
    codex_os_task_show = codex_os_task_sub.add_parser("show", help="Show one registered Codex OS task")
    add_codex_os_common(codex_os_task_show)
    codex_os_task_show.add_argument("--task-id", required=True)
    codex_os_task_show.add_argument("--json", action="store_true", help="Print JSON instead of the human report")
    codex_os_task_next = codex_os_task_sub.add_parser("next", help="Show the first non-terminal registered task")
    add_codex_os_common(codex_os_task_next)
    codex_os_task_next.add_argument("--lane", choices=CODEX_OS_LANES, help="Limit next task to one lane")
    codex_os_task_next.add_argument("--json", action="store_true", help="Print JSON instead of the human report")
    for name, help_text in (
        ("start", "Mark a registered task as Running"),
        ("verify", "Mark a registered task as Verifying"),
        ("block", "Mark a registered task as Blocked"),
    ):
        task_parser = codex_os_task_sub.add_parser(name, help=help_text)
        add_codex_os_common(task_parser)
        task_parser.add_argument("--task-id", required=True)
        task_parser.add_argument("--next-action", help="Next action or recovery note")
        task_parser.add_argument("--validation", help="Validation command or summary")
        task_parser.add_argument("--validation-status", choices=CODEX_OS_VALIDATION_STATUSES)
        task_parser.add_argument("--automation-scope", choices=CODEX_OS_AUTOMATION_SCOPES)
        task_parser.add_argument("--write", action="store_true", help="Update the registry")
    codex_os_finish = codex_os_sub.add_parser("finish", help="Close a Codex OS task with validation and evidence references")
    add_codex_os_common(codex_os_finish)
    codex_os_finish.add_argument("--task-id", required=True)
    codex_os_finish.add_argument("--status", choices=["Done", "Blocked", "Abandoned"], required=True)
    codex_os_finish.add_argument("--validation", help="Fresh validation command/result summary")
    codex_os_finish.add_argument("--handoff-file", help="Handoff file path")
    codex_os_finish.add_argument("--next-action", help="Next action when blocked or follow-up remains")
    codex_os_finish.add_argument("--archive-recommendation", choices=CODEX_OS_ARCHIVE_RECOMMENDATIONS, default="keep")
    add_codex_os_task_fields(codex_os_finish)
    codex_os_finish.add_argument("--json", action="store_true", help="Print JSON instead of the human report")
    codex_os_finish.add_argument("--write", action="store_true", help="Update the registry")

    workflow = subparsers.add_parser("workflow", help="Manage versioned workflow templates, plans, and queue candidates")
    workflow_sub = workflow.add_subparsers(dest="workflow_command", required=True)
    workflow_sub.add_parser("doctor", help="Validate versioned workflow structure and gates")
    workflow_sub.add_parser("status", help="Show versioned workflow status and promotion gates")
    workflow_sub.add_parser("check-template", help=f"Run the full managed template reference gate; defaults to {DEFAULT_VERSION}")
    workflow_init = workflow_sub.add_parser("init", help="Render or write a new v* workflow version skeleton")
    workflow_init.add_argument("--version", required=True, help="Workflow version to initialize, such as v2")
    workflow_init.add_argument("--title", help="Workflow title; defaults to 'AreaMatrix <version> planning workflow'")
    workflow_init.add_argument("--write", action="store_true", help="Write version files instead of printing a preview")
    workflow_init.add_argument("--out-dir", help="Version output directory; defaults to workflow/versions/<version>")
    workflow_init.add_argument("--force", action="store_true", help="Allow overwriting existing version skeleton files when --write is used")
    workflow_discuss = workflow_sub.add_parser("discuss", help="Manage pre-change workflow discussion gates")
    workflow_discuss.add_argument("--version", required=True, help="Workflow version to discuss, such as v2")
    workflow_discuss_sub = workflow_discuss.add_subparsers(dest="discuss_command", required=True)
    workflow_discuss_sub.add_parser("doctor", help="Validate the discussion gate for one workflow version")
    workflow_discuss_sub.add_parser("preview", help="Preview the discussion gate state for one workflow version")
    workflow_discuss_init = workflow_discuss_sub.add_parser("init", help="Render discussion gate starter files")
    workflow_discuss_init.add_argument("--write", action="store_true", help="Write discussion files instead of printing a preview")
    workflow_discuss_init.add_argument("--out-dir", help="Discussion output directory; defaults to workflow/versions/<version>/discussion")
    workflow_discuss_init.add_argument("--force", action="store_true", help="Allow overwriting existing discussion files when --write is used")
    workflow_baseline = workflow_sub.add_parser("baseline", help="Manage docs baseline and drift checks")
    workflow_baseline.add_argument(
        "--version",
        default=DEFAULT_VERSION,
        help=f"Workflow version to inspect; defaults to managed template reference {DEFAULT_VERSION}. Use --version vN for real workflows.",
    )
    workflow_baseline_sub = workflow_baseline.add_subparsers(dest="baseline_command", required=True)
    workflow_baseline_sub.add_parser("preview", help="Preview docs baseline without writing files")
    workflow_baseline_write = workflow_baseline_sub.add_parser("write", help="Write docs baseline file")
    workflow_baseline_write.add_argument("--force", action="store_true", help="Allow overwriting existing baseline file")
    workflow_baseline_sub.add_parser("doctor", help="Validate docs baseline and drift")
    workflow_middle = workflow_sub.add_parser("middle", help="Manage feature-level middle-layer workflow ledgers")
    workflow_middle.add_argument("--version", required=True, help="Workflow version to inspect, such as v2")
    workflow_middle.add_argument("--feature", help="Inspect only one feature id")
    workflow_middle_sub = workflow_middle.add_subparsers(dest="middle_command", required=True)
    workflow_middle_sub.add_parser("doctor", help="Validate middle-layer ledgers and matching changes")
    workflow_middle_sub.add_parser("preview", help="Preview docs -> middle-layer -> changes -> slices")
    workflow_middle_init = workflow_middle_sub.add_parser("init", help="Render middle-layer starter files")
    workflow_middle_init.add_argument("--write", action="store_true", help="Write middle-layer files instead of printing a preview")
    workflow_middle_init.add_argument("--out-dir", help="Middle-layer output directory; defaults to workflow/versions/<version>/middle-layer")
    workflow_middle_init.add_argument("--force", action="store_true", help="Allow overwriting existing middle-layer files when --write is used")
    workflow_plan = workflow_sub.add_parser("plan", help="Render or validate docs-change ledger plans")
    workflow_plan.add_argument("--version", default=DEFAULT_VERSION, help=f"Workflow version to plan; defaults to {DEFAULT_VERSION}")
    workflow_plan.add_argument("--feature", help="Render only one feature id")
    workflow_plan.add_argument("--write", action="store_true", help="Write plan files instead of printing a preview")
    workflow_plan.add_argument("--out-dir", help="Plan output directory; defaults to workflow/versions/<version>/plans")
    workflow_plan.add_argument("--force", action="store_true", help="Allow overwriting existing plan files when --write is used")
    workflow_plan_sub = workflow_plan.add_subparsers(dest="plan_command")
    workflow_plan_sub.add_parser("doctor", help="Validate plan gate without writing files")
    workflow_drafts = workflow_sub.add_parser("drafts", help="Validate workflow draft artifacts")
    workflow_drafts.add_argument("--version", default=DEFAULT_VERSION, help=f"Workflow version to inspect; defaults to {DEFAULT_VERSION}")
    workflow_drafts.add_argument("--feature", help="Inspect only one feature id")
    workflow_drafts_sub = workflow_drafts.add_subparsers(dest="drafts_command", required=True)
    workflow_drafts_sub.add_parser("doctor", help="Validate draft gate without writing files")
    workflow_queue = workflow_sub.add_parser("queue", help="Render or validate workflow queue candidates")
    workflow_queue.add_argument("--version", default=DEFAULT_VERSION, help=f"Workflow version to queue; defaults to {DEFAULT_VERSION}")
    workflow_queue.add_argument("--feature", help="Render only one feature id")
    workflow_queue.add_argument("--write", action="store_true", help="Write queue candidate files instead of printing a preview")
    workflow_queue.add_argument("--out-dir", help="Queue output directory; defaults to workflow/versions/<version>/queue")
    workflow_queue.add_argument("--force", action="store_true", help="Allow overwriting existing queue files when --write is used")
    workflow_queue_sub = workflow_queue.add_subparsers(dest="queue_command")
    workflow_queue_sub.add_parser("doctor", help="Validate queue gate without writing files")
    workflow_promote = workflow_sub.add_parser("promote", help="Preview, approve, or apply workflow promotion")
    workflow_promote.add_argument("--version", default=DEFAULT_VERSION, help=f"Workflow version to promote-preview; defaults to {DEFAULT_VERSION}")
    workflow_promote.add_argument("--feature", help="Preview only one feature id, including upstream feature dependencies")
    workflow_promote.add_argument("--preview", action="store_true", help="Explicit preview mode; this is also the default")
    workflow_promote.add_argument("--write", action="store_true", help="Write promotion preview files instead of printing to stdout")
    workflow_promote.add_argument("--out-dir", help="Promotion preview output directory; defaults to workflow/versions/<version>/promotion")
    workflow_promote.add_argument("--force", action="store_true", help="Allow overwriting existing promotion preview files when --write is used")
    workflow_promote_sub = workflow_promote.add_subparsers(dest="promote_command")
    workflow_promote_sub.add_parser("preview", help="Preview workflow promotion without writing live files")
    workflow_promote_approve = workflow_promote_sub.add_parser("approve", help="Write or preview promotion approval")
    workflow_promote_approve.add_argument("--write", action="store_true", help="Write approval file")
    workflow_promote_approve.add_argument("--force", action="store_true", help="Allow overwriting existing approval file")
    workflow_promote_apply = workflow_promote_sub.add_parser("apply", help="Preview or apply approved promotion")
    workflow_promote_apply.add_argument("--preview", action="store_true", help="Preview apply gates")
    workflow_promote_apply.add_argument("--write", action="store_true", help="Write live promotion files after gates pass")
    workflow_project = workflow_sub.add_parser("project", help="Project live task-loop results back to workflow")
    workflow_project.add_argument(
        "--version",
        default=DEFAULT_VERSION,
        help=f"Workflow version to project; defaults to managed template reference {DEFAULT_VERSION}. Use --version vN for real workflows.",
    )
    workflow_project_sub = workflow_project.add_subparsers(dest="project_command", required=True)
    workflow_project_sub.add_parser("preview", help="Preview workflow projection")
    workflow_project_write = workflow_project_sub.add_parser("write", help="Write workflow projection file")
    workflow_project_write.add_argument("--force", action="store_true", help="Allow overwriting existing projection file")
    workflow_project_sub.add_parser("doctor", help="Validate workflow projection")
    workflow_closeout = workflow_sub.add_parser("closeout", help="Preview, write, or validate workflow closeout")
    workflow_closeout.add_argument(
        "--version",
        default=DEFAULT_VERSION,
        help=f"Workflow version to close out; defaults to managed template reference {DEFAULT_VERSION}. Use --version vN for real workflows.",
    )
    workflow_closeout_sub = workflow_closeout.add_subparsers(dest="closeout_command", required=True)
    workflow_closeout_sub.add_parser("preview", help="Preview workflow closeout")
    workflow_closeout_write = workflow_closeout_sub.add_parser("write", help="Write workflow closeout file")
    workflow_closeout_write.add_argument("--force", action="store_true", help="Allow overwriting existing closeout file")
    workflow_closeout_sub.add_parser("doctor", help="Validate workflow closeout")

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    root = project_root()
    try:
        if args.command == "check":
            if args.target is None:
                return run_quick_check(root)
            if args.task_label and args.target != "task":
                parser.error("task_label is only valid with './dev check task <label>'")
            if args.target == "governance":
                return run_governance_check(root)
            if args.target == "skills":
                return run_skills_check(root)
            if args.target == "quality":
                return run_quality_check(root)
            if args.target == "wording":
                return run_wording_audit(root)
            if args.target == "task-loop":
                return run_task_loop_check(root)
            if args.target == "prompts":
                return run_prompts_check(root)
            if args.target == "diff":
                return run_diff_check(root)
            if args.target == "secrets":
                return run_secrets_check(root)
            if args.target == "codex-os":
                return run_codex_os_check(root)
            if args.target == "all":
                return run_all_check(root)
            if args.target == "task":
                if not args.task_label:
                    parser.error("'./dev check task' requires a task label")
                return run_task_check(args.task_label, root)
        if args.command == "wording" and args.wording_command == "audit":
            return run_wording_audit(root, args)
        if args.command == "build" and args.build_target == "core":
            return run_core_build(root, profile=args.profile, out_dir=args.out_dir, deployment_target=args.deployment_target)
        if args.command == "test" and args.test_target == "macos":
            return run_macos_tests(
                root,
                scheme=args.scheme,
                test_bundle_name=args.test_bundle_name,
                destination=args.destination,
                derived_data_path=args.derived_data_path,
                keep_derived_data=args.keep_derived_data or None,
                test_log=args.test_log,
                build_log=args.build_log,
                result_bundle_path=args.result_bundle_path,
                only_testing=args.only_testing,
                disable_parallel_testing=args.disable_parallel_testing,
            )
        if args.command == "bindings" and args.bindings_command == "update":
            return run_bindings_update(root, args.udl, args.out_dir)
        if args.command == "release" and args.release_command == "preflight":
            return run_release_preflight(root, notary_profile=args.notary_profile)
        if args.command == "release" and args.release_command == "readiness-build":
            return run_release_readiness_build(
                root,
                install=args.install,
                build_number=args.build_number,
                derived_data_path=args.derived_data_path,
                destination=args.destination,
                applications_dir=args.applications_dir,
            )
        if args.command == "changes" and args.changes_command == "doctor":
            return run_changes_doctor(root, args)
        if args.command == "changes" and args.changes_command == "preview":
            return run_changes_preview(root, args)
        if args.command == "changes" and args.changes_command == "generate":
            return run_changes_generate(root, args)
        if args.command == "backlog":
            return run_backlog_command(root, args)
        if args.command == "tasks":
            return run_tasks_command(root, args)
        if args.command == "codex-os":
            return run_codex_os_command(root, args)
        if args.command == "workflow" and args.workflow_command == "doctor":
            return run_workflow_doctor(root, args)
        if args.command == "workflow" and args.workflow_command == "status":
            return run_workflow_status(root, args)
        if args.command == "workflow" and args.workflow_command == "check-template":
            return run_workflow_check_template(root, args)
        if args.command == "workflow" and args.workflow_command == "init":
            return run_workflow_init(root, args)
        if args.command == "workflow" and args.workflow_command == "discuss":
            return run_workflow_discuss(root, args)
        if args.command == "workflow" and args.workflow_command == "baseline":
            return run_workflow_baseline(root, args)
        if args.command == "workflow" and args.workflow_command == "middle":
            return run_workflow_middle(root, args)
        if args.command == "workflow" and args.workflow_command == "plan":
            return run_workflow_plan(root, args)
        if args.command == "workflow" and args.workflow_command == "drafts":
            return run_workflow_drafts(root, args)
        if args.command == "workflow" and args.workflow_command == "queue":
            return run_workflow_queue(root, args)
        if args.command == "workflow" and args.workflow_command == "promote":
            return run_workflow_promote(root, args)
        if args.command == "workflow" and args.workflow_command == "project":
            return run_workflow_project(root, args)
        if args.command == "workflow" and args.workflow_command == "closeout":
            return run_workflow_closeout(root, args)
        parser.error("unsupported command")
        return 2
    except ToolError as exc:
        return print_error(exc)


if __name__ == "__main__":
    raise SystemExit(main())
