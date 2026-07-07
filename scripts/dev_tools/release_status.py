"""Read-only formal release status aggregation behind ./dev release status."""

from __future__ import annotations

import json
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence
from urllib.parse import urlparse


FORMAL_RELEASE_TAG = "v0.1.0"
RELEASE_BLOCKING_STATUSES = {"open", "blocked-external", "blocked-decision", "deferred"}
NON_EMPTY = "<non-empty>"
POSITIVE_INTEGER = "<positive-integer>"
NON_PLACEHOLDER = "<non-placeholder>"
GITHUB_HTTPS_URL = "<github-https-url>"
RELEASE_EVIDENCE_RECORDS = {
    "v1-rl-002": {
        "path": "workflow/versions/v1-mvp/evidence/icloud-placeholder-smoke-evidence.md",
        "mode": "icloud_placeholder_smoke_record",
        "release_gate": "blocked_until_real_icloud_download_retry_and_db_evidence_pass",
    },
    "v1-rl-003": {
        "path": "workflow/versions/v1-mvp/evidence/distribution-signing-notarization.md",
        "mode": "distribution_signing_notarization_record",
        "release_gate": "block_if_any_pending_or_blocked",
    },
    "v1-rl-004": {
        "path": "workflow/versions/v1-mvp/evidence/final-tag-release-evidence.md",
        "mode": "final_tag_release_record",
        "release_gate": "block_until_all_release_gates_closed_and_final_tag_pushed",
    },
    "v1-rl-006": {
        "path": "workflow/versions/v1-mvp/evidence/alpha-feedback-route.md",
        "mode": "alpha_feedback_release_decision_record",
        "release_gate": "block_if_any_pending",
    },
    "v1-ref-003-1-task-05": {
        "path": "workflow/versions/v1-mvp/evidence/release-gate-review-task05.md",
        "mode": "release_gate_review_task05_record",
        "release_gate": "deferred_to_formal_release_evidence_review",
    },
}
RELEASE_EVIDENCE_CLOSURE_REQUIREMENTS: dict[str, dict[str, tuple[Any, ...]]] = {
    "v1-rl-002": {
        "status": ("pass", "closed"),
        "metadata_probe.status": ("captured", "pass"),
        "ui_retry.status": ("pass",),
        "ui_retry.result": ("pass",),
        "placeholder_after.downloaded_file_observed": ("pass",),
        "repo_and_db_evidence.repo_file_state": ("pass",),
        "repo_and_db_evidence.db_row_result": ("pass",),
        "repo_and_db_evidence.retry_import_or_conflict_result": ("pass",),
        "user_file_invariants.placeholder_marker_not_silently_deleted": ("pass",),
        "user_file_invariants.original_file_not_deleted": ("pass",),
        "user_file_invariants.conflicted_copy_not_auto_merged": ("pass",),
        "user_file_invariants.no_unrequested_overwrite": ("pass",),
        "user_file_invariants.no_readme_or_areamatrix_overwrite": ("pass",),
    },
    "v1-rl-003": {
        "status": ("pass", "closed"),
        "preflight_json.status": ("PASS",),
        "developer_id_identity.status": ("pass",),
        "notarytool_profile.status": ("pass",),
        "codesign_developer_id_team.status": ("pass",),
        "notarytool_submission.status": ("accepted",),
        "stapler_app.status": ("pass",),
        "formal_dmg.status": ("pass",),
        "formal_dmg.sha256": (NON_EMPTY,),
        "formal_dmg.codesign_status": ("pass",),
        "formal_dmg.notarization_status": ("accepted",),
        "stapler_dmg.status": ("pass",),
        "spctl_assess.status": ("pass",),
        "clean_mac_first_launch.status": ("pass",),
        "clean_mac_first_launch.gatekeeper_result": ("accepted", "pass"),
        "clean_mac_first_launch.first_launch_result": ("pass",),
        "clean_mac_first_launch.repo_selection_or_configured_repo_result": ("pass",),
    },
    "v1-rl-004": {
        "status": ("pass", "closed"),
        "release_candidate.commit": (NON_EMPTY,),
        "release_candidate.status": ("pass",),
        "release_candidate.ci_status": ("pass",),
        "release_candidate.release_checklist_status": ("pass",),
        "required_gates.v1_rl_002_icloud_placeholder.status": ("pass",),
        "required_gates.v1_rl_003_distribution.status": ("pass",),
        "required_gates.v1_rl_006_feedback_route.status": ("pass",),
        "final_tag.created": (True,),
        "final_tag.annotated": (True, "pass"),
        "final_tag.pushed": (True,),
        "formal_release.github_release_url": (NON_EMPTY,),
        "formal_release.artifact_dmg_sha256": (NON_EMPTY,),
        "formal_release.release_notes_path": (NON_EMPTY,),
        "formal_release.notarization_evidence_path": (NON_EMPTY,),
    },
    "v1-rl-006": {
        "schema_version": (1,),
        "release": (FORMAL_RELEASE_TAG,),
        "status": ("pass", "ready", "closed"),
        "alpha_feedback_release_decision.status": ("ready", "pass"),
        "alpha_feedback_release_decision.release_candidate": (FORMAL_RELEASE_TAG,),
        "alpha_feedback_release_decision.trusted_tester_list.status": ("pass",),
        "alpha_feedback_release_decision.trusted_tester_list.source": (NON_PLACEHOLDER,),
        "alpha_feedback_release_decision.trusted_tester_list.tester_count": (POSITIVE_INTEGER,),
        "alpha_feedback_release_decision.announcement.status": ("pass",),
        "alpha_feedback_release_decision.announcement.url": (GITHUB_HTTPS_URL,),
        "alpha_feedback_release_decision.feedback_route.status": ("pass",),
        "alpha_feedback_release_decision.feedback_route.primary": (NON_PLACEHOLDER,),
        "alpha_feedback_release_decision.feedback_route.secondary": (NON_PLACEHOLDER,),
        "alpha_feedback_release_decision.triage_owner.status": ("pass",),
        "alpha_feedback_release_decision.triage_owner.owner": (NON_PLACEHOLDER,),
        "alpha_feedback_release_decision.triage_owner.response_slo": (NON_PLACEHOLDER,),
        "decision_side_effects.testers_invited": (True,),
        "decision_side_effects.announcement_published": (True,),
        "decision_side_effects.feedback_owner_assigned": (True,),
        "decision_side_effects.feedback_route_marked_ready": (True,),
    },
    "v1-ref-003-1-task-05": {
        "status": ("closed", "pass"),
        "release_evidence_review.review_completed": (True,),
        "release_evidence_review.reviewer": (NON_EMPTY,),
        "release_evidence_review.reviewed_at": (NON_EMPTY,),
    },
}
ALPHA_FEEDBACK_TEMPLATE_PATH = ".github/ISSUE_TEMPLATE/alpha_feedback.md"
ALPHA_FEEDBACK_CONFIG_PATH = ".github/ISSUE_TEMPLATE/config.yml"
ALPHA_FEEDBACK_RECORD_PATH = "workflow/versions/v1-mvp/evidence/alpha-feedback-route.md"
FINAL_TAG_RECORD_PATH = "workflow/versions/v1-mvp/evidence/final-tag-release-evidence.md"
FINAL_TAG_SELF_RESIDUAL_ID = "v1-rl-004"
ICLOUD_PLACEHOLDER_RECORD_PATH = "workflow/versions/v1-mvp/evidence/icloud-placeholder-smoke-evidence.md"
ICLOUD_PLACEHOLDER_RESIDUAL_ID = "v1-rl-002"
TASK05_RELEASE_GATE_RECORD_PATH = "workflow/versions/v1-mvp/evidence/release-gate-review-task05.md"
TASK05_RELEASE_GATE_RESIDUAL_ID = "v1-ref-003-1-task-05"


@dataclass(frozen=True)
class ResidualItem:
    id: str
    status: str
    type: str
    title: str
    source: str
    current_impact: str
    executable_task: bool

    @property
    def blocks_formal_alpha(self) -> bool:
        return self.status in RELEASE_BLOCKING_STATUSES and self.current_impact == "formal-alpha-blocked"

    def as_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "status": self.status,
            "type": self.type,
            "title": self.title,
            "source": self.source,
            "current_impact": self.current_impact,
            "executable_task": self.executable_task,
            "blocks_formal_alpha": self.blocks_formal_alpha,
        }


