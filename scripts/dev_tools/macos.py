"""macOS XCTest runner with local sandbox fallback."""

from __future__ import annotations

import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Mapping, Sequence

from .artifacts import macos_derived_data_dir
from .common import fail, project_root, require_command
from .macos_release_probe import RELEASE_APP_LAUNCH_BLOCKED, run_release_app_launch_probe

MACOS_TESTS_BLOCKED_BY_XCODE_ENVIRONMENT = 75
SWIFT_WATCHER_COVERAGE_THRESHOLD = 0.60
SWIFT_BRIDGE_COVERAGE_THRESHOLD = 0.50
SWIFT_WATCHER_COVERAGE_FILES = {
    "PlatformServices/InFlightFileChangeTracker.swift",
    "PlatformServices/MainExternalCreatedFileWatcher.swift",
    "PlatformServices/MainExternalSyncEvents.swift",
}
PERFORMANCE_TEST_SUITES = frozenset({"AreaMatrixPerfTests", "ObservabilityPerformanceTests"})


def _run_and_tee(argv: Sequence[str], log_path: Path, *, env: Mapping[str, str] | None = None) -> int:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    with log_path.open("w", encoding="utf-8") as log:
        proc = subprocess.Popen(
            [str(part) for part in argv],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=merged_env,
        )
        assert proc.stdout is not None
        for line in proc.stdout:
            sys.stdout.write(line)
            log.write(line)
        return proc.wait()


def _sandbox_failure(log_path: Path) -> bool:
    text = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else ""
    return bool(
        re.search(r"testmanagerd\.control|Failed to establish communication with the test runner", text)
        and re.search(r"sandbox", text, flags=re.IGNORECASE)
    )


def _xcode_system_content_failure(log_path: Path) -> bool:
    text = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else ""
    return all(
        marker in text
        for marker in [
            "A required plugin failed to load",
            "IDESimulatorFoundation",
            "DVTDownloads",
            "xcodebuild -runFirstLaunch",
        ]
    )


def _codex_local_xcode_system_content_blocked(log_path: Path) -> bool:
    return os.environ.get("CODEX_SANDBOX") == "seatbelt" and _xcode_system_content_failure(log_path)


def _requested_xctest_suites(only_testing: Sequence[str]) -> list[str]:
    suites: set[str] = set()
    for test_id in only_testing:
        parts = [part for part in test_id.split("/") if part]
        if len(parts) >= 2:
            suites.add(parts[1])
    return sorted(suites)


def _has_real_test_or_build_failure(text: str) -> bool:
    failure_markers = [
        "Testing cancelled because the build failed.",
        "The following build commands failed",
        "Unable to find module dependency",
    ]
    if any(marker in text for marker in failure_markers):
        return True
    if re.search(r"Test Case '.*' failed", text):
        return True
    if re.search(r"Test Suite '.*' failed at", text):
        return True
    return bool(re.search(r"Executed \d+ tests?, with [1-9]\d* failures", text))


def _xcodebuild_tests_passed_before_sandbox_teardown(log_path: Path, only_testing: Sequence[str]) -> bool:
    if not _sandbox_failure(log_path):
        return False
    text = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else ""
    if _has_real_test_or_build_failure(text):
        return False
    if "Test Suite 'Selected tests' passed" not in text:
        return False
    return all(f"Test Suite '{suite}' passed" in text for suite in _requested_xctest_suites(only_testing))


def _parallel_xcodebuild_retry_allowed(log_path: Path) -> bool:
    text = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else ""
    return ("Testing started" in text or "Test Suite '" in text) and not _has_real_test_or_build_failure(text)


def _find_test_bundle(derived_data_dir: Path, test_bundle_name: str) -> Path | None:
    products_dir = derived_data_dir / "Build/Products"
    default_bundle = products_dir / "Debug" / test_bundle_name
    if default_bundle.is_dir():
        return default_bundle
    if not products_dir.exists():
        return None
    for path in products_dir.rglob(test_bundle_name):
        if path.is_dir():
            return path
    return None


def _fallback_env(products_dir: Path, scheme: str) -> dict[str, str]:
    app_macos_dir = products_dir / f"{scheme}.app/Contents/MacOS"
    if not app_macos_dir.is_dir():
        fail(f"app binary directory not found at {app_macos_dir}.")

    env = os.environ.copy()
    env["DYLD_LIBRARY_PATH"] = f"{app_macos_dir}:{env.get('DYLD_LIBRARY_PATH', '')}"
    env["DYLD_FRAMEWORK_PATH"] = f"{products_dir}:{env.get('DYLD_FRAMEWORK_PATH', '')}"
    env["AREAMATRIX_XCTEST_FALLBACK"] = "1"
    return env


