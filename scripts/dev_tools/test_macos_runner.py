"""Regression tests for the macOS XCTest sandbox fallback gate."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.dev_tools.macos import (
    STAGE1_APP_LAUNCH_BLOCKED,
    _codex_local_xcode_system_content_blocked,
    _handle_stage1_app_launch_probe_result,
    _run_sandbox_fallback,
    _run_macos_tests_inner,
    _xcodebuild_tests_passed_before_sandbox_teardown,
    _xcode_system_content_failure,
)
from scripts.dev_tools.macos_stage1_probe import (
    _direct_launch_probe_blocked,
    _launchservices_probe_blocked,
)


class MacOSTestRunnerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp.name)

    def tearDown(self) -> None:
        self.tmp.cleanup()

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

    def test_xcode_system_content_block_keeps_codex_local_validation_green(self) -> None:
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

        self.assertEqual(result, 0)

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

    def test_stage1_launch_probe_block_keeps_local_validation_green(self) -> None:
        self.assertEqual(_handle_stage1_app_launch_probe_result(STAGE1_APP_LAUNCH_BLOCKED), 0)

    def test_stage1_launch_probe_keeps_real_probe_failure_red(self) -> None:
        self.assertEqual(_handle_stage1_app_launch_probe_result(42), 42)

    def test_sandbox_fallback_passes_when_only_release_launch_is_locally_blocked(self) -> None:
        bundle = self.tmp_path / "AreaMatrixTests.xctest"
        bundle.mkdir()

        with patch("scripts.dev_tools.macos._find_or_build_test_bundle", return_value=bundle), \
            patch("scripts.dev_tools.macos._run_filtered_xctest_bundle", return_value=0), \
            patch("scripts.dev_tools.macos.run_stage1_app_launch_probe", return_value=STAGE1_APP_LAUNCH_BLOCKED):
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

    def test_sandbox_fallback_fails_real_release_launch_probe_error(self) -> None:
        bundle = self.tmp_path / "AreaMatrixTests.xctest"
        bundle.mkdir()

        with patch("scripts.dev_tools.macos._find_or_build_test_bundle", return_value=bundle), \
            patch("scripts.dev_tools.macos._run_filtered_xctest_bundle", return_value=0), \
            patch("scripts.dev_tools.macos.run_stage1_app_launch_probe", return_value=42):
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

    def test_teardown_sandbox_pass_still_runs_stage1_release_probe(self) -> None:
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
            patch(
                "scripts.dev_tools.macos.run_stage1_app_launch_probe",
                return_value=STAGE1_APP_LAUNCH_BLOCKED,
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


if __name__ == "__main__":
    unittest.main()
