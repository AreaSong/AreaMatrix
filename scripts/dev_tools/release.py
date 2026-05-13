"""Release distribution preflight checks behind ./dev."""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

from .common import command_text, require_command


DEFAULT_NOTARY_PROFILE = "AC_PASSWORD"


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