def _products_dir_for_test_bundle(test_bundle: Path, scheme: str) -> Path:
    for candidate in test_bundle.parents:
        if (candidate / f"{scheme}.app/Contents/MacOS").is_dir():
            return candidate
    fail(f"app products directory not found for {test_bundle}.")


def _run_xctest_bundle(test_bundle: Path, scheme: str) -> int:
    if not test_bundle.is_dir():
        fail(f"test bundle not found at {test_bundle}.")

    products_dir = _products_dir_for_test_bundle(test_bundle, scheme)
    env = _fallback_env(products_dir, scheme)
    print()
    print(f"==> xcrun xctest {test_bundle}")
    return subprocess.run(["xcrun", "xctest", str(test_bundle)], env=env, check=False).returncode


def _includes_release_perf_tests(only_testing: Sequence[str]) -> bool:
    return any(
        test_id == "AreaMatrixTests/AreaMatrixPerfTests"
        or test_id.startswith("AreaMatrixTests/AreaMatrixPerfTests/")
        for test_id in only_testing
    )


def _performance_test_ids(only_testing: Sequence[str]) -> list[str]:
    return [
        test_id
        for test_id in only_testing
        if len(parts := [part for part in test_id.split("/") if part]) >= 2
        and parts[1] in PERFORMANCE_TEST_SUITES
    ]


def _includes_performance_tests(only_testing: Sequence[str]) -> bool:
    return bool(_performance_test_ids(only_testing))


def _xcode_test_env(only_testing: Sequence[str]) -> dict[str, str] | None:
    env = {"AREAMATRIX_TEST_MODE": "1"}
    if _includes_performance_tests(only_testing):
        env["AREAMATRIX_RUN_PERF_TESTS"] = "1"
    return env


def _handle_release_app_launch_probe_result(probe_rc: int) -> int:
    if probe_rc == 0:
        return 0
    if probe_rc == RELEASE_APP_LAUNCH_BLOCKED:
        print("macOS tests: release real .app launch probe was blocked by local sandbox.")
        print("macOS tests: local XCTest validation passed; release checklist remains blocked.")
        return 0
    return probe_rc


def _run_release_probe_when_requested(
    root: Path,
    derived_data_dir: Path,
    build_base: Sequence[str],
    build_log_path: Path,
    only_testing: Sequence[str],
) -> int:
    if not _includes_release_perf_tests(only_testing):
        return 0

    probe_rc = run_release_app_launch_probe(
        root,
        derived_data_dir,
        build_base,
        build_log_path,
        _run_and_tee,
    )
    return _handle_release_app_launch_probe_result(probe_rc)


def _xctest_filter(only_testing: Sequence[str]) -> list[str]:
    filters: list[str] = []
    for test_id in only_testing:
        parts = [part for part in test_id.split("/") if part]
        if len(parts) < 2:
            fail(f"--only-testing expects TARGET/CLASS or TARGET/CLASS/METHOD, got {test_id!r}.")
        target, class_name, *method = parts
        filter_id = f"{target}.{class_name}"
        if method:
            filter_id = f"{filter_id}/{method[0]}"
        filters.extend(["-XCTest", filter_id])
    return filters


def _run_filtered_xctest_bundle(test_bundle: Path, scheme: str, only_testing: Sequence[str]) -> int:
    if not test_bundle.is_dir():
        fail(f"test bundle not found at {test_bundle}.")

    products_dir = _products_dir_for_test_bundle(test_bundle, scheme)
    env = _fallback_env(products_dir, scheme)
    env["AREAMATRIX_TEST_MODE"] = "1"
    if _includes_performance_tests(only_testing):
        env["AREAMATRIX_RUN_PERF_TESTS"] = "1"
    filters = _xctest_filter(only_testing)
    print()
    print(f"==> xcrun xctest {' '.join(filters)} {test_bundle}")
    return subprocess.run(["xcrun", "xctest", *filters, str(test_bundle)], env=env, check=False).returncode


def _run_explicit_performance_tests(
    derived_data_dir: Path,
    scheme: str,
    test_bundle_name: str,
    only_testing: Sequence[str],
) -> int:
    performance_ids = _performance_test_ids(only_testing)
    if not performance_ids:
        return 0
    test_bundle = _find_test_bundle(derived_data_dir, test_bundle_name)
    if test_bundle is None:
        fail(f"test bundle not found under {derived_data_dir}.")
    return _run_filtered_xctest_bundle(test_bundle, scheme, performance_ids)


