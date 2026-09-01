"""Regression tests for high-frequency AreaMatrix developer commands."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.dev_tools import checks, developer
from scripts.dev_tools.cli import _build_parser
from scripts.dev_tools.common import ToolError


class DeveloperWorkflowTest(unittest.TestCase):
    def test_cli_parser_supports_governance_affected_check_alias(self) -> None:
        args = _build_parser().parse_args(["check", "affected", "--list"])

        self.assertEqual(args.target, "affected")
        self.assertTrue(args.list)

    def test_cli_parser_supports_layered_macos_test_modes_and_plan(self) -> None:
        parser = _build_parser()
        build = parser.parse_args(["test", "macos", "--build-for-testing", "--test-plan", "AreaMatrix-Unit"])
        self.assertTrue(build.build_for_testing)
        self.assertFalse(build.test_without_building)
        self.assertEqual(build.test_plan, "AreaMatrix-Unit")

        run = parser.parse_args(["test", "macos", "--test-without-building", "--test-plan", "AreaMatrix-Integration"])
        self.assertFalse(run.build_for_testing)
        self.assertTrue(run.test_without_building)
        self.assertEqual(run.test_plan, "AreaMatrix-Integration")

        with self.assertRaises(SystemExit):
            parser.parse_args(["test", "macos", "--build-for-testing", "--test-without-building"])

    def test_cli_parser_supports_build_metrics_summary(self) -> None:
        args = _build_parser().parse_args(
            ["metrics", "build", "--limit", "25", "--json", "--strict"]
        )

        self.assertEqual(args.metrics_target, "build")
        self.assertEqual(args.limit, 25)
        self.assertTrue(args.json)
        self.assertTrue(args.strict)

        with self.assertRaises(SystemExit) as error:
            _build_parser().parse_args(["metrics", "build", "--limit", "0"])
        self.assertEqual(error.exception.code, 2)

    def test_developer_workflow_contract_keeps_cli_swift_and_docs_aligned(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            sources = {
                "scripts/dev_tools/developer.py": 'DEVELOPER_SCENARIOS = ("catalog", "catalog-dark")\n',
                "scripts/dev_tools/cli.py": '\n'.join([
                    'test_sub.add_parser("changed")',
                    'run_sub.add_parser("macos")',
                    'doctor_sub.add_parser("build")',
                    'metrics_sub.add_parser("build")',
                ]),
                "apps/macos/AreaMatrix/App/AreaMatrixDeveloperScenario.swift": '\n'.join([
                    'enum AreaMatrixDeveloperScenario: String {',
                    '    case catalog',
                    '    case catalogDark = "catalog-dark"',
                    '}',
                ]),
                "docs/development/build.md": '\n'.join([
                    './dev doctor build',
                    './dev metrics build',
                    './dev run macos --scenario catalog',
                    './dev run macos --scenario catalog-dark',
                ]),
                "docs/development/testing.md": './dev test changed\n',
            }
            for relative, source in sources.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source, encoding="utf-8")
            failures = checks.FailureCollector()

            checks._check_developer_workflow_contract(root, failures)

            self.assertEqual(failures.count, 0)

    def test_swift_scenario_parser_ignores_later_enum_cases(self) -> None:
        source = '\n'.join([
            'enum AreaMatrixDeveloperScenario: String {',
            '    case catalog',
            '    case catalogDark = "catalog-dark"',
            '}',
            'enum AreaMatrixDeveloperSurfaceFeature: String {',
            '    case artificialIntelligence = "AI"',
            '}',
        ])

        self.assertEqual(
            checks._swift_developer_scenario_ids(source),
            ["catalog", "catalog-dark"],
        )

    def test_changed_layers_are_deduplicated_and_ordered(self) -> None:
        layers = developer._changed_test_layers(
            [
                "scripts/dev_tools/developer.py",
                "core/src/lib.rs",
                "apps/macos/AreaMatrix/App/AreaMatrixApp.swift",
                "apps/ios/Package.swift",
                "docs/development/build.md",
                "core/tests/example.rs",
            ]
        )

        self.assertEqual(
            layers,
            [
                "developer-tools",
                "rust-core",
                "macos-client",
                "ios-client",
                "docs-governance",
            ],
        )

    def test_changed_test_list_mode_does_not_execute_gates(self) -> None:
        with (
            patch("scripts.dev_tools.developer.changed_paths", return_value=["core/src/lib.rs"]),
            patch("scripts.dev_tools.developer.run_step") as run_step,
        ):
            self.assertEqual(developer.run_changed_tests(Path("/repo"), list_only=True), 0)

        run_step.assert_not_called()

    def test_changed_rust_gate_uses_validation_lane_lock(self) -> None:
        root = Path("/repo")
        completed = subprocess.CompletedProcess(args=[], returncode=0)
        with (
            patch("scripts.dev_tools.developer.changed_paths", return_value=["core/src/lib.rs"]),
            patch("scripts.dev_tools.developer.cargo_lane_lock") as cargo_lane_lock,
            patch("scripts.dev_tools.developer.run_step", return_value=completed) as run_step,
        ):
            self.assertEqual(developer.run_changed_tests(root), 0)

        cargo_lane_lock.assert_called_once_with(root, lane="validation", operation="changed-tests")
        self.assertEqual(
            run_step.call_args.kwargs["env"],
            {"CARGO_TARGET_DIR": str(root / ".build/cargo/validation")},
        )

    def test_ios_only_change_builds_ios_package_without_macos_tests(self) -> None:
        root = Path("/repo")
        completed = subprocess.CompletedProcess(args=[], returncode=0)
        with (
            patch("scripts.dev_tools.developer.changed_paths", return_value=["apps/ios/Package.swift"]),
            patch("scripts.dev_tools.developer.run_step", return_value=completed) as run_step,
            patch("scripts.dev_tools.developer.run_localization_check") as localization,
            patch("scripts.dev_tools.developer.run_macos_tests") as macos_tests,
        ):
            self.assertEqual(developer.run_changed_tests(root), 0)

        run_step.assert_called_once_with(
            ["swift", "build", "--package-path", "apps/ios"],
            cwd=root,
            check=False,
        )
        localization.assert_not_called()
        macos_tests.assert_not_called()

    def test_macos_change_tests_modules_before_xctest(self) -> None:
        root = Path("/repo")
        completed = subprocess.CompletedProcess(args=[], returncode=0)
        with (
            patch(
                "scripts.dev_tools.developer.changed_paths",
                return_value=["apps/macos/Packages/AreaMatrixModules/Package.swift"],
            ),
            patch("scripts.dev_tools.developer.run_step", return_value=completed) as run_step,
            patch("scripts.dev_tools.developer.run_localization_check", return_value=0),
            patch("scripts.dev_tools.developer.run_macos_tests", return_value=0) as macos_tests,
        ):
            self.assertEqual(developer.run_changed_tests(root), 0)

        run_step.assert_called_once_with(
            ["swift", "test", "--package-path", "apps/macos/Packages/AreaMatrixModules"],
            cwd=root,
            check=False,
        )
        macos_tests.assert_called_once_with(root)

    def test_build_doctor_accepts_isolated_lanes_and_incremental_xcode_phase(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / ".cargo").mkdir()
            (root / ".cargo/config.toml").write_text(
                '[build]\ntarget-dir = ".build/cargo/validation"\n', encoding="utf-8"
            )
            project = root / "apps/macos/AreaMatrix.xcodeproj/project.pbxproj"
            project.parent.mkdir(parents=True)
            project.write_text(
                "\n".join(
                    [
                        "alwaysOutOfDate = 0;",
                        "basedOnDependencyAnalysis = 1;",
                        'dependencyFile = "$(DERIVED_FILE_DIR)/AreaMatrixCoreSDK.d";',
                        '"$(SRCROOT)/../../.build/core-sdk/current/manifest.json",',
                        '"$(SRCROOT)/../../scripts/dev_tools/core_sdk_artifact.py",',
                        "build core-sdk --dependency-file",
                        "build core-sdk --verify-only --dependency-file",
                    ]
                ),
                encoding="utf-8",
            )
            locks = root / ".build/locks/cargo"
            locks.mkdir(parents=True)
            (locks / "sdk.lock").write_text(json.dumps({"lane": "sdk"}), encoding="utf-8")

            self.assertEqual(developer.run_build_doctor(root), 0)

    def test_unknown_scenario_fails_before_build(self) -> None:
        with self.assertRaisesRegex(ToolError, "unknown developer scenario"):
            developer.run_macos_developer_scenario(Path("/repo"), scenario="unknown")

    def test_all_settings_pages_are_available_as_cli_scenarios(self) -> None:
        self.assertEqual(
            tuple(scenario for scenario in developer.DEVELOPER_SCENARIOS if scenario.startswith("settings-")),
            (
                "settings-about",
                "settings-advanced",
                "settings-classifier",
                "settings-general",
                "settings-integrations",
                "settings-language",
                "settings-platform-differences",
                "settings-repository",
            ),
        )

    def test_all_onboarding_pages_are_available_as_cli_scenarios(self) -> None:
        self.assertEqual(
            tuple(
                scenario
                for scenario in developer.DEVELOPER_SCENARIOS
                if scenario == "onboarding" or scenario.startswith("onboarding-")
            ),
            (
                "onboarding",
                "onboarding-confirm",
                "onboarding-database-repair",
                "onboarding-done",
                "onboarding-failed",
                "onboarding-initializing",
                "onboarding-recovery",
                "onboarding-validate-path",
            ),
        )

    def test_all_search_pages_are_available_as_cli_scenarios(self) -> None:
        self.assertEqual(
            tuple(scenario for scenario in developer.DEVELOPER_SCENARIOS if scenario.startswith("search-")),
            (
                "search-query-error",
                "search-saved-search",
                "search-empty",
                "search-index-status",
                "search-semantic-results",
                "search-smart-list",
            ),
        )

    def test_all_file_action_pages_are_available_as_cli_scenarios(self) -> None:
        self.assertEqual(
            tuple(scenario for scenario in developer.DEVELOPER_SCENARIOS if scenario.startswith("file-actions-")),
            (
                "file-actions-batch-add-tags",
                "file-actions-batch-change-category",
                "file-actions-batch-delete",
                "file-actions-batch-rename",
                "file-actions-change-category",
                "file-actions-classifier-impact",
                "file-actions-delete",
                "file-actions-rename",
                "file-actions-replace",
                "file-actions-tag-suggestions",
                "file-actions-undo-history",
            ),
        )

    def test_all_ai_pages_are_available_as_cli_scenarios(self) -> None:
        self.assertEqual(
            tuple(
                scenario
                for scenario in developer.DEVELOPER_SCENARIOS
                if scenario.startswith("ai-") and scenario != "ai-unavailable"
            ),
            (
                "ai-call-log",
                "ai-classification-suggestion",
                "ai-privacy-rules",
                "ai-settings",
                "ai-summary-editor",
                "ai-tag-suggestions",
                "ai-local-model-status",
                "ai-remote-model-config",
            ),
        )

    def test_all_import_pages_are_available_as_cli_scenarios(self) -> None:
        self.assertEqual(
            tuple(
                scenario
                for scenario in developer.DEVELOPER_SCENARIOS
                if scenario.startswith("import-") and scenario != "import-conflict"
            ),
            (
                "import-entry",
                "import-folder-preview",
                "import-progress",
                "import-result",
            ),
        )

    def test_command_palette_and_detail_pages_are_available_as_cli_scenarios(self) -> None:
        self.assertEqual(
            developer.DEVELOPER_SCENARIOS[2:7],
            (
                "command-palette",
                "detail-log",
                "detail-note",
                "detail-pane",
                "detail-multi-selection",
            ),
        )

    def test_diagnostics_pages_are_available_as_cli_scenarios(self) -> None:
        self.assertEqual(
            tuple(scenario for scenario in developer.DEVELOPER_SCENARIOS if scenario.startswith("diagnostics-")),
            (
                "diagnostics-console",
                "diagnostics-package-preview",
                "diagnostics-settings",
            ),
        )

    def test_main_list_page_is_available_as_cli_scenario(self) -> None:
        self.assertIn("main-repository-content", developer.DEVELOPER_SCENARIOS)

    def test_sync_conflict_pages_are_available_as_cli_scenarios(self) -> None:
        self.assertEqual(
            tuple(
                scenario for scenario in developer.DEVELOPER_SCENARIOS if scenario.startswith("sync-conflicts-")
            ),
            (
                "sync-conflicts-icloud-list",
                "sync-conflicts-icloud-minimal",
                "sync-conflicts-entry",
                "sync-conflicts-replace-confirmation",
                "sync-conflicts-review",
            ),
        )

    def test_scenario_axes_are_forwarded_to_debug_process(self) -> None:
        root = Path("/repo")
        completed = subprocess.CompletedProcess(args=[], returncode=0)
        with (
            patch.object(Path, "is_file", return_value=True),
            patch("scripts.dev_tools.developer.subprocess.run", return_value=completed) as run,
        ):
            result = developer.run_macos_developer_scenario(
                root,
                scenario="sync-conflict",
                theme="dark",
                locale="zh-Hans",
                viewport="compact",
                no_build=True,
            )

        self.assertEqual(result, 0)
        environment = run.call_args.kwargs["env"]
        self.assertEqual(environment["AREAMATRIX_SCENARIO"], "sync-conflict")
        self.assertEqual(environment["AREAMATRIX_SCENARIO_THEME"], "dark")
        self.assertEqual(environment["AREAMATRIX_SCENARIO_LOCALE"], "zh-Hans")
        self.assertEqual(environment["AREAMATRIX_SCENARIO_VIEWPORT"], "compact")

    def test_legacy_dark_scenario_alias_preserves_compatibility(self) -> None:
        root = Path("/repo")
        completed = subprocess.CompletedProcess(args=[], returncode=0)
        with (
            patch.object(Path, "is_file", return_value=True),
            patch("scripts.dev_tools.developer.subprocess.run", return_value=completed) as run,
        ):
            result = developer.run_macos_developer_scenario(
                root,
                scenario="ui-catalog-dark",
                no_build=True,
            )

        self.assertEqual(result, 0)
        environment = run.call_args.kwargs["env"]
        self.assertEqual(environment["AREAMATRIX_SCENARIO"], "ui-catalog")
        self.assertEqual(environment["AREAMATRIX_SCENARIO_THEME"], "dark")

    def test_foreground_scenario_stops_cleanly_on_keyboard_interrupt(self) -> None:
        root = Path("/repo")
        executable = root / ".build/derived-data/macos-run/Build/Products/Debug/AreaMatrix.app/Contents/MacOS/AreaMatrix"
        with (
            patch.object(Path, "is_file", return_value=True),
            patch("scripts.dev_tools.developer.subprocess.run", side_effect=KeyboardInterrupt),
        ):
            result = developer.run_macos_developer_scenario(
                root,
                scenario="ui-catalog",
                no_build=True,
            )

        self.assertEqual(result, 130)


if __name__ == "__main__":
    unittest.main()
