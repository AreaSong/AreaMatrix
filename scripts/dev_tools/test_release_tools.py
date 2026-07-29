"""Regression tests for release preflight helpers."""

from __future__ import annotations

import contextlib
import io
import json
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

from scripts.dev_tools import release
from scripts.dev_tools import release_status
from scripts.dev_tools.cli import _build_parser
from scripts.dev_tools.common import ToolError


class ReleaseToolsTest(unittest.TestCase):
    def _write_release_status_fixture(
        self,
        root: Path,
        *,
        include_release_blockers: bool = True,
        formal_alpha_status: str | None = None,
        include_evidence_records: bool = True,
    ) -> None:
        if formal_alpha_status is None:
            formal_alpha_status = "blocked" if include_release_blockers else "ready"
        (root / "workflow/residuals").mkdir(parents=True)
        (root / "workflow/versions/v1-mvp/residuals").mkdir(parents=True)
        (root / ".github/workflows").mkdir(parents=True)
        (root / "workflow/residuals/residuals.yaml").write_text(
            "\n".join(
                [
                    "version: 1",
                    "items:",
                    "  - id: global-ref-example",
                    "    status: reference-only",
                    "    type: historical-reference",
                    "    title: Example reference",
                    "    source: workflow/references/example.md",
                    "    current_impact: none",
                    "    executable_task: false",
                    "version_residuals:",
                    "  - version: v1-mvp",
                    "    source: workflow/versions/v1-mvp/residuals/residuals.yaml",
                    "    status: mixed-blocked",
                ]
            ),
            encoding="utf-8",
        )
        lines = [
            "version: 1",
            "version_status:",
            "  technical_queue: complete",
            "  task_count: 637",
            f"  formal_alpha: {formal_alpha_status}",
            "  release_blocker_policy: deferred-until-formal-distribution",
            "items:",
        ]
        if include_release_blockers:
            for residual_id, status, title in [
                ("v1-rl-002", "blocked-external", "iCloud placeholder evidence"),
                ("v1-rl-003", "blocked-external", "Distribution evidence"),
                ("v1-rl-004", "blocked-decision", "Final tag evidence"),
                ("v1-rl-006", "blocked-decision", "Feedback route decision"),
                ("v1-ref-003-1-task-05", "deferred", "Release gate review"),
            ]:
                lines.extend(
                    [
                        f"  - id: {residual_id}",
                        f"    status: {status}",
                        "    type: release-evidence",
                        f"    title: {title}",
                        "    source: workflow/versions/v1-mvp/evidence/release-checklist.md",
                        "    current_impact: formal-alpha-blocked",
                        "    executable_task: false",
                    ]
                )
        else:
            for residual_id, title in [
                ("v1-rl-002", "iCloud placeholder evidence"),
                ("v1-rl-003", "Distribution evidence"),
                ("v1-rl-004", "Final tag evidence"),
                ("v1-rl-006", "Feedback route decision"),
                ("v1-ref-003-1-task-05", "Release gate review"),
            ]:
                lines.extend(
                    [
                        f"  - id: {residual_id}",
                        "    status: closed",
                        "    type: release-evidence",
                        f"    title: {title}",
                        "    source: workflow/versions/v1-mvp/evidence/release-checklist.md",
                        "    current_impact: none",
                        "    executable_task: false",
                    ]
                )
        lines.extend(
            [
                "  - id: v1-ex-001",
                "    status: accepted-exception",
                "    type: closeout-exception",
                "    title: Accepted checkpoint gaps",
                "    source: workflow/versions/v1-mvp/closeout/checkpoint-accepted-exceptions.md",
                "    current_impact: none",
                "    executable_task: false",
            ]
        )
        (root / "workflow/versions/v1-mvp/residuals/residuals.yaml").write_text(
            "\n".join(lines),
            encoding="utf-8",
        )
        (root / ".github/workflows/core-ci.yml").write_text("name: Core CI\n", encoding="utf-8")
        if include_evidence_records:
            closes = {residual_id: True for residual_id in release_status.RELEASE_EVIDENCE_RECORDS}
            if include_release_blockers:
                closes = {}
            self._write_release_evidence_records(root, closes_override=closes)

    def _write_release_evidence_records(self, root: Path, *, closes_override: dict[str, bool] | None = None) -> None:
        closes_override = closes_override or {}
        status_by_id = {
            "v1-rl-002": "blocked",
            "v1-rl-003": "blocked",
            "v1-rl-004": "blocked",
            "v1-rl-006": "blocked",
            "v1-ref-003-1-task-05": "deferred",
        }
        for residual_id, spec in release_status.RELEASE_EVIDENCE_RECORDS.items():
            path = root / str(spec["path"])
            path.parent.mkdir(parents=True, exist_ok=True)
            closes = closes_override.get(residual_id, False)
            status = status_by_id[residual_id]
            closure_lines: list[str] = []
            if closes:
                requirements = release_status.RELEASE_EVIDENCE_CLOSURE_REQUIREMENTS[residual_id]
                status = str(requirements["status"][0])
                for field, allowed in requirements.items():
                    if field == "status":
                        continue
                    value = "evidence-value"
                    if release_status.POSITIVE_INTEGER in allowed:
                        value = "3"
                    elif release_status.GITHUB_HTTPS_URL in allowed:
                        value = "https://github.com/AreaMatrix/AreaMatrix/discussions/1"
                    elif release_status.NON_PLACEHOLDER in allowed:
                        if field.endswith(".source"):
                            value = "private-tester-roster-2026-07-06"
                        elif field.endswith(".primary"):
                            value = "GitHub issue template: Alpha Feedback"
                        elif field.endswith(".secondary"):
                            value = "GitHub Discussions Q&A category"
                        elif field.endswith(".owner"):
                            value = "@areamatrix/release-triage"
                        elif field.endswith(".response_slo"):
                            value = "2 business days"
                        else:
                            value = "recorded-release-decision"
                    elif release_status.NON_EMPTY not in allowed:
                        value = str(allowed[0]).lower() if isinstance(allowed[0], bool) else str(allowed[0])
                    closure_lines.append(f"{field}: {value}")
            path.write_text(
                "\n".join(
                    [
                        f"# Evidence {residual_id}",
                        "",
                        "```yaml",
                        "schema_version: 1",
                        f"mode: {spec['mode']}",
                        f"residual_id: {residual_id}",
                        f"status: {status}",
                        f"closes_residual: {str(closes).lower()}",
                        f"release_gate: {spec['release_gate']}",
                        *closure_lines,
                        "```",
                    ]
                ),
                encoding="utf-8",
            )

    def _set_version_residual_state(
        self,
        root: Path,
        residual_id: str,
        *,
        status: str,
        current_impact: str,
    ) -> None:
        path = root / "workflow/versions/v1-mvp/residuals/residuals.yaml"
        lines = path.read_text(encoding="utf-8").splitlines()
        in_target = False
        updated: list[str] = []
        for line in lines:
            if line.startswith("  - id: "):
                in_target = line.strip() == f"- id: {residual_id}"
            if in_target and line.startswith("    status: "):
                updated.append(f"    status: {status}")
                continue
            if in_target and line.startswith("    current_impact: "):
                updated.append(f"    current_impact: {current_impact}")
                continue
            updated.append(line)
        path.write_text("\n".join(updated), encoding="utf-8")

    def _write_ready_final_tag_record(self, root: Path) -> None:
        record = root / release_status.FINAL_TAG_RECORD_PATH
        record.parent.mkdir(parents=True, exist_ok=True)
        record.write_text(
            "\n".join(
                [
                    "# Final tag",
                    "",
                    "```yaml",
                    "schema_version: 1",
                    "mode: final_tag_release_record",
                    "residual_id: v1-rl-004",
                    "release: v0.1.0",
                    "status: ready",
                    "closes_residual: false",
                    "release_gate: block_until_all_release_gates_closed_and_final_tag_pushed",
                    "release_candidate:",
                    "  commit: abc123",
                    "  branch: main",
                    "  status: pass",
                    "  ci_status: pass",
                    "  release_checklist_status: pass",
                    "required_gates:",
                    "  v1_rl_002_icloud_placeholder:",
                    "    status: pass",
                    "  v1_rl_003_distribution:",
                    "    status: pass",
                    "  v1_rl_006_feedback_route:",
                    "    status: pass",
                    "final_tag:",
                    "  name: v0.1.0",
                    "  created: false",
                    "  annotated: pending",
                    "  pushed: false",
                    "```",
                ]
            ),
            encoding="utf-8",
        )

    def _write_ready_icloud_placeholder_record(self, root: Path) -> None:
        record = root / release_status.ICLOUD_PLACEHOLDER_RECORD_PATH
        record.parent.mkdir(parents=True, exist_ok=True)
        record.write_text(
            "\n".join(
                [
                    "# iCloud smoke",
                    "",
                    "```yaml",
                    "schema_version: 1",
                    "mode: icloud_placeholder_smoke_record",
                    "residual_id: v1-rl-002",
                    "manual_evidence_id: M-02",
                    "status: ready",
                    "closes_residual: false",
                    "release_gate: blocked_until_real_icloud_download_retry_and_db_evidence_pass",
                    "metadata_probe:",
                    "  command: ./dev release icloud-placeholder-evidence --path <path> --json",
                    "  status: captured",
                    "  mode: icloud_placeholder_metadata_probe",
                    "  closes_residual: false",
                    "  privacy:",
                    "    path_redaction: true",
                    "    raw_path_fields_present: false",
                    "  side_effects:",
                    "    download_attempted: false",
                    "    file_content_read_attempted: false",
                    "    file_write_attempted: false",
                    "    db_write_attempted: false",
                    "    project_write_attempted: false",
                    "    areamatrix_metadata_write_attempted: false",
                    "environment:",
                    "  macos_version: 15.5",
                    "  icloud_drive: enabled",
                    "  icloud_account: signed_in",
                    "  app_build: 202606161707",
                    "  repo_path: redacted-repo-path",
                    "  source_path: redacted-source-path",
                    "placeholder_before:",
                    "  mdls_downloading_status: not_downloaded",
                    "  mdls_is_downloaded: false",
                    "  finder_or_screenshot_ref: evidence/screenshot-before.png",
                    "ui_retry:",
                    "  status: pass",
                    "  action: Download & retry",
                    "  app_surface: single_file_import",
                    "  result: pass",
                    "placeholder_after:",
                    "  mdls_downloading_status: downloaded",
                    "  mdls_is_downloaded: true",
                    "  downloaded_file_observed: pass",
                    "repo_and_db_evidence:",
                    "  repo_file_state: pass",
                    "  db_row_query: SELECT path FROM files WHERE id = <redacted>",
                    "  db_row_result: pass",
                    "  retry_import_or_conflict_result: pass",
                    "user_file_invariants:",
                    "  placeholder_marker_not_silently_deleted: pass",
                    "  original_file_not_deleted: pass",
                    "  conflicted_copy_not_auto_merged: pass",
                    "  no_unrequested_overwrite: pass",
                    "  no_readme_or_areamatrix_overwrite: pass",
                    "```",
                ]
            ),
            encoding="utf-8",
        )

    def _write_ready_task05_release_gate_review_record(self, root: Path) -> None:
        record = root / release_status.TASK05_RELEASE_GATE_RECORD_PATH
        record.parent.mkdir(parents=True, exist_ok=True)
        record.write_text(
            "\n".join(
                [
                    "# Release gate review task05",
                    "",
                    "```yaml",
                    "schema_version: 1",
                    "mode: release_gate_review_task05_record",
                    "residual_id: v1-ref-003-1-task-05",
                    "task_label: 3-1/task-05",
                    "status: ready",
                    "closes_residual: false",
                    "release_gate: deferred_to_formal_release_evidence_review",
                    "task_loop_evidence:",
                    "  completed_task_loop_run_id: null",
                    "  verify_result_pass: false",
                    "  copy_log_archived: false",
                    "  verify_log_archived: false",
                    "  tracked_incomplete_summaries_excluded_from_pass: 5",
                    "release_evidence_review:",
                    "  source_checklist: workflow/versions/v1-mvp/evidence/release-checklist.md",
                    "  source_notes: workflow/versions/v1-mvp/evidence/release-notes/release-notes-0.1.0.md",
                    "  close_condition: handle through fresh formal release evidence review without fabricating task-loop evidence",
                    "  current_release_status: formal_alpha_blocked",
                    "  review_completed: true",
                    "  reviewer: release-owner",
                    "  reviewed_at: 2026-07-06T12:00:00Z",
                    "forbidden_repair:",
                    "  progress_json_rewrite_attempted: false",
                    "  task_loop_log_rewrite_attempted: false",
                    "  run_summary_rewrite_attempted: false",
                    "  git_checkpoint_backfill_attempted: false",
                    "  tag_or_release_created: false",
                    "```",
                ]
            ),
            encoding="utf-8",
        )

    def test_developer_id_identity_parser_filters_non_developer_id_certificates(self) -> None:
        output = "\n".join(
            [
                '  1) ABCDEF "Apple Development: Example (TEAMID)"',
                '  2) FEDCBA "Developer ID Application: Example, Inc. (TEAMID)"',
                "     2 valid identities found",
            ]
        )

        self.assertEqual(
            release._developer_id_identities(output),
            ["Developer ID Application: Example, Inc. (TEAMID)"],
        )

    def test_developer_id_identity_blocks_when_only_development_identity_exists(self) -> None:
        completed = type(
            "Completed",
            (),
            {
                "returncode": 0,
                "stdout": '  1) ABCDEF "Apple Development: Example (TEAMID)"\n1 valid identities found\n',
            },
        )()

        with (
            patch("scripts.dev_tools.release.require_command"),
            patch("scripts.dev_tools.release._run_capture", return_value=completed),
        ):
            result = release.check_developer_id_identity()

        self.assertEqual(result.status, "BLOCKED")
        self.assertIn("no valid Developer ID Application", result.detail)

    def test_notary_profile_passes_when_history_command_succeeds(self) -> None:
        completed = type("Completed", (), {"returncode": 0, "stdout": "Successfully received history\n"})()

        with (
            patch("scripts.dev_tools.release.require_command"),
            patch("scripts.dev_tools.release._run_capture", return_value=completed),
        ):
            result = release.check_notary_profile("AC_PASSWORD")

        self.assertEqual(result.status, "PASS")
        self.assertIn("AC_PASSWORD", result.detail)

    def test_release_preflight_returns_blocked_when_any_check_fails(self) -> None:
        checks = [
            release.PreflightCheck("Developer ID Application identity", "PASS", "ok"),
            release.PreflightCheck("notarytool keychain profile", "BLOCKED", "missing"),
        ]

        with (
            patch("scripts.dev_tools.release.check_developer_id_identity", return_value=checks[0]),
            patch("scripts.dev_tools.release.check_notary_profile", return_value=checks[1]),
        ):
            self.assertEqual(release.run_release_preflight(__import__("pathlib").Path("/tmp")), 1)

    def test_release_preflight_json_keeps_blocked_evidence_machine_readable(self) -> None:
        checks = [
            release.PreflightCheck("Developer ID Application identity", "BLOCKED", "missing identity"),
            release.PreflightCheck("notarytool keychain profile", "BLOCKED", "missing profile"),
        ]

        stdout = io.StringIO()
        with (
            patch("scripts.dev_tools.release.check_developer_id_identity", return_value=checks[0]),
            patch("scripts.dev_tools.release.check_notary_profile", return_value=checks[1]),
            contextlib.redirect_stdout(stdout),
        ):
            exit_code = release.run_release_preflight(Path("/tmp"), notary_profile="AC_PASSWORD", json_output=True)

        self.assertEqual(exit_code, 1)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["mode"], "release_distribution_preflight")
        self.assertEqual(payload["status"], "BLOCKED")
        self.assertEqual(payload["release_gate"], "block_if_any_check_blocked")
        self.assertEqual(payload["blocked_by"], ["Developer ID Application identity", "notarytool keychain profile"])
        self.assertIn("Developer ID Application signing identity", payload["required_distribution_evidence"])
        self.assertIn("notarized or stapled app", payload["does_not_prove"])
        template = payload["evidence_record_template"]
        self.assertEqual(template["schema_version"], 1)
        self.assertEqual(template["mode"], "distribution_signing_notarization_record")
        self.assertEqual(template["residual_id"], "v1-rl-003")
        self.assertEqual(template["release"], "v0.1.0")
        self.assertFalse(template["closes_residual"])
        self.assertEqual(template["preflight_json"]["command"], "./dev release preflight --json")
        self.assertEqual(template["preflight_json"]["status"], "BLOCKED")
        self.assertEqual(
            template["preflight_json"]["blocked_by"],
            ["Developer ID Application identity", "notarytool keychain profile"],
        )
        self.assertEqual(template["preflight_json"]["captured_at"], "<YYYY-MM-DD>")
        self.assertEqual(template["artifact_probe"]["mode"], "distribution_artifact_probe")
        self.assertEqual(template["artifact_probe"]["probe_status"], "pending | captured | blocked | partial | unsupported_platform")
        self.assertEqual(template["artifact_probe"]["distribution_requirements_status"], "blocked | pass")
        self.assertEqual(template["artifact_probe"]["status_semantics"], "probe.status captured is not a distribution pass")
        self.assertFalse(template["artifact_probe"]["closes_residual"])
        self.assertEqual(template["developer_id_identity"]["command"], "security find-identity -v -p codesigning")
        self.assertEqual(template["developer_id_identity"]["team_id"], "<TEAM_ID>")
        self.assertEqual(template["notarytool_profile"]["profile"], "AC_PASSWORD")
        self.assertEqual(
            template["notarytool_profile"]["command"],
            "xcrun notarytool history --keychain-profile AC_PASSWORD",
        )
        self.assertEqual(template["codesign_developer_id_team"]["required_signature"], "Developer ID Application")
        self.assertIn("Signature=adhoc", template["codesign_developer_id_team"]["rejects"])
        self.assertEqual(template["notarytool_submission"]["artifact"], "<zip-or-dmg-path>")
        self.assertEqual(template["notarytool_submission"]["log_url"], "<notarytool-log-url>")
        self.assertIn('xcrun stapler validate "$APP_PATH"', template["stapler_app"]["command"])
        self.assertEqual(template["formal_dmg"]["sha256"], "<sha256>")
        self.assertEqual(template["formal_dmg"]["codesign_status"], "pending | pass | blocked")
        self.assertEqual(template["formal_dmg"]["notarization_status"], "pending | accepted | blocked")
        self.assertEqual(template["stapler_dmg"]["status"], "pending | pass | blocked")
        self.assertEqual(template["spctl_assess"]["required_source"], "Notarized Developer ID")
        self.assertEqual(template["clean_mac_first_launch"]["gatekeeper_result"], "pending | accepted | blocked")
        self.assertEqual(
            template["clean_mac_first_launch"]["repo_selection_or_configured_repo_result"],
            "pending | pass | blocked",
        )
        self.assertEqual(template["release_gate"], "block_if_any_pending_or_blocked")

    def test_release_status_json_keeps_formal_release_blocked_and_read_only(self) -> None:
        def fake_git_lines(root: Path, args: list[str]) -> tuple[int, str]:
            del root
            if args[:2] == ["tag", "--list"]:
                return 0, "v0.1.0-unnotarized-preview.2\n"
            if args[:2] == ["ls-remote", "--tags"]:
                return 0, "abc123\trefs/tags/v0.1.0-unnotarized-preview.2\n"
            raise AssertionError(f"unexpected git args: {args}")

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(root)
            with patch("scripts.dev_tools.release_status._git_lines", side_effect=fake_git_lines):
                payload = release_status.release_status_result(root, include_remote=True)

        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual(payload["mode"], "release_status")
        self.assertEqual(payload["release"], "v0.1.0")
        self.assertEqual(payload["status"], "BLOCKED")
        self.assertFalse(payload["closes_residual"])
        self.assertEqual(payload["technical_queue"]["status"], "complete")
        self.assertEqual(payload["technical_queue"]["task_count"], 637)
        self.assertEqual(payload["formal_alpha"]["status"], "blocked")
        self.assertEqual(payload["index_consistency_gate"]["status"], "PASS")
        self.assertEqual(payload["release_evidence_audit_gate"]["status"], "PASS")
        self.assertEqual(payload["release_evidence_audit_gate"]["records_checked"], 5)
        self.assertEqual(
            [item["id"] for item in payload["release_blockers"]],
            ["v1-rl-002", "v1-rl-003", "v1-rl-004", "v1-rl-006", "v1-ref-003-1-task-05"],
        )
        self.assertEqual(payload["residual_evidence_gate"]["status"], "BLOCKED")
        self.assertEqual(
            payload["residual_evidence_gate"]["blocked_by"],
            [
                "residual:v1-rl-002",
                "residual:v1-rl-003",
                "residual:v1-rl-004",
                "residual:v1-rl-006",
                "residual:v1-ref-003-1-task-05",
            ],
        )
        self.assertTrue(payload["residual_evidence_gate"]["required_before_formal_tag"])
        self.assertTrue(payload["residual_evidence_gate"]["does_not_require_formal_tag_to_exist"])
        self.assertEqual(payload["formal_tag_gate"]["status"], "BLOCKED")
        self.assertEqual(
            payload["formal_tag_gate"]["blocked_by"],
            ["formal_tag_local_missing:v0.1.0", "formal_tag_remote_missing:v0.1.0"],
        )
        self.assertFalse(payload["tag"]["local_exists"])
        self.assertFalse(payload["tag"]["remote_exists"])
        self.assertEqual(payload["tag"]["local_preview_tags"], ["v0.1.0-unnotarized-preview.2"])
        self.assertEqual(payload["tag"]["remote_preview_tags"], ["v0.1.0-unnotarized-preview.2"])
        self.assertFalse(payload["release_workflow"]["exists"])
        self.assertEqual(payload["preflight"]["status"], "not_run")
        self.assertFalse(payload["preflight"]["run"])
        self.assertIn("residual:v1-rl-003", payload["blocked_by"])
        self.assertIn("residual:v1-rl-004", payload["blocked_by"])
        self.assertIn("formal_tag_local_missing:v0.1.0", payload["blocked_by"])
        self.assertIn("formal_tag_remote_missing:v0.1.0", payload["blocked_by"])
        self.assertIn("any residual is closed", payload["does_not_prove"])
        self.assertIn(
            "Fresh formal release evidence review for 3-1/task-05 without backfilling task-loop evidence",
            payload["next_required_evidence"],
        )

    def test_release_status_blocks_when_evidence_audit_fails(self) -> None:
        def fake_git_lines(root: Path, args: list[str]) -> tuple[int, str]:
            del root
            if args[:2] == ["tag", "--list"]:
                return 0, "v0.1.0-unnotarized-preview.2\n"
            if args[:2] == ["ls-remote", "--tags"]:
                return 0, "abc123\trefs/tags/v0.1.0-unnotarized-preview.2\n"
            raise AssertionError(f"unexpected git args: {args}")

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(root, include_evidence_records=False)
            self._write_release_evidence_records(root, closes_override={"v1-rl-002": True})
            with patch("scripts.dev_tools.release_status._git_lines", side_effect=fake_git_lines):
                payload = release_status.release_status_result(root, include_remote=True)

        self.assertEqual(payload["status"], "BLOCKED")
        self.assertEqual(payload["release_evidence_audit_gate"]["status"], "BLOCKED")
        self.assertIn(
            "release_evidence_audit:v1-rl-002:blocking_residual_closes_true",
            payload["blocked_by"],
        )

    def test_release_status_blocks_inconsistent_formal_alpha_index(self) -> None:
        def fake_git_lines(root: Path, args: list[str]) -> tuple[int, str]:
            del root
            if args[:2] == ["tag", "--list"]:
                return 0, "v0.1.0\n"
            if args[:2] == ["ls-remote", "--tags"]:
                return 0, "abc123\trefs/tags/v0.1.0\n"
            raise AssertionError(f"unexpected git args: {args}")

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(
                root,
                include_release_blockers=False,
                formal_alpha_status="blocked",
            )
            with patch("scripts.dev_tools.release_status._git_lines", side_effect=fake_git_lines):
                payload = release_status.release_status_result(root, include_remote=True)

        self.assertEqual(payload["status"], "BLOCKED")
        self.assertEqual(payload["release_blockers"], [])
        self.assertEqual(payload["residual_evidence_gate"]["status"], "PASS")
        self.assertEqual(payload["formal_tag_gate"]["status"], "PASS")
        self.assertEqual(payload["release_evidence_audit_gate"]["status"], "PASS")
        self.assertEqual(payload["index_consistency_gate"]["status"], "BLOCKED")
        self.assertEqual(
            payload["index_consistency_gate"]["blocked_by"],
            ["formal_alpha_status_blocked_without_release_blockers"],
        )
        self.assertEqual(payload["blocked_by"], ["formal_alpha_status_blocked_without_release_blockers"])

    def test_release_status_residual_gate_can_pass_before_formal_tag_exists(self) -> None:
        def fake_git_lines(root: Path, args: list[str]) -> tuple[int, str]:
            del root
            if args[:2] == ["tag", "--list"]:
                return 0, ""
            if args[:2] == ["ls-remote", "--tags"]:
                return 0, ""
            raise AssertionError(f"unexpected git args: {args}")

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(root, include_release_blockers=False)
            with patch("scripts.dev_tools.release_status._git_lines", side_effect=fake_git_lines):
                payload = release_status.release_status_result(root, include_remote=True)

        self.assertEqual(payload["status"], "BLOCKED")
        self.assertEqual(payload["release_blockers"], [])
        self.assertEqual(payload["formal_alpha"]["status"], "ready")
        self.assertEqual(payload["index_consistency_gate"]["status"], "PASS")
        self.assertEqual(payload["release_evidence_audit_gate"]["status"], "PASS")
        self.assertEqual(payload["residual_evidence_gate"]["status"], "PASS")
        self.assertEqual(payload["residual_evidence_gate"]["blocked_by"], [])
        self.assertEqual(payload["formal_tag_gate"]["status"], "BLOCKED")
        self.assertEqual(
            payload["formal_tag_gate"]["blocked_by"],
            ["formal_tag_local_missing:v0.1.0", "formal_tag_remote_missing:v0.1.0"],
        )
        self.assertEqual(
            payload["blocked_by"],
            ["formal_tag_local_missing:v0.1.0", "formal_tag_remote_missing:v0.1.0"],
        )
        self.assertFalse(payload["closes_residual"])

    def test_release_status_pass_still_does_not_close_residuals(self) -> None:
        def fake_git_lines(root: Path, args: list[str]) -> tuple[int, str]:
            del root
            if args[:2] == ["tag", "--list"]:
                return 0, "v0.1.0\n"
            if args[:2] == ["ls-remote", "--tags"]:
                return 0, "abc123\trefs/tags/v0.1.0\n"
            raise AssertionError(f"unexpected git args: {args}")

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(root, include_release_blockers=False)
            with patch("scripts.dev_tools.release_status._git_lines", side_effect=fake_git_lines):
                payload = release_status.release_status_result(root, include_remote=True)

        self.assertEqual(payload["status"], "PASS")
        self.assertEqual(payload["blocked_by"], [])
        self.assertEqual(payload["release_blockers"], [])
        self.assertEqual(payload["formal_alpha"]["status"], "ready")
        self.assertEqual(payload["index_consistency_gate"]["status"], "PASS")
        self.assertEqual(payload["release_evidence_audit_gate"]["status"], "PASS")
        self.assertEqual(payload["residual_evidence_gate"]["status"], "PASS")
        self.assertEqual(payload["formal_tag_gate"]["status"], "PASS")
        self.assertTrue(payload["tag"]["local_exists"])
        self.assertTrue(payload["tag"]["remote_exists"])
        self.assertFalse(payload["closes_residual"])
        self.assertIn("any residual is closed", payload["does_not_prove"])

    def test_release_status_json_command_exits_nonzero_when_blocked(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(root)
            stdout = io.StringIO()
            with (
                patch("scripts.dev_tools.release_status._git_lines", return_value=(0, "")),
                contextlib.redirect_stdout(stdout),
            ):
                exit_code = release_status.run_release_status(root, json_output=True)

        self.assertEqual(exit_code, 1)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["status"], "BLOCKED")
        self.assertFalse(payload["closes_residual"])

    def test_final_tag_readiness_audit_keeps_current_state_blocked_without_side_effects(self) -> None:
        root = Path(__file__).resolve().parents[2]

        payload = release_status.final_tag_readiness_audit_result(root)

        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual(payload["mode"], "final_tag_readiness_audit")
        self.assertEqual(payload["residual_id"], "v1-rl-004")
        self.assertEqual(payload["release"], "v0.1.0")
        self.assertEqual(payload["status"], "BLOCKED")
        self.assertFalse(payload["closes_residual"])
        self.assertFalse(payload["ready_to_create_formal_tag"])
        self.assertEqual(payload["record"]["status"], "blocked")
        self.assertFalse(payload["record"]["closes_residual"])
        self.assertEqual(payload["pre_tag_release_evidence_gate"]["status"], "BLOCKED")
        self.assertEqual(
            payload["pre_tag_release_evidence_gate"]["blocked_by"],
            ["v1-rl-002", "v1-rl-003", "v1-rl-006", "v1-ref-003-1-task-05"],
        )
        self.assertEqual(payload["tag_prerequisite_gate"]["status"], "BLOCKED")
        self.assertIn("pre_tag_residual:v1-rl-002", payload["blocked_by"])
        self.assertIn("prerequisite:release_candidate.commit", payload["blocked_by"])
        self.assertFalse(payload["audit_side_effects"]["tag_created"])
        self.assertFalse(payload["audit_side_effects"]["tag_pushed"])
        self.assertFalse(payload["audit_side_effects"]["github_release_created"])
        self.assertFalse(payload["audit_side_effects"]["project_write_attempted"])
        self.assertIn("formal v0.1.0 tag exists", payload["does_not_prove"])
        self.assertIn("v1-rl-004 is closed", payload["does_not_prove"])

    def test_final_tag_readiness_audit_can_pass_when_only_tag_action_remains(self) -> None:
        def fake_git_lines(root: Path, args: list[str]) -> tuple[int, str]:
            del root
            if args[:2] == ["tag", "--list"]:
                return 0, ""
            if args[:2] == ["ls-remote", "--tags"]:
                return 0, ""
            raise AssertionError(f"unexpected git args: {args}")

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(root, include_release_blockers=False)
            self._set_version_residual_state(
                root,
                "v1-rl-004",
                status="blocked-decision",
                current_impact="formal-alpha-blocked",
            )
            self._write_ready_final_tag_record(root)
            with patch("scripts.dev_tools.release_status._git_lines", side_effect=fake_git_lines):
                payload = release_status.final_tag_readiness_audit_result(root, include_remote=True)

        self.assertEqual(payload["status"], "PASS")
        self.assertFalse(payload["closes_residual"])
        self.assertFalse(payload["record"]["closes_residual"])
        self.assertEqual(payload["pre_tag_release_evidence_gate"]["status"], "PASS")
        self.assertEqual(payload["pre_tag_release_evidence_gate"]["blocked_by"], [])
        self.assertEqual(payload["tag_prerequisite_gate"]["status"], "PASS")
        self.assertFalse(payload["formal_tag"]["local_exists"])
        self.assertFalse(payload["formal_tag"]["remote_exists"])
        self.assertTrue(payload["ready_to_create_formal_tag"])
        self.assertEqual(payload["blocked_by"], [])
        self.assertFalse(payload["audit_side_effects"]["tag_created"])
        self.assertTrue(payload["audit_side_effects"]["network_attempted"])
        self.assertIn("formal v0.1.0 tag was pushed", payload["does_not_prove"])

    def test_release_status_parser_supports_json_and_remote_flags(self) -> None:
        parser = _build_parser()
        args = parser.parse_args(["release", "status", "--json", "--remote"])

        self.assertEqual(args.release_command, "status")
        self.assertTrue(args.json)
        self.assertTrue(args.remote)

    def test_final_tag_readiness_audit_parser_supports_json_and_remote_flags(self) -> None:
        parser = _build_parser()
        args = parser.parse_args(["release", "final-tag-readiness-audit", "--json", "--remote"])

        self.assertEqual(args.release_command, "final-tag-readiness-audit")
        self.assertTrue(args.json)
        self.assertTrue(args.remote)

    def test_icloud_placeholder_smoke_audit_keeps_current_smoke_blocked_without_side_effects(self) -> None:
        root = Path(__file__).resolve().parents[2]

        payload = release_status.icloud_placeholder_smoke_audit_result(root)

        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual(payload["mode"], "icloud_placeholder_smoke_audit")
        self.assertEqual(payload["residual_id"], "v1-rl-002")
        self.assertEqual(payload["manual_evidence_id"], "M-02")
        self.assertEqual(payload["status"], "BLOCKED")
        self.assertFalse(payload["closes_residual"])
        self.assertEqual(payload["record"]["status"], "blocked")
        self.assertFalse(payload["record"]["closes_residual"])
        self.assertEqual(payload["smoke_evidence_gate"]["status"], "BLOCKED")
        self.assertIn("smoke:metadata_probe.status", payload["blocked_by"])
        self.assertIn("smoke:ui_retry.status", payload["blocked_by"])
        self.assertIn("smoke:repo_and_db_evidence.db_row_result", payload["blocked_by"])
        self.assertFalse(payload["audit_side_effects"]["icloud_download_attempted"])
        self.assertFalse(payload["audit_side_effects"]["file_content_read_attempted"])
        self.assertFalse(payload["audit_side_effects"]["file_write_attempted"])
        self.assertFalse(payload["audit_side_effects"]["db_write_attempted"])
        self.assertFalse(payload["audit_side_effects"]["areamatrix_metadata_write_attempted"])
        self.assertIn("v1-rl-002 is closed", payload["does_not_prove"])
        self.assertIn("formal alpha release readiness", payload["does_not_prove"])

    def test_icloud_placeholder_smoke_audit_can_pass_complete_record_without_closing_residual(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(root)
            self._write_ready_icloud_placeholder_record(root)

            payload = release_status.icloud_placeholder_smoke_audit_result(root)

        self.assertEqual(payload["status"], "PASS")
        self.assertFalse(payload["closes_residual"])
        self.assertFalse(payload["record"]["closes_residual"])
        self.assertEqual(payload["smoke_evidence_gate"]["status"], "PASS")
        self.assertEqual(payload["blocked_by"], [])
        self.assertFalse(payload["audit_side_effects"]["icloud_download_attempted"])
        self.assertFalse(payload["audit_side_effects"]["project_write_attempted"])
        self.assertIn("Download & retry succeeded", payload["does_not_prove"])
        self.assertIn("v1-rl-002 is closed", payload["does_not_prove"])

    def test_icloud_placeholder_smoke_audit_parser_supports_json_flag(self) -> None:
        parser = _build_parser()
        args = parser.parse_args(["release", "icloud-placeholder-smoke-audit", "--json"])

        self.assertEqual(args.release_command, "icloud-placeholder-smoke-audit")
        self.assertTrue(args.json)

    def test_gate_review_task05_audit_keeps_current_review_blocked_without_side_effects(self) -> None:
        root = Path(__file__).resolve().parents[2]

        payload = release_status.task05_release_review_audit_result(root)

        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual(payload["mode"], "task05_release_review_audit")
        self.assertEqual(payload["residual_id"], "v1-ref-003-1-task-05")
        self.assertEqual(payload["task_label"], "3-1/task-05")
        self.assertEqual(payload["status"], "BLOCKED")
        self.assertFalse(payload["closes_residual"])
        self.assertEqual(
            payload["release_gate"],
            "audit_only_block_until_fresh_release_evidence_review_ready",
        )
        self.assertEqual(payload["record"]["status"], "deferred")
        self.assertFalse(payload["record"]["closes_residual"])
        self.assertEqual(payload["release_evidence_review_gate"]["status"], "BLOCKED")
        self.assertEqual(payload["task_loop_boundary_gate"]["status"], "PASS")
        self.assertEqual(payload["forbidden_repair_gate"]["status"], "PASS")
        self.assertIn("review:status", payload["blocked_by"])
        self.assertIn("review:release_evidence_review.review_completed", payload["blocked_by"])
        self.assertIn("review:release_evidence_review.reviewer", payload["blocked_by"])
        self.assertIn("review:release_evidence_review.reviewed_at", payload["blocked_by"])
        self.assertFalse(payload["audit_side_effects"]["progress_json_rewritten"])
        self.assertFalse(payload["audit_side_effects"]["task_loop_logs_rewritten"])
        self.assertFalse(payload["audit_side_effects"]["run_summaries_rewritten"])
        self.assertFalse(payload["audit_side_effects"]["git_checkpoint_backfilled"])
        self.assertFalse(payload["audit_side_effects"]["tag_created"])
        self.assertFalse(payload["audit_side_effects"]["network_attempted"])
        self.assertIn("task-loop VERIFY_RESULT PASS exists", payload["does_not_prove"])
        self.assertIn("v1-ref-003-1-task-05 is closed", payload["does_not_prove"])

    def test_gate_review_task05_audit_can_pass_fresh_review_without_closing_residual(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(root)
            self._write_ready_task05_release_gate_review_record(root)

            payload = release_status.task05_release_review_audit_result(root)

        self.assertEqual(payload["status"], "PASS")
        self.assertFalse(payload["closes_residual"])
        self.assertFalse(payload["record"]["closes_residual"])
        self.assertEqual(payload["release_evidence_review_gate"]["status"], "PASS")
        self.assertEqual(payload["task_loop_boundary_gate"]["status"], "PASS")
        self.assertEqual(payload["forbidden_repair_gate"]["status"], "PASS")
        self.assertEqual(payload["blocked_by"], [])
        self.assertFalse(payload["audit_side_effects"]["progress_json_rewritten"])
        self.assertFalse(payload["audit_side_effects"]["git_checkpoint_backfilled"])
        self.assertFalse(payload["audit_side_effects"]["tag_created"])
        self.assertIn("historical progress, logs, summaries", payload["does_not_prove"][1])
        self.assertIn("v1-ref-003-1-task-05 is closed", payload["does_not_prove"])

    def test_gate_review_task05_audit_parser_supports_json_flag(self) -> None:
        parser = _build_parser()
        args = parser.parse_args(["release", "task05-release-review-audit", "--json"])

        self.assertEqual(args.release_command, "task05-release-review-audit")
        self.assertTrue(args.json)

    def test_release_evidence_audit_current_records_align_with_residual_index(self) -> None:
        root = Path(__file__).resolve().parents[2]

        payload = release_status.release_evidence_audit_result(root)

        self.assertEqual(payload["status"], "PASS")
        self.assertFalse(payload["closes_residual"])
        self.assertEqual(
            [record["residual_id"] for record in payload["records"]],
            ["v1-rl-002", "v1-rl-003", "v1-rl-004", "v1-rl-006", "v1-ref-003-1-task-05"],
        )
        self.assertTrue(all(record["closes_residual"] is False for record in payload["records"]))
        self.assertIn("any residual is closed", payload["does_not_prove"])

    def test_release_evidence_audit_blocks_when_blocking_record_claims_closure(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(root)
            self._write_release_evidence_records(root, closes_override={"v1-rl-002": True})

            payload = release_status.release_evidence_audit_result(root)

        self.assertEqual(payload["status"], "BLOCKED")
        self.assertIn("v1-rl-002:blocking_residual_closes_true", payload["blocked_by"])
        v1_rl_002 = next(record for record in payload["records"] if record["residual_id"] == "v1-rl-002")
        self.assertTrue(v1_rl_002["residual_blocks_formal_alpha"])
        self.assertTrue(v1_rl_002["closes_residual"])

    def test_release_evidence_audit_blocks_closed_residual_with_incomplete_record(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(root, include_release_blockers=False)
            spec = release_status.RELEASE_EVIDENCE_RECORDS["v1-rl-003"]
            path = root / str(spec["path"])
            path.write_text(
                "\n".join(
                    [
                        "# Evidence v1-rl-003",
                        "",
                        "```yaml",
                        "schema_version: 1",
                        f"mode: {spec['mode']}",
                        "residual_id: v1-rl-003",
                        "status: blocked",
                        "closes_residual: true",
                        f"release_gate: {spec['release_gate']}",
                        "```",
                    ]
                ),
                encoding="utf-8",
            )

            payload = release_status.release_evidence_audit_result(root)

        self.assertEqual(payload["status"], "BLOCKED")
        self.assertIn("v1-rl-003:closed_residual_required_fields_incomplete", payload["blocked_by"])
        v1_rl_003 = next(record for record in payload["records"] if record["residual_id"] == "v1-rl-003")
        field_check = next(
            check for check in v1_rl_003["checks"] if check["name"] == "closed_residual_required_fields_complete"
        )
        self.assertEqual(field_check["status"], "BLOCKED")
        self.assertTrue(field_check["fields"])

    def test_release_evidence_audit_requires_complete_alpha_feedback_decision_fields(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(root, include_release_blockers=False)
            spec = release_status.RELEASE_EVIDENCE_RECORDS["v1-rl-006"]
            path = root / str(spec["path"])
            path.write_text(
                "\n".join(
                    [
                        "# Evidence v1-rl-006",
                        "",
                        "```yaml",
                        "schema_version: 1",
                        f"mode: {spec['mode']}",
                        "residual_id: v1-rl-006",
                        "status: ready",
                        "closes_residual: true",
                        f"release_gate: {spec['release_gate']}",
                        "alpha_feedback_release_decision.status: ready",
                        "alpha_feedback_release_decision.trusted_tester_list.status: pass",
                        "alpha_feedback_release_decision.trusted_tester_list.tester_count: 3",
                        "alpha_feedback_release_decision.announcement.status: pass",
                        "alpha_feedback_release_decision.announcement.url: https://example.invalid/discussion",
                        "alpha_feedback_release_decision.feedback_route.status: pass",
                        "alpha_feedback_release_decision.triage_owner.status: pass",
                        "alpha_feedback_release_decision.triage_owner.owner: release-owner",
                        "decision_side_effects.announcement_published: true",
                        "decision_side_effects.feedback_owner_assigned: true",
                        "decision_side_effects.feedback_route_marked_ready: true",
                        "```",
                    ]
                ),
                encoding="utf-8",
            )

            payload = release_status.release_evidence_audit_result(root)

        self.assertEqual(payload["status"], "BLOCKED")
        self.assertIn("v1-rl-006:closed_residual_required_fields_incomplete", payload["blocked_by"])
        v1_rl_006 = next(record for record in payload["records"] if record["residual_id"] == "v1-rl-006")
        field_check = next(
            check for check in v1_rl_006["checks"] if check["name"] == "closed_residual_required_fields_complete"
        )
        missing_fields = {field["field"] for field in field_check["fields"]}
        self.assertIn("alpha_feedback_release_decision.trusted_tester_list.source", missing_fields)
        self.assertIn("alpha_feedback_release_decision.feedback_route.primary", missing_fields)
        self.assertIn("alpha_feedback_release_decision.feedback_route.secondary", missing_fields)
        self.assertIn("alpha_feedback_release_decision.triage_owner.response_slo", missing_fields)
        self.assertIn("decision_side_effects.testers_invited", missing_fields)

    def test_release_evidence_audit_blocks_zero_alpha_feedback_tester_count(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(root, include_release_blockers=False)
            spec = release_status.RELEASE_EVIDENCE_RECORDS["v1-rl-006"]
            path = root / str(spec["path"])
            path.write_text(
                "\n".join(
                    [
                        "# Evidence v1-rl-006",
                        "",
                        "```yaml",
                        "schema_version: 1",
                        f"mode: {spec['mode']}",
                        "residual_id: v1-rl-006",
                        "status: ready",
                        "closes_residual: true",
                        f"release_gate: {spec['release_gate']}",
                        "alpha_feedback_release_decision.status: ready",
                        "alpha_feedback_release_decision.trusted_tester_list.status: pass",
                        "alpha_feedback_release_decision.trusted_tester_list.source: release-owner-approved-list",
                        "alpha_feedback_release_decision.trusted_tester_list.tester_count: 0",
                        "alpha_feedback_release_decision.announcement.status: pass",
                        "alpha_feedback_release_decision.announcement.url: https://example.invalid/discussion",
                        "alpha_feedback_release_decision.feedback_route.status: pass",
                        "alpha_feedback_release_decision.feedback_route.primary: GitHub issue template: Alpha Feedback",
                        "alpha_feedback_release_decision.feedback_route.secondary: release-owner-email",
                        "alpha_feedback_release_decision.triage_owner.status: pass",
                        "alpha_feedback_release_decision.triage_owner.owner: release-owner",
                        "alpha_feedback_release_decision.triage_owner.response_slo: 2 business days",
                        "decision_side_effects.testers_invited: true",
                        "decision_side_effects.announcement_published: true",
                        "decision_side_effects.feedback_owner_assigned: true",
                        "decision_side_effects.feedback_route_marked_ready: true",
                        "```",
                    ]
                ),
                encoding="utf-8",
            )

            payload = release_status.release_evidence_audit_result(root)

        self.assertEqual(payload["status"], "BLOCKED")
        self.assertIn("v1-rl-006:closed_residual_required_fields_incomplete", payload["blocked_by"])
        v1_rl_006 = next(record for record in payload["records"] if record["residual_id"] == "v1-rl-006")
        field_check = next(
            check for check in v1_rl_006["checks"] if check["name"] == "closed_residual_required_fields_complete"
        )
        zero_count_field = next(
            field
            for field in field_check["fields"]
            if field["field"] == "alpha_feedback_release_decision.trusted_tester_list.tester_count"
        )
        self.assertEqual(zero_count_field["actual"], 0)
        self.assertIn(release_status.POSITIVE_INTEGER, zero_count_field["expected"])

    def test_alpha_feedback_decision_audit_can_pass_ready_decision_without_closing_residual(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(root)
            template = root / release_status.ALPHA_FEEDBACK_TEMPLATE_PATH
            template.parent.mkdir(parents=True, exist_ok=True)
            template.write_text(
                "\n".join(
                    [
                        'labels: ["alpha-feedback", "needs-triage"]',
                        "## 测试版本 / Build",
                        "DMG SHA-256",
                        "## 测试环境 / Environment",
                        "Clean user or clean Mac",
                        "In iCloud Drive",
                        "## 数据安全确认 / Data Safety Check",
                        "用户文件",
                        ".areamatrix/",
                    ]
                ),
                encoding="utf-8",
            )
            config = root / release_status.ALPHA_FEEDBACK_CONFIG_PATH
            config.write_text(
                "\n".join(
                    [
                        "discussions/categories/q-a",
                        "discussions/categories/ideas",
                        "security/advisories/new",
                    ]
                ),
                encoding="utf-8",
            )
            record = root / release_status.ALPHA_FEEDBACK_RECORD_PATH
            record.write_text(
                "\n".join(
                    [
                        "# Feedback route",
                        "",
                        "```yaml",
                        "schema_version: 1",
                        "mode: alpha_feedback_release_decision_record",
                        "residual_id: v1-rl-006",
                        "release: v0.1.0",
                        "status: ready",
                        "closes_residual: false",
                        "release_gate: block_if_any_pending",
                        "alpha_feedback_release_decision:",
                        "  status: ready",
                        "  release_candidate: v0.1.0",
                        "  trusted_tester_list:",
                        "    status: pass",
                        "    source: private-tester-roster-2026-07-06",
                        "    tester_count: 3",
                        "  announcement:",
                        "    status: pass",
                        "    url: https://github.com/AreaMatrix/AreaMatrix/discussions/1",
                        "  feedback_route:",
                        "    status: pass",
                        "    primary: GitHub issue template: Alpha Feedback",
                        "    secondary: GitHub Discussions Q&A category",
                        "  triage_owner:",
                        "    status: pass",
                        "    owner: @areamatrix/release-triage",
                        "    response_slo: 2 business days",
                        "decision_side_effects:",
                        "  testers_invited: true",
                        "  announcement_published: true",
                        "  feedback_owner_assigned: true",
                        "  feedback_route_marked_ready: true",
                        "```",
                    ]
                ),
                encoding="utf-8",
            )

            payload = release_status.alpha_feedback_decision_audit_result(root)

        self.assertEqual(payload["status"], "PASS")
        self.assertFalse(payload["closes_residual"])
        self.assertFalse(payload["record"]["closes_residual"])
        self.assertEqual(payload["decision_gate"]["status"], "PASS")
        self.assertEqual(payload["blocked_by"], [])
        self.assertIn("v1-rl-006 is closed", payload["does_not_prove"])
        self.assertIn("formal alpha release readiness", payload["does_not_prove"])

    def test_alpha_feedback_decision_audit_blocks_zero_tester_count(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(root)
            template = root / release_status.ALPHA_FEEDBACK_TEMPLATE_PATH
            template.parent.mkdir(parents=True, exist_ok=True)
            template.write_text(
                "\n".join(
                    [
                        'labels: ["alpha-feedback", "needs-triage"]',
                        "## 测试版本 / Build",
                        "DMG SHA-256",
                        "## 测试环境 / Environment",
                        "Clean user or clean Mac",
                        "In iCloud Drive",
                        "## 数据安全确认 / Data Safety Check",
                        "用户文件",
                        ".areamatrix/",
                    ]
                ),
                encoding="utf-8",
            )
            config = root / release_status.ALPHA_FEEDBACK_CONFIG_PATH
            config.write_text(
                "\n".join(
                    [
                        "discussions/categories/q-a",
                        "discussions/categories/ideas",
                        "security/advisories/new",
                    ]
                ),
                encoding="utf-8",
            )
            record = root / release_status.ALPHA_FEEDBACK_RECORD_PATH
            record.write_text(
                "\n".join(
                    [
                        "# Feedback route",
                        "",
                        "```yaml",
                        "schema_version: 1",
                        "mode: alpha_feedback_release_decision_record",
                        "residual_id: v1-rl-006",
                        "release: v0.1.0",
                        "status: ready",
                        "closes_residual: false",
                        "release_gate: block_if_any_pending",
                        "alpha_feedback_release_decision:",
                        "  status: ready",
                        "  release_candidate: v0.1.0",
                        "  trusted_tester_list:",
                        "    status: pass",
                        "    source: private-tester-roster-2026-07-06",
                        "    tester_count: 0",
                        "  announcement:",
                        "    status: pass",
                        "    url: https://github.com/AreaMatrix/AreaMatrix/discussions/1",
                        "  feedback_route:",
                        "    status: pass",
                        "    primary: GitHub issue template: Alpha Feedback",
                        "    secondary: GitHub Discussions Q&A category",
                        "  triage_owner:",
                        "    status: pass",
                        "    owner: @areamatrix/release-triage",
                        "    response_slo: 2 business days",
                        "decision_side_effects:",
                        "  testers_invited: true",
                        "  announcement_published: true",
                        "  feedback_owner_assigned: true",
                        "  feedback_route_marked_ready: true",
                        "```",
                    ]
                ),
                encoding="utf-8",
            )

            payload = release_status.alpha_feedback_decision_audit_result(root)

        self.assertEqual(payload["status"], "BLOCKED")
        self.assertEqual(payload["decision_gate"]["status"], "BLOCKED")
        self.assertIn(
            "decision:alpha_feedback_release_decision.trusted_tester_list.tester_count",
            payload["blocked_by"],
        )

    def test_alpha_feedback_decision_audit_blocks_placeholder_decision_values(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(root)
            template = root / release_status.ALPHA_FEEDBACK_TEMPLATE_PATH
            template.parent.mkdir(parents=True, exist_ok=True)
            template.write_text(
                "\n".join(
                    [
                        'labels: ["alpha-feedback", "needs-triage"]',
                        "## 测试版本 / Build",
                        "DMG SHA-256",
                        "## 测试环境 / Environment",
                        "Clean user or clean Mac",
                        "In iCloud Drive",
                        "## 数据安全确认 / Data Safety Check",
                        "用户文件",
                        ".areamatrix/",
                    ]
                ),
                encoding="utf-8",
            )
            config = root / release_status.ALPHA_FEEDBACK_CONFIG_PATH
            config.write_text(
                "\n".join(
                    [
                        "discussions/categories/q-a",
                        "discussions/categories/ideas",
                        "security/advisories/new",
                    ]
                ),
                encoding="utf-8",
            )
            record = root / release_status.ALPHA_FEEDBACK_RECORD_PATH
            record.write_text(
                "\n".join(
                    [
                        "# Feedback route",
                        "",
                        "```yaml",
                        "schema_version: 1",
                        "mode: alpha_feedback_release_decision_record",
                        "residual_id: v1-rl-006",
                        "release: v0.1.0",
                        "status: ready",
                        "closes_residual: false",
                        "release_gate: block_if_any_pending",
                        "alpha_feedback_release_decision:",
                        "  status: ready",
                        "  release_candidate: v0.1.0",
                        "  trusted_tester_list:",
                        "    status: pass",
                        "    source: release-owner-approved-list",
                        "    tester_count: 3",
                        "  announcement:",
                        "    status: pass",
                        "    url: https://example.invalid/discussion",
                        "  feedback_route:",
                        "    status: pass",
                        "    primary: GitHub issue template: Alpha Feedback",
                        "    secondary: release-owner-email",
                        "  triage_owner:",
                        "    status: pass",
                        "    owner: release-owner",
                        "    response_slo: 2 business days",
                        "decision_side_effects:",
                        "  announcement_published: true",
                        "  feedback_owner_assigned: true",
                        "  feedback_route_marked_ready: true",
                        "```",
                    ]
                ),
                encoding="utf-8",
            )

            payload = release_status.alpha_feedback_decision_audit_result(root)

        self.assertEqual(payload["status"], "BLOCKED")
        self.assertEqual(payload["decision_gate"]["status"], "BLOCKED")
        self.assertIn(
            "decision:alpha_feedback_release_decision.trusted_tester_list.source",
            payload["blocked_by"],
        )
        self.assertIn("decision:alpha_feedback_release_decision.announcement.url", payload["blocked_by"])
        self.assertIn("decision:alpha_feedback_release_decision.feedback_route.secondary", payload["blocked_by"])
        self.assertIn("decision:alpha_feedback_release_decision.triage_owner.owner", payload["blocked_by"])
        self.assertIn("decision:decision_side_effects.testers_invited", payload["blocked_by"])

    def test_alpha_feedback_decision_audit_blocks_when_residual_is_not_current_blocker(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_release_status_fixture(root)
            self._set_version_residual_state(
                root,
                "v1-rl-006",
                status="closed",
                current_impact="none",
            )
            template = root / release_status.ALPHA_FEEDBACK_TEMPLATE_PATH
            template.parent.mkdir(parents=True, exist_ok=True)
            template.write_text(
                "\n".join(
                    [
                        'labels: ["alpha-feedback", "needs-triage"]',
                        "## 测试版本 / Build",
                        "DMG SHA-256",
                        "## 测试环境 / Environment",
                        "Clean user or clean Mac",
                        "In iCloud Drive",
                        "## 数据安全确认 / Data Safety Check",
                        "用户文件",
                        ".areamatrix/",
                    ]
                ),
                encoding="utf-8",
            )
            config = root / release_status.ALPHA_FEEDBACK_CONFIG_PATH
            config.write_text(
                "\n".join(
                    [
                        "discussions/categories/q-a",
                        "discussions/categories/ideas",
                        "security/advisories/new",
                    ]
                ),
                encoding="utf-8",
            )
            record = root / release_status.ALPHA_FEEDBACK_RECORD_PATH
            record.write_text(
                "\n".join(
                    [
                        "# Feedback route",
                        "",
                        "```yaml",
                        "schema_version: 1",
                        "mode: alpha_feedback_release_decision_record",
                        "residual_id: v1-rl-006",
                        "release: v0.1.0",
                        "status: ready",
                        "closes_residual: false",
                        "release_gate: block_if_any_pending",
                        "alpha_feedback_release_decision:",
                        "  status: ready",
                        "  release_candidate: v0.1.0",
                        "  trusted_tester_list:",
                        "    status: pass",
                        "    source: private-tester-roster-2026-07-06",
                        "    tester_count: 3",
                        "  announcement:",
                        "    status: pass",
                        "    url: https://github.com/AreaMatrix/AreaMatrix/discussions/1",
                        "  feedback_route:",
                        "    status: pass",
                        "    primary: GitHub issue template: Alpha Feedback",
                        "    secondary: GitHub Discussions Q&A category",
                        "  triage_owner:",
                        "    status: pass",
                        "    owner: @areamatrix/release-triage",
                        "    response_slo: 2 business days",
                        "decision_side_effects:",
                        "  testers_invited: true",
                        "  announcement_published: true",
                        "  feedback_owner_assigned: true",
                        "  feedback_route_marked_ready: true",
                        "```",
                    ]
                ),
                encoding="utf-8",
            )

            payload = release_status.alpha_feedback_decision_audit_result(root)

        self.assertEqual(payload["status"], "BLOCKED")
        self.assertEqual(payload["residual_gate"]["status"], "BLOCKED")
        self.assertIn("residual:residual_status_blocked_decision", payload["blocked_by"])
        self.assertIn("residual:residual_blocks_formal_alpha", payload["blocked_by"])

    def test_release_evidence_audit_parser_supports_json_flag(self) -> None:
        parser = _build_parser()
        args = parser.parse_args(["release", "evidence-audit", "--json"])

        self.assertEqual(args.release_command, "evidence-audit")
        self.assertTrue(args.json)

    def test_alpha_feedback_decision_audit_keeps_current_decision_blocked(self) -> None:
        root = Path(__file__).resolve().parents[2]

        payload = release_status.alpha_feedback_decision_audit_result(root)

        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual(payload["mode"], "alpha_feedback_decision_audit")
        self.assertEqual(payload["residual_id"], "v1-rl-006")
        self.assertEqual(payload["release"], "v0.1.0")
        self.assertEqual(payload["status"], "BLOCKED")
        self.assertFalse(payload["closes_residual"])
        self.assertEqual(
            payload["release_gate"],
            "audit_only_block_until_alpha_feedback_decision_ready",
        )
        self.assertEqual(payload["record"]["status"], "blocked")
        self.assertFalse(payload["record"]["closes_residual"])
        self.assertEqual(payload["local_entrypoints"]["issue_template"]["status"], "PASS")
        self.assertEqual(payload["local_entrypoints"]["discussion_links"]["status"], "PASS")
        self.assertEqual(payload["decision_gate"]["status"], "BLOCKED")
        self.assertIn("decision:alpha_feedback_release_decision.trusted_tester_list.status", payload["blocked_by"])
        self.assertIn("decision:alpha_feedback_release_decision.trusted_tester_list.source", payload["blocked_by"])
        self.assertIn("decision:alpha_feedback_release_decision.announcement.url", payload["blocked_by"])
        self.assertIn("decision:alpha_feedback_release_decision.feedback_route.secondary", payload["blocked_by"])
        self.assertIn("decision:alpha_feedback_release_decision.triage_owner.owner", payload["blocked_by"])
        self.assertIn("decision:alpha_feedback_release_decision.triage_owner.response_slo", payload["blocked_by"])
        self.assertFalse(payload["audit_side_effects"]["github_discussion_created"])
        self.assertFalse(payload["audit_side_effects"]["testers_invited"])
        self.assertFalse(payload["audit_side_effects"]["announcement_published"])
        self.assertFalse(payload["audit_side_effects"]["feedback_owner_assigned"])
        self.assertFalse(payload["audit_side_effects"]["feedback_route_marked_ready"])
        self.assertFalse(payload["audit_side_effects"]["network_attempted"])
        self.assertFalse(payload["audit_side_effects"]["project_write_attempted"])
        self.assertIn("v1-rl-006 is closed", payload["does_not_prove"])
        self.assertIn("formal alpha release readiness", payload["does_not_prove"])

    def test_alpha_feedback_decision_audit_json_command_exits_nonzero_when_blocked(self) -> None:
        root = Path(__file__).resolve().parents[2]
        stdout = io.StringIO()

        with contextlib.redirect_stdout(stdout):
            exit_code = release_status.run_alpha_feedback_decision_audit(root, json_output=True)

        self.assertEqual(exit_code, 1)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["status"], "BLOCKED")
        self.assertFalse(payload["closes_residual"])

    def test_alpha_feedback_decision_audit_parser_supports_json_flag(self) -> None:
        parser = _build_parser()
        args = parser.parse_args(["release", "alpha-feedback-decision-audit", "--json"])

        self.assertEqual(args.release_command, "alpha-feedback-decision-audit")
        self.assertTrue(args.json)

    def test_icloud_placeholder_evidence_parser_supports_sensitive_path_opt_in(self) -> None:
        parser = _build_parser()
        args = parser.parse_args(
            [
                "release",
                "icloud-placeholder-evidence",
                "--path",
                "/tmp/Report.pdf.icloud",
                "--json",
                "--include-sensitive-paths",
            ]
        )

        self.assertEqual(args.release_command, "icloud-placeholder-evidence")
        self.assertTrue(args.json)
        self.assertTrue(args.include_sensitive_paths)

    def test_readiness_build_parser_supports_install_confirmation(self) -> None:
        parser = _build_parser()
        args = parser.parse_args(
            [
                "release",
                "readiness-build",
                "--install",
                "--install-confirm",
                "/Applications/AreaMatrix.app",
            ]
        )

        self.assertEqual(args.release_command, "readiness-build")
        self.assertTrue(args.install)
        self.assertEqual(args.install_confirm, "/Applications/AreaMatrix.app")

    def test_distribution_evidence_doc_keeps_preflight_template_fields(self) -> None:
        root = Path(__file__).resolve().parents[2]
        record = (root / "workflow/versions/v1-mvp/evidence/distribution-signing-notarization.md").read_text(
            encoding="utf-8"
        )
        yaml_block = record.split("```yaml", 1)[1].split("```", 1)[0]
        template = release._distribution_evidence_record_template(
            "BLOCKED",
            ["Developer ID Application identity", "notarytool keychain profile"],
            notary_profile="AC_PASSWORD",
        )
        for key in template.keys():
            self.assertIn(f"\n{key}:", f"\n{yaml_block}")
        self.assertIn("status: blocked", yaml_block)
        self.assertIn("closes_residual: false", yaml_block)
        self.assertIn("release_gate: block_if_any_pending_or_blocked", yaml_block)
        self.assertIn("command: ./dev release preflight --json", yaml_block)
        self.assertIn("Developer ID Application identity", yaml_block)
        self.assertIn("notarytool keychain profile", yaml_block)
        self.assertIn("formal v0.1.0 release readiness", yaml_block)

    def test_release_preflight_result_pass_has_no_blockers(self) -> None:
        checks = [
            release.PreflightCheck("Developer ID Application identity", "PASS", "ok"),
            release.PreflightCheck("notarytool keychain profile", "PASS", "ok"),
        ]

        payload = release.release_preflight_result(checks, notary_profile="AC_PASSWORD")

        self.assertEqual(payload["status"], "PASS")
        self.assertEqual(payload["blocked_by"], [])
        self.assertEqual(len(payload["checks"]), 2)
        self.assertEqual(payload["evidence_record_template"]["schema_version"], 1)
        self.assertEqual(payload["evidence_record_template"]["residual_id"], "v1-rl-003")
        self.assertFalse(payload["evidence_record_template"]["closes_residual"])
        self.assertEqual(payload["evidence_record_template"]["preflight_json"]["status"], "PASS")
        self.assertEqual(payload["evidence_record_template"]["preflight_json"]["blocked_by"], [])
        self.assertEqual(
            payload["evidence_record_template"]["release_gate"],
            "block_if_any_pending_or_blocked",
        )
        self.assertIn("formal v0.1.0 release readiness", payload["does_not_prove"])

    def test_distribution_artifact_probe_collects_metadata_with_redaction(self) -> None:
        def fake_run_capture(argv: list[str]) -> object:
            path = argv[-1]
            if argv[:3] == ["codesign", "-dv", "--verbose=4"]:
                stdout = "\n".join(
                    [
                        f"Executable={path}/Contents/MacOS/SecretLaunchName",
                        "Signature=adhoc",
                        "TeamIdentifier=not set",
                    ]
                )
            else:
                stdout = f"{path}: valid on disk\n"
            return type("Completed", (), {"returncode": 0, "stdout": stdout})()

        with tempfile.TemporaryDirectory() as temp_dir:
            app_path = Path(temp_dir) / "SecretLaunchName.app"
            app_path.mkdir()
            dmg_path = Path(temp_dir) / "SecretLaunchName-0.1.0.dmg"
            dmg_path.write_text("fixture dmg marker", encoding="utf-8")
            with (
                patch("scripts.dev_tools.release.shutil.which", return_value="/usr/bin/tool"),
                patch("scripts.dev_tools.release._run_capture", side_effect=fake_run_capture) as run_capture,
            ):
                evidence = release.collect_distribution_artifact_probe(app_path, dmg_path)

        self.assertEqual(evidence["schema_version"], 1)
        self.assertEqual(evidence["mode"], "distribution_artifact_probe")
        self.assertEqual(evidence["residual_id"], "v1-rl-003")
        self.assertEqual(evidence["status"], "captured")
        self.assertEqual(evidence["probe"]["status"], "captured")
        self.assertEqual(evidence["distribution_requirements"]["status"], "blocked")
        self.assertIn("app.codesign_display:Signature=adhoc", evidence["distribution_requirements"]["blocked_by"])
        self.assertIn("app.codesign_display:TeamIdentifier=not set", evidence["distribution_requirements"]["blocked_by"])
        self.assertIn("dmg.sha256:skipped", evidence["distribution_requirements"]["blocked_by"])
        self.assertIn("notarytool_submission:not_proven_by_probe", evidence["blocked_by"])
        self.assertFalse(evidence["distribution_requirements"]["release_ready"])
        self.assertFalse(evidence["closes_residual"])
        self.assertEqual(evidence["release_gate"], release.DISTRIBUTION_ARTIFACT_PROBE_GATE)
        self.assertEqual(evidence["target"]["app"]["absolute_path"], release.REDACTED_PATH)
        self.assertEqual(evidence["target"]["dmg"]["absolute_path"], release.REDACTED_PATH)
        self.assertTrue(evidence["privacy"]["path_redaction"])
        self.assertFalse(evidence["privacy"]["raw_path_fields_present"])
        self.assertNotIn(str(app_path), evidence["app"]["codesign_display"]["command"])
        self.assertNotIn(str(dmg_path), evidence["dmg"]["codesign_verify"]["output_summary"])
        self.assertNotIn("SecretLaunchName.app", evidence["app"]["codesign_display"]["output_summary"])
        self.assertNotIn("SecretLaunchName", evidence["app"]["codesign_display"]["output_summary"])
        self.assertTrue(evidence["side_effects"]["signature_verification_read_attempted"])
        self.assertTrue(evidence["side_effects"]["artifact_content_read_attempted"])
        self.assertFalse(evidence["side_effects"]["full_dmg_hash_read_attempted"])
        self.assertFalse(evidence["side_effects"]["file_write_attempted"])
        self.assertFalse(evidence["side_effects"]["artifact_write_attempted"])
        self.assertFalse(evidence["side_effects"]["mount_attempted"])
        self.assertFalse(evidence["side_effects"]["notary_submit_attempted"])
        self.assertFalse(evidence["side_effects"]["staple_attempted"])
        self.assertTrue(evidence["side_effects"]["network_not_initiated_by_tool"])
        self.assertFalse(evidence["side_effects"]["external_system_assessment_attempted"])
        self.assertFalse(evidence["side_effects"]["network_may_be_attempted_by_system_assessment"])
        self.assertEqual(evidence["dmg"]["sha256"]["status"], "skipped")
        self.assertFalse(evidence["dmg"]["sha256"]["attempted"])
        self.assertIn("v1-rl-003 is closed", evidence["does_not_prove"])
        commands = [call.args[0][0] for call in run_capture.call_args_list]
        self.assertEqual(commands, ["codesign", "codesign", "codesign", "codesign"])

    def test_distribution_artifact_probe_hash_dmg_requires_explicit_opt_in(self) -> None:
        def fake_run_capture(argv: list[str]) -> object:
            if argv[:3] == ["shasum", "-a", "256"]:
                return type("Completed", (), {"returncode": 0, "stdout": f"abc123  {argv[-1]}\n"})()
            return type("Completed", (), {"returncode": 0, "stdout": "ok\n"})()

        with tempfile.TemporaryDirectory() as temp_dir:
            app_path = Path(temp_dir) / "AreaMatrix.app"
            app_path.mkdir()
            dmg_path = Path(temp_dir) / "AreaMatrix-0.1.0.dmg"
            dmg_path.write_text("fixture dmg marker", encoding="utf-8")
            with (
                patch("scripts.dev_tools.release.shutil.which", return_value="/usr/bin/tool"),
                patch("scripts.dev_tools.release._run_capture", side_effect=fake_run_capture) as run_capture,
            ):
                evidence = release.collect_distribution_artifact_probe(
                    app_path,
                    dmg_path,
                    hash_dmg=True,
                    include_sensitive_paths=True,
                )

        self.assertEqual(evidence["status"], "captured")
        self.assertFalse(evidence["privacy"]["path_redaction"])
        self.assertTrue(evidence["privacy"]["raw_path_fields_present"])
        self.assertIn(str(app_path), evidence["app"]["codesign_display"]["command"])
        self.assertTrue(evidence["dmg"]["sha256"]["attempted"])
        self.assertTrue(evidence["dmg"]["sha256"]["full_artifact_read_attempted"])
        self.assertEqual(evidence["dmg"]["sha256"]["sha256"], "abc123")
        self.assertTrue(evidence["side_effects"]["artifact_content_read_attempted"])
        self.assertTrue(evidence["side_effects"]["full_dmg_hash_read_attempted"])
        commands = [call.args[0][0] for call in run_capture.call_args_list]
        self.assertEqual(commands, ["codesign", "codesign", "codesign", "codesign", "shasum"])

    def test_distribution_artifact_probe_optional_system_checks_mark_network_uncertain(self) -> None:
        def fake_run_capture(argv: list[str]) -> object:
            path = argv[-1]
            if argv[0] == "spctl":
                stdout = f"{path}: accepted\nsource=Notarized Developer ID\n"
            elif argv[:3] == ["xcrun", "stapler", "validate"]:
                stdout = f"The validate action worked for {path}\n"
            elif argv[:3] == ["codesign", "-dv", "--verbose=4"]:
                stdout = "\n".join(
                    [
                        "Authority=Developer ID Application: Example, Inc. (TEAMID)",
                        "TeamIdentifier=TEAMID",
                    ]
                )
            else:
                stdout = f"{path}: valid on disk\n"
            return type("Completed", (), {"returncode": 0, "stdout": stdout})()

        with tempfile.TemporaryDirectory() as temp_dir:
            app_path = Path(temp_dir) / "PrivateArtifact.app"
            app_path.mkdir()
            dmg_path = Path(temp_dir) / "PrivateArtifact.dmg"
            dmg_path.write_text("fixture dmg marker", encoding="utf-8")
            with (
                patch("scripts.dev_tools.release.shutil.which", return_value="/usr/bin/tool"),
                patch("scripts.dev_tools.release._run_capture", side_effect=fake_run_capture),
            ):
                evidence = release.collect_distribution_artifact_probe(
                    app_path,
                    dmg_path,
                    spctl=True,
                    stapler_validate=True,
                )

        self.assertEqual(evidence["status"], "captured")
        self.assertTrue(evidence["side_effects"]["external_system_assessment_attempted"])
        self.assertTrue(evidence["side_effects"]["network_may_be_attempted_by_system_assessment"])
        self.assertTrue(evidence["side_effects"]["network_not_initiated_by_tool"])
        self.assertNotIn("PrivateArtifact", evidence["app"]["spctl_assess"]["output_summary"])
        self.assertNotIn("PrivateArtifact", evidence["dmg"]["stapler_validate"]["output_summary"])
        self.assertIn("dmg.sha256:skipped", evidence["distribution_requirements"]["blocked_by"])

    def test_distribution_artifact_probe_blocks_missing_paths_without_running_commands(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            app_path = Path(temp_dir) / "Missing.app"
            dmg_path = Path(temp_dir) / "Missing.dmg"
            with (
                patch("scripts.dev_tools.release.shutil.which", return_value="/usr/bin/tool"),
                patch("scripts.dev_tools.release._run_capture") as run_capture,
            ):
                evidence = release.collect_distribution_artifact_probe(app_path, dmg_path)

        self.assertEqual(evidence["status"], "blocked")
        self.assertIn("target.app:path does not exist", evidence["blocked_by"])
        self.assertIn("target.dmg:path does not exist", evidence["blocked_by"])
        self.assertFalse(evidence["target"]["app"]["lexists"])
        self.assertFalse(evidence["target"]["dmg"]["lexists"])
        self.assertFalse(evidence["side_effects"]["artifact_content_read_attempted"])
        self.assertFalse(evidence["side_effects"]["signature_verification_read_attempted"])
        self.assertFalse(evidence["side_effects"]["full_dmg_hash_read_attempted"])
        run_capture.assert_not_called()

    def test_distribution_artifact_probe_parser_supports_read_only_flags(self) -> None:
        parser = _build_parser()
        args = parser.parse_args(
            [
                "release",
                "distribution-artifact-probe",
                "--app-path",
                "/tmp/AreaMatrix.app",
                "--dmg-path",
                "/tmp/AreaMatrix.dmg",
                "--json",
                "--hash-dmg",
                "--spctl",
                "--stapler-validate",
                "--include-sensitive-paths",
            ]
        )

        self.assertEqual(args.release_command, "distribution-artifact-probe")
        self.assertEqual(args.app_path, "/tmp/AreaMatrix.app")
        self.assertEqual(args.dmg_path, "/tmp/AreaMatrix.dmg")
        self.assertTrue(args.json)
        self.assertTrue(args.hash_dmg)
        self.assertTrue(args.spctl)
        self.assertTrue(args.stapler_validate)
        self.assertTrue(args.include_sensitive_paths)

    def test_icloud_placeholder_evidence_collects_metadata_without_side_effects(self) -> None:
        mdls_output = "\n".join(
            [
                'kMDItemUbiquitousItemDownloadingStatus = "NotDownloaded"',
                "kMDItemUbiquitousItemIsDownloaded = 0",
                "kMDItemUbiquitousItemIsUploaded = 1",
                "kMDItemUbiquitousItemHasUnresolvedConflicts = 0",
                'kMDItemFSName = "Report.pdf.icloud"',
            ]
        )
        completed = type("Completed", (), {"returncode": 0, "stdout": mdls_output})()

        with tempfile.TemporaryDirectory() as temp_dir:
            placeholder = Path(temp_dir) / "Report.pdf.icloud"
            placeholder.write_text("fixture marker", encoding="utf-8")
            with (
                patch("scripts.dev_tools.release.shutil.which", return_value="/usr/bin/mdls"),
                patch("scripts.dev_tools.release._run_capture", return_value=completed) as run_capture,
            ):
                evidence = release.collect_icloud_placeholder_evidence(placeholder)

        self.assertEqual(evidence["schema_version"], 1)
        self.assertEqual(evidence["mode"], "icloud_placeholder_metadata_probe")
        self.assertEqual(evidence["residual_id"], "v1-rl-002")
        self.assertEqual(evidence["manual_evidence_id"], "M-02")
        self.assertEqual(evidence["status"], "captured")
        self.assertFalse(evidence["closes_residual"])
        self.assertEqual(
            evidence["release_gate"],
            "blocked_until_real_icloud_download_retry_and_db_evidence_pass",
        )
        self.assertTrue(evidence["target"]["icloud_marker_filename"])
        self.assertEqual(evidence["target"]["input_path"], release.REDACTED_PATH)
        self.assertEqual(evidence["target"]["absolute_path"], release.REDACTED_PATH)
        self.assertEqual(
            evidence["icloud_metadata"]["values"]["kMDItemUbiquitousItemDownloadingStatus"],
            "NotDownloaded",
        )
        self.assertEqual(evidence["icloud_metadata"]["values"]["kMDItemFSName"], release.REDACTED_FILENAME)
        self.assertNotIn(str(placeholder), evidence["icloud_metadata"]["command"])
        self.assertTrue(evidence["privacy"]["path_redaction"])
        self.assertFalse(evidence["privacy"]["raw_path_fields_present"])
        self.assertFalse(evidence["side_effects"]["download_attempted"])
        self.assertFalse(evidence["side_effects"]["file_content_read_attempted"])
        self.assertFalse(evidence["side_effects"]["file_write_attempted"])
        self.assertFalse(evidence["side_effects"]["db_write_attempted"])
        self.assertFalse(evidence["side_effects"]["project_write_attempted"])
        self.assertFalse(evidence["side_effects"]["areamatrix_metadata_write_attempted"])
        self.assertIn("DB row evidence", evidence["manual_smoke_required"])
        self.assertIn("v1-rl-002 is closed", evidence["does_not_prove"])
        run_capture.assert_called_once()
        self.assertEqual(run_capture.call_args.args[0][0], "mdls")
        self.assertEqual(run_capture.call_args.args[0][-1], str(placeholder))

    def test_icloud_placeholder_evidence_sensitive_paths_require_explicit_opt_in(self) -> None:
        mdls_output = "\n".join(
            [
                'kMDItemUbiquitousItemDownloadingStatus = "NotDownloaded"',
                'kMDItemFSName = "Report.pdf.icloud"',
            ]
        )
        completed = type("Completed", (), {"returncode": 0, "stdout": mdls_output})()

        with tempfile.TemporaryDirectory() as temp_dir:
            placeholder = Path(temp_dir) / "Report.pdf.icloud"
            placeholder.write_text("fixture marker", encoding="utf-8")
            with (
                patch("scripts.dev_tools.release.shutil.which", return_value="/usr/bin/mdls"),
                patch("scripts.dev_tools.release._run_capture", return_value=completed),
            ):
                evidence = release.collect_icloud_placeholder_evidence(
                    placeholder,
                    include_sensitive_paths=True,
                )

        self.assertEqual(evidence["target"]["input_path"], str(placeholder))
        self.assertEqual(evidence["target"]["absolute_path"], str(placeholder))
        self.assertEqual(evidence["icloud_metadata"]["values"]["kMDItemFSName"], "Report.pdf.icloud")
        self.assertIn(str(placeholder), evidence["icloud_metadata"]["command"])
        self.assertFalse(evidence["privacy"]["path_redaction"])
        self.assertTrue(evidence["privacy"]["raw_path_fields_present"])

    def test_icloud_placeholder_evidence_does_not_follow_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            target = Path(temp_dir) / "target.pdf"
            target.write_text("fixture target", encoding="utf-8")
            symlink = Path(temp_dir) / "target.pdf.icloud"
            symlink.symlink_to(target)
            with (
                patch("scripts.dev_tools.release.shutil.which", return_value="/usr/bin/mdls"),
                patch("scripts.dev_tools.release._run_capture") as run_capture,
            ):
                evidence = release.collect_icloud_placeholder_evidence(symlink)

        self.assertEqual(evidence["status"], "metadata_blocked")
        self.assertTrue(evidence["target"]["is_symlink"])
        self.assertEqual(evidence["target"]["file_type"], "symlink")
        self.assertEqual(evidence["icloud_metadata"]["error_summary"], "symlink target not inspected")
        self.assertFalse(evidence["icloud_metadata"]["mdls_attempted"])
        run_capture.assert_not_called()

    def test_icloud_placeholder_evidence_keeps_broken_symlink_lexical(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            symlink = Path(temp_dir) / "missing-target.pdf.icloud"
            symlink.symlink_to(Path(temp_dir) / "missing-target.pdf")
            with (
                patch("scripts.dev_tools.release.shutil.which", return_value="/usr/bin/mdls"),
                patch("scripts.dev_tools.release._run_capture") as run_capture,
            ):
                evidence = release.collect_icloud_placeholder_evidence(symlink)

        self.assertEqual(evidence["status"], "metadata_blocked")
        self.assertTrue(evidence["target"]["exists"])
        self.assertTrue(evidence["target"]["lexists"])
        self.assertTrue(evidence["target"]["is_symlink"])
        self.assertEqual(evidence["target"]["file_type"], "symlink")
        self.assertEqual(evidence["icloud_metadata"]["error_summary"], "symlink target not inspected")
        self.assertFalse(evidence["icloud_metadata"]["mdls_attempted"])
        self.assertFalse(evidence["side_effects"]["download_attempted"])
        self.assertFalse(evidence["side_effects"]["file_content_read_attempted"])
        run_capture.assert_not_called()

    def test_icloud_placeholder_evidence_marks_missing_mdls_as_unsupported_platform(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            placeholder = Path(temp_dir) / "Report.pdf.icloud"
            placeholder.write_text("fixture marker", encoding="utf-8")
            with patch("scripts.dev_tools.release.shutil.which", return_value=None):
                evidence = release.collect_icloud_placeholder_evidence(placeholder)

        self.assertEqual(evidence["status"], "unsupported_platform")
        self.assertFalse(evidence["icloud_metadata"]["mdls_available"])
        self.assertFalse(evidence["icloud_metadata"]["mdls_attempted"])
        self.assertEqual(evidence["icloud_metadata"]["error_summary"], "mdls command not found")
        self.assertFalse(evidence["closes_residual"])

    def test_icloud_placeholder_evidence_json_returns_nonzero_for_missing_path(self) -> None:
        stdout = io.StringIO()
        missing_path = Path("/tmp/areamatrix-missing-placeholder.icloud")

        with (
            patch("scripts.dev_tools.release.shutil.which", return_value="/usr/bin/mdls"),
            contextlib.redirect_stdout(stdout),
        ):
            exit_code = release.run_icloud_placeholder_evidence(missing_path, json_output=True)

        self.assertEqual(exit_code, 1)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["status"], "path_missing")
        self.assertEqual(payload["mode"], "icloud_placeholder_metadata_probe")
        self.assertEqual(payload["residual_id"], "v1-rl-002")
        self.assertFalse(payload["closes_residual"])
        self.assertFalse(payload["target"]["lexists"])
        self.assertEqual(payload["target"]["absolute_path"], release.REDACTED_PATH)
        self.assertTrue(payload["privacy"]["path_redaction"])
        self.assertFalse(payload["side_effects"]["download_attempted"])
        self.assertEqual(payload["icloud_metadata"]["error_summary"], "path does not exist")

    def test_default_readiness_build_number_uses_timestamp_format(self) -> None:
        build_number = release.default_readiness_build_number(datetime(2026, 6, 12, 12, 34))

        self.assertEqual(build_number, "202606121234")

    def test_readiness_xcodebuild_command_overrides_build_number(self) -> None:
        command = release._readiness_xcodebuild_command(
            Path("/repo"),
            build_number="202606121234",
            derived_data_path=Path("/repo/build/ReleaseReadiness"),
            destination="platform=macOS,arch=arm64",
        )

        self.assertIn("CURRENT_PROJECT_VERSION=202606121234", command)
        self.assertIn("CODE_SIGNING_ALLOWED=YES", command)
        self.assertIn("CODE_SIGN_STYLE=Manual", command)
        self.assertIn("CODE_SIGN_IDENTITY=-", command)
        self.assertIn("DEVELOPMENT_TEAM=", command)
        self.assertFalse(any(value.startswith("AREAMATRIX_CARGO_TARGET_DIR=") for value in command))
        self.assertFalse(any(value.startswith("LIBRARY_SEARCH_PATHS=") for value in command))
        self.assertFalse(any(value.startswith("OTHER_LDFLAGS=") for value in command))
        self.assertIn("-configuration", command)
        self.assertIn("Release", command)

    def test_readiness_build_rejects_core_dylib_linkage(self) -> None:
        completed = type(
            "Completed",
            (),
            {
                "returncode": 0,
                "stdout": "/repo/core/target/aarch64-apple-darwin/release/deps/libarea_matrix_core.dylib\n",
            },
        )()

        with patch("scripts.dev_tools.release._run_capture", return_value=completed):
            with self.assertRaises(ToolError):
                release._verify_app_is_self_contained(Path("/repo/build/AreaMatrix.app"))

    def test_readiness_build_accepts_static_core_linkage(self) -> None:
        completed = type("Completed", (), {"returncode": 0, "stdout": "/usr/lib/libSystem.B.dylib\n"})()

        with patch("scripts.dev_tools.release._run_capture", return_value=completed):
            release._verify_app_is_self_contained(Path("/repo/build/AreaMatrix.app"))

    def test_release_readiness_build_rejects_invalid_build_number(self) -> None:
        with (
            patch("scripts.dev_tools.release.require_command"),
            patch("scripts.dev_tools.release.run_step") as run_step,
        ):
            with self.assertRaises(ToolError):
                release.run_release_readiness_build(Path("/repo"), build_number="not-a-build-number")
            run_step.assert_not_called()

    def test_release_readiness_build_requires_install_confirmation_before_build(self) -> None:
        with (
            patch("scripts.dev_tools.release.require_command") as require_command,
            patch("scripts.dev_tools.release.run_step") as run_step,
        ):
            with self.assertRaises(ToolError):
                release.run_release_readiness_build(
                    Path("/repo"),
                    install=True,
                    build_number="202606121234",
                )

        require_command.assert_not_called()
        run_step.assert_not_called()

    def test_release_readiness_build_accepts_matching_install_confirmation(self) -> None:
        completed = type("Completed", (), {"returncode": 1})()
        with (
            patch("scripts.dev_tools.release.require_command"),
            patch("scripts.dev_tools.release.run_step", return_value=completed) as run_step,
        ):
            exit_code = release.run_release_readiness_build(
                Path("/repo"),
                install=True,
                build_number="202606121234",
                install_confirm="/Applications/AreaMatrix.app",
            )

        self.assertEqual(exit_code, 1)
        run_step.assert_called_once()


if __name__ == "__main__":
    unittest.main()
