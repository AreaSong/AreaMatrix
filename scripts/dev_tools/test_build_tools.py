"""Regression tests for developer build helpers."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.dev_tools import build, checks
from scripts.task_loop.runner import RuntimeConfig, TaskLoopRunner


class BuildToolsTest(unittest.TestCase):
    def test_locked_uniffi_version_reads_core_lockfile(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            core_dir = Path(tmp)
            (core_dir / "Cargo.lock").write_text(
                "\n".join(
                    [
                        "[[package]]",
                        'name = "other"',
                        'version = "1.0.0"',
                        "",
                        "[[package]]",
                        'name = "uniffi"',
                        'version = "0.28.3"',
                    ]
                ),
                encoding="utf-8",
            )

            self.assertEqual(build._locked_uniffi_version(core_dir), "0.28.3")

    def test_uniffi_command_prefers_configured_binary(self) -> None:
        with patch.dict("os.environ", {"UNIFFI_BINDGEN": "/tmp/custom-uniffi-bindgen"}):
            self.assertEqual(
                build._uniffi_bindgen_command(Path("/tmp/core")),
                ["/tmp/custom-uniffi-bindgen"],
            )

    def test_wrapper_crate_calls_uniffi_cli_entrypoint(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wrapper_dir = Path(tmp) / "wrapper"
            uniffi_source = Path(tmp) / "uniffi-0.28.3"

            build._write_uniffi_wrapper_crate(wrapper_dir, uniffi_source)

            self.assertIn('features = ["cli"]', (wrapper_dir / "Cargo.toml").read_text(encoding="utf-8"))
            self.assertIn("uniffi_bindgen_main", (wrapper_dir / "src/main.rs").read_text(encoding="utf-8"))

    def test_root_udl_uses_synthetic_bindgen_crate(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            core_dir = Path(tmp) / "core"
            core_dir.mkdir()
            (core_dir / "Cargo.toml").write_text(
                "\n".join(
                    [
                        "[package]",
                        'name = "area_matrix_core"',
                        'version = "0.1.0"',
                    ]
                ),
                encoding="utf-8",
            )
            udl = core_dir / "area_matrix.udl"
            udl.write_text("namespace area_matrix {}\n", encoding="utf-8")
            tool_root = Path(tmp) / "uniffi-tool"

            with patch.dict("os.environ", {"AREAMATRIX_UNIFFI_BINDGEN_TOOL_ROOT": str(tool_root)}):
                bindgen_udl = build._prepare_udl_bindgen_crate(core_dir)

            self.assertEqual(bindgen_udl, tool_root / "udl-crate/src/area_matrix.udl")
            self.assertTrue(bindgen_udl.is_symlink())
            self.assertEqual(bindgen_udl.readlink(), udl)
            manifest = (tool_root / "udl-crate/Cargo.toml").read_text(encoding="utf-8")
            self.assertIn('name = "area_matrix_core"', manifest)

    def test_check_all_core_build_uses_temp_generated_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "apps/macos/AreaMatrix.xcodeproj").mkdir(parents=True)

            calls: list[Path] = []

            def fake_core_build(_root: Path, *, out_dir: Path) -> int:
                calls.append(out_dir)
                return 7

            with (
                patch.dict("os.environ", {}, clear=True),
                patch("scripts.dev_tools.checks._run_macos_prerequisites_check", return_value=0),
                patch("scripts.dev_tools.checks.run_core_build", fake_core_build),
            ):
                self.assertEqual(checks._run_macos_checks(root), 7)

            self.assertEqual(calls, [Path("/private/tmp/areamatrix-check-all/Bridge/UniFFI")])

    def test_macos_checks_stop_at_prerequisites_before_build(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "apps/macos/AreaMatrix.xcodeproj").mkdir(parents=True)

            with (
                patch("scripts.dev_tools.checks._run_macos_prerequisites_check", return_value=9),
                patch("scripts.dev_tools.checks.run_core_build") as core_build,
                patch("scripts.dev_tools.checks.run_macos_tests") as macos_tests,
            ):
                self.assertEqual(checks._run_macos_checks(root), 9)

            core_build.assert_not_called()
            macos_tests.assert_not_called()

    def test_macos_prerequisites_reports_all_missing_tools(self) -> None:
        completed = type(
            "Completed",
            (),
            {"returncode": 0, "stdout": "aarch64-apple-darwin\n", "stderr": ""},
        )()

        def fake_which(command: str) -> str | None:
            if command == "rustup":
                return "/usr/bin/rustup"
            return None

        with (
            patch("scripts.dev_tools.checks.shutil.which", side_effect=fake_which),
            patch("scripts.dev_tools.checks.subprocess.run", return_value=completed),
            ):
                self.assertEqual(checks._run_macos_prerequisites_check(), 1)

    def test_swift_checks_use_repo_dev_tool_configs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config_dir = root / "scripts/dev_tools"
            config_dir.mkdir(parents=True)
            (config_dir / "swiftformat.conf").write_text("--swiftversion 5.9\n", encoding="utf-8")
            (config_dir / "swiftlint.yml").write_text("disabled_rules: []\n", encoding="utf-8")

            self.assertEqual(
                checks._swiftformat_lint_args(root),
                [
                    "swiftformat",
                    "--lint",
                    ".",
                    "--config",
                    config_dir / "swiftformat.conf",
                    "--exclude",
                    "AreaMatrix/Bridge/Generated,AreaMatrix/Bridge/UniFFI",
                    "--cache",
                    "ignore",
                ],
            )
            self.assertEqual(
                checks._swiftlint_lint_args(root),
                [
                    "swiftlint",
                    "lint",
                    "--strict",
                    "--config",
                    config_dir / "swiftlint.yml",
                    "--force-exclude",
                    ".",
                    "--no-cache",
                ],
            )

    def test_core_build_checks_required_targets_before_bindgen_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            core_dir = root / "core"
            core_dir.mkdir()
            (core_dir / "Cargo.toml").write_text("[package]\nname = \"area_matrix_core\"\n", encoding="utf-8")
            (core_dir / "area_matrix.udl").write_text("namespace area_matrix {}\n", encoding="utf-8")
            (core_dir / "build.rs").write_text("fn main() {}\n", encoding="utf-8")

            calls: list[str] = []

            def require_target(target: str) -> None:
                calls.append(target)
                if target == "x86_64-apple-darwin":
                    raise SystemExit(1)

            with (
                patch("scripts.dev_tools.build.require_command"),
                patch("scripts.dev_tools.build._host_triple", return_value="aarch64-apple-darwin"),
                patch("scripts.dev_tools.build._require_rust_target", side_effect=require_target),
                patch("scripts.dev_tools.build._uniffi_bindgen_command") as bindgen,
            ):
                with self.assertRaises(SystemExit):
                    build.run_core_build(root, out_dir=Path("/tmp/generated"))

            self.assertEqual(calls, ["aarch64-apple-darwin", "x86_64-apple-darwin"])
            bindgen.assert_not_called()

    def test_task_check_path_resolves_phase_task_label(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            task = root / "tasks/prompts/phase-4/4-1-stage2-experience/task-15-c2-03-integration-verify.md"
            task.parent.mkdir(parents=True)
            task.write_text("# 4-1/task-15\n", encoding="utf-8")

            self.assertEqual(checks._task_path(root, "4-1/task-15"), task)

    def test_task_check_maps_c2_03_to_saved_search_tests(self) -> None:
        text = "Core ability C2-03 saved-search-crud"

        self.assertEqual(
            checks._core_task_test_commands(text),
            [
                ["cargo", "test", "--test", "saved_search_contract_api", "--", "--nocapture"],
                ["cargo", "test", "--test", "saved_search_implementation", "--", "--nocapture"],
                ["cargo", "test", "--test", "saved_search_failure_recovery", "--", "--nocapture"],
                ["cargo", "test", "--test", "saved_search_validation", "--", "--nocapture"],
            ],
        )

    def test_task_check_maps_c2_04_to_smart_list_tests(self) -> None:
        text = "Core ability C2-04 smart-lists"

        self.assertEqual(
            checks._core_task_test_commands(text),
            [
                ["cargo", "test", "--test", "smart_list_contract_api", "--", "--nocapture"],
                ["cargo", "test", "--test", "smart_list_implementation", "--", "--nocapture"],
                ["cargo", "test", "--test", "smart_list_failure_recovery", "--", "--nocapture"],
            ],
        )

    def test_task_check_discovers_capability_tests_from_spec_slug(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            spec_dir = root / "docs/core/capability-specs/stage-2-experience"
            tests_dir = root / "core/tests"
            spec_dir.mkdir(parents=True)
            tests_dir.mkdir(parents=True)
            (spec_dir / "C2-05-tag-crud.md").write_text("# C2-05 tag-crud\n", encoding="utf-8")
            for name in [
                "tag_crud_contract_api.rs",
                "tag_crud_implementation.rs",
                "tag_crud_failure_recovery.rs",
            ]:
                (tests_dir / name).write_text("// test\n", encoding="utf-8")

            self.assertEqual(
                checks._core_task_test_commands("Core ability C2-05 tag-crud", root),
                [
                    ["cargo", "test", "--test", "tag_crud_contract_api", "--", "--nocapture"],
                    ["cargo", "test", "--test", "tag_crud_failure_recovery", "--", "--nocapture"],
                    ["cargo", "test", "--test", "tag_crud_implementation", "--", "--nocapture"],
                ],
            )

    def test_core_task_check_fails_when_no_targeted_tests_are_mapped(self) -> None:
        text = "Core ability C4-99 imaginary capability"

        with (
            patch("scripts.dev_tools.checks.require_command"),
            patch.dict("os.environ", {}, clear=True),
            patch("scripts.dev_tools.checks.run_step") as run_step,
        ):
            run_step.return_value.returncode = 0

            self.assertEqual(checks._run_core_task_checks(Path("/tmp/repo"), text), 2)

        self.assertEqual(
            [call.args[0] for call in run_step.call_args_list],
            [
                ["cargo", "fmt", "--all", "--", "--check"],
                ["cargo", "clippy", "--all-targets", "--all-features", "--", "-D", "warnings"],
            ],
        )

    def test_core_task_check_allows_explicit_full_fallback(self) -> None:
        text = "Core ability C4-99 imaginary capability"

        with (
            patch("scripts.dev_tools.checks.require_command"),
            patch.dict("os.environ", {checks.ALLOW_FULL_TASK_FALLBACK_ENV: "1"}, clear=True),
            patch("scripts.dev_tools.checks.run_step") as run_step,
        ):
            run_step.return_value.returncode = 0

            self.assertEqual(checks._run_core_task_checks(Path("/tmp/repo"), text), 0)

        self.assertEqual(
            [call.args[0] for call in run_step.call_args_list],
            [
                ["cargo", "fmt", "--all", "--", "--check"],
                ["cargo", "clippy", "--all-targets", "--all-features", "--", "-D", "warnings"],
                ["cargo", "test", "--workspace"],
            ],
        )

    def test_task_check_detects_stage_closeout_without_core_integration_false_positive(self) -> None:
        core_integration = "# 4-1/task-15: C2-03 integration-verify\n- 阶段：Stage 2 Experience\n"
        stage_closeout = "# 4-1/task-143: stage-2-experience integration verify\n"

        self.assertFalse(checks._is_stage_closeout_task(core_integration))
        self.assertTrue(checks._is_stage_closeout_task(stage_closeout))

    def test_verify_suffix_defers_runner_checkpoint_evidence(self) -> None:
        cfg = RuntimeConfig(root_dir=Path("/tmp/areamatrix"))
        cfg.git_checkpoint = "commit"

        suffix = TaskLoopRunner(cfg).verify_suffix()

        self.assertIn("runner 写入 completed progress 和 Git checkpoint 之前", suffix)
        self.assertIn("progress.json", suffix)
        self.assertIn("git add", suffix)
        self.assertIn("GIT_CHECKPOINT=commit", suffix)
        self.assertIn("runner checkpoint 阶段", suffix)


if __name__ == "__main__":
    unittest.main()
