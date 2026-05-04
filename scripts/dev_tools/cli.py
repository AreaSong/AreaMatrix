"""CLI dispatcher for the AreaMatrix root ./dev tool surface."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence

from .build import run_bindings_update, run_core_build
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
from .macos import run_macos_tests


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

    bindings = subparsers.add_parser("bindings", help="Manage generated language bindings")
    bindings_sub = bindings.add_subparsers(dest="bindings_command", required=True)
    update = bindings_sub.add_parser("update", help="Regenerate Swift bindings from an explicit UDL")
    update.add_argument("--udl", required=True, help="UDL file path")
    update.add_argument("--out-dir", "--output-dir", dest="out_dir", required=True, help="Output directory")

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
            )
        if args.command == "bindings" and args.bindings_command == "update":
            return run_bindings_update(root, args.udl, args.out_dir)
        parser.error("unsupported command")
        return 2
    except ToolError as exc:
        return print_error(exc)


if __name__ == "__main__":
    raise SystemExit(main())
