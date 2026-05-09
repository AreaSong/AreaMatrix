"""CLI dispatcher for the AreaMatrix root ./dev tool surface."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence

from .build import run_bindings_update, run_core_build
from .changes import run_changes_doctor, run_changes_generate, run_changes_preview
from .checks import (
    run_all_check,
    run_diff_check,
    run_governance_check,
    run_prompts_check,
    run_quick_check,
    run_skills_check,
    run_task_loop_check,
)
from .common import ToolError, print_error, project_root
from .discussion import run_workflow_discuss
from .macos import run_macos_tests
from .middle_layer import run_workflow_middle
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


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="./dev", description="AreaMatrix developer tools")
    subparsers = parser.add_subparsers(dest="command", required=True)

    check = subparsers.add_parser("check", help="Run repo health checks")
    check.add_argument("target", nargs="?", choices=["governance", "skills", "task-loop", "prompts", "diff", "all"])

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

    workflow = subparsers.add_parser("workflow", help="Manage versioned workflow templates, plans, and queue candidates")
    workflow_sub = workflow.add_subparsers(dest="workflow_command", required=True)
    workflow_sub.add_parser("doctor", help="Validate versioned workflow structure and gates")
    workflow_sub.add_parser("status", help="Show versioned workflow status and promotion gates")
    workflow_sub.add_parser("check-template", help=f"Run the full managed template reference gate; defaults to {DEFAULT_VERSION}")
    workflow_init = workflow_sub.add_parser("init", help="Render or write a new v* workflow version skeleton")
    workflow_init.add_argument("--version", required=True, help="Workflow version to initialize, such as v3")
    workflow_init.add_argument("--title", help="Workflow title; defaults to 'AreaMatrix <version> planning workflow'")
    workflow_init.add_argument("--write", action="store_true", help="Write version files instead of printing a preview")
    workflow_init.add_argument("--out-dir", help="Version output directory; defaults to workflow/versions/<version>")
    workflow_init.add_argument("--force", action="store_true", help="Allow overwriting existing version skeleton files when --write is used")
    workflow_discuss = workflow_sub.add_parser("discuss", help="Manage pre-change workflow discussion gates")
    workflow_discuss.add_argument("--version", required=True, help="Workflow version to discuss, such as v3")
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
    workflow_middle.add_argument("--version", required=True, help="Workflow version to inspect, such as v3")
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
            if args.target == "governance":
                return run_governance_check(root)
            if args.target == "skills":
                return run_skills_check(root)
            if args.target == "task-loop":
                return run_task_loop_check(root)
            if args.target == "prompts":
                return run_prompts_check(root)
            if args.target == "diff":
                return run_diff_check(root)
            if args.target == "all":
                return run_all_check(root)
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
            )
        if args.command == "bindings" and args.bindings_command == "update":
            return run_bindings_update(root, args.udl, args.out_dir)
        if args.command == "changes" and args.changes_command == "doctor":
            return run_changes_doctor(root, args)
        if args.command == "changes" and args.changes_command == "preview":
            return run_changes_preview(root, args)
        if args.command == "changes" and args.changes_command == "generate":
            return run_changes_generate(root, args)
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
