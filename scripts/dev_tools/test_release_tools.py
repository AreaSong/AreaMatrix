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
from scripts.dev_tools.common import ToolError


class ReleaseToolsTest(unittest.TestCase):
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
        self.assertEqual(payload["evidence_record_template"]["release_gate"], "block_if_any_pending_or_blocked")

    def test_release_preflight_result_pass_has_no_blockers(self) -> None:
        checks = [
            release.PreflightCheck("Developer ID Application identity", "PASS", "ok"),
            release.PreflightCheck("notarytool keychain profile", "PASS", "ok"),
        ]

        payload = release.release_preflight_result(checks, notary_profile="AC_PASSWORD")

        self.assertEqual(payload["status"], "PASS")
        self.assertEqual(payload["blocked_by"], [])
        self.assertEqual(len(payload["checks"]), 2)

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
        self.assertEqual(evidence["icloud_metadata"]["values"]["kMDItemUbiquitousItemDownloadingStatus"], "NotDownloaded")
        self.assertFalse(evidence["side_effects"]["download_attempted"])
        self.assertFalse(evidence["side_effects"]["file_content_read_attempted"])
        self.assertFalse(evidence["side_effects"]["db_write_attempted"])
        self.assertIn("DB row evidence", evidence["manual_smoke_required"])
        self.assertIn("v1-rl-002 is closed", evidence["does_not_prove"])
        run_capture.assert_called_once()
        self.assertEqual(run_capture.call_args.args[0][0], "mdls")

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
        self.assertIn("LIBRARY_SEARCH_PATHS=/repo/core/target/aarch64-apple-darwin/release", command)
        self.assertIn("OTHER_LDFLAGS=/repo/core/target/aarch64-apple-darwin/release/libarea_matrix_core.a", command)
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


if __name__ == "__main__":
    unittest.main()