def _test_base_args(
    project_path: Path,
    scheme: str,
    destination: str,
    derived_data_dir: Path,
    result_bundle: str | Path | None,
    only_testing: Sequence[str],
    disable_parallel_testing: bool = False,
    enable_code_coverage: bool = False,
) -> list[str]:
    base = [
        "-project",
        str(project_path),
        "-scheme",
        scheme,
        "-destination",
        destination,
        "-derivedDataPath",
        str(derived_data_dir),
        "-testLanguage",
        "en",
    ]
    if result_bundle:
        base.extend(["-resultBundlePath", str(result_bundle)])
    if disable_parallel_testing:
        base.extend(["-parallel-testing-enabled", "NO"])
    if enable_code_coverage:
        base.extend(["-enableCodeCoverage", "YES"])
    for test_id in only_testing:
        base.append(f"-only-testing:{test_id}")
    base.append("CODE_SIGNING_ALLOWED=NO")
    return base


def _build_for_testing_base_args(
    project_path: Path,
    scheme: str,
    destination: str,
    derived_data_dir: Path,
) -> list[str]:
    return [
        "-project",
        str(project_path),
        "-scheme",
        scheme,
        "-destination",
        destination,
        "-derivedDataPath",
        str(derived_data_dir),
        "CODE_SIGNING_ALLOWED=NO",
    ]


def _find_or_build_test_bundle(
    derived_data_dir: Path,
    test_bundle_name: str,
    build_base: Sequence[str],
    build_log_path: Path,
) -> Path:
    test_bundle = _find_test_bundle(derived_data_dir, test_bundle_name)
    if test_bundle is not None:
        return test_bundle

    print()
    print("==> xcodebuild build-for-testing")
    rc = _run_and_tee(["xcodebuild", "build-for-testing", *build_base], build_log_path)
    if rc != 0:
        raise ToolExit(rc)
    test_bundle = _find_test_bundle(derived_data_dir, test_bundle_name)
    if test_bundle is None:
        fail(f"unable to locate {test_bundle_name} under {derived_data_dir}.")
    return test_bundle


class ToolExit(Exception):
    def __init__(self, code: int) -> None:
        self.code = code


def _run_sandbox_fallback(
    root: Path,
    derived_data_dir: Path,
    scheme: str,
    test_bundle_name: str,
    build_base: Sequence[str],
    build_log_path: Path,
    only_testing: Sequence[str],
) -> int:
    print()
    print("==> xcodebuild test was blocked by local sandboxed testmanagerd access.")
    print("    Reusing the built XCTest bundle for direct XCTest execution.")
    try:
        test_bundle = _find_or_build_test_bundle(
            derived_data_dir,
            test_bundle_name,
            build_base,
            build_log_path,
        )
    except ToolExit as error:
        return error.code

    if only_testing:
        rc = _run_filtered_xctest_bundle(test_bundle, scheme, only_testing)
    else:
        rc = _run_xctest_bundle(test_bundle, scheme)
    if rc == 0 and _includes_release_perf_tests(only_testing):
        probe_rc = run_release_app_launch_probe(
            root,
            derived_data_dir,
            build_base,
            build_log_path,
            _run_and_tee,
        )
        rc = _handle_release_app_launch_probe_result(probe_rc)
    if rc == 0:
        _validate_localization_compiler_keys(root, derived_data_dir)
        print("macOS tests: xcrun xctest passed after xcodebuild test sandbox block.")
    return rc