def _yaml_scalar(value: str) -> Any:
    raw = value.strip()
    if raw in {"", "null"}:
        return None
    if raw in {"true", "false"}:
        return raw == "true"
    if raw.startswith('"') and raw.endswith('"') and len(raw) >= 2:
        return raw[1:-1]
    if re.fullmatch(r"\d+", raw):
        return int(raw)
    return raw


def _read_yaml_section_scalars(path: Path, section: str) -> dict[str, Any]:
    result: dict[str, Any] = {}
    in_section = False
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if not raw_line.startswith(" ") and stripped.endswith(":"):
            if in_section:
                break
            in_section = stripped == f"{section}:"
            continue
        if not in_section:
            continue
        match = re.match(r"\s{2}([A-Za-z0-9_]+):\s*(.*)$", raw_line)
        if match:
            result[match.group(1)] = _yaml_scalar(match.group(2))
    return result


def _read_yaml_items(path: Path) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    in_items = False
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if not raw_line.startswith(" ") and stripped.endswith(":"):
            if in_items:
                break
            in_items = stripped == "items:"
            continue
        if not in_items:
            continue
        if raw_line.startswith("  - "):
            if current:
                items.append(current)
            current = {}
            key_value = raw_line[4:].strip()
        elif current is not None and raw_line.startswith("    "):
            key_value = stripped
        else:
            continue
        if ":" in key_value and not key_value.startswith("- "):
            key, value = key_value.split(":", 1)
            if value.strip():
                current[key.strip()] = _yaml_scalar(value)
    if current:
        items.append(current)
    return items


def _first_yaml_block(path: Path) -> str | None:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"```yaml\n(.*?)\n```", text, flags=re.DOTALL)
    return match.group(1) if match else None


def _read_yaml_block_scalars(block: str) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for raw_line in block.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#") or raw_line.startswith(" "):
            continue
        if ":" not in stripped:
            continue
        key, value = stripped.split(":", 1)
        if value.strip():
            result[key.strip()] = _yaml_scalar(value)
    return result


def _read_yaml_block_flat_scalars(block: str) -> dict[str, Any]:
    result: dict[str, Any] = {}
    stack: list[tuple[int, str]] = []
    for raw_line in block.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("- ") or ":" not in stripped:
            continue
        indent = len(raw_line) - len(raw_line.lstrip(" "))
        while stack and stack[-1][0] >= indent:
            stack.pop()
        key, value = stripped.split(":", 1)
        path = ".".join([*[part for _, part in stack], key.strip()])
        if value.strip():
            result[path] = _yaml_scalar(value)
        else:
            stack.append((indent, key.strip()))
    return result


PLACEHOLDER_TEXT_VALUES = {
    "example",
    "example.invalid",
    "example.com",
    "placeholder",
    "pending",
    "blocked",
    "todo",
    "tbd",
    "n/a",
    "na",
    "none",
    "null",
    "release-owner",
    "release-owner-email",
    "release-owner-approved-list",
}


def _is_non_placeholder_text(actual: Any) -> bool:
    if not isinstance(actual, str):
        return False
    value = actual.strip()
    if not value or value.startswith("<") or value.endswith(">"):
        return False
    normalized = value.lower()
    if normalized in PLACEHOLDER_TEXT_VALUES:
        return False
    if normalized.endswith(".invalid") or "example.invalid" in normalized:
        return False
    return True


def _is_github_https_url(actual: Any) -> bool:
    if not isinstance(actual, str) or not _is_non_placeholder_text(actual):
        return False
    parsed = urlparse(actual.strip())
    return parsed.scheme == "https" and parsed.netloc == "github.com" and bool(parsed.path.strip("/"))


def _is_positive_integer(actual: Any) -> bool:
    if isinstance(actual, bool):
        return False
    if isinstance(actual, int):
        return actual > 0
    if isinstance(actual, str):
        return re.fullmatch(r"[1-9]\d*", actual) is not None
    return False


def _value_matches(actual: Any, allowed: tuple[Any, ...]) -> bool:
    if GITHUB_HTTPS_URL in allowed:
        return _is_github_https_url(actual)
    if NON_PLACEHOLDER in allowed:
        return _is_non_placeholder_text(actual)
    if POSITIVE_INTEGER in allowed:
        return _is_positive_integer(actual)
    if NON_EMPTY in allowed:
        return actual not in {None, "", "null", "pending", "blocked", "fail"}
    return actual in allowed


def _version_residual_sources(global_residuals: Path) -> list[str]:
    sources: list[str] = []
    in_section = False
    for raw_line in global_residuals.read_text(encoding="utf-8").splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if not raw_line.startswith(" ") and stripped.endswith(":"):
            if in_section:
                break
            in_section = stripped == "version_residuals:"
            continue
        if in_section:
            match = re.match(r"\s{4}source:\s*(.+)$", raw_line)
            if match:
                sources.append(str(_yaml_scalar(match.group(1))))
    return sources


def _load_residual_items(root: Path) -> list[ResidualItem]:
    global_residuals = root / "workflow/residuals/residuals.yaml"
    item_dicts = list(_read_yaml_items(global_residuals))
    for source in _version_residual_sources(global_residuals):
        item_dicts.extend(_read_yaml_items(root / source))
    return [
        ResidualItem(
            id=str(item.get("id", "")),
            status=str(item.get("status", "")),
            type=str(item.get("type", "")),
            title=str(item.get("title", "")),
            source=str(item.get("source", "")),
            current_impact=str(item.get("current_impact", "")),
            executable_task=bool(item.get("executable_task", False)),
        )
        for item in item_dicts
    ]


