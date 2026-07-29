"""Regression tests for high-frequency AreaMatrix developer commands."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.dev_tools import checks, developer
from scripts.dev_tools.common import ToolError


class DeveloperWorkflowTest(unittest.TestCase):
    def test_developer_workflow_contract_keeps_cli_swift_and_docs_aligned(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            sources = {
                "scripts/dev_tools/developer.py": 'DEVELOPER_SCENARIOS = ("catalog", "catalog-dark")\n',
                "scripts/dev_tools/cli.py": '\n'.join([
                    'test_sub.add_parser("changed")',
                    'run_sub.add_parser("macos")',
                    'doctor_sub.add_parser("build")',
                ]),
                "apps/macos/AreaMatrix/App/AreaMatrixDeveloperScenario.swift": '\n'.join([
                    'enum AreaMatrixDeveloperScenario: String {',
                    '    case catalog',
                    '    case catalogDark = "catalog-dark"',
                    '}',
                ]),
                "docs/development/build.md": '\n'.join([
                    './dev doctor build',
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
                        'dependencyFile = "$(DERIVED_FILE_DIR)/AreaMatrixCoreSDK.d";',
                        '"$(SRCROOT)/../../.build/core-sdk/current/manifest.json",',
                        '"$(SRCROOT)/../../scripts/dev_tools/core_sdk_artifact.py",',
                        "build core-sdk --dependency-file",
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