def _validate_localization_compiler_keys(root: Path, derived_data_dir: Path) -> None:
    catalog_path = root / "apps/macos/AreaMatrix/Localizations/Localizable.xcstrings"
    if not catalog_path.is_file():
        fail(f"macOS localization catalog not found at {catalog_path}.")
    try:
        catalog_keys = set(json.loads(catalog_path.read_text(encoding="utf-8")).get("strings", {}))
    except json.JSONDecodeError:
        fail(f"macOS localization catalog is invalid JSON: {catalog_path}.")

    compiler_keys: set[str] = set()
    app_build_root = derived_data_dir / "Build/Intermediates.noindex/AreaMatrix.build"
    for path in app_build_root.rglob("*.stringsdata"):
        if "AreaMatrixTests.build" in path.parts:
            continue
        try:
            tables = json.loads(path.read_text(encoding="utf-8")).get("tables", {})
        except json.JSONDecodeError:
            fail(f"compiler localization metadata is invalid JSON: {path}.")
        if not isinstance(tables, dict):
            continue
        for entries in tables.values():
            if not isinstance(entries, list):
                continue
            compiler_keys.update(
                entry["key"]
                for entry in entries
                if isinstance(entry, dict) and isinstance(entry.get("key"), str)
            )

    if not compiler_keys:
        fail("macOS compiler emitted no localization keys; verify SWIFT_EMIT_LOC_STRINGS remains enabled.")
    missing = sorted(compiler_keys - catalog_keys)
    if missing:
        preview = ", ".join(repr(key) for key in missing[:10])
        suffix = "" if len(missing) <= 10 else f" (+{len(missing) - 10} more)"
        fail(f"macOS String Catalog is missing compiler-emitted keys: {preview}{suffix}.")
    print(f"macOS compiler localization contract: PASS ({len(compiler_keys)} keys)")


def _resolve_derived_data_dir(
    root: Path,
    derived_data_path: str | Path | None,
    *,
    temporary: bool = False,
) -> tuple[Path, bool]:
    if temporary:
        if derived_data_path is not None:
            fail("--derived-data-path cannot be combined with --temporary-derived-data.")
        temp_root = os.environ.get("TMPDIR", "/tmp")
        return Path(tempfile.mkdtemp(prefix="areamatrix-xcode-tests.", dir=temp_root)), True
    configured_path = derived_data_path or os.environ.get("DERIVED_DATA_PATH")
    if configured_path:
        return macos_derived_data_dir(root, configured=configured_path), False
    if os.environ.get("AREAMATRIX_TEMP_DERIVED_DATA", "0") != "1":
        return macos_derived_data_dir(root), False
    temp_root = os.environ.get("TMPDIR", "/tmp")
    return Path(tempfile.mkdtemp(prefix="areamatrix-xcode-tests.", dir=temp_root)), True


def _resolve_log_paths(
    derived_data_dir: Path,
    test_log: str | Path | None,
    build_log: str | Path | None,
) -> tuple[Path, Path]:
    default_test_log = derived_data_dir / "xcodebuild-test.log"
    default_build_log = derived_data_dir / "xcodebuild-build-for-testing.log"
    test_log_path = Path(test_log or os.environ.get("XCODEBUILD_TEST_LOG", default_test_log))
    build_log_path = Path(build_log or os.environ.get("XCODEBUILD_BUILD_LOG", default_build_log))
    return test_log_path, build_log_path


def run_macos_tests(
    root: Path | None = None,
    *,
    scheme: str | None = None,
    test_bundle_name: str | None = None,
    destination: str | None = None,
    derived_data_path: str | Path | None = None,
    temporary_derived_data: bool = False,
    keep_derived_data: bool | None = None,
    test_log: str | Path | None = None,
    build_log: str | Path | None = None,
    result_bundle_path: str | Path | None = None,
    only_testing: Sequence[str] | None = None,
    disable_parallel_testing: bool = False,
    enable_code_coverage: bool = False,
    coverage_gate: bool = False,
) -> int:
    started_at = time.monotonic()
    result: int | None = None
    root = (root or project_root()).resolve()
    project_path = root / "apps/macos/AreaMatrix.xcodeproj"
    scheme = scheme or os.environ.get("XCODE_SCHEME", "AreaMatrix")
    test_bundle_name = test_bundle_name or os.environ.get("XCODE_TEST_BUNDLE_NAME", "AreaMatrixTests.xctest")
    destination = destination or os.environ.get("XCODE_DESTINATION", f"platform=macOS,arch={platform.machine()}")
    keep = keep_derived_data if keep_derived_data is not None else os.environ.get("KEEP_DERIVED_DATA", "0") == "1"
    derived_data_dir, created = _resolve_derived_data_dir(
        root,
        derived_data_path,
        temporary=temporary_derived_data,
    )
    test_log_path, build_log_path = _resolve_log_paths(derived_data_dir, test_log, build_log)
    result_bundle = result_bundle_path or os.environ.get("XCODE_RESULT_BUNDLE_PATH")
    if coverage_gate and not result_bundle:
        fail("macOS coverage gate requires --result-bundle-path.")
    if coverage_gate:
        enable_code_coverage = True

    try:
        require_command("xcodebuild")
        require_command("xcrun")
        if not project_path.is_dir():
            fail(f"Xcode project not found at {project_path}.")
        derived_data_dir.mkdir(parents=True, exist_ok=True)
        result = _run_macos_tests_inner(
            root,
            project_path,
            scheme,
            test_bundle_name,
            destination,
            derived_data_dir,
            test_log_path,
            build_log_path,
            result_bundle,
            list(only_testing or []),
            disable_parallel_testing,
            enable_code_coverage,
            coverage_gate,
        )
        return result
    finally:
        status = result if result is not None else "error"
        print(
            "macOS test metrics: "
            f"status={status} derived_data={'temporary' if created else 'persistent'} "
            f"duration_seconds={time.monotonic() - started_at:.3f}"
        )
        if created and not keep:
            shutil.rmtree(derived_data_dir, ignore_errors=True)


