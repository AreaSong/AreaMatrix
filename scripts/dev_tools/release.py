"""Release distribution and local readiness build helpers behind ./dev."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import stat
import tempfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Sequence

from .common import command_text, fail, require_command, run_step


DEFAULT_NOTARY_PROFILE = "AC_PASSWORD"
DEFAULT_READINESS_BUILD_DERIVED_DATA = "build/ReleaseReadiness"
DEFAULT_READINESS_BUILD_DESTINATION = "platform=macOS,arch=arm64"
DEFAULT_APPLICATIONS_DIR = "/Applications"
REDACTED_PATH = "<redacted-path>"
REDACTED_FILENAME = "<redacted-filename>"
ICLOUD_MDLS_FIELDS = [
    "kMDItemUbiquitousItemDownloadingStatus",
    "kMDItemUbiquitousItemIsDownloaded",
    "kMDItemUbiquitousItemIsUploaded",
    "kMDItemUbiquitousItemHasUnresolvedConflicts",
    "kMDItemFSName",
]
DISTRIBUTION_ARTIFACT_PROBE_GATE = "probe_only_blocked_until_formal_distribution_evidence"
_NOTARY_PROFILE_PATTERN = re.compile(r"^[A-Za-z0-9._-]+$")


@dataclass(frozen=True)
class PreflightCheck:
    name: str
    status: str
    detail: str

    @property
    def passed(self) -> bool:
        return self.status == "PASS"


def _run_capture(argv: Sequence[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(part) for part in argv],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


def _developer_id_identities(output: str) -> list[str]:
    identities: list[str] = []
    pattern = re.compile(r'"(Developer ID Application:[^"]+)"')
    for line in output.splitlines():
        match = pattern.search(line)
        if match:
            identities.append(match.group(1))
    return identities


def check_developer_id_identity() -> PreflightCheck:
    require_command("security")
    argv = ["security", "find-identity", "-v", "-p", "codesigning"]
    proc = _run_capture(argv)
    if proc.returncode != 0:
        return PreflightCheck(
            "Developer ID Application identity",
            "BLOCKED",
            f"{command_text(argv)} failed with exit {proc.returncode}",
        )

    identities = _developer_id_identities(proc.stdout or "")
    if not identities:
        return PreflightCheck(
            "Developer ID Application identity",
            "BLOCKED",
            "no valid Developer ID Application signing identity found",
        )

    return PreflightCheck(
        "Developer ID Application identity",
        "PASS",
        f"{len(identities)} valid Developer ID Application identity found",
    )


def check_notary_profile(profile: str) -> PreflightCheck:
    if not _NOTARY_PROFILE_PATTERN.fullmatch(profile):
        return PreflightCheck(
            "notarytool keychain profile",
            "BLOCKED",
            "profile must contain only letters, numbers, '.', '_', or '-'; shell metacharacters are not allowed",
        )

    require_command("xcrun")
    argv = ["xcrun", "notarytool", "history", "--keychain-profile", profile]
    proc = _run_capture(argv)
    if proc.returncode == 0:
        return PreflightCheck(
            "notarytool keychain profile",
            "PASS",
            f"notarytool profile `{profile}` is usable",
        )

    output = " ".join((proc.stdout or "").split())
    if len(output) > 220:
        output = f"{output[:217]}..."
    detail = output or f"{command_text(argv)} failed with exit {proc.returncode}"
    return PreflightCheck(
        "notarytool keychain profile",
        "BLOCKED",
        f"profile `{profile}` is not usable: {detail}",
    )


def _distribution_evidence_record_template(
    status: str,
    blocked_by: Sequence[str],
    *,
    notary_profile: str,
) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "mode": "distribution_signing_notarization_record",
        "residual_id": "v1-rl-003",
        "release": "v0.1.0",
        "status": "pending | pass | blocked",
        "closes_residual": False,
        "release_gate": "block_if_any_pending_or_blocked",
        "preflight_json": {
            "command": "./dev release preflight --json",
            "status": status,
            "blocked_by": list(blocked_by),
            "captured_at": "<YYYY-MM-DD>",
        },
        "artifact_probe": {
            "status": "pending | captured | blocked | partial | unsupported_platform",
            "probe_status": "pending | captured | blocked | partial | unsupported_platform",
            "distribution_requirements_status": "blocked | pass",
            "mode": "distribution_artifact_probe",
            "command": './dev release distribution-artifact-probe --app-path "$APP_PATH" --dmg-path "$DMG_PATH" --json',
            "path_redaction": True,
            "hash_dmg_default": "skipped",
            "status_semantics": "probe.status captured is not a distribution pass",
            "closes_residual": False,
            "does_not_prove": [
                "Developer ID signed app",
                "accepted notarization",
                "stapled app or stapled DMG",
                "formal v0.1.0 release readiness",
            ],
        },
        "developer_id_identity": {
            "status": "pending | pass | blocked",
            "command": "security find-identity -v -p codesigning",
            "identity": "<Developer ID Application identity>",
            "team_id": "<TEAM_ID>",
        },
        "notarytool_profile": {
            "status": "pending | pass | blocked",
            "profile": notary_profile,
            "command": f"xcrun notarytool history --keychain-profile {notary_profile}",
        },
        "codesign_developer_id_team": {
            "status": "pending | pass | blocked",
            "app_path": "<APP_PATH>",
            "command": 'codesign -dv --verbose=4 "$APP_PATH"',
            "required_signature": "Developer ID Application",
            "team_identifier": "<TEAM_ID>",
            "rejects": ["Signature=adhoc", "TeamIdentifier=not set"],
        },
        "notarytool_submission": {
            "status": "pending | accepted | blocked",
            "artifact": "<zip-or-dmg-path>",
            "command": "xcrun notarytool submit ... --wait",
            "submission_id": "<notarytool-submission-id>",
            "log_url": "<notarytool-log-url>",
        },
        "stapler_app": {
            "status": "pending | pass | blocked",
            "command": ['xcrun stapler staple "$APP_PATH"', 'xcrun stapler validate "$APP_PATH"'],
        },
        "formal_dmg": {
            "status": "pending | pass | blocked",
            "path": "<DMG_PATH>",
            "sha256": "<sha256>",
            "codesign_status": "pending | pass | blocked",
            "notarization_status": "pending | accepted | blocked",
            "notarization_submission_id": "<notarytool-submission-id>",
            "notarization_log_url": "<notarytool-log-url>",
        },
        "stapler_dmg": {
            "status": "pending | pass | blocked",
            "command": ['xcrun stapler staple "$DMG_PATH"', 'xcrun stapler validate "$DMG_PATH"'],
        },
        "spctl_assess": {
            "status": "pending | pass | blocked",
            "app_command": 'spctl -a -t exec -vv "$APP_PATH"',
            "dmg_command": 'spctl --assess -vvv --type install "$DMG_PATH"',
            "required_source": "Notarized Developer ID",
        },
        "clean_mac_first_launch": {
            "status": "pending | pass | blocked",
            "machine": "<clean-mac-id>",
            "macos_version": "<macOS version>",
            "gatekeeper_result": "pending | accepted | blocked",
            "first_launch_result": "pending | pass | blocked",
            "repo_selection_or_configured_repo_result": "pending | pass | blocked",
            "evidence_path": "<clean-mac-evidence-path>",
        },
    }


def release_preflight_result(checks: Sequence[PreflightCheck], *, notary_profile: str) -> dict[str, Any]:
    blocked_by = [check.name for check in checks if not check.passed]
    status = "PASS" if not blocked_by else "BLOCKED"
    return {
        "mode": "release_distribution_preflight",
        "status": status,
        "release_gate": "block_if_any_check_blocked",
        "notary_profile": notary_profile,
        "checks": [
            {
                "name": check.name,
                "status": check.status,
                "detail": check.detail,
            }
            for check in checks
        ],
        "blocked_by": blocked_by,
        "required_distribution_evidence": [
            "Developer ID Application signing identity",
            "codesign -dv --verbose=4 shows Developer ID team",
            "xcrun notarytool submit returns accepted submission",
            "stapler staple and stapler validate pass for app and DMG",
            "formal DMG checksum is recorded",
            "clean Mac first launch passes Gatekeeper",
        ],
        "evidence_record_template": _distribution_evidence_record_template(
            status,
            blocked_by,
            notary_profile=notary_profile,
        ),
        "does_not_prove": [
            "Developer ID signed app",
            "notarized or stapled app",
            "formal notarized DMG",
            "clean Mac first launch",
            "formal v0.1.0 release readiness",
        ],
    }


def run_release_preflight(
    root: Path,
    *,
    notary_profile: str = DEFAULT_NOTARY_PROFILE,
    json_output: bool = False,
) -> int:
    del root
    checks = [
        check_developer_id_identity(),
        check_notary_profile(notary_profile),
    ]
    result = release_preflight_result(checks, notary_profile=notary_profile)

    if json_output:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result["status"] == "PASS" else 1

    print("release distribution preflight")
    for check in checks:
        print(f"- {check.status}: {check.name} - {check.detail}")

    if result["status"] == "PASS":
        print("release distribution preflight: PASS")
        return 0

    print("release distribution preflight: BLOCKED")
    return 1


def _absolute_input_path(path: Path) -> Path:
    expanded = path.expanduser()
    if expanded.is_absolute():
        return expanded
    return Path.cwd() / expanded


def _file_type_from_mode(mode: int) -> str:
    if stat.S_ISLNK(mode):
        return "symlink"
    if stat.S_ISREG(mode):
        return "file"
    if stat.S_ISDIR(mode):
        return "directory"
    return "other"


def _summarize_mdls_output(output: str) -> str:
    summary = " ".join(output.split())
    if len(summary) > 240:
        return f"{summary[:237]}..."
    return summary


def _parse_mdls_values(output: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in output.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if value.startswith('"') and value.endswith('"') and len(value) >= 2:
            value = value[1:-1]
        values[key] = value
    return values


def _mdls_icloud_metadata(path: Path) -> dict[str, Any]:
    if shutil.which("mdls") is None:
        return {
            "mdls_attempted": False,
            "mdls_available": False,
            "mdls_exit_code": None,
            "values": {},
            "error_summary": "mdls command not found",
        }
    argv = ["mdls", "-nullMarker", "__AREAMATRIX_NULL__"]
    for field in ICLOUD_MDLS_FIELDS:
        argv.extend(["-name", field])
    argv.append(str(path))
    proc = _run_capture(argv)
    values = _parse_mdls_values(proc.stdout or "")
    return {
        "mdls_attempted": True,
        "mdls_available": True,
        "mdls_exit_code": proc.returncode,
        "values": values if proc.returncode == 0 else {},
        "error_summary": "" if proc.returncode == 0 else _summarize_mdls_output(proc.stdout or ""),
        "command": command_text(argv),
    }


def _skipped_icloud_metadata(reason: str) -> dict[str, Any]:
    return {
        "mdls_attempted": False,
        "mdls_available": shutil.which("mdls") is not None,
        "mdls_exit_code": None,
        "values": {},
        "error_summary": reason,
    }


def _replace_sensitive_values(text: str, replacements: Sequence[tuple[str, str]]) -> str:
    redacted = text
    for sensitive, replacement in sorted(replacements, key=lambda item: len(item[0]), reverse=True):
        if sensitive:
            redacted = redacted.replace(sensitive, replacement)
    return redacted


def _redact_icloud_placeholder_evidence_paths(
    evidence: dict[str, Any],
    absolute_path: Path,
    input_path: Path,
) -> dict[str, Any]:
    path_replacements = [
        (str(absolute_path), REDACTED_PATH),
        (str(input_path), REDACTED_PATH),
        (command_text([str(absolute_path)]), REDACTED_PATH),
        (command_text([str(input_path)]), REDACTED_PATH),
    ]
    filename_replacements = [(absolute_path.name, REDACTED_FILENAME)]

    target = evidence["target"]
    target["input_path"] = REDACTED_PATH
    target["absolute_path"] = REDACTED_PATH
    target["path_redacted"] = True
    if "lstat_error" in target:
        target["lstat_error"] = _replace_sensitive_values(str(target["lstat_error"]), path_replacements)

    metadata = evidence["icloud_metadata"]
    if "command" in metadata:
        metadata["command"] = _replace_sensitive_values(str(metadata["command"]), path_replacements)
    if metadata.get("error_summary"):
        redacted_error = _replace_sensitive_values(str(metadata["error_summary"]), path_replacements)
        metadata["error_summary"] = _replace_sensitive_values(redacted_error, filename_replacements)
    values = metadata.get("values", {})
    if isinstance(values, dict) and "kMDItemFSName" in values:
        values["kMDItemFSName"] = REDACTED_FILENAME

    evidence["privacy"]["path_redaction"] = True
    evidence["privacy"]["raw_path_fields_present"] = False
    evidence["privacy"]["redacted_fields"] = [
        "target.input_path",
        "target.absolute_path",
        "target.lstat_error",
        "icloud_metadata.command",
        "icloud_metadata.error_summary",
        "icloud_metadata.values.kMDItemFSName",
    ]
    return evidence


def collect_icloud_placeholder_evidence(path: Path, *, include_sensitive_paths: bool = False) -> dict[str, Any]:
    absolute_path = _absolute_input_path(path)
    path_lexists = os.path.lexists(absolute_path)
    target: dict[str, Any] = {
        "input_path": str(path),
        "absolute_path": str(absolute_path),
        "exists": path_lexists,
        "lexists": path_lexists,
        "icloud_marker_filename": absolute_path.name.endswith(".icloud"),
    }
    status = "captured"
    mdls: dict[str, Any]
    if path_lexists:
        try:
            metadata = absolute_path.lstat()
            is_symlink = stat.S_ISLNK(metadata.st_mode)
            target.update(
                {
                    "file_type": _file_type_from_mode(metadata.st_mode),
                    "is_symlink": is_symlink,
                    "lstat_size_bytes": metadata.st_size,
                    "lstat_mtime_ns": metadata.st_mtime_ns,
                }
            )
            if is_symlink:
                status = "metadata_blocked"
                mdls = _skipped_icloud_metadata("symlink target not inspected")
            else:
                mdls = _mdls_icloud_metadata(absolute_path)
                if not mdls["mdls_available"]:
                    status = "unsupported_platform"
                elif mdls["mdls_exit_code"] != 0:
                    status = "metadata_blocked"
        except OSError as exc:
            status = "metadata_blocked"
            target["lstat_error"] = str(exc)
            mdls = _skipped_icloud_metadata("lstat failed")
    else:
        status = "path_missing"
        target.update({"file_type": "missing", "is_symlink": False})
        mdls = _skipped_icloud_metadata("path does not exist")

    evidence = {
        "schema_version": 1,
        "mode": "icloud_placeholder_metadata_probe",
        "residual_id": "v1-rl-002",
        "manual_evidence_id": "M-02",
        "status": status,
        "closes_residual": False,
        "release_gate": "blocked_until_real_icloud_download_retry_and_db_evidence_pass",
        "target": target,
        "icloud_metadata": mdls,
        "side_effects": {
            "download_attempted": False,
            "file_content_read_attempted": False,
            "file_write_attempted": False,
            "db_write_attempted": False,
            "project_write_attempted": False,
            "areamatrix_metadata_write_attempted": False,
        },
        "privacy": {
            "path_redaction": False,
            "raw_path_fields_present": True,
            "redacted_fields": [],
        },
        "manual_smoke_required": [
            "mdls downloading status before Download & retry",
            "UI action: Download & retry",
            "retry result",
            "DB row evidence",
            "user-file invariants after retry",
            "mdls downloading status after retry",
        ],
        "required_follow_up": [
            "Run on a real iCloud Drive placeholder environment.",
            "Record Finder or mdls before/after downloading status.",
            "Perform Download & retry in the app UI.",
            "Record retry result, DB row evidence, and user-file invariants.",
            "Update recovery-scenarios.md and release-checklist.md only after real manual evidence passes.",
        ],
        "does_not_prove": [
            "Download & retry succeeded",
            "DB rows match the retried import or conflict flow",
            "User files, conflicted copies, or placeholder markers were preserved after retry",
            "v1-rl-002 is closed",
            "Stage 1 alpha is release-ready",
        ],
    }
    if include_sensitive_paths:
        return evidence
    return _redact_icloud_placeholder_evidence_paths(evidence, absolute_path, path)


def run_icloud_placeholder_evidence(
    path: Path,
    *,
    json_output: bool = False,
    include_sensitive_paths: bool = False,
) -> int:
    evidence = collect_icloud_placeholder_evidence(path, include_sensitive_paths=include_sensitive_paths)
    if json_output:
        print(json.dumps(evidence, ensure_ascii=False, indent=2))
    else:
        print("iCloud placeholder evidence probe")
        print(f"- status: {evidence['status']}")
        print(f"- release gate: {evidence['release_gate']}")
        target = evidence["target"]
        print(f"- path: {target['absolute_path']}")
        print(f"- exists: {target['exists']}")
        print(f"- file type: {target.get('file_type', 'unknown')}")
        print(f"- icloud marker filename: {target['icloud_marker_filename']}")
        print(f"- download attempted: {evidence['side_effects']['download_attempted']}")
        print(f"- file content read attempted: {evidence['side_effects']['file_content_read_attempted']}")
        mdls = evidence["icloud_metadata"]
        print(f"- mdls attempted: {mdls['mdls_attempted']}")
        if mdls.get("error_summary"):
            print(f"- mdls note: {mdls['error_summary']}")
    return 0 if evidence["status"] == "captured" else 1


def _artifact_target_metadata(path: Path, *, expected_file_type: str) -> tuple[dict[str, Any], Path]:
    absolute_path = _absolute_input_path(path)
    path_lexists = os.path.lexists(absolute_path)
    target: dict[str, Any] = {
        "input_path": str(path),
        "absolute_path": str(absolute_path),
        "exists": path_lexists,
        "lexists": path_lexists,
        "expected_file_type": expected_file_type,
        "status": "blocked",
        "safe_to_probe": False,
    }
    if not path_lexists:
        target.update(
            {
                "file_type": "missing",
                "is_symlink": False,
                "reason": "path does not exist",
            }
        )
        return target, absolute_path
    try:
        metadata = absolute_path.lstat()
    except OSError as exc:
        target["reason"] = f"lstat failed: {exc}"
        return target, absolute_path

    file_type = _file_type_from_mode(metadata.st_mode)
    is_symlink = stat.S_ISLNK(metadata.st_mode)
    target.update(
        {
            "file_type": file_type,
            "is_symlink": is_symlink,
            "lstat_size_bytes": metadata.st_size,
            "lstat_mtime_ns": metadata.st_mtime_ns,
        }
    )
    if is_symlink:
        target["reason"] = "symlink target not inspected"
        return target, absolute_path
    if file_type != expected_file_type:
        target["reason"] = f"expected {expected_file_type}, found {file_type}"
        return target, absolute_path
    target["status"] = "pass"
    target["safe_to_probe"] = True
    return target, absolute_path


def _skipped_artifact_probe(command: Sequence[str], reason: str) -> dict[str, Any]:
    return {
        "status": "skipped",
        "attempted": False,
        "available": shutil.which(str(command[0])) is not None if command else False,
        "exit_code": None,
        "command": command_text(command),
        "output_summary": reason,
    }


def _artifact_probe_command(
    command: Sequence[str],
    *,
    command_name: str,
    safe_to_probe: bool,
    skip_reason: str = "target is not safe to probe",
) -> dict[str, Any]:
    if not safe_to_probe:
        return _skipped_artifact_probe(command, skip_reason)
    if shutil.which(command_name) is None:
        return {
            "status": "unsupported_platform",
            "attempted": False,
            "available": False,
            "exit_code": None,
            "command": command_text(command),
            "output_summary": f"{command_name} command not found",
        }
    proc = _run_capture(command)
    return {
        "status": "pass" if proc.returncode == 0 else "blocked",
        "attempted": True,
        "available": True,
        "exit_code": proc.returncode,
        "command": command_text(command),
        "output_summary": _summarize_mdls_output(proc.stdout or ""),
    }


def _dmg_sha256_probe(dmg_path: Path, *, safe_to_probe: bool, hash_dmg: bool) -> dict[str, Any]:
    command = ["shasum", "-a", "256", str(dmg_path)]
    if not hash_dmg:
        result = _skipped_artifact_probe(command, "use --hash-dmg to read DMG bytes and compute SHA-256")
        result["full_artifact_read_attempted"] = False
        result["sha256"] = None
        return result
    result = _artifact_probe_command(command, command_name="shasum", safe_to_probe=safe_to_probe)
    result["full_artifact_read_attempted"] = result["attempted"]
    result["sha256"] = None
    if result["status"] == "pass":
        result["sha256"] = (result["output_summary"].split() or [None])[0]
    return result


def _artifact_probe_blockers(evidence: dict[str, Any]) -> tuple[str, list[str]]:
    blocked_by: list[str] = []
    unsupported_by: list[str] = []
    partial_by: list[str] = []

    for target_name, target in evidence["target"].items():
        if target["status"] != "pass":
            blocked_by.append(f"target.{target_name}:{target.get('reason', target['status'])}")

    command_groups = {
        "app": evidence["app"],
        "dmg": evidence["dmg"],
    }
    for group_name, commands in command_groups.items():
        for command_name, result in commands.items():
            status = result.get("status")
            if status == "blocked":
                blocked_by.append(f"{group_name}.{command_name}")
            elif status == "unsupported_platform":
                if command_name in {"spctl_assess", "stapler_validate", "sha256"}:
                    partial_by.append(f"{group_name}.{command_name}")
                else:
                    unsupported_by.append(f"{group_name}.{command_name}")
            elif status == "skipped" and command_name in {"spctl_assess", "stapler_validate"}:
                option_name = "spctl" if command_name == "spctl_assess" else "stapler_validate"
                if evidence["options"].get(option_name, False):
                    partial_by.append(f"{group_name}.{command_name}")

    if blocked_by:
        return "blocked", blocked_by
    if unsupported_by:
        return "unsupported_platform", unsupported_by
    if partial_by:
        return "partial", partial_by
    return "captured", []


def _distribution_requirement_blockers(evidence: dict[str, Any]) -> list[str]:
    blockers: list[str] = []

    for target_name, target in evidence["target"].items():
        if target["status"] != "pass":
            blockers.append(f"target.{target_name}:{target.get('reason', target['status'])}")

    for artifact_name in ("app", "dmg"):
        commands = evidence[artifact_name]
        for command_name in ("codesign_display", "codesign_verify"):
            if commands[command_name]["status"] != "pass":
                blockers.append(f"{artifact_name}.{command_name}:{commands[command_name]['status']}")

        display = commands["codesign_display"].get("output_summary", "")
        if "Signature=adhoc" in display:
            blockers.append(f"{artifact_name}.codesign_display:Signature=adhoc")
        if "TeamIdentifier=not set" in display:
            blockers.append(f"{artifact_name}.codesign_display:TeamIdentifier=not set")
        if commands["codesign_display"]["status"] == "pass" and "Developer ID Application" not in display:
            blockers.append(f"{artifact_name}.codesign_display:Developer ID Application missing")

        if commands["stapler_validate"]["status"] != "pass":
            blockers.append(f"{artifact_name}.stapler_validate:{commands['stapler_validate']['status']}")
        if commands["spctl_assess"]["status"] != "pass":
            blockers.append(f"{artifact_name}.spctl_assess:{commands['spctl_assess']['status']}")
        spctl_output = commands["spctl_assess"].get("output_summary", "")
        if commands["spctl_assess"]["status"] == "pass" and "Notarized Developer ID" not in spctl_output:
            blockers.append(f"{artifact_name}.spctl_assess:Notarized Developer ID missing")

    if evidence["dmg"]["sha256"]["status"] != "pass":
        blockers.append(f"dmg.sha256:{evidence['dmg']['sha256']['status']}")

    blockers.extend(
        [
            "notarytool_submission:not_proven_by_probe",
            "clean_mac_first_launch:not_proven_by_probe",
        ]
    )
    return blockers


def _redact_distribution_artifact_probe_paths(
    evidence: dict[str, Any],
    path_pairs: Sequence[tuple[Path, Path]],
) -> dict[str, Any]:
    path_replacements: list[tuple[str, str]] = []
    filename_replacements: list[tuple[str, str]] = []
    for input_path, absolute_path in path_pairs:
        path_replacements.extend(
            [
                (str(absolute_path), REDACTED_PATH),
                (str(input_path), REDACTED_PATH),
                (command_text([str(absolute_path)]), REDACTED_PATH),
                (command_text([str(input_path)]), REDACTED_PATH),
            ]
        )
        filename_replacements.extend(
            [
                (absolute_path.name, REDACTED_FILENAME),
                (input_path.name, REDACTED_FILENAME),
                (absolute_path.stem, REDACTED_FILENAME),
                (input_path.stem, REDACTED_FILENAME),
            ]
        )

    def redact_value(value: Any) -> Any:
        if isinstance(value, str):
            redacted = _replace_sensitive_values(value, path_replacements)
            return _replace_sensitive_values(redacted, filename_replacements)
        if isinstance(value, list):
            return [redact_value(item) for item in value]
        if isinstance(value, dict):
            return {key: redact_value(item) for key, item in value.items()}
        return value

    redacted = redact_value(evidence)
    for target in redacted["target"].values():
        target["input_path"] = REDACTED_PATH
        target["absolute_path"] = REDACTED_PATH
        target["path_redacted"] = True
    redacted["privacy"]["path_redaction"] = True
    redacted["privacy"]["raw_path_fields_present"] = False
    redacted["privacy"]["redacted_fields"] = [
        "target.*.input_path",
        "target.*.absolute_path",
        "target.*.reason",
        "*.command",
        "*.output_summary",
        "*.sha256 command output paths",
        "path stems in command output",
    ]
    return redacted


def collect_distribution_artifact_probe(
    app_path: Path,
    dmg_path: Path,
    *,
    hash_dmg: bool = False,
    spctl: bool = False,
    stapler_validate: bool = False,
    include_sensitive_paths: bool = False,
) -> dict[str, Any]:
    app_target, absolute_app_path = _artifact_target_metadata(app_path, expected_file_type="directory")
    dmg_target, absolute_dmg_path = _artifact_target_metadata(dmg_path, expected_file_type="file")
    app_safe = bool(app_target["safe_to_probe"])
    dmg_safe = bool(dmg_target["safe_to_probe"])

    app = {
        "codesign_display": _artifact_probe_command(
            ["codesign", "-dv", "--verbose=4", str(absolute_app_path)],
            command_name="codesign",
            safe_to_probe=app_safe,
        ),
        "codesign_verify": _artifact_probe_command(
            ["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(absolute_app_path)],
            command_name="codesign",
            safe_to_probe=app_safe,
        ),
        "spctl_assess": _artifact_probe_command(
            ["spctl", "-a", "-t", "exec", "-vv", str(absolute_app_path)],
            command_name="spctl",
            safe_to_probe=app_safe and spctl,
            skip_reason="use --spctl to run Gatekeeper assessment",
        ),
        "stapler_validate": _artifact_probe_command(
            ["xcrun", "stapler", "validate", str(absolute_app_path)],
            command_name="xcrun",
            safe_to_probe=app_safe and stapler_validate,
            skip_reason="use --stapler-validate to validate stapled ticket",
        ),
    }
    dmg = {
        "codesign_display": _artifact_probe_command(
            ["codesign", "-dv", "--verbose=4", str(absolute_dmg_path)],
            command_name="codesign",
            safe_to_probe=dmg_safe,
        ),
        "codesign_verify": _artifact_probe_command(
            ["codesign", "--verify", "--verbose=2", str(absolute_dmg_path)],
            command_name="codesign",
            safe_to_probe=dmg_safe,
        ),
        "spctl_assess": _artifact_probe_command(
            ["spctl", "--assess", "-vvv", "--type", "install", str(absolute_dmg_path)],
            command_name="spctl",
            safe_to_probe=dmg_safe and spctl,
            skip_reason="use --spctl to run Gatekeeper assessment",
        ),
        "stapler_validate": _artifact_probe_command(
            ["xcrun", "stapler", "validate", str(absolute_dmg_path)],
            command_name="xcrun",
            safe_to_probe=dmg_safe and stapler_validate,
            skip_reason="use --stapler-validate to validate stapled ticket",
        ),
        "sha256": _dmg_sha256_probe(absolute_dmg_path, safe_to_probe=dmg_safe, hash_dmg=hash_dmg),
    }
    signature_verification_read_attempted = any(
        result.get("attempted")
        for result in (
            app["codesign_display"],
            app["codesign_verify"],
            dmg["codesign_display"],
            dmg["codesign_verify"],
        )
    )
    external_system_assessment_attempted = any(
        result.get("attempted")
        for result in (
            app["spctl_assess"],
            app["stapler_validate"],
            dmg["spctl_assess"],
            dmg["stapler_validate"],
        )
    )
    evidence = {
        "schema_version": 1,
        "mode": "distribution_artifact_probe",
        "residual_id": "v1-rl-003",
        "release": "v0.1.0",
        "status": "captured",
        "closes_residual": False,
        "release_gate": DISTRIBUTION_ARTIFACT_PROBE_GATE,
        "target": {
            "app": app_target,
            "dmg": dmg_target,
        },
        "options": {
            "hash_dmg": hash_dmg,
            "spctl": spctl,
            "stapler_validate": stapler_validate,
        },
        "app": app,
        "dmg": dmg,
        "side_effects": {
            "metadata_read_attempted": True,
            "signature_verification_read_attempted": bool(signature_verification_read_attempted),
            "full_dmg_hash_read_attempted": bool(dmg["sha256"].get("full_artifact_read_attempted")),
            "artifact_content_read_attempted": bool(
                signature_verification_read_attempted or dmg["sha256"].get("full_artifact_read_attempted")
            ),
            "file_write_attempted": False,
            "artifact_write_attempted": False,
            "mount_attempted": False,
            "notary_submit_attempted": False,
            "staple_attempted": False,
            "network_not_initiated_by_tool": True,
            "external_system_assessment_attempted": bool(external_system_assessment_attempted),
            "network_may_be_attempted_by_system_assessment": bool(external_system_assessment_attempted),
            "install_attempted": False,
            "db_write_attempted": False,
            "project_write_attempted": False,
            "areamatrix_metadata_write_attempted": False,
        },
        "privacy": {
            "path_redaction": False,
            "raw_path_fields_present": True,
            "redacted_fields": [],
        },
        "required_follow_up": [
            "Run Developer ID signing with a valid Apple Developer Program identity.",
            "Submit the formal artifact to notarytool and retain accepted submission id and log URL.",
            "Staple and validate both app and DMG.",
            "Record formal DMG SHA-256 after notarized/stapled artifact is finalized.",
            "Run spctl and clean Mac first launch evidence before closing v1-rl-003.",
        ],
        "does_not_prove": [
            "Developer ID signed app",
            "accepted notarization",
            "stapled app or stapled DMG",
            "formal notarized DMG checksum",
            "clean Mac first launch",
            "formal alpha readiness",
            "v1-rl-003 is closed",
        ],
    }
    probe_status, probe_blocked_by = _artifact_probe_blockers(evidence)
    distribution_blocked_by = _distribution_requirement_blockers(evidence)
    evidence["status"] = probe_status
    evidence["probe"] = {
        "status": probe_status,
        "blocked_by": probe_blocked_by,
        "capture_only": True,
    }
    evidence["distribution_requirements"] = {
        "status": "blocked" if distribution_blocked_by else "pass",
        "blocked_by": distribution_blocked_by,
        "release_ready": False,
        "closes_residual": False,
    }
    evidence["blocked_by"] = list(dict.fromkeys([*probe_blocked_by, *distribution_blocked_by]))
    if include_sensitive_paths:
        return evidence
    return _redact_distribution_artifact_probe_paths(
        evidence,
        [(app_path, absolute_app_path), (dmg_path, absolute_dmg_path)],
    )


def run_distribution_artifact_probe(
    app_path: Path,
    dmg_path: Path,
    *,
    json_output: bool = False,
    hash_dmg: bool = False,
    spctl: bool = False,
    stapler_validate: bool = False,
    include_sensitive_paths: bool = False,
) -> int:
    evidence = collect_distribution_artifact_probe(
        app_path,
        dmg_path,
        hash_dmg=hash_dmg,
        spctl=spctl,
        stapler_validate=stapler_validate,
        include_sensitive_paths=include_sensitive_paths,
    )
    if json_output:
        print(json.dumps(evidence, ensure_ascii=False, indent=2))
    else:
        print("distribution artifact probe")
        print(f"- probe status: {evidence['probe']['status']}")
        print(f"- distribution requirements: {evidence['distribution_requirements']['status']}")
        print(f"- release gate: {evidence['release_gate']}")
        print(f"- closes residual: {str(evidence['closes_residual']).lower()}")
        print(f"- app: {evidence['target']['app']['absolute_path']}")
        print(f"- dmg: {evidence['target']['dmg']['absolute_path']}")
        print(f"- artifact content read attempted: {evidence['side_effects']['artifact_content_read_attempted']}")
        print(f"- full dmg hash read attempted: {evidence['side_effects']['full_dmg_hash_read_attempted']}")
        print(f"- notary submit attempted: {evidence['side_effects']['notary_submit_attempted']}")
        print(f"- staple attempted: {evidence['side_effects']['staple_attempted']}")
        print("- does not prove release readiness")
        if evidence["blocked_by"]:
            print(f"- blocked by: {', '.join(evidence['blocked_by'])}")
    if evidence["status"] != "captured":
        return 1
    return 0 if evidence["distribution_requirements"]["status"] == "pass" else 1


def default_readiness_build_number(now: datetime | None = None) -> str:
    """Return the timestamp-style build number used for local readiness builds."""

    return (now or datetime.now()).strftime("%Y%m%d%H%M")


def _readiness_xcodebuild_command(
    root: Path,
    *,
    build_number: str,
    derived_data_path: Path,
    destination: str,
) -> list[str]:
    return [
        "xcodebuild",
        "-project",
        str(root / "apps/macos/AreaMatrix.xcodeproj"),
        "-scheme",
        "AreaMatrix",
        "-configuration",
        "Release",
        "-destination",
        destination,
        "-derivedDataPath",
        str(derived_data_path),
        "CODE_SIGNING_ALLOWED=YES",
        "CODE_SIGN_STYLE=Manual",
        "CODE_SIGN_IDENTITY=-",
        "DEVELOPMENT_TEAM=",
        f"CURRENT_PROJECT_VERSION={build_number}",
        "build",
    ]


def _plist_value(app_path: Path, key: str) -> str:
    proc = _run_capture(["/usr/libexec/PlistBuddy", "-c", f"Print :{key}", app_path / "Contents/Info.plist"])
    if proc.returncode != 0:
        fail(f"unable to read {key} from {app_path}: {(proc.stdout or '').strip()}", proc.returncode)
    return (proc.stdout or "").strip()


def _sha256(path: Path) -> str:
    proc = _run_capture(["shasum", "-a", "256", path])
    if proc.returncode != 0:
        fail(f"unable to hash {path}.", proc.returncode)
    return (proc.stdout or "").split()[0]


def _codesign_summary(app_path: Path) -> list[str]:
    proc = _run_capture(["codesign", "-dv", "--verbose=2", app_path])
    lines: list[str] = []
    for line in (proc.stdout or "").splitlines():
        if line.startswith(("Identifier=", "Signature=", "TeamIdentifier=")):
            lines.append(line)
    return lines


def _verify_app_signature(app_path: Path) -> None:
    proc = _run_capture(["codesign", "--verify", "--deep", "--strict", "--verbose=2", app_path])
    if proc.returncode != 0:
        fail(f"readiness app bundle codesign verification failed: {(proc.stdout or '').strip()}", proc.returncode)


def _verify_app_is_self_contained(app_path: Path) -> None:
    executable = app_path / "Contents/MacOS/AreaMatrix"
    proc = _run_capture(["otool", "-L", executable])
    if proc.returncode != 0:
        fail(f"unable to inspect readiness app dependencies: {(proc.stdout or '').strip()}", proc.returncode)
    if "libarea_matrix_core.dylib" in (proc.stdout or ""):
        fail("readiness app links libarea_matrix_core.dylib; rebuild with the static core archive before distribution.")


def _is_area_matrix_running() -> bool:
    proc = subprocess.run(["pgrep", "-x", "AreaMatrix"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return proc.returncode == 0


def _quit_area_matrix_for_install() -> None:
    if not _is_area_matrix_running():
        return
    print("==> AreaMatrix is running; asking it to quit before install")
    subprocess.run(
        ["osascript", "-e", 'tell application "AreaMatrix" to quit'],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    for _ in range(20):
        if not _is_area_matrix_running():
            return
        import time

        time.sleep(0.5)
    fail("AreaMatrix is still running. Quit it manually, then rerun with --install.")


def _install_app_bundle(app_path: Path, applications_dir: Path) -> Path:
    require_command("ditto")
    if not app_path.is_dir():
        fail(f"readiness app bundle not found at {app_path}.")
    if not applications_dir.is_dir():
        fail(f"Applications directory not found at {applications_dir}.")

    _quit_area_matrix_for_install()

    destination = applications_dir / "AreaMatrix.app"
    # Reserve both names atomically.  A PID is not an ownership boundary: a
    # previous process (or another user) may have left a sibling with the same
    # suffix, so never remove a predictable path before using it.
    temp_root = _reserve_install_root(applications_dir, ".AreaMatrix.app.readiness-")
    backup_root: Path | None = None
    try:
        backup_root = _reserve_install_root(applications_dir, ".AreaMatrix.app.previous-")
        temp_destination = temp_root / destination.name
        backup_destination = backup_root / destination.name

        proc = _run_capture(["ditto", app_path, temp_destination])
        if proc.returncode != 0:
            fail(f"unable to copy app bundle to temporary install path: {(proc.stdout or '').strip()}", proc.returncode)

        moved_to_backup = False
        try:
            if destination.exists():
                if backup_destination.exists():
                    fail(f"refusing to overwrite an unexpected backup path: {backup_destination}")
                destination.rename(backup_destination)
                moved_to_backup = True
            temp_destination.rename(destination)
        except OSError as exc:
            if moved_to_backup and backup_destination.exists() and not destination.exists():
                backup_destination.rename(destination)
            fail(f"unable to install {destination}: {exc}")
        finally:
            _remove_owned_install_path(temp_root)

        _remove_owned_install_path(backup_root)
        backup_root = None
        return destination
    finally:
        _remove_owned_install_path(temp_root)
        if backup_root is not None and not (backup_root / destination.name).exists():
            _remove_owned_install_path(backup_root)


def _reserve_install_root(applications_dir: Path, prefix: str) -> Path:
    """Create a private unique directory; its contents are owned by this call."""

    return Path(tempfile.mkdtemp(prefix=prefix, dir=applications_dir))


def _remove_owned_install_path(path: Path) -> None:
    """Remove only the path reserved by this invocation, if it still exists."""

    try:
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        else:
            path.unlink()
    except FileNotFoundError:
        pass


def _require_readiness_install_confirmation(install: bool, applications_dir: str | Path, install_confirm: str | None) -> None:
    if not install:
        return
    expected = str(Path(applications_dir) / "AreaMatrix.app")
    if install_confirm == expected:
        return
    fail(
        "readiness-build --install replaces "
        f"{expected}; rerun with --install-confirm {command_text([expected])} to confirm this local app write."
    )


def _print_readiness_summary(label: str, app_path: Path) -> None:
    executable = app_path / "Contents/MacOS/AreaMatrix"
    print(f"{label}: {app_path}")
    print(f"- app version: {_plist_value(app_path, 'CFBundleShortVersionString')}")
    print(f"- build number: {_plist_value(app_path, 'CFBundleVersion')}")
    print(f"- executable sha256: {_sha256(executable)}")
    for line in _codesign_summary(app_path):
        print(f"- {line}")


def run_release_readiness_build(
    root: Path,
    *,
    install: bool = False,
    build_number: str | None = None,
    derived_data_path: str | Path = DEFAULT_READINESS_BUILD_DERIVED_DATA,
    destination: str = DEFAULT_READINESS_BUILD_DESTINATION,
    applications_dir: str | Path = DEFAULT_APPLICATIONS_DIR,
    install_confirm: str | None = None,
) -> int:
    build_number = build_number or default_readiness_build_number()
    if not re.fullmatch(r"\d{12}", build_number):
        fail("readiness build number must use YYYYMMDDHHMM format.")
    _require_readiness_install_confirmation(install, applications_dir, install_confirm)

    require_command("xcodebuild")
    require_command("codesign")
    require_command("shasum")

    derived_data = Path(derived_data_path)
    if not derived_data.is_absolute():
        derived_data = root / derived_data

    print("AreaMatrix release readiness build")
    print(f"- build number: {build_number}")
    print("- signing: adhoc / local readiness only")
    print("- notarization: skipped")

    rc = run_step(
        _readiness_xcodebuild_command(
            root,
            build_number=build_number,
            derived_data_path=derived_data,
            destination=destination,
        ),
        check=False,
    ).returncode
    if rc != 0:
        return rc

    app_path = derived_data / "Build/Products/Release/AreaMatrix.app"
    if not app_path.is_dir():
        fail(f"xcodebuild succeeded but app bundle was not found at {app_path}.")

    _verify_app_signature(app_path)
    _verify_app_is_self_contained(app_path)

    print()
    _print_readiness_summary("readiness app", app_path)

    if install:
        installed_path = _install_app_bundle(app_path, Path(applications_dir))
        print()
        _print_readiness_summary("installed app", installed_path)

    print()
    print("release readiness build: PASS")
    print("distribution release: BLOCKED until Developer ID signing and notarization are configured")
    return 0