def _git_lines(root: Path, args: Sequence[str]) -> tuple[int, str]:
    proc = subprocess.run(
        ["git", *args],
        cwd=root,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return proc.returncode, proc.stdout or ""


def _remote_tags_from_ls_remote(output: str) -> list[str]:
    tags: set[str] = set()
    for line in output.splitlines():
        fields = line.split()
        if len(fields) < 2 or not fields[1].startswith("refs/tags/"):
            continue
        tag = fields[1].removeprefix("refs/tags/").removesuffix("^{}")
        tags.add(tag)
    return sorted(tags)


def _tag_status(root: Path, release_tag: str, *, include_remote: bool) -> dict[str, Any]:
    local_code, local_output = _git_lines(root, ["tag", "--list", f"{release_tag}*"])
    local_tags = sorted(line.strip() for line in local_output.splitlines() if line.strip()) if local_code == 0 else []
    result: dict[str, Any] = {
        "formal_tag": release_tag,
        "local_query_status": "pass" if local_code == 0 else "blocked",
        "local_query_exit_code": local_code,
        "local_exists": release_tag in local_tags,
        "local_preview_tags": [tag for tag in local_tags if tag != release_tag],
        "remote_checked": include_remote,
        "remote_query_status": "not_checked",
        "remote_exists": None,
        "remote_preview_tags": [],
    }
    if include_remote:
        remote_code, remote_output = _git_lines(root, ["ls-remote", "--tags", "origin", f"refs/tags/{release_tag}*"])
        remote_tags = _remote_tags_from_ls_remote(remote_output) if remote_code == 0 else []
        result.update(
            {
                "remote_query_status": "pass" if remote_code == 0 else "blocked",
                "remote_query_exit_code": remote_code,
                "remote_exists": release_tag in remote_tags,
                "remote_preview_tags": [tag for tag in remote_tags if tag != release_tag],
            }
        )
    return result


def _release_workflow_status(root: Path) -> dict[str, Any]:
    workflows_dir = root / ".github/workflows"
    candidates = sorted([*workflows_dir.glob("*.yml"), *workflows_dir.glob("*.yaml")]) if workflows_dir.is_dir() else []
    release_paths: list[str] = []
    for path in candidates:
        text = path.read_text(encoding="utf-8", errors="replace").lower()
        name = path.name.lower()
        name_match = any(token in name for token in ("release", "notar", "distribution"))
        content_match = any(token in text for token in ("notarytool", "xcrun stapler", "developer id application"))
        if name_match or content_match:
            release_paths.append(str(path.relative_to(root)))
    return {
        "exists": bool(release_paths),
        "paths": release_paths,
        "checked": [str(path.relative_to(root)) for path in candidates],
    }


def release_status_result(root: Path, *, include_remote: bool = False) -> dict[str, Any]:
    root = root.resolve()
    version_residuals = root / "workflow/versions/v1-mvp/residuals/residuals.yaml"
    version_status = _read_yaml_section_scalars(version_residuals, "version_status")
    residuals = _load_residual_items(root)
    release_blockers = [item for item in residuals if item.blocks_formal_alpha]
    non_current = [item for item in residuals if not item.blocks_formal_alpha]
    tag = _tag_status(root, FORMAL_RELEASE_TAG, include_remote=include_remote)
    evidence_audit = release_evidence_audit_result(root)
    residual_blocked_by = [f"residual:{item.id}" for item in release_blockers]
    tag_blocked_by: list[str] = []
    if not tag["local_exists"]:
        tag_blocked_by.append(f"formal_tag_local_missing:{FORMAL_RELEASE_TAG}")
    if include_remote and not tag["remote_exists"]:
        tag_blocked_by.append(f"formal_tag_remote_missing:{FORMAL_RELEASE_TAG}")
    residual_evidence_status = "PASS" if not residual_blocked_by else "BLOCKED"
    tag_status = "PASS" if not tag_blocked_by else "BLOCKED"
    formal_alpha_status = version_status.get("formal_alpha")
    index_consistency_blocked_by: list[str] = []
    if residual_evidence_status == "PASS" and formal_alpha_status == "blocked":
        index_consistency_blocked_by.append("formal_alpha_status_blocked_without_release_blockers")
    if residual_evidence_status == "BLOCKED" and formal_alpha_status != "blocked":
        index_consistency_blocked_by.append("formal_alpha_status_not_blocked_with_release_blockers")
    index_consistency_status = "PASS" if not index_consistency_blocked_by else "BLOCKED"
    evidence_audit_blocked_by = [
        f"release_evidence_audit:{item}" for item in evidence_audit["blocked_by"]
    ]
    blocked_by = [
        *residual_blocked_by,
        *tag_blocked_by,
        *index_consistency_blocked_by,
        *evidence_audit_blocked_by,
    ]
    status = "PASS" if not blocked_by else "BLOCKED"
    return {
        "schema_version": 1,
        "mode": "release_status",
        "release": FORMAL_RELEASE_TAG,
        "status": status,
        "closes_residual": False,
        "release_gate": "block_if_any_release_residual_open_or_formal_tag_missing",
        "technical_queue": {
            "status": version_status.get("technical_queue"),
            "task_count": version_status.get("task_count"),
            "source": "workflow/versions/v1-mvp/residuals/residuals.yaml",
        },
        "formal_alpha": {
            "status": formal_alpha_status,
            "release_blocker_policy": version_status.get("release_blocker_policy"),
        },
        "index_consistency_gate": {
            "status": index_consistency_status,
            "blocked_by": index_consistency_blocked_by,
        },
        "residual_evidence_gate": {
            "status": residual_evidence_status,
            "blocked_by": residual_blocked_by,
            "required_before_formal_tag": True,
            "does_not_require_formal_tag_to_exist": True,
        },
        "formal_tag_gate": {
            "status": tag_status,
            "blocked_by": tag_blocked_by,
            "required_after_residual_evidence_gate_passes": True,
        },
        "release_evidence_audit_gate": {
            "status": evidence_audit["status"],
            "command": "./dev release evidence-audit --json",
            "blocked_by": evidence_audit_blocked_by,
            "records_checked": len(evidence_audit["records"]),
            "closes_residual": False,
        },
        "release_blockers": [item.as_dict() for item in release_blockers],
        "indexed_non_current_residuals": [item.as_dict() for item in non_current],
        "tag": tag,
        "release_workflow": _release_workflow_status(root),
        "preflight": {
            "command": "./dev release preflight --json",
            "run": False,
            "status": "not_run",
            "evidence_template_available": True,
        },
        "blocked_by": blocked_by,
        "does_not_prove": [
            "Developer ID signed app",
            "notarized or stapled app",
            "formal notarized DMG",
            "clean Mac first launch",
            "formal v0.1.0 release readiness",
            "any residual is closed",
        ],
        "next_required_evidence": [
            "Real iCloud placeholder Download & retry smoke with DB and user-file invariant evidence",
            "Developer ID signing, accepted notarization, stapled app and DMG, "
            "formal checksum, spctl, clean Mac evidence",
            "Trusted tester list, announcement or Discussion link, feedback route, and triage owner",
            "Fresh formal release evidence review for 3-1/task-05 without backfilling task-loop evidence",
            "Formal release candidate commit and annotated v0.1.0 tag push after gates close",
        ],
    }


def release_evidence_audit_result(root: Path) -> dict[str, Any]:
    root = root.resolve()
    residuals = {item.id: item for item in _load_residual_items(root)}
    records: list[dict[str, Any]] = []
    blocked_by: list[str] = []

    for residual_id, spec in RELEASE_EVIDENCE_RECORDS.items():
        relative_path = str(spec["path"])
        path = root / relative_path
        checks: list[dict[str, Any]] = []
        record = {
            "residual_id": residual_id,
            "path": relative_path,
            "mode": None,
            "status": "missing",
            "closes_residual": None,
            "release_gate": None,
            "residual_status": None,
            "residual_blocks_formal_alpha": None,
            "checks": checks,
        }
        records.append(record)

        item = residuals.get(residual_id)
        if item is None:
            checks.append({"name": "residual_index_present", "status": "BLOCKED"})
            blocked_by.append(f"{residual_id}:residual_index_missing")
            continue
        record["residual_status"] = item.status
        record["residual_blocks_formal_alpha"] = item.blocks_formal_alpha
        checks.append({"name": "residual_index_present", "status": "PASS"})

        if not path.is_file():
            checks.append({"name": "evidence_file_present", "status": "BLOCKED"})
            blocked_by.append(f"{residual_id}:evidence_file_missing")
            continue
        checks.append({"name": "evidence_file_present", "status": "PASS"})

        block = _first_yaml_block(path)
        if block is None:
            checks.append({"name": "yaml_record_present", "status": "BLOCKED"})
            blocked_by.append(f"{residual_id}:yaml_record_missing")
            continue
        checks.append({"name": "yaml_record_present", "status": "PASS"})

        scalars = _read_yaml_block_scalars(block)
        flat_scalars = _read_yaml_block_flat_scalars(block)
        record["mode"] = scalars.get("mode")
        record["status"] = scalars.get("status")
        record["closes_residual"] = scalars.get("closes_residual")
        record["release_gate"] = scalars.get("release_gate")

        expected = {
            "residual_id": residual_id,
            "mode": spec["mode"],
            "release_gate": spec["release_gate"],
        }
        for field, expected_value in expected.items():
            actual = scalars.get(field)
            check_status = "PASS" if actual == expected_value else "BLOCKED"
            checks.append(
                {
                    "name": f"{field}_matches",
                    "status": check_status,
                    "expected": expected_value,
                    "actual": actual,
                }
            )
            if check_status == "BLOCKED":
                blocked_by.append(f"{residual_id}:{field}_mismatch")

        closes_residual = scalars.get("closes_residual")
        if item.blocks_formal_alpha and closes_residual is not False:
            checks.append({"name": "blocking_residual_keeps_closes_false", "status": "BLOCKED"})
            blocked_by.append(f"{residual_id}:blocking_residual_closes_true")
        else:
            checks.append({"name": "blocking_residual_keeps_closes_false", "status": "PASS"})

        if item.status == "closed" and closes_residual is not True:
            checks.append({"name": "closed_residual_has_closure_record", "status": "BLOCKED"})
            blocked_by.append(f"{residual_id}:closed_residual_missing_closure_record")
        else:
            checks.append({"name": "closed_residual_has_closure_record", "status": "PASS"})

        missing_or_blocked_fields: list[dict[str, Any]] = []
        if item.status == "closed":
            for field, allowed in RELEASE_EVIDENCE_CLOSURE_REQUIREMENTS[residual_id].items():
                actual = flat_scalars.get(field)
                if not _value_matches(actual, allowed):
                    missing_or_blocked_fields.append(
                        {
                            "field": field,
                            "expected": list(allowed),
                            "actual": actual,
                        }
                    )
        if missing_or_blocked_fields:
            checks.append(
                {
                    "name": "closed_residual_required_fields_complete",
                    "status": "BLOCKED",
                    "fields": missing_or_blocked_fields,
                }
            )
            blocked_by.append(f"{residual_id}:closed_residual_required_fields_incomplete")
        else:
            checks.append({"name": "closed_residual_required_fields_complete", "status": "PASS"})

    status = "PASS" if not blocked_by else "BLOCKED"
    return {
        "schema_version": 1,
        "mode": "release_evidence_audit",
        "status": status,
        "closes_residual": False,
        "release_gate": "audit_only_does_not_prove_release_readiness",
        "records": records,
        "blocked_by": blocked_by,
        "does_not_prove": [
            "any residual is closed",
            "Developer ID signed app",
            "notarized or stapled app",
            "clean Mac first launch",
            "formal v0.1.0 release readiness",
        ],
    }


def _text_check(text: str, needle: str) -> dict[str, Any]:
    return {
        "needle": needle,
        "status": "PASS" if needle in text else "BLOCKED",
    }


def _entrypoint_status(checks: Sequence[dict[str, Any]]) -> str:
    return "PASS" if all(check["status"] == "PASS" for check in checks) else "BLOCKED"


def _alpha_feedback_entrypoints(root: Path) -> dict[str, Any]:
    template_path = root / ALPHA_FEEDBACK_TEMPLATE_PATH
    template_text = template_path.read_text(encoding="utf-8") if template_path.is_file() else ""
    template_checks = [
        _text_check(template_text, "labels: [\"alpha-feedback\", \"needs-triage\"]"),
        _text_check(template_text, "## 测试版本 / Build"),
        _text_check(template_text, "DMG SHA-256"),
        _text_check(template_text, "## 测试环境 / Environment"),
        _text_check(template_text, "Clean user or clean Mac"),
        _text_check(template_text, "In iCloud Drive"),
        _text_check(template_text, "## 数据安全确认 / Data Safety Check"),
        _text_check(template_text, "用户文件"),
        _text_check(template_text, ".areamatrix/"),
    ]

    config_path = root / ALPHA_FEEDBACK_CONFIG_PATH
    config_text = config_path.read_text(encoding="utf-8") if config_path.is_file() else ""
    config_checks = [
        _text_check(config_text, "discussions/categories/q-a"),
        _text_check(config_text, "discussions/categories/ideas"),
        _text_check(config_text, "security/advisories/new"),
    ]

    return {
        "issue_template": {
            "path": ALPHA_FEEDBACK_TEMPLATE_PATH,
            "status": "PASS" if template_path.is_file() and _entrypoint_status(template_checks) == "PASS" else "BLOCKED",
            "exists": template_path.is_file(),
            "checks": template_checks,
        },
        "discussion_links": {
            "path": ALPHA_FEEDBACK_CONFIG_PATH,
            "status": "PASS" if config_path.is_file() and _entrypoint_status(config_checks) == "PASS" else "BLOCKED",
            "exists": config_path.is_file(),
            "checks": config_checks,
        },
    }


def _alpha_feedback_decision_field_checks(flat_scalars: dict[str, Any]) -> list[dict[str, Any]]:
    required: list[tuple[str, tuple[Any, ...], str]] = [
        ("schema_version", (1,), "schema version is not 1"),
        ("release", (FORMAL_RELEASE_TAG,), "release is not v0.1.0"),
        ("status", ("pass", "ready", "closed"), "top-level record status is not ready/pass/closed"),
        ("alpha_feedback_release_decision.status", ("ready", "pass"), "release decision status is pending"),
        (
            "alpha_feedback_release_decision.release_candidate",
            (FORMAL_RELEASE_TAG,),
            "release candidate is not v0.1.0",
        ),
        ("alpha_feedback_release_decision.trusted_tester_list.status", ("pass",), "trusted tester list is pending"),
        (
            "alpha_feedback_release_decision.trusted_tester_list.source",
            (NON_PLACEHOLDER,),
            "trusted tester source is missing or placeholder-like",
        ),
        (
            "alpha_feedback_release_decision.trusted_tester_list.tester_count",
            (POSITIVE_INTEGER,),
            "trusted tester count must be a positive integer",
        ),
        ("alpha_feedback_release_decision.announcement.status", ("pass",), "announcement or Discussion is pending"),
        (
            "alpha_feedback_release_decision.announcement.url",
            (GITHUB_HTTPS_URL,),
            "announcement URL must be a non-placeholder GitHub HTTPS URL",
        ),
        ("alpha_feedback_release_decision.feedback_route.status", ("pass",), "feedback route decision is pending"),
        (
            "alpha_feedback_release_decision.feedback_route.primary",
            (NON_PLACEHOLDER,),
            "primary feedback route is missing or placeholder-like",
        ),
        (
            "alpha_feedback_release_decision.feedback_route.secondary",
            (NON_PLACEHOLDER,),
            "secondary feedback route is missing or placeholder-like",
        ),
        ("alpha_feedback_release_decision.triage_owner.status", ("pass",), "triage owner status is pending"),
        (
            "alpha_feedback_release_decision.triage_owner.owner",
            (NON_PLACEHOLDER,),
            "triage owner is missing or placeholder-like",
        ),
        (
            "alpha_feedback_release_decision.triage_owner.response_slo",
            (NON_PLACEHOLDER,),
            "triage response SLO is missing or placeholder-like",
        ),
        ("decision_side_effects.testers_invited", (True,), "trusted testers have not been invited"),
        ("decision_side_effects.announcement_published", (True,), "announcement has not been published"),
        ("decision_side_effects.feedback_owner_assigned", (True,), "feedback owner has not been assigned"),
        ("decision_side_effects.feedback_route_marked_ready", (True,), "feedback route has not been marked ready"),
    ]
    checks: list[dict[str, Any]] = []
    for field, allowed, reason in required:
        actual = flat_scalars.get(field)
        status = "PASS" if _value_matches(actual, allowed) else "BLOCKED"
        checks.append(
            {
                "field": field,
                "status": status,
                "actual": actual,
                "expected": list(allowed),
                "reason": None if status == "PASS" else reason,
            }
        )
    return checks


def _final_tag_prerequisite_checks(flat_scalars: dict[str, Any]) -> list[dict[str, Any]]:
    required: list[tuple[str, tuple[Any, ...], str]] = [
        ("status", ("ready", "pass"), "final tag record status is not ready/pass"),
        ("release_candidate.commit", (NON_EMPTY,), "release candidate commit is missing"),
        ("release_candidate.status", ("pass",), "release candidate status is pending"),
        ("release_candidate.ci_status", ("pass",), "release candidate CI status is pending"),
        ("release_candidate.release_checklist_status", ("pass",), "release checklist is not pass"),
        ("required_gates.v1_rl_002_icloud_placeholder.status", ("pass",), "iCloud placeholder gate is not pass"),
        ("required_gates.v1_rl_003_distribution.status", ("pass",), "distribution gate is not pass"),
        ("required_gates.v1_rl_006_feedback_route.status", ("pass",), "feedback route gate is not pass"),
        ("final_tag.name", (FORMAL_RELEASE_TAG,), "formal tag name is not v0.1.0"),
        ("final_tag.created", (False,), "formal tag has already been created or is not false"),
        ("final_tag.pushed", (False,), "formal tag has already been pushed or is not false"),
    ]
    checks: list[dict[str, Any]] = []
    for field, allowed, reason in required:
        actual = flat_scalars.get(field)
        status = "PASS" if _value_matches(actual, allowed) else "BLOCKED"
        checks.append(
            {
                "field": field,
                "status": status,
                "actual": actual,
                "expected": list(allowed),
                "reason": None if status == "PASS" else reason,
            }
        )
    return checks


def _icloud_placeholder_smoke_field_checks(flat_scalars: dict[str, Any]) -> list[dict[str, Any]]:
    required: list[tuple[str, tuple[Any, ...], str]] = [
        ("status", ("pass", "ready"), "top-level smoke record status is not pass/ready"),
        ("metadata_probe.status", ("captured", "pass"), "metadata probe has not been captured"),
        ("metadata_probe.mode", ("icloud_placeholder_metadata_probe",), "metadata probe mode is missing"),
        ("metadata_probe.closes_residual", (False,), "metadata probe must not close the residual"),
        ("metadata_probe.privacy.path_redaction", (True,), "metadata probe path redaction is not true"),
        ("metadata_probe.privacy.raw_path_fields_present", (False,), "raw path fields are present"),
        ("metadata_probe.side_effects.download_attempted", (False,), "metadata probe attempted a download"),
        (
            "metadata_probe.side_effects.file_content_read_attempted",
            (False,),
            "metadata probe attempted to read file content",
        ),
        ("metadata_probe.side_effects.file_write_attempted", (False,), "metadata probe attempted a file write"),
        ("metadata_probe.side_effects.db_write_attempted", (False,), "metadata probe attempted a DB write"),
        ("metadata_probe.side_effects.project_write_attempted", (False,), "metadata probe attempted a project write"),
        (
            "metadata_probe.side_effects.areamatrix_metadata_write_attempted",
            (False,),
            "metadata probe attempted an .areamatrix metadata write",
        ),
        ("environment.macos_version", (NON_EMPTY,), "macOS version is missing"),
        ("environment.icloud_drive", ("enabled",), "iCloud Drive is not enabled"),
        ("environment.icloud_account", ("signed_in",), "iCloud account is not signed in"),
        ("environment.app_build", (NON_EMPTY,), "app build is missing"),
        ("environment.repo_path", (NON_EMPTY,), "redacted repo path or evidence reference is missing"),
        ("environment.source_path", (NON_EMPTY,), "redacted source path or evidence reference is missing"),
        ("placeholder_before.mdls_downloading_status", (NON_EMPTY,), "before mdls downloading status is missing"),
        ("placeholder_before.mdls_is_downloaded", (NON_EMPTY,), "before mdls downloaded status is missing"),
        ("placeholder_before.finder_or_screenshot_ref", (NON_EMPTY,), "before screenshot or Finder evidence is missing"),
        ("ui_retry.status", ("pass",), "UI retry status is not pass"),
        ("ui_retry.action", ("Download & retry",), "UI action is not Download & retry"),
        ("ui_retry.result", ("pass",), "UI retry result is not pass"),
        ("placeholder_after.mdls_downloading_status", (NON_EMPTY,), "after mdls downloading status is missing"),
        ("placeholder_after.mdls_is_downloaded", (NON_EMPTY,), "after mdls downloaded status is missing"),
        ("placeholder_after.downloaded_file_observed", ("pass",), "downloaded file was not observed"),
        ("repo_and_db_evidence.repo_file_state", ("pass",), "repo file state is not pass"),
        ("repo_and_db_evidence.db_row_query", (NON_EMPTY,), "DB row query evidence is missing"),
        ("repo_and_db_evidence.db_row_result", ("pass",), "DB row result is not pass"),
        ("repo_and_db_evidence.retry_import_or_conflict_result", ("pass",), "retry import/conflict result is not pass"),
        (
            "user_file_invariants.placeholder_marker_not_silently_deleted",
            ("pass",),
            "placeholder marker invariant is not pass",
        ),
        ("user_file_invariants.original_file_not_deleted", ("pass",), "original file invariant is not pass"),
        (
            "user_file_invariants.conflicted_copy_not_auto_merged",
            ("pass",),
            "conflicted copy invariant is not pass",
        ),
        ("user_file_invariants.no_unrequested_overwrite", ("pass",), "no-overwrite invariant is not pass"),
        (
            "user_file_invariants.no_readme_or_areamatrix_overwrite",
            ("pass",),
            "README/AREAMATRIX overwrite invariant is not pass",
        ),
    ]
    checks: list[dict[str, Any]] = []
    for field, allowed, reason in required:
        actual = flat_scalars.get(field)
        status = "PASS" if _value_matches(actual, allowed) else "BLOCKED"
        checks.append(
            {
                "field": field,
                "status": status,
                "actual": actual,
                "expected": list(allowed),
                "reason": None if status == "PASS" else reason,
            }
        )
    return checks


def _task05_release_review_field_checks(flat_scalars: dict[str, Any]) -> list[dict[str, Any]]:
    required: list[tuple[str, tuple[Any, ...], str]] = [
        ("status", ("ready", "pass", "closed"), "top-level release review record is not ready/pass/closed"),
        (
            "release_evidence_review.source_checklist",
            ("workflow/versions/v1-mvp/evidence/release-checklist.md",),
            "source checklist path is not the release checklist",
        ),
        (
            "release_evidence_review.source_notes",
            ("workflow/versions/v1-mvp/evidence/release-notes/release-notes-0.1.0.md",),
            "source release notes path is not the v0.1.0 release notes",
        ),
        (
            "release_evidence_review.close_condition",
            ("handle through fresh formal release evidence review without fabricating task-loop evidence",),
            "close condition does not preserve the fresh-review/no-backfill boundary",
        ),
        ("release_evidence_review.review_completed", (True,), "fresh release evidence review is not complete"),
        ("release_evidence_review.reviewer", (NON_EMPTY,), "reviewer is missing"),
        ("release_evidence_review.reviewed_at", (NON_EMPTY,), "review timestamp is missing"),
    ]
    checks: list[dict[str, Any]] = []
    for field, allowed, reason in required:
        actual = flat_scalars.get(field)
        status = "PASS" if _value_matches(actual, allowed) else "BLOCKED"
        checks.append(
            {
                "field": field,
                "status": status,
                "actual": actual,
                "expected": list(allowed),
                "reason": None if status == "PASS" else reason,
            }
        )
    return checks


def _task05_task_loop_boundary_checks(flat_scalars: dict[str, Any]) -> list[dict[str, Any]]:
    required: list[tuple[str, tuple[Any, ...], str]] = [
        (
            "task_loop_evidence.completed_task_loop_run_id",
            (None,),
            "completed task-loop run id must remain null; do not fabricate a run",
        ),
        (
            "task_loop_evidence.verify_result_pass",
            (False,),
            "task-loop VERIFY_RESULT PASS must remain false unless real archived evidence exists",
        ),
        (
            "task_loop_evidence.copy_log_archived",
            (False,),
            "copy log must not be marked archived without real archived evidence",
        ),
        (
            "task_loop_evidence.verify_log_archived",
            (False,),
            "verify log must not be marked archived without real archived evidence",
        ),
        (
            "task_loop_evidence.tracked_incomplete_summaries_excluded_from_pass",
            (5,),
            "tracked incomplete summaries count must remain excluded from PASS evidence",
        ),
    ]
    checks: list[dict[str, Any]] = []
    for field, allowed, reason in required:
        actual = flat_scalars.get(field)
        status = "PASS" if _value_matches(actual, allowed) else "BLOCKED"
        checks.append(
            {
                "field": field,
                "status": status,
                "actual": actual,
                "expected": list(allowed),
                "reason": None if status == "PASS" else reason,
            }
        )
    return checks


def _task05_forbidden_repair_checks(flat_scalars: dict[str, Any]) -> list[dict[str, Any]]:
    required: list[tuple[str, tuple[Any, ...], str]] = [
        ("forbidden_repair.progress_json_rewrite_attempted", (False,), "progress.json rewrite was attempted"),
        ("forbidden_repair.task_loop_log_rewrite_attempted", (False,), "task-loop log rewrite was attempted"),
        ("forbidden_repair.run_summary_rewrite_attempted", (False,), "run summary rewrite was attempted"),
        (
            "forbidden_repair.git_checkpoint_backfill_attempted",
            (False,),
            "git checkpoint backfill was attempted",
        ),
        ("forbidden_repair.tag_or_release_created", (False,), "tag or release was created"),
    ]
    checks: list[dict[str, Any]] = []
    for field, allowed, reason in required:
        actual = flat_scalars.get(field)
        status = "PASS" if _value_matches(actual, allowed) else "BLOCKED"
        checks.append(
            {
                "field": field,
                "status": status,
                "actual": actual,
                "expected": list(allowed),
                "reason": None if status == "PASS" else reason,
            }
        )
    return checks


def task05_release_review_audit_result(root: Path) -> dict[str, Any]:
    root = root.resolve()
    evidence_path = root / TASK05_RELEASE_GATE_RECORD_PATH
    residuals = {item.id: item for item in _load_residual_items(root)}
    residual = residuals.get(TASK05_RELEASE_GATE_RESIDUAL_ID)
    record_checks: list[dict[str, Any]] = []
    flat_scalars: dict[str, Any] = {}
    scalars: dict[str, Any] = {}

    if not evidence_path.is_file():
        record_checks.append({"name": "evidence_file_present", "status": "BLOCKED"})
    else:
        record_checks.append({"name": "evidence_file_present", "status": "PASS"})
        block = _first_yaml_block(evidence_path)
        if block is None:
            record_checks.append({"name": "yaml_record_present", "status": "BLOCKED"})
        else:
            record_checks.append({"name": "yaml_record_present", "status": "PASS"})
            scalars = _read_yaml_block_scalars(block)
            flat_scalars = _read_yaml_block_flat_scalars(block)
            expected = {
                "residual_id": TASK05_RELEASE_GATE_RESIDUAL_ID,
                "task_label": "3-1/task-05",
                "mode": "release_gate_review_task05_record",
                "release_gate": "deferred_to_formal_release_evidence_review",
            }
            for field, expected_value in expected.items():
                actual = scalars.get(field)
                record_checks.append(
                    {
                        "name": f"{field}_matches",
                        "status": "PASS" if actual == expected_value else "BLOCKED",
                        "expected": expected_value,
                        "actual": actual,
                    }
                )
            record_checks.append(
                {
                    "name": "audit_record_keeps_closes_false",
                    "status": "PASS" if scalars.get("closes_residual") is False else "BLOCKED",
                    "actual": scalars.get("closes_residual"),
                }
            )

    review_checks = _task05_release_review_field_checks(flat_scalars)
    task_loop_checks = _task05_task_loop_boundary_checks(flat_scalars)
    forbidden_checks = _task05_forbidden_repair_checks(flat_scalars)
    blocked_by = [
        f"record:{check['name']}"
        for check in record_checks
        if check["status"] == "BLOCKED"
    ]
    blocked_by.extend(f"review:{check['field']}" for check in review_checks if check["status"] == "BLOCKED")
    blocked_by.extend(
        f"task_loop_boundary:{check['field']}"
        for check in task_loop_checks
        if check["status"] == "BLOCKED"
    )
    blocked_by.extend(
        f"forbidden_repair:{check['field']}"
        for check in forbidden_checks
        if check["status"] == "BLOCKED"
    )
    status = "PASS" if not blocked_by else "BLOCKED"

    return {
        "schema_version": 1,
        "mode": "task05_release_review_audit",
        "residual_id": TASK05_RELEASE_GATE_RESIDUAL_ID,
        "release": FORMAL_RELEASE_TAG,
        "task_label": "3-1/task-05",
        "status": status,
        "closes_residual": False,
        "release_gate": "audit_only_block_until_fresh_release_evidence_review_ready",
        "record": {
            "path": TASK05_RELEASE_GATE_RECORD_PATH,
            "status": scalars.get("status", "missing"),
            "mode": scalars.get("mode"),
            "release_gate": scalars.get("release_gate"),
            "closes_residual": scalars.get("closes_residual"),
            "checks": record_checks,
        },
        "residual": residual.as_dict() if residual else None,
        "release_evidence_review_gate": {
            "status": "PASS" if all(check["status"] == "PASS" for check in review_checks) else "BLOCKED",
            "checks": review_checks,
        },
        "task_loop_boundary_gate": {
            "status": "PASS" if all(check["status"] == "PASS" for check in task_loop_checks) else "BLOCKED",
            "checks": task_loop_checks,
        },
        "forbidden_repair_gate": {
            "status": "PASS" if all(check["status"] == "PASS" for check in forbidden_checks) else "BLOCKED",
            "checks": forbidden_checks,
        },
        "blocked_by": blocked_by,
        "review_record_template": {
            "command": "./dev release task05-release-review-audit --json",
            "fill_in": [
                "release_evidence_review.review_completed",
                "release_evidence_review.reviewer",
                "release_evidence_review.reviewed_at",
            ],
            "must_remain_false_or_null": [
                "task_loop_evidence.completed_task_loop_run_id",
                "task_loop_evidence.verify_result_pass",
                "task_loop_evidence.copy_log_archived",
                "task_loop_evidence.verify_log_archived",
                "forbidden_repair.progress_json_rewrite_attempted",
                "forbidden_repair.task_loop_log_rewrite_attempted",
                "forbidden_repair.run_summary_rewrite_attempted",
                "forbidden_repair.git_checkpoint_backfill_attempted",
                "forbidden_repair.tag_or_release_created",
                "closes_residual",
            ],
        },
        "audit_side_effects": {
            "progress_json_rewritten": False,
            "task_loop_logs_rewritten": False,
            "run_summaries_rewritten": False,
            "git_checkpoint_backfilled": False,
            "commit_created": False,
            "tag_created": False,
            "github_release_created": False,
            "project_write_attempted": False,
            "network_attempted": False,
        },
        "does_not_prove": [
            "task-loop VERIFY_RESULT PASS exists",
            "historical progress, logs, summaries, checkpoint metadata, commits, or tags were repaired",
            "release evidence blockers are closed",
            "formal alpha release readiness",
            "v1-ref-003-1-task-05 is closed",
        ],
    }


def icloud_placeholder_smoke_audit_result(root: Path) -> dict[str, Any]:
    root = root.resolve()
    evidence_path = root / ICLOUD_PLACEHOLDER_RECORD_PATH
    residuals = {item.id: item for item in _load_residual_items(root)}
    residual = residuals.get(ICLOUD_PLACEHOLDER_RESIDUAL_ID)
    record_checks: list[dict[str, Any]] = []
    flat_scalars: dict[str, Any] = {}
    scalars: dict[str, Any] = {}

    if not evidence_path.is_file():
        record_checks.append({"name": "evidence_file_present", "status": "BLOCKED"})
    else:
        record_checks.append({"name": "evidence_file_present", "status": "PASS"})
        block = _first_yaml_block(evidence_path)
        if block is None:
            record_checks.append({"name": "yaml_record_present", "status": "BLOCKED"})
        else:
            record_checks.append({"name": "yaml_record_present", "status": "PASS"})
            scalars = _read_yaml_block_scalars(block)
            flat_scalars = _read_yaml_block_flat_scalars(block)
            expected = {
                "residual_id": ICLOUD_PLACEHOLDER_RESIDUAL_ID,
                "manual_evidence_id": "M-02",
                "mode": "icloud_placeholder_smoke_record",
                "release_gate": "blocked_until_real_icloud_download_retry_and_db_evidence_pass",
            }
            for field, expected_value in expected.items():
                actual = scalars.get(field)
                record_checks.append(
                    {
                        "name": f"{field}_matches",
                        "status": "PASS" if actual == expected_value else "BLOCKED",
                        "expected": expected_value,
                        "actual": actual,
                    }
                )
            record_checks.append(
                {
                    "name": "audit_record_keeps_closes_false",
                    "status": "PASS" if scalars.get("closes_residual") is False else "BLOCKED",
                    "actual": scalars.get("closes_residual"),
                }
            )

    smoke_checks = _icloud_placeholder_smoke_field_checks(flat_scalars)
    blocked_by = [
        f"record:{check['name']}"
        for check in record_checks
        if check["status"] == "BLOCKED"
    ]
    blocked_by.extend(f"smoke:{check['field']}" for check in smoke_checks if check["status"] == "BLOCKED")
    status = "PASS" if not blocked_by else "BLOCKED"

    return {
        "schema_version": 1,
        "mode": "icloud_placeholder_smoke_audit",
        "residual_id": ICLOUD_PLACEHOLDER_RESIDUAL_ID,
        "release": FORMAL_RELEASE_TAG,
        "manual_evidence_id": "M-02",
        "status": status,
        "closes_residual": False,
        "release_gate": "audit_only_block_until_real_icloud_smoke_evidence_ready",
        "record": {
            "path": ICLOUD_PLACEHOLDER_RECORD_PATH,
            "status": scalars.get("status", "missing"),
            "mode": scalars.get("mode"),
            "release_gate": scalars.get("release_gate"),
            "closes_residual": scalars.get("closes_residual"),
            "checks": record_checks,
        },
        "residual": residual.as_dict() if residual else None,
        "smoke_evidence_gate": {
            "status": "PASS" if all(check["status"] == "PASS" for check in smoke_checks) else "BLOCKED",
            "checks": smoke_checks,
        },
        "blocked_by": blocked_by,
        "audit_side_effects": {
            "icloud_download_attempted": False,
            "file_content_read_attempted": False,
            "file_write_attempted": False,
            "db_write_attempted": False,
            "project_write_attempted": False,
            "areamatrix_metadata_write_attempted": False,
            "network_attempted": False,
        },
        "does_not_prove": [
            "Download & retry succeeded",
            "DB rows match the retried import or conflict flow",
            "user files, conflicted copies, or placeholder markers were preserved after retry",
            "v1-rl-002 is closed",
            "formal alpha release readiness",
        ],
    }


def final_tag_readiness_audit_result(root: Path, *, include_remote: bool = False) -> dict[str, Any]:
    root = root.resolve()
    evidence_path = root / FINAL_TAG_RECORD_PATH
    residuals = {item.id: item for item in _load_residual_items(root)}
    residual = residuals.get(FINAL_TAG_SELF_RESIDUAL_ID)
    record_checks: list[dict[str, Any]] = []
    flat_scalars: dict[str, Any] = {}
    scalars: dict[str, Any] = {}

    if not evidence_path.is_file():
        record_checks.append({"name": "evidence_file_present", "status": "BLOCKED"})
    else:
        record_checks.append({"name": "evidence_file_present", "status": "PASS"})
        block = _first_yaml_block(evidence_path)
        if block is None:
            record_checks.append({"name": "yaml_record_present", "status": "BLOCKED"})
        else:
            record_checks.append({"name": "yaml_record_present", "status": "PASS"})
            scalars = _read_yaml_block_scalars(block)
            flat_scalars = _read_yaml_block_flat_scalars(block)
            expected = {
                "residual_id": FINAL_TAG_SELF_RESIDUAL_ID,
                "release": FORMAL_RELEASE_TAG,
                "mode": "final_tag_release_record",
                "release_gate": "block_until_all_release_gates_closed_and_final_tag_pushed",
            }
            for field, expected_value in expected.items():
                actual = scalars.get(field)
                record_checks.append(
                    {
                        "name": f"{field}_matches",
                        "status": "PASS" if actual == expected_value else "BLOCKED",
                        "expected": expected_value,
                        "actual": actual,
                    }
                )
            record_checks.append(
                {
                    "name": "audit_record_keeps_closes_false_before_tag",
                    "status": "PASS" if scalars.get("closes_residual") is False else "BLOCKED",
                    "actual": scalars.get("closes_residual"),
                }
            )

    release_status = release_status_result(root, include_remote=include_remote)
    pre_tag_blockers = [
        item["id"]
        for item in release_status["release_blockers"]
        if item["id"] != FINAL_TAG_SELF_RESIDUAL_ID
    ]
    pre_tag_gate_status = "PASS" if not pre_tag_blockers else "BLOCKED"
    prerequisite_checks = _final_tag_prerequisite_checks(flat_scalars)
    tag = release_status["tag"]
    tag_query_blocked_by: list[str] = []
    if tag["local_query_status"] == "blocked":
        tag_query_blocked_by.append("formal_tag_local_query_blocked")
    if include_remote and tag["remote_query_status"] == "blocked":
        tag_query_blocked_by.append("formal_tag_remote_query_blocked")

    blocked_by = [
        f"record:{check['name']}"
        for check in record_checks
        if check["status"] == "BLOCKED"
    ]
    blocked_by.extend(f"prerequisite:{check['field']}" for check in prerequisite_checks if check["status"] == "BLOCKED")
    blocked_by.extend(f"pre_tag_residual:{residual_id}" for residual_id in pre_tag_blockers)
    blocked_by.extend(release_status["release_evidence_audit_gate"]["blocked_by"])
    blocked_by.extend(f"tag_query:{item}" for item in tag_query_blocked_by)
    status = "PASS" if not blocked_by else "BLOCKED"

    return {
        "schema_version": 1,
        "mode": "final_tag_readiness_audit",
        "residual_id": FINAL_TAG_SELF_RESIDUAL_ID,
        "release": FORMAL_RELEASE_TAG,
        "status": status,
        "closes_residual": False,
        "release_gate": "audit_only_block_until_pre_tag_evidence_ready",
        "record": {
            "path": FINAL_TAG_RECORD_PATH,
            "status": scalars.get("status", "missing"),
            "mode": scalars.get("mode"),
            "release_gate": scalars.get("release_gate"),
            "closes_residual": scalars.get("closes_residual"),
            "checks": record_checks,
        },
        "residual": residual.as_dict() if residual else None,
        "pre_tag_release_evidence_gate": {
            "status": pre_tag_gate_status,
            "blocked_by": pre_tag_blockers,
            "excludes_self_residual": FINAL_TAG_SELF_RESIDUAL_ID,
            "reason": "v1-rl-004 is the formal tag action itself; all other release evidence must pass first",
        },
        "release_evidence_audit_gate": release_status["release_evidence_audit_gate"],
        "tag_prerequisite_gate": {
            "status": "PASS" if all(check["status"] == "PASS" for check in prerequisite_checks) else "BLOCKED",
            "checks": prerequisite_checks,
        },
        "formal_tag": {
            "local_exists": tag["local_exists"],
            "local_preview_tags": tag["local_preview_tags"],
            "remote_checked": include_remote,
            "remote_exists": tag["remote_exists"],
            "remote_preview_tags": tag["remote_preview_tags"],
            "query_blocked_by": tag_query_blocked_by,
        },
        "ready_to_create_formal_tag": status == "PASS",
        "blocked_by": blocked_by,
        "audit_side_effects": {
            "tag_created": False,
            "tag_pushed": False,
            "github_release_created": False,
            "network_attempted": include_remote,
            "project_write_attempted": False,
        },
        "does_not_prove": [
            "formal v0.1.0 tag exists",
            "formal v0.1.0 tag was pushed",
            "GitHub Release exists",
            "Developer ID signed app",
            "notarized or stapled app",
            "formal v0.1.0 release readiness",
            "v1-rl-004 is closed",
        ],
    }


def alpha_feedback_decision_audit_result(root: Path) -> dict[str, Any]:
    root = root.resolve()
    evidence_path = root / ALPHA_FEEDBACK_RECORD_PATH
    residuals = {item.id: item for item in _load_residual_items(root)}
    residual = residuals.get("v1-rl-006")
    residual_checks: list[dict[str, Any]] = []
    record_checks: list[dict[str, Any]] = []
    flat_scalars: dict[str, Any] = {}
    scalars: dict[str, Any] = {}

    if residual is None:
        residual_checks.append({"name": "residual_index_present", "status": "BLOCKED"})
    else:
        residual_checks.append({"name": "residual_index_present", "status": "PASS"})
        residual_checks.append(
            {
                "name": "residual_status_blocked_decision",
                "status": "PASS" if residual.status == "blocked-decision" else "BLOCKED",
                "actual": residual.status,
            }
        )
        residual_checks.append(
            {
                "name": "residual_blocks_formal_alpha",
                "status": "PASS" if residual.blocks_formal_alpha else "BLOCKED",
                "actual": residual.blocks_formal_alpha,
            }
        )

    if not evidence_path.is_file():
        record_checks.append({"name": "evidence_file_present", "status": "BLOCKED"})
    else:
        record_checks.append({"name": "evidence_file_present", "status": "PASS"})
        block = _first_yaml_block(evidence_path)
        if block is None:
            record_checks.append({"name": "yaml_record_present", "status": "BLOCKED"})
        else:
            record_checks.append({"name": "yaml_record_present", "status": "PASS"})
            scalars = _read_yaml_block_scalars(block)
            flat_scalars = _read_yaml_block_flat_scalars(block)
            expected = {
                "residual_id": "v1-rl-006",
                "mode": "alpha_feedback_release_decision_record",
                "release_gate": "block_if_any_pending",
            }
            for field, expected_value in expected.items():
                actual = scalars.get(field)
                record_checks.append(
                    {
                        "name": f"{field}_matches",
                        "status": "PASS" if actual == expected_value else "BLOCKED",
                        "expected": expected_value,
                        "actual": actual,
                    }
                )
            record_checks.append(
                {
                    "name": "audit_record_keeps_closes_false",
                    "status": "PASS" if scalars.get("closes_residual") is False else "BLOCKED",
                    "actual": scalars.get("closes_residual"),
                }
            )

    entrypoints = _alpha_feedback_entrypoints(root)
    decision_checks = _alpha_feedback_decision_field_checks(flat_scalars)
    blocked_by = [
        f"residual:{check['name']}"
        for check in residual_checks
        if check["status"] == "BLOCKED"
    ]
    blocked_by.extend(
        f"record:{check['name']}"
        for check in record_checks
        if check["status"] == "BLOCKED"
    )
    for group_name, entrypoint in entrypoints.items():
        if entrypoint["status"] == "BLOCKED":
            blocked_by.append(f"entrypoint:{group_name}")
        blocked_by.extend(
            f"entrypoint:{group_name}:{check['needle']}"
            for check in entrypoint["checks"]
            if check["status"] == "BLOCKED"
        )
    blocked_by.extend(
        f"decision:{check['field']}"
        for check in decision_checks
        if check["status"] == "BLOCKED"
    )
    status = "PASS" if not blocked_by else "BLOCKED"
    return {
        "schema_version": 1,
        "mode": "alpha_feedback_decision_audit",
        "residual_id": "v1-rl-006",
        "release": FORMAL_RELEASE_TAG,
        "status": status,
        "closes_residual": False,
        "release_gate": "audit_only_block_until_alpha_feedback_decision_ready",
        "record": {
            "path": ALPHA_FEEDBACK_RECORD_PATH,
            "status": scalars.get("status", "missing"),
            "mode": scalars.get("mode"),
            "release_gate": scalars.get("release_gate"),
            "closes_residual": scalars.get("closes_residual"),
            "checks": record_checks,
        },
        "residual": residual.as_dict() if residual else None,
        "residual_gate": {
            "status": "PASS" if all(check["status"] == "PASS" for check in residual_checks) else "BLOCKED",
            "checks": residual_checks,
        },
        "local_entrypoints": entrypoints,
        "decision_gate": {
            "status": "PASS" if all(check["status"] == "PASS" for check in decision_checks) else "BLOCKED",
            "checks": decision_checks,
        },
        "blocked_by": blocked_by,
        "decision_record_template": {
            "command": "./dev release alpha-feedback-decision-audit --json",
            "fill_in": [
                "alpha_feedback_release_decision.trusted_tester_list.source",
                "alpha_feedback_release_decision.trusted_tester_list.tester_count",
                "alpha_feedback_release_decision.announcement.url",
                "alpha_feedback_release_decision.feedback_route.secondary",
                "alpha_feedback_release_decision.triage_owner.owner",
                "alpha_feedback_release_decision.triage_owner.response_slo",
            ],
            "required_side_effects": [
                "testers_invited",
                "announcement_published",
                "feedback_owner_assigned",
                "feedback_route_marked_ready",
            ],
            "must_remain_false_for_audit_only_helper": [
                "closes_residual",
            ],
        },
        "audit_side_effects": {
            "github_discussion_created": False,
            "testers_invited": False,
            "announcement_published": False,
            "feedback_owner_assigned": False,
            "feedback_route_marked_ready": False,
            "network_attempted": False,
            "project_write_attempted": False,
        },
        "does_not_prove": [
            "trusted tester list exists",
            "formal announcement or Discussion exists",
            "feedback route is final",
            "triage owner has accepted responsibility",
            "v1-rl-006 is closed",
            "formal alpha release readiness",
        ],
    }


def run_release_status(root: Path, *, json_output: bool = False, include_remote: bool = False) -> int:
    result = release_status_result(root, include_remote=include_remote)
    if json_output:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result["status"] == "PASS" else 1

    print("AreaMatrix release status")
    print(f"- release: {result['release']}")
    print(f"- status: {result['status']}")
    queue = result["technical_queue"]
    print(f"- technical queue: {queue['status']} ({queue['task_count']}/{queue['task_count']})")
    print(f"- formal alpha: {result['formal_alpha']['status']}")
    blocker_ids = [item["id"] for item in result["release_blockers"]]
    print(f"- release blockers: {', '.join(blocker_ids) if blocker_ids else 'none'}")
    print(f"- residual evidence gate: {result['residual_evidence_gate']['status']}")
    tag = result["tag"]
    local_tag = "present" if tag["local_exists"] else "missing"
    print(f"- local formal tag {tag['formal_tag']}: {local_tag}")
    if tag["remote_checked"]:
        remote_tag = "present" if tag["remote_exists"] else "missing"
        print(f"- remote formal tag {tag['formal_tag']}: {remote_tag}")
    print(f"- formal tag gate: {result['formal_tag_gate']['status']}")
    print(f"- release evidence audit gate: {result['release_evidence_audit_gate']['status']}")
    workflow = result["release_workflow"]
    workflow_state = "present" if workflow["exists"] else "missing"
    print(f"- release workflow: {workflow_state}")
    print("- closes residual: false")
    return 0 if result["status"] == "PASS" else 1


def run_release_evidence_audit(root: Path, *, json_output: bool = False) -> int:
    result = release_evidence_audit_result(root)
    if json_output:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result["status"] == "PASS" else 1

    print("AreaMatrix release evidence audit")
    print(f"- status: {result['status']}")
    for record in result["records"]:
        print(
            f"- {record['residual_id']}: {record['status']} "
            f"({record['path']}, closes_residual={str(record['closes_residual']).lower()})"
        )
    print("- closes residual: false")
    return 0 if result["status"] == "PASS" else 1


def run_final_tag_readiness_audit(root: Path, *, json_output: bool = False, include_remote: bool = False) -> int:
    result = final_tag_readiness_audit_result(root, include_remote=include_remote)
    if json_output:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result["status"] == "PASS" else 1

    print("AreaMatrix final tag readiness audit")
    print(f"- status: {result['status']}")
    print(f"- residual: {result['residual_id']}")
    print(f"- pre-tag release evidence gate: {result['pre_tag_release_evidence_gate']['status']}")
    print(f"- tag prerequisite gate: {result['tag_prerequisite_gate']['status']}")
    print(f"- ready to create formal tag: {str(result['ready_to_create_formal_tag']).lower()}")
    print("- closes residual: false")
    if result["blocked_by"]:
        print(f"- blocked by: {', '.join(result['blocked_by'])}")
    return 0 if result["status"] == "PASS" else 1


def run_icloud_placeholder_smoke_audit(root: Path, *, json_output: bool = False) -> int:
    result = icloud_placeholder_smoke_audit_result(root)
    if json_output:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result["status"] == "PASS" else 1

    print("AreaMatrix iCloud placeholder smoke audit")
    print(f"- status: {result['status']}")
    print(f"- residual: {result['residual_id']}")
    print(f"- manual evidence: {result['manual_evidence_id']}")
    print(f"- smoke evidence gate: {result['smoke_evidence_gate']['status']}")
    print("- closes residual: false")
    if result["blocked_by"]:
        print(f"- blocked by: {', '.join(result['blocked_by'])}")
    return 0 if result["status"] == "PASS" else 1


def run_task05_release_review_audit(root: Path, *, json_output: bool = False) -> int:
    result = task05_release_review_audit_result(root)
    if json_output:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result["status"] == "PASS" else 1

    print("AreaMatrix task05 release review audit")
    print(f"- status: {result['status']}")
    print(f"- residual: {result['residual_id']}")
    print(f"- task label: {result['task_label']}")
    print(f"- release evidence review gate: {result['release_evidence_review_gate']['status']}")
    print(f"- task-loop boundary gate: {result['task_loop_boundary_gate']['status']}")
    print(f"- forbidden repair gate: {result['forbidden_repair_gate']['status']}")
    print("- closes residual: false")
    if result["blocked_by"]:
        print(f"- blocked by: {', '.join(result['blocked_by'])}")
    return 0 if result["status"] == "PASS" else 1


def gate_review_task05_audit_result(root: Path) -> dict[str, Any]:
    return task05_release_review_audit_result(root)


def run_alpha_feedback_decision_audit(root: Path, *, json_output: bool = False) -> int:
    result = alpha_feedback_decision_audit_result(root)
    if json_output:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result["status"] == "PASS" else 1

    print("AreaMatrix alpha feedback decision audit")
    print(f"- status: {result['status']}")
    print(f"- residual: {result['residual_id']}")
    print(f"- issue template: {result['local_entrypoints']['issue_template']['status']}")
    print(f"- discussion links: {result['local_entrypoints']['discussion_links']['status']}")
    print(f"- decision gate: {result['decision_gate']['status']}")
    print("- closes residual: false")
    if result["blocked_by"]:
        print(f"- blocked by: {', '.join(result['blocked_by'])}")
    return 0 if result["status"] == "PASS" else 1
