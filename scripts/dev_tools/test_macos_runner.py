"""Regression tests for the macOS XCTest sandbox fallback gate."""

from __future__ import annotations

import io
import json
import re
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

from scripts.dev_tools.macos import (
    MACOS_TESTS_BLOCKED_BY_XCODE_ENVIRONMENT,
    RELEASE_APP_LAUNCH_BLOCKED,
    _codex_local_xcode_system_content_blocked,
    _evaluate_swift_coverage_report,
    _handle_release_app_launch_probe_result,
    _parallel_xcodebuild_retry_allowed,
    _products_dir_for_test_bundle,
    _normalise_test_plan,
    _resolve_derived_data_dir,
    run_macos_tests,
    _run_sandbox_fallback,
    _run_macos_tests_inner,
    _test_base_args,
    _test_plan_selected_tests,
    _validate_localization_compiler_keys,
    _xcodebuild_tests_passed_before_sandbox_teardown,
    _xcode_system_content_failure,
    _xcode_test_env,
    _build_for_testing_base_args,
)
from scripts.dev_tools.common import ToolError
from scripts.dev_tools.macos_release_probe import (
    _direct_launch_probe_blocked,
    _launchservices_probe_blocked,
)


class MacOSTestRunnerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp.name)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_default_derived_data_is_persistent_and_workspace_local(self) -> None:
        root = self.tmp_path / "workspace"

        derived, temporary = _resolve_derived_data_dir(root, None)

        self.assertEqual(derived, (root / ".build/derived-data/macos-tests").resolve())
        self.assertFalse(temporary)

    def test_temporary_derived_data_remains_explicit(self) -> None:
        root = self.tmp_path / "workspace"
        with patch.dict("os.environ", {"TMPDIR": str(self.tmp_path)}, clear=True):
            derived, temporary = _resolve_derived_data_dir(root, None, temporary=True)

        self.assertTrue(temporary)
        self.assertTrue(derived.name.startswith("areamatrix-xcode-tests."))

    def test_explicit_temporary_derived_data_overrides_environment_path(self) -> None:
        root = self.tmp_path / "workspace"
        environment_path = self.tmp_path / "environment-derived-data"
        with patch.dict(
            "os.environ",
            {"TMPDIR": str(self.tmp_path), "DERIVED_DATA_PATH": str(environment_path)},
            clear=True,
        ):
            derived, temporary = _resolve_derived_data_dir(root, None, temporary=True)

        self.assertTrue(temporary)
        self.assertNotEqual(derived, environment_path)

    def test_explicit_path_and_temporary_derived_data_are_mutually_exclusive(self) -> None:
        with self.assertRaises(ToolError):
            _resolve_derived_data_dir(
                self.tmp_path / "workspace",
                self.tmp_path / "explicit-derived-data",
                temporary=True,
            )

    def test_test_plan_name_accepts_name_or_xctestplan_filename(self) -> None:
        root = self.tmp_path / "workspace"
        plan = root / "apps/macos/AreaMatrix-Unit.xctestplan"
        plan.parent.mkdir(parents=True)
        plan.write_text('{"testTargets": [{"selectedTests": []}]}', encoding="utf-8")

        self.assertEqual(_normalise_test_plan(root, "AreaMatrix-Unit"), "AreaMatrix-Unit")
        self.assertEqual(_normalise_test_plan(root, "AreaMatrix-Unit.xctestplan"), "AreaMatrix-Unit")

    def test_test_plan_name_rejects_unknown_or_missing_plan(self) -> None:
        root = self.tmp_path / "workspace"
        with self.assertRaises(ToolError):
            _normalise_test_plan(root, "AreaMatrix-Unknown")

        plan = root / "apps/macos/AreaMatrix-Unit.xctestplan"
        plan.parent.mkdir(parents=True)
        with self.assertRaises(ToolError):
            _normalise_test_plan(root, "AreaMatrix-Unit")

    def test_test_plan_selected_tests_are_available_for_hostless_fallback(self) -> None:
        root = self.tmp_path / "workspace"
        plan = root / "apps/macos/AreaMatrix-Unit.xctestplan"
        plan.parent.mkdir(parents=True)
        plan.write_text(
            json.dumps(
                {
                    "testTargets": [
                        {
                            "selectedTests": [
                                "AreaMatrixTests/AppLanguageTests/testSystemLanguageResolutionSupportsEnglishAndSimplifiedChinese"
                            ]
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )

        self.assertEqual(
            _test_plan_selected_tests(root, "AreaMatrix-Unit"),
            [
                "AreaMatrixTests/AppLanguageTests/testSystemLanguageResolutionSupportsEnglishAndSimplifiedChinese"
            ],
        )

    def test_outer_runner_reports_persistent_derived_data_metrics(self) -> None:
        root = self.tmp_path / "workspace"
        (root / "apps/macos/AreaMatrix.xcodeproj").mkdir(parents=True)
        output = io.StringIO()

        with (
            patch("scripts.dev_tools.macos.require_command"),
            patch("scripts.dev_tools.macos._run_macos_tests_inner", return_value=0),
            redirect_stdout(output),
        ):
            self.assertEqual(run_macos_tests(root), 0)

        self.assertRegex(
            output.getvalue(),
            re.compile(
                r"macOS test metrics: status=0 derived_data=persistent duration_seconds=\d+\.\d{3}"
            ),
        )

    def test_outer_runner_reports_nonzero_temporary_metrics_and_cleans_cache(self) -> None:
        root = self.tmp_path / "workspace"
        (root / "apps/macos/AreaMatrix.xcodeproj").mkdir(parents=True)
        temporary_cache = self.tmp_path / "temporary-derived-data"
        output = io.StringIO()

        with (
            patch("scripts.dev_tools.macos.require_command"),
            patch("scripts.dev_tools.macos.tempfile.mkdtemp", return_value=str(temporary_cache)),
            patch("scripts.dev_tools.macos._run_macos_tests_inner", return_value=65),
            redirect_stdout(output),
        ):
            self.assertEqual(run_macos_tests(root, temporary_derived_data=True), 65)

        self.assertFalse(temporary_cache.exists())
        self.assertRegex(
            output.getvalue(),
            re.compile(
                r"macOS test metrics: status=65 derived_data=temporary duration_seconds=\d+\.\d{3}"
            ),
        )

    def write_localization_compiler_fixture(
        self,
        *,
        catalog_keys: tuple[str, ...] = ("App key",),
        app_entries: object = None,
        test_entries: object = None,
    ) -> tuple[Path, Path]:
        root = self.tmp_path / "workspace"
        catalog = root / "apps/macos/AreaMatrix/Localizations/Localizable.xcstrings"
        catalog.parent.mkdir(parents=True)
        catalog.write_text(
            json.dumps({"strings": {key: {} for key in catalog_keys}}),
            encoding="utf-8",
        )
        derived = self.tmp_path / "DerivedData"
        build_root = derived / "Build/Intermediates.noindex/AreaMatrix.build"
        app_metadata = build_root / "Debug/AreaMatrix.build/Objects-normal/arm64/App.stringsdata"
        app_metadata.parent.mkdir(parents=True)
        app_metadata.write_text(
            json.dumps({
                "tables": {"Localizable": app_entries if app_entries is not None else [{"key": "App key"}]}
            }),
            encoding="utf-8",
        )
        if test_entries is not None:
            test_metadata = build_root / "Debug/AreaMatrixTests.build/Objects-normal/arm64/Tests.stringsdata"
            test_metadata.parent.mkdir(parents=True)
            test_metadata.write_text(
                json.dumps({"tables": {"Localizable": test_entries}}),
                encoding="utf-8",
            )
        return root, derived

    def test_localization_compiler_validator_accepts_matching_app_keys_and_excludes_tests(self) -> None:
        root, derived = self.write_localization_compiler_fixture(
            test_entries=[{"key": "Test-only key"}],
        )

        _validate_localization_compiler_keys(root, derived)

    def test_localization_compiler_validator_rejects_missing_catalog_key(self) -> None:
        root, derived = self.write_localization_compiler_fixture(
            catalog_keys=("Other key",),
        )

        with self.assertRaises(ToolError):
            _validate_localization_compiler_keys(root, derived)

    def test_localization_compiler_validator_rejects_invalid_metadata(self) -> None:
        root, derived = self.write_localization_compiler_fixture()
        metadata = next((derived / "Build").rglob("*.stringsdata"))
        metadata.write_text("{invalid", encoding="utf-8")

        with self.assertRaises(ToolError):
            _validate_localization_compiler_keys(root, derived)

    def test_localization_compiler_validator_rejects_empty_app_metadata(self) -> None:
        root, derived = self.write_localization_compiler_fixture(app_entries=[])

        with self.assertRaises(ToolError):
            _validate_localization_compiler_keys(root, derived)

    def test_accepts_passed_selected_suite_with_sandbox_teardown_error(self) -> None:
        log_path = self.write_log(
            "\n".join(
                [
                    "Test Suite 'Selected tests' passed at 2026-05-09.",
                    "Test Suite 'AreaMatrixPerfTests' passed at 2026-05-09.",
                    "Executed 5 tests, with 0 failures (0 unexpected)",
                    "com.apple.testmanagerd.control was invalidated: Sandbox restriction.",
                ]
            )
        )

        result = _xcodebuild_tests_passed_before_sandbox_teardown(
            log_path,
            ["AreaMatrixTests/AreaMatrixPerfTests"],
        )

        self.assertTrue(result)

    def test_rejects_real_test_failure_even_with_sandbox_teardown_error(self) -> None:
        log_path = self.write_log(
            "\n".join(
                [
                    "Test Suite 'Selected tests' passed at 2026-05-09.",
                    "Test Suite 'AreaMatrixPerfTests' passed at 2026-05-09.",
                    "Executed 5 tests, with 1 failures (0 unexpected)",
                    "Test Case '-[AreaMatrixTests.AreaMatrixPerfTests testExample]' failed",
                    "com.apple.testmanagerd.control was invalidated: Sandbox restriction.",
                ]
            )
        )

        result = _xcodebuild_tests_passed_before_sandbox_teardown(
            log_path,
            ["AreaMatrixTests/AreaMatrixPerfTests"],
        )

        self.assertFalse(result)

    def test_rejects_failed_build_even_with_sandbox_teardown_error(self) -> None:
        log_path = self.write_log(
            "\n".join(
                [
                    "Test Suite 'Selected tests' passed at 2026-05-09.",
                    "Testing cancelled because the build failed.",
                    "com.apple.testmanagerd.control was invalidated: Sandbox restriction.",
                ]
            )
        )

        result = _xcodebuild_tests_passed_before_sandbox_teardown(
            log_path,
            ["AreaMatrixTests/AreaMatrixPerfTests"],
        )

        self.assertFalse(result)

    def test_parallel_retry_requires_test_activity_without_real_failure(self) -> None:
        retryable = self.tmp_path / "retryable.log"
        retryable.write_text(
            "Testing started\n"
            "Test Suite 'AreaMatrixTests.xctest' started\n"
            "Executed 12 tests, with 0 failures (0 unexpected)\n",
            encoding="utf-8",
        )
        failed = self.tmp_path / "failed.log"
        failed.write_text(
            "Testing started\n"
            "Test Case '-[AreaMatrixTests.ExampleTests testExample]' failed\n",
            encoding="utf-8",
        )

        self.assertTrue(_parallel_xcodebuild_retry_allowed(retryable))
        self.assertFalse(_parallel_xcodebuild_retry_allowed(failed))

    def test_parallel_xcodebuild_without_real_failure_retries_serially_once(self) -> None:
        project = self.tmp_path / "AreaMatrix.xcodeproj"
        project.mkdir()
        test_log = self.tmp_path / "xcodebuild-test.log"
        build_log = self.tmp_path / "xcodebuild-build.log"
        invocations: list[list[str]] = []

        def fake_run_and_tee(argv, log_path, env=None):
            del env
            invocations.append(list(argv))
            if "-parallel-testing-enabled" not in argv:
                log_path.write_text(
                    "Testing started\nExecuted 12 tests, with 0 failures (0 unexpected)\n",
                    encoding="utf-8",
                )
                return 65
            log_path.write_text("Test Suite 'All tests' passed\n", encoding="utf-8")
            return 0

        with patch("scripts.dev_tools.macos._run_and_tee", side_effect=fake_run_and_tee), \
            patch("scripts.dev_tools.macos._validate_localization_compiler_keys"):
            result = _run_macos_tests_inner(
                self.tmp_path,
                project,
                "AreaMatrix",
                "AreaMatrixTests.xctest",
                "platform=macOS,arch=arm64",
                self.tmp_path,
                test_log,
                build_log,
                None,
                [],
            )

        self.assertEqual(result, 0)
        self.assertEqual(len(invocations), 2)
        self.assertNotIn("-parallel-testing-enabled", invocations[0])
        self.assertIn("-parallel-testing-enabled", invocations[1])

    def test_detects_xcode_system_content_failure(self) -> None:
        log_path = self.write_log(
            "\n".join(
                [
                    "A required plugin failed to load.",
                    "com.apple.dt.IDESimulatorFoundation",
                    "Symbol not found in DVTDownloads.framework",
                    "try running 'xcodebuild -runFirstLaunch'",
                ]
            )
        )

        self.assertTrue(_xcode_system_content_failure(log_path))

    def test_xcode_system_content_block_requires_codex_sandbox(self) -> None:
        log_path = self.write_log(
            "\n".join(
                [
                    "A required plugin failed to load.",
                    "IDESimulatorFoundation",
                    "DVTDownloads",
                    "xcodebuild -runFirstLaunch",
                ]
            )
        )

        with patch.dict("os.environ", {"CODEX_SANDBOX": "seatbelt"}, clear=False):
            self.assertTrue(_codex_local_xcode_system_content_blocked(log_path))

        with patch.dict("os.environ", {"CODEX_SANDBOX": ""}, clear=False):
            self.assertFalse(_codex_local_xcode_system_content_blocked(log_path))

    def test_xcode_system_content_block_returns_explicit_blocked_status(self) -> None:
        project = self.tmp_path / "AreaMatrix.xcodeproj"
        project.mkdir()
        test_log = self.tmp_path / "xcodebuild-test.log"
        build_log = self.tmp_path / "xcodebuild-build.log"

        def fake_run_and_tee(_argv, log_path, env=None):
            log_path.write_text(
                "\n".join(
                    [
                        "A required plugin failed to load.",
                        "IDESimulatorFoundation",
                        "DVTDownloads",
                        "xcodebuild -runFirstLaunch",
                    ]
                ),
                encoding="utf-8",
            )
            return 70

        with patch.dict("os.environ", {"CODEX_SANDBOX": "seatbelt"}, clear=False), \
            patch("scripts.dev_tools.macos._run_and_tee", side_effect=fake_run_and_tee):
            result = _run_macos_tests_inner(
                self.tmp_path,
                project,
                "AreaMatrix",
                "AreaMatrixTests.xctest",
                "platform=macOS,arch=arm64",
                self.tmp_path,
                test_log,
                build_log,
                None,
                [],
            )

        self.assertEqual(result, MACOS_TESTS_BLOCKED_BY_XCODE_ENVIRONMENT)

    def test_launchservices_probe_blocked_requires_codex_sandbox(self) -> None:
        output = (
            "application launch failed: The application could not be launched because it is corrupt. "
            "domain=NSCocoaErrorDomain code=259"
        )

        with patch.dict("os.environ", {"CODEX_SANDBOX": "seatbelt"}, clear=False):
            self.assertTrue(_launchservices_probe_blocked(output))

        with patch.dict("os.environ", {"CODEX_SANDBOX": ""}, clear=False):
            self.assertFalse(_launchservices_probe_blocked(output))

    def test_direct_launch_probe_blocked_requires_codex_sandbox(self) -> None:
        output = "error: first visible window did not appear before timeout"

        with patch.dict("os.environ", {"CODEX_SANDBOX": "seatbelt"}, clear=False):
            self.assertTrue(_direct_launch_probe_blocked(output))

        with patch.dict("os.environ", {"CODEX_SANDBOX": ""}, clear=False):
            self.assertFalse(_direct_launch_probe_blocked(output))

    def test_release_launch_probe_block_keeps_local_validation_green(self) -> None:
        self.assertEqual(_handle_release_app_launch_probe_result(RELEASE_APP_LAUNCH_BLOCKED), 0)

    def test_release_launch_probe_keeps_real_probe_failure_red(self) -> None:
        self.assertEqual(_handle_release_app_launch_probe_result(42), 42)

    def test_performance_tests_are_enabled_only_for_explicit_perf_selection(self) -> None:
        self.assertEqual(_xcode_test_env([]), {"AREAMATRIX_TEST_MODE": "1"})
        self.assertEqual(
            _xcode_test_env(["AreaMatrixTests/AISummaryPrivacyRuleTests"]),
            {"AREAMATRIX_TEST_MODE": "1"},
        )
        self.assertEqual(
            _xcode_test_env(["AreaMatrixTests/AreaMatrixPerfTests"]),
            {
                "AREAMATRIX_TEST_MODE": "1",
                "AREAMATRIX_RUN_PERF_TESTS": "1",
            },
        )
        self.assertEqual(
            _xcode_test_env(["AreaMatrixTests/AreaMatrixPerfTests/testMemoryBaselinesUnderReleaseThresholds"]),
            {
                "AREAMATRIX_TEST_MODE": "1",
                "AREAMATRIX_RUN_PERF_TESTS": "1",
            },
        )
        self.assertEqual(
            _xcode_test_env(["AreaMatrixTests/ObservabilityPerformanceTests"]),
            {
                "AREAMATRIX_TEST_MODE": "1",
                "AREAMATRIX_RUN_PERF_TESTS": "1",
            },
        )
        self.assertEqual(
            _xcode_test_env([], "AreaMatrix-Performance"),
            {
                "AREAMATRIX_TEST_MODE": "1",
                "AREAMATRIX_RUN_PERF_TESTS": "1",
            },
        )

    def test_nested_test_bundle_resolves_host_app_products_directory(self) -> None:
        products = self.tmp_path / "Build/Products/Debug"
        app_binary = products / "AreaMatrix.app/Contents/MacOS"
        app_binary.mkdir(parents=True)
        bundle = products / "AreaMatrix.app/Contents/PlugIns/AreaMatrixTests.xctest"
        bundle.mkdir(parents=True)

        self.assertEqual(_products_dir_for_test_bundle(bundle, "AreaMatrix"), products)

    def test_xcodebuild_success_runs_explicit_observability_performance_tests(self) -> None:
        project = self.tmp_path / "AreaMatrix.xcodeproj"
        project.mkdir()
        bundle = self.tmp_path / "AreaMatrixTests.xctest"
        bundle.mkdir()

        with patch("scripts.dev_tools.macos._run_and_tee", return_value=0), \
            patch("scripts.dev_tools.macos._find_test_bundle", return_value=bundle), \
            patch("scripts.dev_tools.macos._run_filtered_xctest_bundle", return_value=0) as direct, \
            patch("scripts.dev_tools.macos._validate_localization_compiler_keys"):
            result = _run_macos_tests_inner(
                self.tmp_path,
                project,
                "AreaMatrix",
                "AreaMatrixTests.xctest",
                "platform=macOS,arch=arm64",
                self.tmp_path,
                self.tmp_path / "test.log",
                self.tmp_path / "build.log",
                None,
                ["AreaMatrixTests/ObservabilityPerformanceTests"],
            )

        self.assertEqual(result, 0)
        direct.assert_called_once_with(
            bundle,
            "AreaMatrix",
            ["AreaMatrixTests/ObservabilityPerformanceTests"],
        )

    def test_disable_parallel_testing_adds_xcodebuild_flag(self) -> None:
        args = _test_base_args(
            self.tmp_path / "AreaMatrix.xcodeproj",
            "AreaMatrix",
            "platform=macOS,arch=arm64",
            self.tmp_path / "DerivedData",
            "TestResults.xcresult",
            ["AreaMatrixTests/BatchChangeCategoryPageIntegrationVerifyTests"],
            disable_parallel_testing=True,
        )

        self.assertIn("-parallel-testing-enabled", args)
        flag_index = args.index("-parallel-testing-enabled")
        self.assertEqual(args[flag_index + 1], "NO")
        self.assertLess(flag_index, args.index("-only-testing:AreaMatrixTests/BatchChangeCategoryPageIntegrationVerifyTests"))

    def test_parallel_testing_flag_is_omitted_by_default(self) -> None:
        args = _build_for_testing_base_args(
            self.tmp_path / "AreaMatrix.xcodeproj",
            "AreaMatrix",
            "platform=macOS,arch=arm64",
            self.tmp_path / "DerivedData",
            enable_code_coverage=True,
        )

        self.assertNotIn("-parallel-testing-enabled", args)

    def test_macos_tests_use_deterministic_english_language(self) -> None:
        args = _test_base_args(
            self.tmp_path / "AreaMatrix.xcodeproj",
            "AreaMatrix",
            "platform=macOS,arch=arm64",
            self.tmp_path / "DerivedData",
            None,
            [],
        )

        self.assertEqual(args[args.index("-testLanguage") + 1], "en")

    def test_test_plan_is_forwarded_to_xcodebuild_test_action(self) -> None:
        args = _test_base_args(
            self.tmp_path / "AreaMatrix.xcodeproj",
            "AreaMatrix",
            "platform=macOS,arch=arm64",
            self.tmp_path / "DerivedData",
            None,
            [],
            test_plan="AreaMatrix-Unit",
        )

        self.assertIn("-testPlan", args)
        self.assertEqual(args[args.index("-testPlan") + 1], "AreaMatrix-Unit")

    def test_build_for_testing_runs_only_build_action(self) -> None:
        project = self.tmp_path / "AreaMatrix.xcodeproj"
        project.mkdir()
        plan = self.tmp_path / "apps/macos/AreaMatrix-Unit.xctestplan"
        plan.parent.mkdir(parents=True)
        plan.write_text('{"testTargets": [{"selectedTests": []}]}', encoding="utf-8")
        invocations: list[list[str]] = []

        def fake_run_and_tee(argv, _log_path, env=None):
            del env
            invocations.append(list(argv))
            return 0

        with patch("scripts.dev_tools.macos._run_and_tee", side_effect=fake_run_and_tee), \
            patch("scripts.dev_tools.macos._validate_localization_compiler_keys"):
            result = _run_macos_tests_inner(
                self.tmp_path,
                project,
                "AreaMatrix",
                "AreaMatrixTests.xctest",
                "platform=macOS,arch=arm64",
                self.tmp_path,
                self.tmp_path / "test.log",
                self.tmp_path / "build.log",
                None,
                [],
                build_for_testing=True,
                test_plan="AreaMatrix-Unit",
            )

        self.assertEqual(result, 0)
        self.assertEqual(len(invocations), 1)
        self.assertEqual(invocations[0][0:2], ["xcodebuild", "build-for-testing"])
        self.assertIn("-testPlan", invocations[0])
        self.assertEqual(invocations[0][invocations[0].index("-testPlan") + 1], "AreaMatrix-Unit")
        self.assertNotIn("test-without-building", invocations[0])

    def test_build_for_testing_forwards_code_coverage_instrumentation(self) -> None:
        args = _build_for_testing_base_args(
            self.tmp_path / "AreaMatrix.xcodeproj",
            "AreaMatrix",
            "platform=macOS,arch=arm64",
            self.tmp_path / "DerivedData",
            enable_code_coverage=True,
        )

        self.assertIn("-enableCodeCoverage", args)
        self.assertEqual(args[args.index("-enableCodeCoverage") + 1], "YES")

    def test_test_without_building_forwards_plan_without_building(self) -> None:
        project = self.tmp_path / "AreaMatrix.xcodeproj"
        project.mkdir()
        plan = self.tmp_path / "apps/macos/AreaMatrix-Unit.xctestplan"
        plan.parent.mkdir(parents=True)
        plan.write_text('{"testTargets": [{"selectedTests": []}]}', encoding="utf-8")
        invocations: list[list[str]] = []

        def fake_run_and_tee(argv, _log_path, env=None):
            del env
            invocations.append(list(argv))
            return 0

        with patch("scripts.dev_tools.macos._run_and_tee", side_effect=fake_run_and_tee), \
            patch("scripts.dev_tools.macos._validate_localization_compiler_keys"):
            result = _run_macos_tests_inner(
                self.tmp_path,
                project,
                "AreaMatrix",
                "AreaMatrixTests.xctest",
                "platform=macOS,arch=arm64",
                self.tmp_path,
                self.tmp_path / "test.log",
                self.tmp_path / "build.log",
                None,
                [],
                test_without_building=True,
                test_plan="AreaMatrix-Unit",
            )

        self.assertEqual(result, 0)
        self.assertEqual(invocations[0][0:2], ["xcodebuild", "test-without-building"])
        self.assertIn("-testPlan", invocations[0])
        self.assertEqual(invocations[0][invocations[0].index("-testPlan") + 1], "AreaMatrix-Unit")

    def test_code_coverage_flag_is_explicit(self) -> None:
        args = _test_base_args(
            self.tmp_path / "AreaMatrix.xcodeproj",
            "AreaMatrix",
            "platform=macOS,arch=arm64",
            self.tmp_path / "DerivedData",
            "TestResults.xcresult",
            [],
            enable_code_coverage=True,
        )

        self.assertIn("-enableCodeCoverage", args)
        self.assertEqual(args[args.index("-enableCodeCoverage") + 1], "YES")

    def test_swift_coverage_gate_uses_weighted_watcher_and_bridge_coverage(self) -> None:
        source_root = self.tmp_path / "apps/macos/AreaMatrix"
        watcher_files = [
            "PlatformServices/InFlightFileChangeTracker.swift",
            "PlatformServices/MainExternalCreatedFileWatcher.swift",
            "PlatformServices/MainExternalSyncEvents.swift",
        ]
        bridge_files = ["Bridge/CoreBridge.swift", "Bridge/CoreFileListing.swift"]
        for relative in [*watcher_files, *bridge_files]:
            path = source_root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("// fixture\n", encoding="utf-8")
        files = [
            self.coverage_file(source_root / watcher_files[0], 6, 10),
            self.coverage_file(source_root / watcher_files[1], 30, 50),
            self.coverage_file(source_root / watcher_files[2], 24, 40),
            self.coverage_file(source_root / bridge_files[0], 1, 1),
            self.coverage_file(source_root / bridge_files[1], 49, 99),
            self.coverage_file(source_root / "Bridge/UniFFI/area_matrix.swift", 0, 1000),
        ]

        result = _evaluate_swift_coverage_report(
            self.tmp_path,
            {"targets": [{"name": "AreaMatrix.app", "files": files}]},
        )

        self.assertEqual(result, 0)

    def test_swift_coverage_gate_rejects_missing_inventory(self) -> None:
        source_root = self.tmp_path / "apps/macos/AreaMatrix"
        for relative in [
            "PlatformServices/InFlightFileChangeTracker.swift",
            "PlatformServices/MainExternalCreatedFileWatcher.swift",
            "PlatformServices/MainExternalSyncEvents.swift",
            "Bridge/CoreBridge.swift",
        ]:
            path = source_root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("// fixture\n", encoding="utf-8")

        with self.assertRaises(ToolError):
            _evaluate_swift_coverage_report(
                self.tmp_path,
                {"targets": [{
                    "name": "AreaMatrix.app",
                    "files": [self.coverage_file(source_root / "Bridge/CoreBridge.swift", 1, 1)],
                }]},
            )

    def test_swift_coverage_gate_allows_declaration_only_bridge_adapter_without_xccov_row(self) -> None:
        source_root = self.tmp_path / "apps/macos/AreaMatrix"
        watcher_files = [
            "PlatformServices/InFlightFileChangeTracker.swift",
            "PlatformServices/MainExternalCreatedFileWatcher.swift",
            "PlatformServices/MainExternalSyncEvents.swift",
        ]
        bridge_files = [
            "Bridge/CoreBridge.swift",
            "Bridge/CoreFileListing.swift",
            "Bridge/CoreBridgeRuntime.swift",
        ]
        for relative in [*watcher_files, *bridge_files]:
            path = source_root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("// fixture\n", encoding="utf-8")
        files = [
            self.coverage_file(source_root / watcher_files[0], 6, 10),
            self.coverage_file(source_root / watcher_files[1], 30, 50),
            self.coverage_file(source_root / watcher_files[2], 24, 40),
            self.coverage_file(source_root / bridge_files[0], 1, 1),
            self.coverage_file(source_root / bridge_files[1], 49, 99),
        ]

        result = _evaluate_swift_coverage_report(
            self.tmp_path,
            {"targets": [{"name": "AreaMatrix.app", "files": files}]},
        )

        self.assertEqual(result, 0)

    def test_sandbox_fallback_passes_when_only_release_launch_is_locally_blocked(self) -> None:
        bundle = self.tmp_path / "AreaMatrixTests.xctest"
        bundle.mkdir()

        with patch("scripts.dev_tools.macos._find_or_build_test_bundle", return_value=bundle), \
            patch("scripts.dev_tools.macos._run_filtered_xctest_bundle", return_value=0), \
            patch("scripts.dev_tools.macos._validate_localization_compiler_keys"), \
            patch("scripts.dev_tools.macos.run_release_app_launch_probe", return_value=RELEASE_APP_LAUNCH_BLOCKED):
            result = _run_sandbox_fallback(
                self.tmp_path,
                self.tmp_path,
                "AreaMatrix",
                "AreaMatrixTests.xctest",
                [],
                self.tmp_path / "build.log",
                ["AreaMatrixTests/AreaMatrixPerfTests"],
            )

        self.assertEqual(result, 0)

    def test_coverage_gate_rejects_direct_xctest_fallback(self) -> None:
        project = self.tmp_path / "AreaMatrix.xcodeproj"
        project.mkdir()
        test_log = self.tmp_path / "xcodebuild-test.log"
        build_log = self.tmp_path / "xcodebuild-build.log"
        result_bundle = self.tmp_path / "TestResults.xcresult"

        def fake_run_and_tee(_argv, log_path, env=None):
            del env
            log_path.write_text(
                "com.apple.testmanagerd.control failed because of a sandbox restriction\n",
                encoding="utf-8",
            )
            return 65

        with patch("scripts.dev_tools.macos._run_and_tee", side_effect=fake_run_and_tee), \
            self.assertRaises(ToolError):
            _run_macos_tests_inner(
                self.tmp_path,
                project,
                "AreaMatrix",
                "AreaMatrixTests.xctest",
                "platform=macOS,arch=arm64",
                self.tmp_path,
                test_log,
                build_log,
                result_bundle,
                [],
                coverage_gate=True,
            )

    def test_sandbox_fallback_fails_real_release_launch_probe_error(self) -> None:
        bundle = self.tmp_path / "AreaMatrixTests.xctest"
        bundle.mkdir()

        with patch("scripts.dev_tools.macos._find_or_build_test_bundle", return_value=bundle), \
            patch("scripts.dev_tools.macos._run_filtered_xctest_bundle", return_value=0), \
            patch("scripts.dev_tools.macos.run_release_app_launch_probe", return_value=42):
            result = _run_sandbox_fallback(
                self.tmp_path,
                self.tmp_path,
                "AreaMatrix",
                "AreaMatrixTests.xctest",
                [],
                self.tmp_path / "build.log",
                ["AreaMatrixTests/AreaMatrixPerfTests"],
            )

        self.assertEqual(result, 42)

    def test_teardown_sandbox_pass_still_runs_release_probe(self) -> None:
        project = self.tmp_path / "AreaMatrix.xcodeproj"
        project.mkdir()
        test_log = self.tmp_path / "xcodebuild-test.log"
        build_log = self.tmp_path / "xcodebuild-build.log"

        def fake_run_and_tee(_argv, log_path, env=None):
            log_path.write_text(
                "\n".join(
                    [
                        "Test Suite 'Selected tests' passed at 2026-05-09.",
                        "Test Suite 'AreaMatrixPerfTests' passed at 2026-05-09.",
                        "Executed 5 tests, with 0 failures (0 unexpected)",
                        "com.apple.testmanagerd.control was invalidated: Sandbox restriction.",
                    ]
                ),
                encoding="utf-8",
            )
            return 75

        with patch("scripts.dev_tools.macos._run_and_tee", side_effect=fake_run_and_tee), \
            patch("scripts.dev_tools.macos._find_test_bundle", return_value=self.tmp_path), \
            patch("scripts.dev_tools.macos._run_filtered_xctest_bundle", return_value=0), \
            patch("scripts.dev_tools.macos._validate_localization_compiler_keys"), \
            patch(
                "scripts.dev_tools.macos.run_release_app_launch_probe",
                return_value=RELEASE_APP_LAUNCH_BLOCKED,
            ) as probe:
            result = _run_macos_tests_inner(
                self.tmp_path,
                project,
                "AreaMatrix",
                "AreaMatrixTests.xctest",
                "platform=macOS,arch=arm64",
                self.tmp_path,
                test_log,
                build_log,
                None,
                ["AreaMatrixTests/AreaMatrixPerfTests"],
            )

        self.assertEqual(result, 0)
        probe.assert_called_once()

    def write_log(self, text: str) -> Path:
        path = self.tmp_path / "xcodebuild-test.log"
        path.write_text(text, encoding="utf-8")
        return path

    @staticmethod
    def coverage_file(path: Path, covered: int, executable: int) -> dict[str, object]:
        return {
            "path": str(path),
            "coveredLines": covered,
            "executableLines": executable,
        }


if __name__ == "__main__":
    unittest.main()
