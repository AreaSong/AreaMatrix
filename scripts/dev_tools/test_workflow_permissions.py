"""Regression tests for GitHub Actions permission validation."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from scripts.dev_tools.checks import (
    FailureCollector,
    _check_rust_toolchain_governance,
    _check_workflow_action_pins,
    _check_workflow_checkout_credentials,
    _check_workflow_permissions,
)


class WorkflowPermissionsTest(unittest.TestCase):
    def _check(self, source: str) -> FailureCollector:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            workflow_dir = root / ".github/workflows"
            workflow_dir.mkdir(parents=True)
            (workflow_dir / "fixture.yml").write_text(source, encoding="utf-8")
            failures = FailureCollector()
            _check_workflow_permissions(root, failures)
            return failures

    def test_accepts_supported_workflow_and_job_permissions(self) -> None:
        failures = self._check(
            "permissions:\n"
            "  contents: read\n"
            "jobs:\n"
            "  audit:\n"
            "    permissions:\n"
            "      actions: read\n"
            "      security-events: write\n"
        )

        self.assertEqual(failures.count, 0)

    def test_accepts_supported_inline_and_global_permission_values(self) -> None:
        failures = self._check("permissions: { contents: read, pull-requests: read }\njobs: {}\n")
        self.assertEqual(failures.count, 0)

        failures = self._check("permissions: read-all\njobs: {}\n")
        self.assertEqual(failures.count, 0)

        failures = self._check(
            "permissions:\n"
            "  \"contents\": \"read\"\n"
            "jobs: {}\n"
        )
        self.assertEqual(failures.count, 0)

    def test_rejects_unsupported_permission_key(self) -> None:
        failures = self._check("permissions:\n  administration: read\n")

        self.assertEqual(failures.count, 1)

    def test_rejects_invalid_permission_value(self) -> None:
        failures = self._check("permissions:\n  contents: admin\n")

        self.assertEqual(failures.count, 1)

    def test_ignores_permission_text_inside_run_block(self) -> None:
        failures = self._check(
            "jobs:\n"
            "  audit:\n"
            "    steps:\n"
            "      - run: |\n"
            "          permissions:\n"
            "            administration: read\n"
        )

        self.assertEqual(failures.count, 0)

    def test_requires_remote_actions_to_use_full_commit_sha(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            workflow_dir = root / ".github/workflows"
            workflow_dir.mkdir(parents=True)
            (workflow_dir / "fixture.yml").write_text(
                "jobs:\n"
                "  audit:\n"
                "    steps:\n"
                "      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2\n",
                encoding="utf-8",
            )
            failures = FailureCollector()
            _check_workflow_action_pins(root, failures)
            self.assertEqual(failures.count, 0)

            (workflow_dir / "fixture.yml").write_text(
                "jobs:\n  audit:\n    steps:\n      - uses: actions/checkout@v4\n",
                encoding="utf-8",
            )
            failures = FailureCollector()
            _check_workflow_action_pins(root, failures)
            self.assertEqual(failures.count, 1)

    def test_checkout_must_disable_persisted_credentials(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            workflow_dir = root / ".github/workflows"
            workflow_dir.mkdir(parents=True)
            workflow = workflow_dir / "fixture.yml"
            checkout = "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"
            workflow.write_text(
                f"jobs:\n  audit:\n    steps:\n      - uses: {checkout}\n"
                "        with:\n          persist-credentials: false\n",
                encoding="utf-8",
            )
            failures = FailureCollector()
            _check_workflow_checkout_credentials(root, failures)
            self.assertEqual(failures.count, 0)

            workflow.write_text(
                f"jobs:\n  audit:\n    steps:\n      - uses: {checkout}\n",
                encoding="utf-8",
            )
            failures = FailureCollector()
            _check_workflow_checkout_credentials(root, failures)
            self.assertEqual(failures.count, 1)

    def test_rust_toolchain_and_action_jobs_remain_aligned(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            workflow_dir = root / ".github/workflows"
            workflow_dir.mkdir(parents=True)
            (root / "rust-toolchain.toml").write_text(
                '[toolchain]\nchannel = "1.88.0"\ncomponents = ["rustfmt", "clippy"]\nprofile = "minimal"\n',
                encoding="utf-8",
            )
            workflow = (
                "jobs:\n"
                "  rust:\n"
                "    steps:\n"
                "      - uses: dtolnay/rust-toolchain@2eae45db285e407f22119950686d47e1101e071b # 1.88.0, reviewed 2026-08-21\n"
                "      - run: test \"$(rustc --version | awk '{print $2}')\" = \"1.88.0\"\n"
            )
            (workflow_dir / "fixture.yml").write_text(workflow, encoding="utf-8")
            failures = FailureCollector()
            _check_rust_toolchain_governance(root, failures)
            self.assertEqual(failures.count, 0)

            (workflow_dir / "fixture.yml").write_text(
                workflow.replace("      - run: test \"$(rustc --version | awk '{print $2}')\" = \"1.88.0\"\n", ""),
                encoding="utf-8",
            )
            failures = FailureCollector()
            _check_rust_toolchain_governance(root, failures)
            self.assertEqual(failures.count, 1)


if __name__ == "__main__":
    unittest.main()
