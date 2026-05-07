"""Workflow status constants shared by developer tools."""

from __future__ import annotations


ARTIFACT_STATUSES = {
    "draft",
    "ready",
    "blocked",
    "deferred",
    "promoted",
    "done",
    "superseded",
}
VERSION_LIFECYCLE_STATUSES = {"planning", "live-running", "archived", "blocked", "template-reference"}


def status_list(values: set[str]) -> str:
    return ", ".join(sorted(values))
