"""Tests for the read-only remote governance audit."""

from __future__ import annotations

import base64
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.dev_tools.cli import _build_parser
from scripts.dev_tools.remote_governance import (
    REQUIRED_WORKFLOW_NAMES,
    REQUIRED_STATUS_CHECK_CONTEXTS,
    remote_governance_audit_result,
)


class RemoteGovernanceAuditTest(unittest.TestCase):
    def _fixture_root(self) -> Path:
        root = Path(tempfile.mkdtemp(prefix="areamatrix-remote-governance-"))
        (root / ".github/workflows").mkdir(parents=True)
        (root / ".github/CODEOWNERS").write_text("* @AreaSong\n", encoding="utf-8")
        (root / ".github/PULL_REQUEST_TEMPLATE.md").write_text(
            "## CODEOWNERS\n- [ ] reviewer review\n", encoding="utf-8"
        )
        return root

    def test_parser_supports_remote_audit(self) -> None:
        args = _build_parser().parse_args(
            ["governance", "remote-audit", "--json", "--remote", "origin", "--branch", "main"]
        )
        self.assertEqual(args.governance_command, "remote-audit")
        self.assertTrue(args.json)
        self.assertEqual(args.branch, "main")

    def test_missing_github_cli_is_explicitly_blocked_without_writes(self) -> None:
        root = self._fixture_root()
        with patch(
            "scripts.dev_tools.remote_governance._git_value",
            side_effect=["main", "https://github.com/AreaSong/AreaMatrix.git"],
        ), patch("scripts.dev_tools.remote_governance.shutil.which", return_value=None):
            payload = remote_governance_audit_result(root)

        self.assertEqual(payload["status"], "BLOCKED")
        self.assertIn("github_cli", payload["blocked_by"])
        self.assertFalse(payload["audit_side_effects"]["network_attempted"])
        self.assertFalse(payload["audit_side_effects"]["file_write_attempted"])
        self.assertFalse(payload["closes_residual"])

    def test_authenticated_remote_policy_can_pass(self) -> None:
        root = self._fixture_root()
        codeowners = base64.b64encode(b"* @AreaSong\n").decode("ascii")
        api_payloads = [
            {
                "workflow_runs": [
                    {
                        "name": "Core CI",
                        "created_at": "2026-08-03T09:02:00Z",
                        "status": "completed",
                        "conclusion": "success",
                    },
                    {
                        "name": "Governance CI",
                        "created_at": "2026-08-03T09:00:00Z",
                        "status": "completed",
                        "conclusion": "success",
                    },
                    {
                        "name": "macOS App CI",
                        "created_at": "2026-08-03T08:58:00Z",
                        "status": "completed",
                        "conclusion": "success",
                    }
                ]
            },
            {
                "url": "https://api.github.com/repos/AreaSong/AreaMatrix/branches/main/protection",
                "required_status_checks": {
                    "strict": True,
                    "contexts": list(REQUIRED_STATUS_CHECK_CONTEXTS),
                },
                "required_pull_request_reviews": {
                    "required_approving_review_count": 1,
                    "require_code_owner_reviews": True,
                    "dismiss_stale_reviews": True,
                },
                "enforce_admins": {"enabled": True},
                "allow_force_pushes": {"enabled": False},
                "allow_deletions": {"enabled": False},
                "required_conversation_resolution": {"enabled": True},
            },
            {"content": codeowners, "encoding": "base64"},
        ]

        def fake_capture(argv, *, cwd):
            del cwd
            if argv[:2] == ["git", "remote"]:
                return type("Result", (), {"returncode": 0, "output": "https://github.com/AreaSong/AreaMatrix.git\n"})()
            if argv[:2] == ["git", "symbolic-ref"]:
                return type("Result", (), {"returncode": 0, "output": "main\n"})()
            if argv[:2] == ["gh", "auth"]:
                return type("Result", (), {"returncode": 0, "output": "Logged in\n"})()
            if argv[:2] == ["gh", "api"]:
                payload = api_payloads.pop(0)
                return type("Result", (), {"returncode": 0, "output": json.dumps(payload)})()
            raise AssertionError(argv)

        with patch("scripts.dev_tools.remote_governance._capture", side_effect=fake_capture), patch(
            "scripts.dev_tools.remote_governance.shutil.which", return_value="/usr/local/bin/gh"
        ):
            payload = remote_governance_audit_result(root)

        self.assertEqual(payload["status"], "PASS")
        self.assertEqual(payload["blocked_by"], [])
        self.assertTrue(payload["audit_side_effects"]["network_attempted"])
        self.assertFalse(payload["audit_side_effects"]["branch_protection_changed"])

    def test_missing_required_status_context_blocks_even_when_review_policy_passes(self) -> None:
        root = self._fixture_root()
        codeowners = base64.b64encode(b"* @AreaSong\n").decode("ascii")
        contexts = list(REQUIRED_STATUS_CHECK_CONTEXTS[:-1])
        api_payloads = [
            {
                "workflow_runs": [
                    {"name": name, "created_at": f"2026-08-0{index}", "status": "completed", "conclusion": "success"}
                    for index, name in enumerate(REQUIRED_WORKFLOW_NAMES, start=1)
                ]
            },
            {
                "url": "https://api.github.com/repos/AreaSong/AreaMatrix/branches/main/protection",
                "required_status_checks": {"strict": True, "contexts": contexts},
                "required_pull_request_reviews": {
                    "required_approving_review_count": 1,
                    "require_code_owner_reviews": True,
                    "dismiss_stale_reviews": True,
                },
                "enforce_admins": {"enabled": True},
                "allow_force_pushes": {"enabled": False},
                "allow_deletions": {"enabled": False},
                "required_conversation_resolution": {"enabled": True},
            },
            {"content": codeowners, "encoding": "base64"},
        ]

        def fake_capture(argv, *, cwd):
            del cwd
            if argv[:2] == ["git", "remote"]:
                return type("Result", (), {"returncode": 0, "output": "https://github.com/AreaSong/AreaMatrix.git\n"})()
            if argv[:2] == ["git", "symbolic-ref"]:
                return type("Result", (), {"returncode": 0, "output": "main\n"})()
            if argv[:2] == ["gh", "auth"]:
                return type("Result", (), {"returncode": 0, "output": "Logged in\n"})()
            if argv[:2] == ["gh", "api"]:
                payload = api_payloads.pop(0)
                return type("Result", (), {"returncode": 0, "output": json.dumps(payload)})()
            raise AssertionError(argv)

        with patch("scripts.dev_tools.remote_governance._capture", side_effect=fake_capture), patch(
            "scripts.dev_tools.remote_governance.shutil.which", return_value="/usr/local/bin/gh"
        ):
            payload = remote_governance_audit_result(root)

        self.assertEqual(payload["status"], "BLOCKED")
        self.assertIn("required_status_checks", payload["blocked_by"])
        check = next(item for item in payload["checks"] if item["id"] == "required_status_checks")
        self.assertEqual(check["missing_required_checks"], [REQUIRED_STATUS_CHECK_CONTEXTS[-1]])

    def test_missing_required_review_blocks_even_when_actions_pass(self) -> None:
        root = self._fixture_root()
        codeowners = base64.b64encode(b"* @AreaSong\n").decode("ascii")
        api_payloads = [
            {
                "workflow_runs": [
                    {"name": "Core CI", "created_at": "2026-08-03", "status": "completed", "conclusion": "success"},
                    {"name": "Governance CI", "created_at": "2026-08-02", "status": "completed", "conclusion": "success"},
                    {"name": "macOS App CI", "created_at": "2026-08-01", "status": "completed", "conclusion": "success"},
                ]
            },
            {
                "url": "https://api.github.com",
                "required_status_checks": {
                    "strict": True,
                    "contexts": list(REQUIRED_STATUS_CHECK_CONTEXTS),
                },
                "required_pull_request_reviews": {
                    "required_approving_review_count": 0,
                    "require_code_owner_reviews": True,
                    "dismiss_stale_reviews": True,
                },
                "enforce_admins": {"enabled": True},
                "allow_force_pushes": {"enabled": False},
                "allow_deletions": {"enabled": False},
                "required_conversation_resolution": {"enabled": True},
            },
            {"content": codeowners, "encoding": "base64"},
        ]

        def fake_capture(argv, *, cwd):
            del cwd
            if argv[:2] == ["git", "remote"]:
                return type("Result", (), {"returncode": 0, "output": "git@github.com:AreaSong/AreaMatrix.git\n"})()
            if argv[:2] == ["git", "symbolic-ref"]:
                return type("Result", (), {"returncode": 0, "output": "main\n"})()
            if argv[:2] == ["gh", "auth"]:
                return type("Result", (), {"returncode": 0, "output": "Logged in\n"})()
            if argv[:2] == ["gh", "api"]:
                payload = api_payloads.pop(0)
                return type("Result", (), {"returncode": 0, "output": json.dumps(payload)})()
            raise AssertionError(argv)

        with patch("scripts.dev_tools.remote_governance._capture", side_effect=fake_capture), patch(
            "scripts.dev_tools.remote_governance.shutil.which", return_value="/usr/local/bin/gh"
        ):
            payload = remote_governance_audit_result(root)

        self.assertEqual(payload["status"], "BLOCKED")
        self.assertIn("required_reviews", payload["blocked_by"])

    def test_actions_token_can_supply_auth_without_local_gh_login(self) -> None:
        root = self._fixture_root()
        codeowners = base64.b64encode(b"* @AreaSong\n").decode("ascii")
        api_payloads = [
            {
                "workflow_runs": [
                    {"name": name, "created_at": f"2026-08-0{index}", "status": "completed", "conclusion": "success"}
                    for index, name in enumerate(("Core CI", "Governance CI", "macOS App CI"), start=1)
                ]
            },
            {
                "url": "https://api.github.com/repos/AreaSong/AreaMatrix/branches/main/protection",
                "required_status_checks": {
                    "strict": True,
                    "contexts": list(REQUIRED_STATUS_CHECK_CONTEXTS),
                },
                "required_pull_request_reviews": {
                    "required_approving_review_count": 1,
                    "require_code_owner_reviews": True,
                    "dismiss_stale_reviews": True,
                },
                "enforce_admins": {"enabled": True},
                "allow_force_pushes": {"enabled": False},
                "allow_deletions": {"enabled": False},
                "required_conversation_resolution": {"enabled": True},
            },
            {"content": codeowners, "encoding": "base64"},
        ]

        def fake_capture(argv, *, cwd):
            del cwd
            if argv[:2] == ["git", "remote"]:
                return type("Result", (), {"returncode": 0, "output": "https://github.com/AreaSong/AreaMatrix.git\n"})()
            if argv[:2] == ["git", "symbolic-ref"]:
                return type("Result", (), {"returncode": 0, "output": "main\n"})()
            if argv[:2] == ["gh", "api"]:
                payload = api_payloads.pop(0)
                return type("Result", (), {"returncode": 0, "output": json.dumps(payload)})()
            raise AssertionError(argv)

        with patch.dict(os.environ, {"GH_TOKEN": "actions-token"}, clear=False), patch(
            "scripts.dev_tools.remote_governance._capture", side_effect=fake_capture
        ), patch("scripts.dev_tools.remote_governance.shutil.which", return_value="/usr/local/bin/gh"):
            payload = remote_governance_audit_result(root)

        self.assertEqual(payload["status"], "PASS")
        self.assertEqual(payload["blocked_by"], [])


if __name__ == "__main__":
    unittest.main()
