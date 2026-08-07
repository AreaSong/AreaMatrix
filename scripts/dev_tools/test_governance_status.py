"""Regression tests for the aggregate governance readiness dashboard."""

from __future__ import annotations

import unittest

from scripts.dev_tools.governance_status import aggregate_governance_status


class GovernanceStatusTest(unittest.TestCase):
    def _dimension(self, status: str) -> dict[str, str]:
        return {"status": status}

    def test_status_is_blocked_when_any_dimension_is_not_pass(self) -> None:
        payload = aggregate_governance_status(
            engineering_maturity=self._dimension("PASS"),
            physical_modularization=self._dimension("IN_PROGRESS"),
            local_governance=self._dimension("PASS"),
            build_governance=self._dimension("PASS"),
            remote_governance=self._dimension("BLOCKED"),
            release=self._dimension("BLOCKED"),
        )

        self.assertEqual(payload["status"], "BLOCKED")
        self.assertIsNone(payload["overall_percentage"])
        self.assertEqual(payload["engineering_maturity_percentage"], 100)
        self.assertEqual(
            payload["blocked_by"],
            ["swift_physical_modularization", "remote_governance", "formal_release"],
        )

    def test_status_passes_only_when_every_dimension_is_pass(self) -> None:
        payload = aggregate_governance_status(
            engineering_maturity=self._dimension("PASS"),
            physical_modularization=self._dimension("PASS"),
            local_governance=self._dimension("PASS"),
            build_governance=self._dimension("PASS"),
            remote_governance=self._dimension("PASS"),
            release=self._dimension("PASS"),
        )

        self.assertEqual(payload["status"], "PASS")
        self.assertEqual(payload["blocked_by"], [])
        self.assertEqual(payload["engineering_maturity_percentage"], 100)