def _run_macos_tests_inner(
    root: Path,
    project_path: Path,
    scheme: str,
    test_bundle_name: str,
    destination: str,
    derived_data_dir: Path,
    test_log_path: Path,
    build_log_path: Path,
    result_bundle: str | Path | None,
    only_testing: Sequence[str],
    disable_parallel_testing: bool = False,
    enable_code_coverage: bool = False,
    coverage_gate: bool = False,
) -> int:
    base = _test_base_args(
        project_path,
        scheme,
        destination,
        derived_data_dir,
        result_bundle,
        only_testing,
        disable_parallel_testing,
        enable_code_coverage,
    )
    build_base = _build_for_testing_base_args(project_path, scheme, destination, derived_data_dir)
    print("==> xcodebuild test")
    rc = _run_and_tee(["xcodebuild", "test", *base], test_log_path, env=_xcode_test_env(only_testing))
    if rc == 0:
        performance_rc = _run_explicit_performance_tests(
            derived_data_dir,
            scheme,
            test_bundle_name,
            only_testing,
        )
        if performance_rc != 0:
            return performance_rc
        _validate_localization_compiler_keys(root, derived_data_dir)
        handled_rc = _run_release_probe_when_requested(
            root,
            derived_data_dir,
            build_base,
            build_log_path,
            only_testing,
        )
        if handled_rc != 0:
            return handled_rc
        if coverage_gate:
            return _run_swift_coverage_gate(root, Path(result_bundle))
        print("macOS tests: xcodebuild test passed.")
        return 0
    if _xcodebuild_tests_passed_before_sandbox_teardown(test_log_path, only_testing):
        performance_rc = _run_explicit_performance_tests(
            derived_data_dir,
            scheme,
            test_bundle_name,
            only_testing,
        )
        if performance_rc != 0:
            return performance_rc
        _validate_localization_compiler_keys(root, derived_data_dir)
        handled_rc = _run_release_probe_when_requested(
            root,
            derived_data_dir,
            build_base,
            build_log_path,
            only_testing,
        )
        if handled_rc != 0:
            return handled_rc
        if coverage_gate:
            return _run_swift_coverage_gate(root, Path(result_bundle))
        print("macOS tests: xcodebuild XCTest suites passed.")
        print("macOS tests: ignoring sandbox-only testmanagerd teardown/reporting failure.")
        return 0
    if _codex_local_xcode_system_content_blocked(test_log_path):
        print("macOS tests: xcodebuild was blocked by local Xcode system content mismatch.")
        print("macOS tests: run 'xcodebuild -runFirstLaunch' or repair Xcode outside this sandbox.")
        print("macOS tests: CI and non-sandbox local runs remain required for XCTest evidence.")
        return MACOS_TESTS_BLOCKED_BY_XCODE_ENVIRONMENT
    if not _sandbox_failure(test_log_path):
        if not disable_parallel_testing and result_bundle is None and _parallel_xcodebuild_retry_allowed(test_log_path):
            print("macOS tests: parallel xcodebuild ended without a real test or build failure.")
            print("macOS tests: retrying once with parallel testing disabled.")
            return _run_macos_tests_inner(
                root,
                project_path,
                scheme,
                test_bundle_name,
                destination,
                derived_data_dir,
                test_log_path,
                build_log_path,
                result_bundle,
                only_testing,
                True,
                enable_code_coverage,
                coverage_gate,
            )
        fail(f"xcodebuild test failed for a non-sandbox reason. See {test_log_path}.", rc)

    if coverage_gate:
        fail("macOS coverage gate requires standard xcodebuild coverage evidence; xctest fallback is not accepted.")
    return _run_sandbox_fallback(
        root,
        derived_data_dir,
        scheme,
        test_bundle_name,
        build_base,
        build_log_path,
        only_testing,
    )


