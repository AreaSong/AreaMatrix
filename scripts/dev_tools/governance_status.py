"""Aggregate AreaMatrix governance readiness without fabricating external evidence."""

from __future__ import annotations

import json
import re
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
from typing import Any, Callable

from .checks import run_governance_check
from .developer import run_build_doctor
from .release import (
    DEFAULT_NOTARY_PROFILE,
    check_developer_id_identity,
    check_notary_profile,
    release_preflight_result,
)
from .release_status import release_status_result
from .remote_governance import remote_governance_audit_result


ROADMAP_PATH = "workflow/versions/v1-mvp/source-docs/roadmap/engineering-maturity-roadmap.md"


def _captured_check(root: Path, check: Callable[[Path], int]) -> dict[str, Any]:
    stdout = StringIO()
    stderr = StringIO()
    with redirect_stdout(stdout), redirect_stderr(stderr):
        exit_code = check(root)
    return {
        "status": "PASS" if exit_code == 0 else "BLOCKED",
        "exit_code": exit_code,
        "output": "\n".join(part for part in (stdout.getvalue().strip(), stderr.getvalue().strip()) if part),
    }


def _roadmap_row(root: Path, label: str) -> dict[str, Any]:
    path = root / ROADMAP_PATH
    if not path.is_file():
        return {"status": "BLOCKED", "detail": f"missing roadmap: {ROADMAP_PATH}"}

    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith(f"| {label} "):
            continue
        fields = [field.strip() for field in line.strip().strip("|").split("|")]
        if len(fields) < 2:
            break
        return {
            "status": fields[1],
            "evidence": fields[2] if len(fields) > 2 else "",
            "close_condition": fields[3] if len(fields) > 3 else "",
            "source": f"{ROADMAP_PATH}:{line_number(path, line)}",
        }
    return {"status": "BLOCKED", "detail": f"roadmap row not found: {label}"}


def line_number(path: Path, line: str) -> int:
    for index, candidate in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if candidate == line:
            return index
    return 1


def _normalise_roadmap_status(value: str) -> str:
    compact = re.sub(r"\s+", "", value)
    if "100%" in compact or any(token in value for token in ("已证明", "已落地", "已闭合")):
        return "PASS"
    if any(token in value for token in ("进行中", "部分完成", "部分证明")):
        return "IN_PROGRESS"
    return "BLOCKED"


def aggregate_governance_status(
    *,
    engineering_maturity: dict[str, Any],
    physical_modularization: dict[str, Any],
    local_governance: dict[str, Any],
    build_governance: dict[str, Any],
    remote_governance: dict[str, Any],
    release: dict[str, Any],
) -> dict[str, Any]:
    dimensions = {
        "engineering_maturity": engineering_maturity,
        "swift_physical_modularization": physical_modularization,
        "local_governance": local_governance,
        "build_governance": build_governance,
        "remote_governance": remote_governance,
        "formal_release": release,
    }
    blocked_by = [name for name, value in dimensions.items() if value.get("status") != "PASS"]
    return {
        "schema_version": 1,
        "mode": "governance_status",
        "status": "PASS" if not blocked_by else "BLOCKED",
        "overall_percentage": None,
        "percentage_policy": "No global weighted percentage is defined; engineering maturity is reported separately.",
        "engineering_maturity_percentage": 100
        if engineering_maturity.get("status") == "PASS"
        else None,
        "blocked_by": blocked_by,
        "dimensions": dimensions,
        "does_not_prove": [
            "external GitHub Actions or branch protection without a fresh remote audit",
            "Developer ID signing, notarization, or clean-Mac evidence without real credentials and hardware",
            "real iCloud placeholder smoke without a real iCloud environment",
            "independent review or v2 execution authorization",
        ],
    }


def governance_status_result(
    root: Path,
    *,
    branch: str | None = None,
    remote: str = "origin",
    recent_runs: int = 10,
    notary_profile: str = DEFAULT_NOTARY_PROFILE,
) -> dict[str, Any]:
    root = root.resolve()
    engineering = _roadmap_row(root, "工程成熟度矩阵")
    engineering["status"] = _normalise_roadmap_status(str(engineering.get("status", "")))
    engineering["criteria"] = "11/11 acceptance conditions"

    physical = _roadmap_row(root, "Swift 物理模块化")
    physical["status"] = _normalise_roadmap_status(str(physical.get("status", "")))

    local_governance = _captured_check(root, run_governance_check)
    build_governance = _captured_check(root, run_build_doctor)
    remote = remote_governance_audit_result(
        root,
        branch=branch,
        remote=remote,
        recent_runs=recent_runs,
    )
    release_status = release_status_result(root, include_remote=False)
    preflight = release_preflight_result(
        [check_developer_id_identity(), check_notary_profile(notary_profile)],
        notary_profile=notary_profile,
    )
    release = {
        "status": "PASS"
        if release_status.get("status") == "PASS" and preflight.get("status") == "PASS"
        else "BLOCKED",
        "release_status": release_status,
        "preflight": preflight,
    }
    return aggregate_governance_status(
        engineering_maturity=engineering,
        physical_modularization=physical,
        local_governance=local_governance,
        build_governance=build_governance,
        remote_governance=remote,
        release=release,
    )


def run_governance_status(
    root: Path,
    *,
    branch: str | None = None,
    remote: str = "origin",
    recent_runs: int = 10,
    notary_profile: str = DEFAULT_NOTARY_PROFILE,
    json_output: bool = False,
) -> int:
    payload = governance_status_result(
        root,
        branch=branch,
        remote=remote,
        recent_runs=recent_runs,
        notary_profile=notary_profile,
    )
    if json_output:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print(f"governance status: {payload['status']}")
        print(f"- engineering maturity: {payload['engineering_maturity_percentage'] or 'not proven'}%")
        for name, dimension in payload["dimensions"].items():
            print(f"- {dimension['status']}: {name}")
        if payload["blocked_by"]:
            print(f"blocked_by: {', '.join(payload['blocked_by'])}")
    return 0 if payload["status"] == "PASS" else 1
