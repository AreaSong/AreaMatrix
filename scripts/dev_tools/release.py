"""Release distribution and local readiness build helpers behind ./dev."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import json
import stat
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Sequence

from .common import command_text, fail, require_command, run_step


DEFAULT_NOTARY_PROFILE = "AC_PASSWORD"
DEFAULT_READINESS_BUILD_DERIVED_DATA = "build/ReleaseReadiness"
DEFAULT_READINESS_BUILD_DESTINATION = "platform=macOS,arch=arm64"
DEFAULT_APPLICATIONS_DIR = "/Applications"
ICLOUD_MDLS_FIELDS = [
    "kMDItemUbiquitousItemDownloadingStatus",
    "kMDItemUbiquitousItemIsDownloaded",
    "kMDItemUbiquitousItemIsUploaded",
    "kMDItemUbiquitousItemHasUnresolvedConflicts",
    "kMDItemFSName",
]


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
        "evidence_record_template": {
            "developer_id_identity": "pending | pass | blocked",
            "codesign_developer_id_team": "pending | pass | blocked",
            "notarytool_submission": "pending | accepted | blocked",
            "stapler_validation": "pending | pass | blocked",
            "formal_dmg_sha256": "<sha256>",
            "clean_mac_first_launch": "pending | pass | blocked",
            "release_gate": "block_if_any_pending_or_blocked",
        },
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


def collect_icloud_placeholder_evidence(path: Path) -> dict[str, Any]:
    absolute_path = _absolute_input_path(path)
    path_lexists = os.path.lexists(absolute_path)
    target: dict[str, Any] = {
        "input_path": str(path),
        "absolute_path": str(absolute_path),
        "exists": absolute_path.exists(),
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

    return {
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


def run_icloud_placeholder_evidence(path: Path, *, json_output: bool = False) -> int:
    evidence = collect_icloud_placeholder_evidence(path)
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
        f"LIBRARY_SEARCH_PATHS={root / 'core/target/aarch64-apple-darwin/release'}",
        f"OTHER_LDFLAGS={root / 'core/target/aarch64-apple-darwin/release/libarea_matrix_core.a'}",
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
    temp_destination = applications_dir / f".AreaMatrix.app.readiness-{os.getpid()}"
    backup_destination = applications_dir / f".AreaMatrix.app.previous-{os.getpid()}"

    shutil.rmtree(temp_destination, ignore_errors=True)
    shutil.rmtree(backup_destination, ignore_errors=True)

    proc = _run_capture(["ditto", app_path, temp_destination])
    if proc.returncode != 0:
        fail(f"unable to copy app bundle to temporary install path: {(proc.stdout or '').strip()}", proc.returncode)

    try:
        if destination.exists():
            destination.rename(backup_destination)
        temp_destination.rename(destination)
    except OSError as exc:
        if backup_destination.exists() and not destination.exists():
            backup_destination.rename(destination)
        fail(f"unable to install {destination}: {exc}")
    finally:
        shutil.rmtree(temp_destination, ignore_errors=True)

    shutil.rmtree(backup_destination, ignore_errors=True)
    return destination


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
) -> int:
    require_command("xcodebuild")
    require_command("codesign")
    require_command("shasum")

    build_number = build_number or default_readiness_build_number()
    if not re.fullmatch(r"\d{12}", build_number):
        fail("readiness build number must use YYYYMMDDHHMM format.")

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