def _run_swift_coverage_gate(root: Path, result_bundle: Path) -> int:
    if not result_bundle.exists():
        fail(f"macOS coverage result bundle not found at {result_bundle}.")
    completed = subprocess.run(
        ["xcrun", "xccov", "view", "--report", "--json", str(result_bundle)],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        fail(f"xccov coverage report failed: {completed.stderr.strip()}", completed.returncode)
    try:
        report = json.loads(completed.stdout)
    except json.JSONDecodeError:
        fail("xccov coverage report returned invalid JSON.")
    return _evaluate_swift_coverage_report(root, report)


def _evaluate_swift_coverage_report(root: Path, report: object) -> int:
    if not isinstance(report, dict) or not isinstance(report.get("targets"), list):
        fail("xccov coverage report is missing targets.")
    app_targets = [
        target
        for target in report["targets"]
        if isinstance(target, dict) and target.get("name") == "AreaMatrix.app"
    ]
    if len(app_targets) != 1:
        fail(f"xccov coverage report expected one AreaMatrix.app target, found {len(app_targets)}.")
    files = app_targets[0].get("files")
    if not isinstance(files, list):
        fail("xccov AreaMatrix.app target is missing files.")

    source_root = (root / "apps/macos/AreaMatrix").resolve()
    missing_watcher_sources = sorted(
        relative for relative in SWIFT_WATCHER_COVERAGE_FILES if not (source_root / relative).is_file()
    )
    if missing_watcher_sources:
        fail(f"Swift Watcher coverage source inventory drift; missing {missing_watcher_sources}.")
    expected_bridge_files = {
        path.relative_to(source_root).as_posix()
        for path in (source_root / "Bridge").rglob("*.swift")
        if "Generated" not in path.parts and "UniFFI" not in path.parts
    }
    if not expected_bridge_files:
        fail("Swift Bridge coverage source inventory is empty.")
    watcher_rows = []
    bridge_rows = []
    for row in files:
        path_value = row.get("path")
        if not isinstance(path_value, str):
            continue
        path = Path(path_value).resolve()
        try:
            relative = path.relative_to(source_root).as_posix()
        except ValueError:
            continue
        if relative in SWIFT_WATCHER_COVERAGE_FILES:
            watcher_rows.append((relative, row))
        if relative.startswith("Bridge/") and not relative.startswith(("Bridge/Generated/", "Bridge/UniFFI/")):
            bridge_rows.append((relative, row))

    found_watcher_files = {relative for relative, _ in watcher_rows}
    if found_watcher_files != SWIFT_WATCHER_COVERAGE_FILES:
        missing = sorted(SWIFT_WATCHER_COVERAGE_FILES - found_watcher_files)
        fail(f"Swift Watcher coverage inventory drift; missing {missing}.")
    found_bridge_files = {relative for relative, _ in bridge_rows}
    if found_bridge_files != expected_bridge_files:
        missing = sorted(expected_bridge_files - found_bridge_files)
        unexpected = sorted(found_bridge_files - expected_bridge_files)
        fail(f"Swift Bridge coverage inventory drift; missing {missing}, unexpected {unexpected}.")
    watcher_coverage = _coverage_ratio(watcher_rows, "Swift Watcher")
    bridge_coverage = _coverage_ratio(bridge_rows, "Swift Bridge")
    print(f"Swift Watcher coverage: {watcher_coverage:.2%} (required {SWIFT_WATCHER_COVERAGE_THRESHOLD:.0%})")
    print(f"Swift Bridge coverage: {bridge_coverage:.2%} (required {SWIFT_BRIDGE_COVERAGE_THRESHOLD:.0%})")
    if watcher_coverage < SWIFT_WATCHER_COVERAGE_THRESHOLD:
        fail("Swift Watcher coverage is below the required threshold.")
    if bridge_coverage < SWIFT_BRIDGE_COVERAGE_THRESHOLD:
        fail("Swift Bridge coverage is below the required threshold.")
    print("macOS coverage gate: PASS")
    return 0


def _coverage_ratio(rows: Sequence[tuple[str, dict]], label: str) -> float:
    if not rows:
        fail(f"{label} coverage inventory is empty.")
    covered = sum(int(row.get("coveredLines", 0)) for _, row in rows)
    executable = sum(int(row.get("executableLines", 0)) for _, row in rows)
    if executable <= 0:
        fail(f"{label} coverage has no executable lines.")
    return covered / executable
