"""Regression tests for release preflight helpers."""

from __future__ import annotations

import unittest
from unittest.mock import patch

from scripts.dev_tools import release


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


if __name__ == "__main__":
    unittest.main()
