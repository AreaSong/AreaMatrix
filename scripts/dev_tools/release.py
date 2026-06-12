"""Release distribution and local QA build helpers behind ./dev."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Sequence

from .common import command_text, fail, require_command, run_step


DEFAULT_NOTARY_PROFILE = "AC_PASSWORD"
DEFAULT_LOCAL_QA_DERIVED_DATA = "build/ReleaseReadiness"
DEFAULT_LOCAL_QA_DESTINATION = "platform=macOS,arch=arm64"
DEFAULT_APPLICATIONS_DIR = "/Applications"


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


def run_release_preflight(root: Path, *, notary_profile: str = DEFAULT_NOTARY_PROFILE) -> int:
    del root
    checks = [
        check_developer_id_identity(),
        check_notary_profile(notary_profile),
    ]

    print("Stage 1 release distribution preflight")
    for check in checks:
        print(f"- {check.status}: {check.name} - {check.detail}")

    if all(check.passed for check in checks):
        print("release distribution preflight: PASS")
        return 0

    print("release distribution preflight: BLOCKED")
    return 1


def default_local_qa_build_number(now: datetime | None = None) -> str:
    """Return the timestamp-style build number used for local QA builds."""

    return (now or datetime.now()).strftime("%Y%m%d%H%M")


def _local_qa_xcodebuild_command(
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
        "CODE_SIGNING_ALLOWED=NO",
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
        fail(f"local QA app bundle not found at {app_path}.")
    if not applications_dir.is_dir():
        fail(f"Applications directory not found at {applications_dir}.")

    _quit_area_matrix_for_install()

    destination = applications_dir / "AreaMatrix.app"
    temp_destination = applications_dir / f".AreaMatrix.app.local-qa-{os.getpid()}"
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


def _print_local_qa_summary(label: str, app_path: Path) -> None:
    executable = app_path / "Contents/MacOS/AreaMatrix"
    print(f"{label}: {app_path}")
    print(f"- app version: {_plist_value(app_path, 'CFBundleShortVersionString')}")
    print(f"- build number: {_plist_value(app_path, 'CFBundleVersion')}")
    print(f"- executable sha256: {_sha256(executable)}")
    for line in _codesign_summary(app_path):
        print(f"- {line}")


def run_release_local_qa(
    root: Path,
    *,
    install: bool = False,
    build_number: str | None = None,
    derived_data_path: str | Path = DEFAULT_LOCAL_QA_DERIVED_DATA,
    destination: str = DEFAULT_LOCAL_QA_DESTINATION,
    applications_dir: str | Path = DEFAULT_APPLICATIONS_DIR,
) -> int:
    require_command("xcodebuild")
    require_command("codesign")
    require_command("shasum")

    build_number = build_number or default_local_qa_build_number()
    if not re.fullmatch(r"\d{12}", build_number):
        fail("local QA build number must use YYYYMMDDHHMM format.")

    derived_data = Path(derived_data_path)
    if not derived_data.is_absolute():
        derived_data = root / derived_data

    print("AreaMatrix local QA release build")
    print(f"- build number: {build_number}")
    print("- signing: adhoc / local QA only")
    print("- notarization: skipped")

    rc = run_step(
        _local_qa_xcodebuild_command(
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

    print()
    _print_local_qa_summary("local QA app", app_path)

    if install:
        installed_path = _install_app_bundle(app_path, Path(applications_dir))
        print()
        _print_local_qa_summary("installed app", installed_path)

    print()
    print("local QA build: PASS")
    print("distribution release: BLOCKED until Developer ID signing and notarization are configured")
    return 0
