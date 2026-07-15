"""Regression tests for developer build helpers."""

from __future__ import annotations

import io
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest.mock import patch

from scripts.dev_tools import build, checks
from scripts.dev_tools.common import ToolError
from scripts.dev_tools.wording import audit_wording
from scripts.task_loop import console
from scripts.task_loop.runner import RuntimeConfig, TaskFile, TaskLoopRunner


class BuildToolsTest(unittest.TestCase):
    def _write_enterprise_governance_fixture(self, root: Path, *, dependency_status: str = "deferred") -> None:
        governance = root / "docs/governance"
        governance.mkdir(parents=True)
        rows = "\n".join(f"| {number} Domain | 满足 | evidence |" for number in range(1, 38))
        (governance / "enterprise-workflow-baseline.md").write_text(
            "# Baseline\n\n" + " ".join(f"G{gate}" for gate in range(9)) + "\n" + rows + "\n",
            encoding="utf-8",
        )
        for name in ["project-charter.md", "operations-lifecycle.md"]:
            (governance / name).write_text(f"# {name}\n", encoding="utf-8")
        document_entries = "\n".join(
            f"""  - id: DOC-{index}
    path: docs/governance/{path}
    authority: governance
    owner: "@AreaSong"
    status: accepted
    last_verified: "2026-07-15"
    review_cycle: quarterly
    review_triggers:
      - changed
"""
            for index, path in enumerate(
                ["enterprise-workflow-baseline.md", "project-charter.md", "operations-lifecycle.md"],
                start=1,
            )
        )
        raid_entries = "\n".join(
            f"""  - id: {entry_id}
    type: dependency
    status: {"open" if entry_id == "AM-RISK-001" else dependency_status}
    severity: high
    owner: "@AreaSong"
    mitigation: fail closed
    due: ongoing
    escalation: gate review
    close_evidence: evidence
"""
            for entry_id in ["AM-RISK-001", "AM-DEP-001", "AM-DEP-002", "AM-DEP-003", "AM-DEP-004"]
        )
        (governance / "governance-register.yaml").write_text(
            """schema_version: 1
upstream:
  spec_id: ASW-EWF-001
  version: 1.0.0
  sha256: ce6a779f243f54440ab9a82886a0d8d0c8a601243260fcdb829beed3f04c96f1
  adoption: adapted-complete
raci:
  accountable: "@AreaSong"
  independent_review:
    missing_reviewer_behavior: blocked
documents:
"""
            + document_entries
            + "raid:\n"
            + raid_entries,
            encoding="utf-8",
        )
        (root / ".areaflow").mkdir(parents=True)
        (root / ".areaflow/status.json").write_text(
            '{"compatibility":{"shim_lifecycle_state":"authoring_only_shim",'
            '"blocked_commands":["./task-loop run","promotion apply","write execution"]}}\n',
            encoding="utf-8",
        )
        execution = root / "workflow/versions/v2/execution"
        execution.mkdir(parents=True)
        (execution / "README.md").write_text("blocked\n", encoding="utf-8")
        promotion = root / "workflow/versions/v2/promotion"
        promotion.mkdir(parents=True)
        (promotion / "promotion.yaml").write_text("live_mapping: pending\n", encoding="utf-8")
        (promotion / "approval.yaml").write_text("approved: false\n", encoding="utf-8")

    def _write_macos_governance_membership_fixture(
        self,
        root: Path,
        *,
        include_build_file: bool = True,
        include_source_membership: bool = True,
    ) -> None:
        tests_dir = root / "apps/macos/AreaMatrixTests"
        tests_dir.mkdir(parents=True)
        test_name = "MacOSArchitectureBoundaryGovernanceTests.swift"
        (tests_dir / test_name).write_text("import XCTest\n", encoding="utf-8")
        project_dir = root / "apps/macos/AreaMatrix.xcodeproj"
        project_dir.mkdir(parents=True)
        build_file = (
            "\t\tAAAAAAAAAAAAAAAAAAAAAAAA /* MacOSArchitectureBoundaryGovernanceTests.swift in Sources */ = "
            "{isa = PBXBuildFile; fileRef = BBBBBBBBBBBBBBBBBBBBBBBB "
            "/* MacOSArchitectureBoundaryGovernanceTests.swift */; };\n"
            if include_build_file
            else ""
        )
        source_member = (
            "\t\t\t\tAAAAAAAAAAAAAAAAAAAAAAAA "
            "/* MacOSArchitectureBoundaryGovernanceTests.swift in Sources */,\n"
            if include_source_membership
            else ""
        )
        (project_dir / "project.pbxproj").write_text(
            """// !$*UTF8*$!
{
\tobjects = {
"""
            + build_file
            + """\t\tBBBBBBBBBBBBBBBBBBBBBBBB /* MacOSArchitectureBoundaryGovernanceTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AreaMatrixTests/MacOSArchitectureBoundaryGovernanceTests.swift; sourceTree = SOURCE_ROOT; };
\t\tCCCCCCCCCCCCCCCCCCCCCCCC /* AreaMatrixTests */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildPhases = (
\t\t\t\tDDDDDDDDDDDDDDDDDDDDDDDD /* Sources */,
\t\t\t);
\t\t};
\t\tDDDDDDDDDDDDDDDDDDDDDDDD /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tfiles = (
"""
            + source_member
            + """\t\t\t);
\t\t};
\t};
}
""",
            encoding="utf-8",
        )

    def _write_bindings_fixture(self, root: Path) -> tuple[Path, Path, Path]:
        core_dir = root / "core"
        core_dir.mkdir(parents=True)
        (core_dir / "Cargo.toml").write_text(
            '[package]\nname = "area_matrix_core"\nversion = "0.1.0"\n',
            encoding="utf-8",
        )
        udl = core_dir / "area_matrix.udl"
        udl.write_text("namespace area_matrix {}\n", encoding="utf-8")
        bindgen_library = core_dir / "target/aarch64-apple-darwin/release/libarea_matrix_core.dylib"
        bindgen_library.parent.mkdir(parents=True)
        bindgen_library.write_bytes(b"host dylib")
        tracked_dir = root / build.DEFAULT_TRACKED_BINDINGS_DIR
        tracked_dir.mkdir(parents=True)
        return udl, bindgen_library, tracked_dir

    @staticmethod
    def _fake_bindgen_run(argv: list[str | Path], **_: object) -> object:
        args = [str(value) for value in argv]
        out_dir = Path(args[args.index("--out-dir") + 1])
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "area_matrix.swift").write_bytes(b"swift binding\n")
        (out_dir / "area_matrixFFI.h").write_bytes(b"ffi header\n")
        (out_dir / "area_matrixFFI.modulemap").write_bytes(b"module map\n")
        return type("Completed", (), {"returncode": 0})()

    def test_locked_uniffi_bindgen_version_reads_core_lockfile(self) -> None:
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

            self.assertEqual(build._locked_uniffi_bindgen_version(core_dir), "0.28.3")

    def test_uniffi_command_prefers_configured_binary(self) -> None:
        with patch.dict("os.environ", {"UNIFFI_BINDGEN": "/tmp/custom-uniffi-bindgen"}):
            self.assertEqual(
                build._uniffi_bindgen_command(Path("/tmp/core")),
                ["/tmp/custom-uniffi-bindgen"],
            )

    def test_uniffi_command_uses_locked_fallback_instead_of_arbitrary_path_binary(self) -> None:
        with (
            patch.dict("os.environ", {}, clear=True),
            patch("scripts.dev_tools.build.shutil.which", return_value="/tmp/unpinned-uniffi-bindgen"),
            patch("scripts.dev_tools.build._build_cached_uniffi_bindgen", return_value=["/tmp/locked-bindgen"]),
        ):
            self.assertEqual(build._uniffi_bindgen_command(Path("/tmp/core")), ["/tmp/locked-bindgen"])

    def test_wrapper_crate_calls_uniffi_cli_entrypoint(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wrapper_dir = Path(tmp) / "wrapper"
            uniffi_source = Path(tmp) / "uniffi-0.28.3"

            build._write_uniffi_wrapper_crate(wrapper_dir, uniffi_source)

            self.assertIn(
                f'uniffi_bindgen = {{ path = "{uniffi_source}" }}',
                (wrapper_dir / "Cargo.toml").read_text(encoding="utf-8"),
            )
            self.assertIn("uniffi_bindgen::generate_bindings", (wrapper_dir / "src/main.rs").read_text(encoding="utf-8"))

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

    def test_bindings_update_passes_host_dylib_and_writes_tracked_artifact_names(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            udl, bindgen_library, tracked_dir = self._write_bindings_fixture(root)
            commands: list[list[str]] = []

            def fake_run(argv: list[str | Path], **kwargs: object) -> object:
                commands.append([str(value) for value in argv])
                return self._fake_bindgen_run(argv, **kwargs)

            with (
                patch("scripts.dev_tools.build._host_triple", return_value="aarch64-apple-darwin"),
                patch("scripts.dev_tools.build._uniffi_bindgen_command", return_value=["uniffi-bindgen"]),
                patch("scripts.dev_tools.build._bindgen_udl_path", return_value=udl),
                patch("scripts.dev_tools.build.run_step", side_effect=fake_run),
            ):
                result = build.run_bindings_update(root, udl, tracked_dir)

            self.assertEqual(result, 0)
            self.assertEqual(len(commands), 1)
            self.assertIn("--lib-file", commands[0])
            actual_library = Path(commands[0][commands[0].index("--lib-file") + 1])
            self.assertEqual(actual_library.resolve(), bindgen_library.resolve())
            self.assertEqual((tracked_dir / "area_matrix.swift").read_bytes(), b"swift binding\n")
            self.assertEqual((tracked_dir / "area_matrixFFI.h").read_bytes(), b"ffi header\n")
            self.assertEqual((tracked_dir / "module.modulemap").read_bytes(), b"module map\n")
            self.assertFalse((tracked_dir / "area_matrixFFI.modulemap").exists())

    def test_binding_artifact_normalization_removes_trailing_whitespace(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            generated_dir = Path(tmp)
            for generated_name, _ in build.BINDING_ARTIFACTS:
                (generated_dir / generated_name).write_text("first  \nsecond\t\n\n", encoding="utf-8")

            build._normalize_binding_artifacts(generated_dir)

            for generated_name, _ in build.BINDING_ARTIFACTS:
                self.assertEqual((generated_dir / generated_name).read_text(encoding="utf-8"), "first\nsecond\n")

    def test_bindings_verify_passes_when_tracked_artifacts_match(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            udl, _, tracked_dir = self._write_bindings_fixture(root)
            (tracked_dir / "area_matrix.swift").write_bytes(b"swift binding\n")
            (tracked_dir / "area_matrixFFI.h").write_bytes(b"ffi header\n")
            (tracked_dir / "module.modulemap").write_bytes(b"module map\n")

            with (
                patch("scripts.dev_tools.build._host_triple", return_value="aarch64-apple-darwin"),
                patch("scripts.dev_tools.build._uniffi_bindgen_command", return_value=["uniffi-bindgen"]),
                patch("scripts.dev_tools.build._bindgen_udl_path", return_value=udl),
                patch("scripts.dev_tools.build.run_step", side_effect=self._fake_bindgen_run),
            ):
                self.assertEqual(build.run_bindings_verify(root), 0)

    def test_bindings_verify_reports_drift_without_writing_tracked_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            udl, _, tracked_dir = self._write_bindings_fixture(root)
            tracked_swift = tracked_dir / "area_matrix.swift"
            tracked_swift.write_bytes(b"stale swift binding\n")
            (tracked_dir / "area_matrixFFI.h").write_bytes(b"ffi header\n")
            (tracked_dir / "module.modulemap").write_bytes(b"module map\n")

            with (
                patch("scripts.dev_tools.build._host_triple", return_value="aarch64-apple-darwin"),
                patch("scripts.dev_tools.build._uniffi_bindgen_command", return_value=["uniffi-bindgen"]),
                patch("scripts.dev_tools.build._bindgen_udl_path", return_value=udl),
                patch("scripts.dev_tools.build.run_step", side_effect=self._fake_bindgen_run),
                redirect_stderr(io.StringIO()),
            ):
                self.assertEqual(build.run_bindings_verify(root), 1)

            self.assertEqual(tracked_swift.read_bytes(), b"stale swift binding\n")

    def test_bindings_verify_requires_host_dylib_from_core_build(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._write_bindings_fixture(root)
            bindgen_library = root / "core/target/aarch64-apple-darwin/release/libarea_matrix_core.dylib"
            bindgen_library.unlink()

            with (
                patch("scripts.dev_tools.build._host_triple", return_value="aarch64-apple-darwin"),
                patch("scripts.dev_tools.build._uniffi_bindgen_command", return_value=["uniffi-bindgen"]),
                patch("scripts.dev_tools.build._bindgen_udl_path", side_effect=lambda path, _: path),
                self.assertRaisesRegex(ToolError, "Run `./dev build core` first"),
            ):
                build.run_bindings_verify(root)

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

    def test_macos_checks_fail_when_source_directory_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, redirect_stderr(io.StringIO()):
            self.assertEqual(checks._run_macos_checks(Path(tmp)), 1)

    def test_macos_checks_fail_when_xcode_project_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, redirect_stderr(io.StringIO()):
            root = Path(tmp)
            (root / "apps/macos").mkdir(parents=True)

            self.assertEqual(checks._run_macos_checks(root), 1)

    def test_macos_governance_membership_accepts_test_target_source(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._write_macos_governance_membership_fixture(root)
            failures = checks.FailureCollector()

            checks._check_macos_governance_test_membership(root, failures)

            self.assertEqual(failures.count, 0)

    def test_macos_governance_membership_rejects_file_reference_without_build_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, redirect_stderr(io.StringIO()):
            root = Path(tmp)
            self._write_macos_governance_membership_fixture(
                root,
                include_build_file=False,
                include_source_membership=False,
            )
            failures = checks.FailureCollector()

            checks._check_macos_governance_test_membership(root, failures)

            self.assertEqual(failures.count, 1)

    def test_macos_governance_membership_rejects_missing_test_sources_entry(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, redirect_stderr(io.StringIO()):
            root = Path(tmp)
            self._write_macos_governance_membership_fixture(root, include_source_membership=False)
            failures = checks.FailureCollector()

            checks._check_macos_governance_test_membership(root, failures)

            self.assertEqual(failures.count, 1)

    def test_enterprise_governance_baseline_accepts_complete_fixture(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._write_enterprise_governance_fixture(root)
            failures = checks.FailureCollector()

            checks._check_enterprise_governance_baseline(root, failures)

            self.assertEqual(failures.count, 0)

    def test_enterprise_governance_baseline_rejects_closed_external_dependency(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, redirect_stderr(io.StringIO()):
            root = Path(tmp)
            self._write_enterprise_governance_fixture(root, dependency_status="closed")
            failures = checks.FailureCollector()

            checks._check_enterprise_governance_baseline(root, failures)

            self.assertGreaterEqual(failures.count, 4)

    def test_ai_runtime_environment_contract_matches_repository(self) -> None:
        failures = checks.FailureCollector()

        checks._check_ai_runtime_environment_contract(Path(__file__).resolve().parents[2], failures)

        self.assertEqual(failures.count, 0)

    def test_ai_runtime_environment_contract_rejects_unknown_core_key(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, redirect_stderr(io.StringIO()):
            root = Path(tmp)
            core_src = root / "core/src"
            core_src.mkdir(parents=True)
            (core_src / "runtime.rs").write_text(
                'const UNKNOWN: &str = "AREAMATRIX_UNKNOWN_RUNTIME";\n',
                encoding="utf-8",
            )
            swift_src = root / "apps/macos/AreaMatrix"
            swift_src.mkdir(parents=True)
            failures = checks.FailureCollector()

            checks._check_ai_runtime_environment_contract(root, failures)

            self.assertEqual(failures.count, 1)

    def test_docs_check_accepts_reachable_pages_and_ignores_code_fences(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "docs").mkdir()
            (root / "README.md").write_text("[Docs](docs/README.md)\n", encoding="utf-8")
            (root / "README.zh-CN.md").write_text("[文档](docs/README.md)\n", encoding="utf-8")
            (root / "docs/README.md").write_text(
                "[Page](page.md)\n\n```markdown\n[Example](missing.md)\n```\n",
                encoding="utf-8",
            )
            (root / "docs/page.md").write_text("# Page\n", encoding="utf-8")

            self.assertEqual(checks.run_docs_check(root), 0)

    def test_docs_check_rejects_broken_and_unreachable_pages(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, redirect_stderr(io.StringIO()):
            root = Path(tmp)
            (root / "docs").mkdir()
            (root / "README.md").write_text("[Docs](docs/README.md)\n", encoding="utf-8")
            (root / "README.zh-CN.md").write_text("[文档](docs/README.md)\n", encoding="utf-8")
            (root / "docs/README.md").write_text("[Missing](missing.md)\n", encoding="utf-8")
            (root / "docs/orphan.md").write_text("# Orphan\n", encoding="utf-8")

            self.assertEqual(checks.run_docs_check(root), 1)

    def test_docs_check_rejects_internal_runtime_details_in_root_readme(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, redirect_stderr(io.StringIO()):
            root = Path(tmp)
            (root / "docs").mkdir()
            (root / "README.md").write_text("[Docs](docs/README.md)\n`.codex/runtime/`\n", encoding="utf-8")
            (root / "README.zh-CN.md").write_text("[文档](docs/README.md)\n", encoding="utf-8")
            (root / "docs/README.md").write_text("# Docs\n", encoding="utf-8")

            self.assertEqual(checks.run_docs_check(root), 1)

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
                    "AreaMatrix/Bridge/Generated,AreaMatrix/Bridge/UniFFI,DerivedData",
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

    def test_quality_check_passes_minimal_owner_fixture(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            files = {
                "docs/development/coding-standards.md": "\n".join(
                    [
                        "# 编码规范",
                        "注释解释 why",
                        "单函数 ≤ 50 行",
                        "嵌套 ≤ 3 层",
                        "./dev check quality",
                    ]
                ),
                "CODE_REVIEW.md": "# Review\n\n阻断项\n\n数据流、控制流、错误流\n",
                "workflow/versions/v1-mvp/execution/_shared/engineering-quality-rules.md": "注释只解释 WHY\nmock-only\n",
                "scripts/dev_tools/swiftlint.yml": "function_body_length: 50\nfile_length: 500\n",
                "scripts/dev_tools/swiftformat.conf": "--maxwidth 120\n",
                "core/AGENTS.md": "Core 保持平台无关\n",
                "apps/macos/AGENTS.md": "SwiftUI 视图只做展示\nCoreBridge\n",
                "docs/architecture/data-model.md": "# Data model\n",
                "docs/architecture/migration.md": "migration rollback 回滚\n",
                "docs/development/release.md": (
                    "Developer ID notarization 公证\n./dev release status\n./dev release evidence-audit\n"
                ),
                "scripts/dev_tools/release.py": "# release helper\n",
                "scripts/dev_tools/release_status.py": (
                    "closes_residual\nrelease_gate\nresidual_evidence_gate\nrelease_evidence_audit\n"
                    "any residual is closed\n"
                ),
                ".codex/skills-src/README.md": "areamatrix-residual-ledger\nareamatrix-codex-os\n",
                ".codex/references/index.md": "./dev check quality\n./dev check wording\n",
                ".codex/references/codex-workflow-and-tools.md": "已有 9 个 AreaMatrix skills\n",
                "tasks/backlog/codex-operating-layer-boundary-regression.md": "现有 9 个 repo-local skills\n",
                "docs/development/ci-governance.md": "./dev check quality\n./dev check wording\n",
                ".github/workflows/governance-ci.yml": "./dev check quality\n./dev check wording\n",
                ".codex/skills-src/areamatrix-validation-driver/SKILL.md": "macOS app\n",
                ".codex/skills-src/areamatrix-doc-sync/SKILL.md": "Core API and UDL\n",
                ".codex/skills-src/areamatrix-file-safety/SKILL.md": "DB metadata and migrations\n",
                ".codex/skills-src/areamatrix-enterprise-governance/SKILL.md": "CI workflows\n",
                ".codex/skills-src/areamatrix-residual-ledger/SKILL.md": "release blockers\n",
                ".codex/skills-src/areamatrix-workflow-planning/SKILL.md": "v* workflow\n",
                ".codex/skills-src/areamatrix-git-checkpoint/SKILL.md": "checkpoint\n",
                ".codex/skills-src/areamatrix-codex-os/SKILL.md": "Codex Operating System\n",
            }
            for relative, text in files.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")

            self.assertEqual(checks.run_quality_check(root), 0)

    def test_quality_check_rejects_stale_skill_count(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            required = {
                "docs/development/coding-standards.md": "注释解释 why\n单函数 ≤ 50 行\n嵌套 ≤ 3 层\n./dev check quality\n",
                "CODE_REVIEW.md": "阻断项\n数据流、控制流、错误流\n",
                "workflow/versions/v1-mvp/execution/_shared/engineering-quality-rules.md": "注释只解释 WHY\nmock-only\n",
                "scripts/dev_tools/swiftlint.yml": "function_body_length: 50\nfile_length: 500\n",
                "scripts/dev_tools/swiftformat.conf": "--maxwidth 120\n",
                "core/AGENTS.md": "平台无关\n",
                "apps/macos/AGENTS.md": "SwiftUI 视图只做展示\nCoreBridge\n",
                "docs/architecture/data-model.md": "",
                "docs/architecture/migration.md": "rollback\n",
                "docs/development/release.md": "notarization\n./dev release status\n./dev release evidence-audit\n",
                "scripts/dev_tools/release.py": "",
                "scripts/dev_tools/release_status.py": (
                    "closes_residual\nrelease_gate\nresidual_evidence_gate\nrelease_evidence_audit\n"
                    "any residual is closed\n"
                ),
                ".codex/skills-src/README.md": "areamatrix-residual-ledger\n",
                ".codex/references/index.md": "./dev check quality\n./dev check wording\n",
                ".codex/references/codex-workflow-and-tools.md": "已有 " + "7 个 " + "AreaMatrix skills\n",
                "tasks/backlog/codex-operating-layer-boundary-regression.md": "现有 8 个 repo-local skills\n",
                "docs/development/ci-governance.md": "./dev check quality\n./dev check wording\n",
                ".github/workflows/governance-ci.yml": "./dev check quality\n./dev check wording\n",
                ".codex/skills-src/areamatrix-validation-driver/SKILL.md": "macOS app\n",
                ".codex/skills-src/areamatrix-doc-sync/SKILL.md": "Core API UDL\n",
                ".codex/skills-src/areamatrix-file-safety/SKILL.md": "DB metadata migrations\n",
                ".codex/skills-src/areamatrix-enterprise-governance/SKILL.md": "CI workflows\n",
                ".codex/skills-src/areamatrix-residual-ledger/SKILL.md": "release blockers\n",
                ".codex/skills-src/areamatrix-workflow-planning/SKILL.md": "v* workflow\n",
                ".codex/skills-src/areamatrix-git-checkpoint/SKILL.md": "checkpoint\n",
            }
            for relative, text in required.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")

            self.assertEqual(checks.run_quality_check(root), 1)

    def test_wording_audit_blocks_long_term_track_terms(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "docs/README.md"
            path.parent.mkdir(parents=True)
            path.write_text(
                "\n".join(
                    [
                        "Current release uses Stage 1 alpha.",
                        "Current release uses Alpha distribution.",
                        "Current release uses BETA distribution.",
                        "Current release uses RELEASE GATE policy.",
                        "Current release uses SPRINT planning.",
                        "后续任务补齐真实闭环验收。",
                    ]
                ),
                encoding="utf-8",
            )

            hits, file_count = audit_wording(root)

            self.assertEqual(file_count, 1)
            self.assertTrue(any(hit.category == "blocked" for hit in hits))
            self.assertTrue(any(hit.term == "Alpha" for hit in hits))
            self.assertTrue(any(hit.term == "BETA" for hit in hits))
            self.assertTrue(any(hit.term == "RELEASE GATE" for hit in hits))
            self.assertTrue(any(hit.term == "SPRINT" for hit in hits))
            self.assertTrue(any(hit.term == "后续任务" for hit in hits))

    def test_wording_audit_blocks_fixture_source_track_ids(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "core/tests/example.rs"
            path.parent.mkdir(parents=True)
            path.write_text(
                "\n".join(
                    [
                        '{ "source":"c1", "id": "area-matrix:C2-demo" }',
                        '{ "source" : "C3", "id": "AREA-MATRIX:c4-demo" }',
                        r'{ \"source\" : \"C4\" }',
                    ]
                ),
                encoding="utf-8",
            )

            hits, file_count = audit_wording(root)

            self.assertEqual(file_count, 1)
            self.assertTrue(any(hit.category == "blocked-test" for hit in hits))
            self.assertTrue(any(hit.term == 'source":"c1' for hit in hits))
            self.assertTrue(any(hit.term == 'source" : "C3' for hit in hits))
            self.assertTrue(any(hit.term == r'source\" : \"C4' for hit in hits))
            self.assertTrue(any(hit.term == "area-matrix:C2-" for hit in hits))
            self.assertTrue(any(hit.term == "AREA-MATRIX:c4-" for hit in hits))

    def test_wording_audit_allows_release_residual_record_archive_test(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "core/tests/release_evidence_residual_records.rs"
            path.parent.mkdir(parents=True)
            path.write_text(
                'const EVIDENCE: &str = include_str!("../../workflow/versions/v1-mvp/evidence/example.md");\n',
                encoding="utf-8",
            )

            hits, file_count = audit_wording(root)

            self.assertEqual(file_count, 1)
            self.assertTrue(hits)
            self.assertTrue(all(hit.category == "allowed-archive-test" for hit in hits))

    def test_wording_audit_blocks_skill_body_track_terms(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / ".codex/skills-src/example/SKILL.md"
            path.parent.mkdir(parents=True)
            path.write_text("Current docs use Stage 1 alpha release.\n", encoding="utf-8")

            hits, file_count = audit_wording(root)

            self.assertEqual(file_count, 1)
            self.assertTrue(any(hit.category == "blocked" for hit in hits))

    def test_wording_audit_allows_skill_policy_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / ".codex/skills-src/example/SKILL.md"
            path.parent.mkdir(parents=True)
            path.write_text(
                "\n".join(
                    [
                        "Do not introduce stage / MVP terms into source-of-truth material.",
                        "Do not treat alpha/beta fixture values as stage pollution.",
                        "Report remaining stage / delivery-track wording hits.",
                    ]
                ),
                encoding="utf-8",
            )

            hits, file_count = audit_wording(root)

            self.assertEqual(file_count, 1)
            self.assertTrue(hits)
            self.assertTrue(all(hit.category == "allowed-policy" for hit in hits))

    def test_wording_audit_allows_skill_operational_history_paths(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / ".codex/skills-src/example/SKILL.md"
            path.parent.mkdir(parents=True)
            path.write_text(
                "\n".join(
                    [
                        "Run `python3 workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py doctor`.",
                        "Use `MAX_RETRIES=0 ./task-loop run --phase phase-1` for runner diagnostics.",
                    ]
                ),
                encoding="utf-8",
            )

            hits, file_count = audit_wording(root)

            self.assertEqual(file_count, 1)
            self.assertTrue(hits)
            self.assertTrue(all(hit.category == "allowed-policy" for hit in hits))

    def test_wording_audit_allows_technical_terms(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "docs/development/build.md"
            path.parent.mkdir(parents=True)
            path.write_text("Xcode Build Phase order matters.\n", encoding="utf-8")

            hits, file_count = audit_wording(root)

            self.assertEqual(file_count, 1)
            self.assertTrue(hits)
            self.assertTrue(all(hit.category == "allowed-technical" for hit in hits))

    def test_wording_audit_allows_release_helper_literal_names(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "docs/development/build.md"
            path.parent.mkdir(parents=True)
            path.write_text(
                "\n".join(
                    [
                        "./dev release alpha-feedback-decision-audit --json",
                        "`alpha-feedback-route.md` stores the decision record.",
                        "Use `.github/ISSUE_TEMPLATE/alpha_feedback.md` for feedback issues.",
                    ]
                ),
                encoding="utf-8",
            )

            hits, file_count = audit_wording(root)

            self.assertEqual(file_count, 1)
            self.assertTrue(hits)
            self.assertTrue(all(hit.category == "allowed-technical" for hit in hits))

    def test_wording_audit_allows_neutral_archive_navigation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "docs/README.md"
            path.parent.mkdir(parents=True)
            path.write_text("历史归档里的旧内部编号不代表未来版本已经开始。\n", encoding="utf-8")

            hits, file_count = audit_wording(root)

            self.assertEqual(file_count, 1)
            self.assertEqual([hit.category for hit in hits], ["allowed-technical"])

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
            task = root / "workflow/versions/v1-mvp/execution/phase-4/4-1-experience/task-15-saved-search-integration-verify.md"
            task.parent.mkdir(parents=True)
            task.write_text("# 4-1/task-15\n", encoding="utf-8")

            self.assertEqual(checks._task_path(root, "4-1/task-15").resolve(), task.resolve())

    def test_task_check_maps_c2_03_to_saved_search_tests(self) -> None:
        text = "Core ability saved-search-core saved-search-crud"

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
        text = "Core ability smart-list smart-lists"

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
            spec_dir = root / "workflow/versions/v1-mvp/source-docs/core/capability-specs/experience"
            tests_dir = root / "core/tests"
            spec_dir.mkdir(parents=True)
            tests_dir.mkdir(parents=True)
            (spec_dir / "tag-crud-core-tag-crud.md").write_text("# tag-crud-core tag-crud\n", encoding="utf-8")
            for name in [
                "tag_crud_contract_api.rs",
                "tag_crud_implementation.rs",
                "tag_crud_failure_recovery.rs",
            ]:
                (tests_dir / name).write_text("// test\n", encoding="utf-8")

            self.assertEqual(
                checks._core_task_test_commands("Core ability tag-crud-core tag-crud", root),
                [
                    ["cargo", "test", "--test", "tag_crud_contract_api", "--", "--nocapture"],
                    ["cargo", "test", "--test", "tag_crud_failure_recovery", "--", "--nocapture"],
                    ["cargo", "test", "--test", "tag_crud_implementation", "--", "--nocapture"],
                ],
            )

    def test_core_task_check_fails_when_no_targeted_tests_are_mapped(self) -> None:
        text = "Core ability unknown-capability imaginary capability"

        with (
            patch("scripts.dev_tools.checks.require_command"),
            patch.dict("os.environ", {}, clear=True),
            patch("scripts.dev_tools.checks.run_step") as run_step,
        ):
            run_step.return_value.returncode = 0

            self.assertEqual(checks._run_core_task_checks(Path("/tmp/repo"), text), 2)

        self.assertEqual(
            [call.args[0] for call in run_step.call_args_list],
            [],
        )

    def test_core_task_check_allows_explicit_full_fallback(self) -> None:
        text = "Core ability unknown-capability imaginary capability"

        with (
            patch("scripts.dev_tools.checks.require_command"),
            patch.dict("os.environ", {checks.ALLOW_FULL_TASK_FALLBACK_ENV: "1"}, clear=True),
            patch("scripts.dev_tools.checks.run_step") as run_step,
        ):
            run_step.return_value.returncode = 0

            self.assertEqual(checks._run_core_task_checks(Path("/tmp/repo"), text), 0)

        self.assertEqual(
            [call.args[0] for call in run_step.call_args_list],
            [["cargo", "test", "--workspace"]],
        )

    def test_atomic_core_task_check_runs_only_targeted_tests(self) -> None:
        text = "Core ability smart-list smart-lists"

        with (
            patch("scripts.dev_tools.checks.require_command"),
            patch("scripts.dev_tools.checks.run_step") as run_step,
        ):
            run_step.return_value.returncode = 0

            self.assertEqual(checks._run_core_task_checks(Path("/tmp/repo"), text), 0)

        self.assertEqual(
            [call.args[0] for call in run_step.call_args_list],
            [
                ["cargo", "test", "--test", "smart_list_contract_api", "--", "--nocapture"],
                ["cargo", "test", "--test", "smart_list_implementation", "--", "--nocapture"],
                ["cargo", "test", "--test", "smart_list_failure_recovery", "--", "--nocapture"],
            ],
        )

    def test_core_integration_task_check_adds_quality_gate(self) -> None:
        text = "Core ability smart-list integration-verify smart-lists"

        with (
            patch("scripts.dev_tools.checks.require_command"),
            patch("scripts.dev_tools.checks.run_step") as run_step,
        ):
            run_step.return_value.returncode = 0

            self.assertEqual(checks._run_core_task_checks(Path("/tmp/repo"), text), 0)

        self.assertEqual(
            [call.args[0] for call in run_step.call_args_list][:2],
            [
                ["cargo", "fmt", "--all", "--", "--check"],
                ["cargo", "clippy", "--all-targets", "--all-features", "--", "-D", "warnings"],
            ],
        )

    def test_mission_critical_file_safety_task_check_adds_quality_gate(self) -> None:
        text = "Core ability smart-list smart-lists"
        entry = checks.TaskManifestEntry(
            raw="### Exact Docs\n- docs/architecture/transactional-import.md",
            risk="Mission-Critical",
            exact_docs=("docs/architecture/transactional-import.md",),
            existing_code=("core/src/**",),
            expected_new_paths=("core/tests/**",),
            forbidden_touches=("apps/**",),
            validation=("./dev check task 4-1/task-18",),
        )

        with (
            patch("scripts.dev_tools.checks.require_command"),
            patch("scripts.dev_tools.checks.run_step") as run_step,
        ):
            run_step.return_value.returncode = 0

            self.assertEqual(checks._run_core_task_checks(Path("/tmp/repo"), text, entry), 0)

        self.assertEqual(
            [call.args[0] for call in run_step.call_args_list][:2],
            [
                ["cargo", "fmt", "--all", "--", "--check"],
                ["cargo", "clippy", "--all-targets", "--all-features", "--", "-D", "warnings"],
            ],
        )

    def test_task_manifest_entry_reads_phase_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = root / "workflow/versions/v1-mvp/execution/_shared/manifests/phase-4.md"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(
                "\n".join(
                    [
                        "## 4-1/task-18",
                        "",
                        "### Risk Level",
                        "- `High`",
                        "",
                        "### Validation",
                        "- ./dev check task 4-1/task-18",
                        "",
                        "## 4-1/task-19",
                    ]
                ),
                encoding="utf-8",
            )

            entry = checks._task_manifest_entry(root, "4-1/task-18")

            self.assertEqual(entry.risk, "High")
            self.assertEqual(entry.validation, ("./dev check task 4-1/task-18",))

    def test_task_check_detects_legacy_closeout_without_core_integration_false_positive(self) -> None:
        core_integration = "# 4-1/task-15: saved-search-core integration-verify\n- 分组：v1 experience\n"
        legacy_marker = "sta" + "ge"
        legacy_closeout = f"# 4-1/task-143: {legacy_marker}-2-experience integration verify\n"

        self.assertFalse(checks._is_legacy_closeout_task(core_integration))
        self.assertTrue(checks._is_legacy_closeout_task(legacy_closeout))

    def test_verify_suffix_defers_runner_checkpoint_evidence(self) -> None:
        cfg = RuntimeConfig(root_dir=Path("/tmp/areamatrix"))
        cfg.git_checkpoint = "commit"

        suffix = TaskLoopRunner(cfg).verify_suffix()

        self.assertIn("runner 写入 completed progress 和 Git checkpoint 之前", suffix)
        self.assertIn("progress.json", suffix)
        self.assertIn("git add", suffix)
        self.assertIn("GIT_CHECKPOINT=commit", suffix)
        self.assertIn("runner checkpoint 收口", suffix)

    def test_retry_prompt_keeps_task_validation_upper_bound(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            verify_log = root / "verify.log"
            verify_log.write_text(
                "验证失败：缺少 targeted saved-search-core failure test 证据。\nVERIFY_RESULT: FAIL\n",
                encoding="utf-8",
            )
            task = TaskFile(
                phase="phase-4",
                task_name="4-1-task-13",
                label="4-1/task-13",
                copy_file=root / "copy.md",
                verify_file=root / "verify.md",
                risk="High",
            )

            prompt = TaskLoopRunner(RuntimeConfig(root_dir=root)).build_copy_retry_prompt(task, 2, verify_log)

        self.assertIn("仍以当前 task manifest 的 `Validation` 为上限", prompt)
        self.assertIn("不要因为 retry、证据不足、上一次 verify 失败或 `core/**` 改动", prompt)
        self.assertIn("重新执行当前 task manifest `Validation`", prompt)
        self.assertNotIn("全部全面修复", prompt)

    def test_verify_suffix_keeps_retry_validation_scoped(self) -> None:
        suffix = TaskLoopRunner(RuntimeConfig(root_dir=Path("/tmp/areamatrix"))).verify_suffix()

        self.assertIn("验证边界不随 retry 次数变化", suffix)
        self.assertIn("当前 task manifest 的 `Validation` 为上限", suffix)
        self.assertIn("除非当前 task manifest 明确要求宽门禁", suffix)
        self.assertNotIn("全部全面修复", suffix)

    def test_runner_defaults_to_single_repair_retry(self) -> None:
        with patch.dict("os.environ", {}, clear=True):
            cfg = RuntimeConfig.from_env()

        self.assertEqual(cfg.max_retries, 1)

    def test_dev_console_wizard_can_select_infinite_repair_retries(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cfg = console.ConsoleConfig(
                runtime=RuntimeConfig(root_dir=root),
                task_loop_bin=root / "task-loop",
                pipeline=root / "workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py",
                console_log_root=root / ".codex/runtime/task-loop/console",
            )

            with (
                patch.dict("os.environ", {}, clear=True),
                patch("sys.stdin.isatty", return_value=True),
                patch("builtins.input", side_effect=["2", "1", "1", "3", "1"]),
            ):
                command = console.build_runner_command(cfg, "run", [])

        self.assertEqual(command.execution_mode, "foreground")
        self.assertEqual(command.env["MAX_RETRIES"], "0")
        self.assertIn("MAX_RETRIES=0", command.env_bits)
        self.assertNotIn("--max-tasks", command.argv)


if __name__ == "__main__":
    unittest.main()
