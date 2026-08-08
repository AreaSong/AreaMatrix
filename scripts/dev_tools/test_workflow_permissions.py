"""Regression tests for GitHub Actions permission validation."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from scripts.dev_tools.checks import FailureCollector, _check_workflow_permissions


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


if __name__ == "__main__":
    unittest.main()
