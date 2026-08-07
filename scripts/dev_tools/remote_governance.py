"""Read-only GitHub governance evidence audit behind ``./dev``."""

from __future__ import annotations

import base64
import json
import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence
from urllib.parse import quote


DEFAULT_REMOTE = "origin"
DEFAULT_RECENT_RUNS = 10
GITHUB_HOSTS = {"github.com", "www.github.com"}
REQUIRED_WORKFLOW_NAMES = ("Core CI", "Governance CI", "macOS App CI")


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    output: str


def _capture(argv: Sequence[str], *, cwd: Path) -> CommandResult:
    proc = subprocess.run(
        [str(part) for part in argv],
        cwd=cwd,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return CommandResult(proc.returncode, proc.stdout or "")


def _github_auth_status(root: Path) -> CommandResult:
    """Use an injected Actions token when available, otherwise inspect gh login state."""
    if os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN"):
        return CommandResult(0, "GitHub token provided by environment")
    return _capture(["gh", "auth", "status"], cwd=root)


def _short_detail(output: str) -> str:
    detail = " ".join(output.split())
    if len(detail) > 180:
        return f"{detail[:177]}..."
    return detail


def _git_value(root: Path, args: Sequence[str]) -> str | None:
    result = _capture(["git", *args], cwd=root)
    if result.returncode != 0:
        return None
    value = result.output.strip()
    return value or None


def _parse_github_remote(remote_url: str) -> tuple[str, str] | None:
    value = remote_url.strip().rstrip("/")
    if value.endswith(".git"):
        value = value[:-4]

    host: str | None = None
    path: str | None = None
    if value.startswith("git@") and ":" in value:
        host, path = value[4:].split(":", 1)
    elif "://" in value:
        scheme, remainder = value.split("://", 1)
        if scheme not in {"https", "http", "ssh", "git"} or "/" not in remainder:
            return None
        host, path = remainder.split("/", 1)
        if "@" in host:
            host = host.split("@", 1)[1]
    if host is None or path is None or host.lower() not in GITHUB_HOSTS:
        return None

    parts = [part for part in path.strip("/").split("/") if part]
    if len(parts) != 2:
        return None
    return parts[0], parts[1]


def _repo_identity(root: Path, remote: str) -> tuple[str, str] | None:
    remote_url = _git_value(root, ["remote", "get-url", remote])
    return _parse_github_remote(remote_url) if remote_url else None


def _current_branch(root: Path, requested: str | None) -> str:
    if requested:
        return requested
    branch = _git_value(root, ["symbolic-ref", "--short", "HEAD"])
    if branch and branch != "HEAD":
        return branch
    return "main"


def _gh_json(root: Path, endpoint: str) -> tuple[Any | None, str | None]:
    result = _capture(["gh", "api", "--method", "GET", endpoint], cwd=root)
    if result.returncode != 0:
        detail = _short_detail(result.output) or f"gh api exited with {result.returncode}"
        return None, detail
    try:
        return json.loads(result.output), None
    except json.JSONDecodeError:
        return None, "GitHub API returned non-JSON output"


def _check(check_id: str, title: str, status: str, detail: str, **extra: Any) -> dict[str, Any]:
    result: dict[str, Any] = {"id": check_id, "title": title, "status": status, "detail": detail}
    result.update(extra)
    return result


def _local_policy_checks(root: Path) -> list[dict[str, Any]]:
    codeowners = root / ".github/CODEOWNERS"
    template = root / ".github/PULL_REQUEST_TEMPLATE.md"
    checks: list[dict[str, Any]] = []

    codeowners_text = codeowners.read_text(encoding="utf-8") if codeowners.is_file() else ""
    has_owner = bool(re.search(r"(?m)^\s*[^#\s][^\n]*\s+@[A-Za-z0-9_.-]+", codeowners_text))
    checks.append(
        _check(
            "local_codeowners",
            "Local CODEOWNERS contains an owner rule",
            "PASS" if has_owner else "BLOCKED",
            "local .github/CODEOWNERS has at least one owner rule"
            if has_owner
            else "local .github/CODEOWNERS is missing or has no owner rule",
        )
    )

    template_text = template.read_text(encoding="utf-8") if template.is_file() else ""
    has_review_fields = "CODEOWNERS" in template_text and bool(
        re.search(r"(?im)^\s*-\s*\[[ xX]\].*(review|评审)", template_text)
    )
    checks.append(
        _check(
            "local_pr_review_template",
            "Local PR template records review ownership",
            "PASS" if has_review_fields else "BLOCKED",
            "local PR template contains CODEOWNERS and a review checklist"
            if has_review_fields
            else "local PR template is missing CODEOWNERS or review checklist evidence",
        )
    )
    return checks


def _remote_codeowners_check(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return _check("remote_codeowners", "Remote CODEOWNERS is present", "BLOCKED", "remote CODEOWNERS response is not an object")
    encoded = payload.get("content")
    if not isinstance(encoded, str):
        return _check("remote_codeowners", "Remote CODEOWNERS is present", "BLOCKED", "remote CODEOWNERS content is missing")
    try:
        content = base64.b64decode(encoded, validate=False).decode("utf-8")
    except (ValueError, UnicodeDecodeError):
        return _check("remote_codeowners", "Remote CODEOWNERS is present", "BLOCKED", "remote CODEOWNERS content is not valid UTF-8")
    has_owner = bool(re.search(r"(?m)^\s*[^#\s][^\n]*\s+@[A-Za-z0-9_.-]+", content))
    return _check(
        "remote_codeowners",
        "Remote CODEOWNERS is present",
        "PASS" if has_owner else "BLOCKED",
        "remote branch CODEOWNERS contains an owner rule" if has_owner else "remote branch CODEOWNERS has no owner rule",
    )


def _branch_protection_checks(payload: Any) -> list[dict[str, Any]]:
    if not isinstance(payload, dict):
        return [
            _check("branch_protection", "Branch protection is enabled", "BLOCKED", "branch protection response is not an object"),
            _check("required_status_checks", "Required status checks are configured", "BLOCKED", "branch protection response is unavailable"),
            _check("required_reviews", "Required pull request reviews are configured", "BLOCKED", "branch protection response is unavailable"),
        ]

    required_status = payload.get("required_status_checks") or {}
    contexts = required_status.get("contexts") or []
    structured_checks = required_status.get("checks") or []
    required_checks = list(contexts)
    required_checks.extend(
        item.get("context")
        for item in structured_checks
        if isinstance(item, dict) and item.get("context")
    )
    reviews = payload.get("required_pull_request_reviews") or {}
    approving_count = reviews.get("required_approving_review_count", 0)
    protection_enabled = bool(
        payload.get("url")
        or payload.get("required_status_checks") is not None
        or payload.get("enforce_admins") is not None
    )

    return [
        _check(
            "branch_protection",
            "Branch protection is enabled",
            "PASS" if protection_enabled else "BLOCKED",
            "remote branch protection endpoint returned a policy"
            if protection_enabled
            else "remote branch protection policy is absent",
        ),
        _check(
            "required_status_checks",
            "Required status checks are configured",
            "PASS" if required_checks else "BLOCKED",
            f"{len(required_checks)} required status check(s) configured"
            if required_checks
            else "no required status checks configured",
            required_checks=required_checks,
        ),
        _check(
            "required_reviews",
            "Required pull request reviews are configured",
            "PASS" if isinstance(approving_count, int) and approving_count >= 1 else "BLOCKED",
            f"{approving_count} approving review(s) required"
            if isinstance(approving_count, int) and approving_count >= 1
            else "no required approving review configured",
            required_approving_review_count=approving_count,
        ),
    ]


def _actions_checks(payload: Any) -> list[dict[str, Any]]:
    runs = payload.get("workflow_runs") if isinstance(payload, dict) else None
    if not isinstance(runs, list) or not runs:
        return [
            _check("recent_actions_runs", "Recent GitHub Actions runs exist", "BLOCKED", "no recent workflow runs returned"),
            _check("latest_actions_success", "Latest GitHub Actions run passed", "BLOCKED", "latest workflow run is unavailable"),
        ]

    ordered = sorted(
        (item for item in runs if isinstance(item, dict)),
        key=lambda item: str(item.get("created_at", "")),
        reverse=True,
    )
    latest_by_workflow: dict[str, dict[str, Any]] = {}
    for item in ordered:
        name = item.get("name")
        if name in REQUIRED_WORKFLOW_NAMES and name not in latest_by_workflow:
            latest_by_workflow[name] = item

    missing = [name for name in REQUIRED_WORKFLOW_NAMES if name not in latest_by_workflow]
    failed = [
        name
        for name, item in latest_by_workflow.items()
        if item.get("status") != "completed" or item.get("conclusion") != "success"
    ]
    latest_success = not missing and not failed
    return [
        _check("recent_actions_runs", "Recent GitHub Actions runs exist", "PASS", f"{len(ordered)} recent workflow run(s) returned"),
        _check(
            "latest_actions_success",
            "Required GitHub Actions workflows passed",
            "PASS" if latest_success else "BLOCKED",
            "Core CI, Governance CI, and macOS App CI latest completed runs succeeded"
            if latest_success
            else "missing workflows: " + ", ".join(missing) + "; failed workflows: " + ", ".join(failed),
            required_workflows=list(REQUIRED_WORKFLOW_NAMES),
            latest_runs={
                name: {
                    "status": item.get("status"),
                    "conclusion": item.get("conclusion"),
                    "created_at": item.get("created_at"),
                }
                for name, item in latest_by_workflow.items()
            },
        ),
    ]


def remote_governance_audit_result(
    root: Path,
    *,
    branch: str | None = None,
    remote: str = DEFAULT_REMOTE,
    recent_runs: int = DEFAULT_RECENT_RUNS,
) -> dict[str, Any]:
    root = root.resolve()
    branch_name = _current_branch(root, branch)
    identity = _repo_identity(root, remote)
    owner, repo = identity if identity else (None, None)
    checks = _local_policy_checks(root)
    blocked_by = [item["id"] for item in checks if item["status"] != "PASS"]
    api_attempted = False

    if not identity:
        checks.extend(
            [
                _check("repository_identity", "GitHub repository is discoverable", "BLOCKED", f"remote {remote!r} is missing or is not a github.com repository"),
                _check("github_authentication", "GitHub CLI authentication is available", "BLOCKED", "repository identity is unavailable"),
            ]
        )
        blocked_by.extend(["repository_identity", "github_authentication"])
    elif shutil.which("gh") is None:
        checks.append(_check("github_cli", "GitHub CLI is installed", "BLOCKED", "gh command is not installed"))
        checks.extend(
            [
                _check("github_authentication", "GitHub CLI authentication is available", "BLOCKED", "cannot authenticate without gh"),
                _check("recent_actions_runs", "Recent GitHub Actions runs exist", "BLOCKED", "cannot query GitHub without gh"),
                _check("branch_protection", "Branch protection is enabled", "BLOCKED", "cannot query GitHub without gh"),
                _check("remote_codeowners", "Remote CODEOWNERS is present", "BLOCKED", "cannot query GitHub without gh"),
            ]
        )
        blocked_by.extend(item["id"] for item in checks if item["status"] != "PASS" and item["id"] not in blocked_by)
    else:
        auth = _github_auth_status(root)
        auth_ok = auth.returncode == 0
        checks.append(
            _check(
                "github_authentication",
                "GitHub CLI authentication is available",
                "PASS" if auth_ok else "BLOCKED",
                "gh authentication is available" if auth_ok else "gh authentication is unavailable or expired",
            )
        )
        if not auth_ok:
            blocked_by.append("github_authentication")
            checks.extend(
                [
                    _check("recent_actions_runs", "Recent GitHub Actions runs exist", "BLOCKED", "cannot query GitHub until gh authentication is available"),
                    _check("latest_actions_success", "Latest GitHub Actions run passed", "BLOCKED", "cannot query GitHub until gh authentication is available"),
                    _check("branch_protection", "Branch protection is enabled", "BLOCKED", "cannot query GitHub until gh authentication is available"),
                    _check("required_status_checks", "Required status checks are configured", "BLOCKED", "cannot query GitHub until gh authentication is available"),
                    _check("required_reviews", "Required pull request reviews are configured", "BLOCKED", "cannot query GitHub until gh authentication is available"),
                    _check("remote_codeowners", "Remote CODEOWNERS is present", "BLOCKED", "cannot query GitHub until gh authentication is available"),
                ]
            )
            blocked_by.extend(item["id"] for item in checks if item["status"] != "PASS" and item["id"] not in blocked_by)
        else:
            api_attempted = True
            repo_path = f"{owner}/{repo}"
            actions_payload, actions_error = _gh_json(
                root,
                f"repos/{repo_path}/actions/runs?branch={quote(branch_name, safe='')}&per_page={max(1, min(recent_runs, 100))}",
            )
            protection_payload, protection_error = _gh_json(
                root,
                f"repos/{repo_path}/branches/{quote(branch_name, safe='')}/protection",
            )
            codeowners_payload, codeowners_error = _gh_json(
                root,
                f"repos/{repo_path}/contents/.github/CODEOWNERS?ref={quote(branch_name, safe='')}",
            )
            checks.extend(
                [
                    _check("recent_actions_runs", "Recent GitHub Actions runs exist", "BLOCKED", actions_error),
                    _check("latest_actions_success", "Latest GitHub Actions run passed", "BLOCKED", "workflow run query failed"),
                ]
                if actions_error
                else _actions_checks(actions_payload)
            )
            checks.extend(
                [
                    _check("branch_protection", "Branch protection is enabled", "BLOCKED", protection_error),
                    _check("required_status_checks", "Required status checks are configured", "BLOCKED", "branch protection query failed"),
                    _check("required_reviews", "Required pull request reviews are configured", "BLOCKED", "branch protection query failed"),
                ]
                if protection_error
                else _branch_protection_checks(protection_payload)
            )
            checks.append(
                _check("remote_codeowners", "Remote CODEOWNERS is present", "BLOCKED", codeowners_error)
                if codeowners_error
                else _remote_codeowners_check(codeowners_payload)
            )
            blocked_by.extend(item["id"] for item in checks if item["status"] != "PASS" and item["id"] not in blocked_by)

    status = "PASS" if not blocked_by else "BLOCKED"
    return {
        "schema_version": 1,
        "mode": "remote_governance_audit",
        "status": status,
        "closes_residual": False,
        "release_gate": "audit_only_does_not_close_v2-dep-004_or_v2-risk-001",
        "repository": {"owner": owner, "name": repo, "remote": remote},
        "branch": branch_name,
        "checks": checks,
        "blocked_by": blocked_by,
        "audit_side_effects": {
            "network_attempted": api_attempted,
            "git_read_attempted": True,
            "file_write_attempted": False,
            "pull_request_created": False,
            "branch_protection_changed": False,
            "workflow_triggered": False,
        },
        "does_not_prove": [
            "qualified independent reviewer completed a review",
            "v2 execution authorization",
            "formal release signing, notarization, or clean-Mac evidence",
            "v2-dep-004 is closed",
            "v2-risk-001 is closed",
        ],
    }


def run_remote_governance_audit(
    root: Path,
    *,
    branch: str | None = None,
    remote: str = DEFAULT_REMOTE,
    recent_runs: int = DEFAULT_RECENT_RUNS,
    json_output: bool = False,
) -> int:
    payload = remote_governance_audit_result(root, branch=branch, remote=remote, recent_runs=recent_runs)
    if json_output:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print(f"remote governance audit: {payload['status']}")
        for check in payload["checks"]:
            print(f"- {check['status']}: {check['title']} ({check['detail']})")
        if payload["blocked_by"]:
            print(f"blocked_by: {', '.join(payload['blocked_by'])}")
    return 0 if payload["status"] == "PASS" else 1
