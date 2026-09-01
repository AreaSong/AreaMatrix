#!/usr/bin/env python3
"""Generate and verify artifact-specific release supply-chain materials."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Sequence
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[2]
REQUIRED_REVIEW_SCOPE = {"licenses", "notices", "source-offer"}
BASE_MATERIALS = {"sbom.cdx.json", "THIRD_PARTY_NOTICES.md", "source-offer.json"}
EXPECTED_INTER_INPUT_SHA256 = "2ad83f2446566c5ecf7c261cc07884a5d5f71965b5df8fd7bb809f83a42bf470"
EXPECTED_INTER_UPSTREAM_COMMIT = "0a5106e0bde18df09374066bf3a7998e3546307d"
EXPECTED_INTER_UPSTREAM_SOURCE = (
    "https://github.com/rsms/inter/commit/0a5106e0bde18df09374066bf3a7998e3546307d"
)
EXPECTED_INTER_SOURCE_ARTIFACT = {
    "type": "github-blob",
    "owner": "linagora",
    "repository": "tmail-flutter",
    "commit": "0e6c107f63e4fd35615605b718963ffa6b2897a4",
    "path": "assets/fonts/Inter/Inter-Bold.ttf",
    "sha256": EXPECTED_INTER_INPUT_SHA256,
    "url": (
        "https://github.com/linagora/tmail-flutter/blob/"
        "0e6c107f63e4fd35615605b718963ffa6b2897a4/assets/fonts/Inter/Inter-Bold.ttf"
    ),
}
NATIVE_RELEASE_TARGETS = {
    "x86_64-pc-windows-msvc": {
        "platform": "windows",
        "manifest": "apps/windows/AreaMatrix/native-core.manifest.json",
        "rid": "win-x64",
        "architecture": "x64",
        "fileName": "area_matrix_core.dll",
    },
    "aarch64-pc-windows-msvc": {
        "platform": "windows",
        "manifest": "apps/windows/AreaMatrix/native-core.manifest.json",
        "rid": "win-arm64",
        "architecture": "arm64",
        "fileName": "area_matrix_core.dll",
    },
    "x86_64-unknown-linux-gnu": {
        "platform": "linux",
        "manifest": "apps/linux/AreaMatrix/native-core.manifest.json",
        "rid": "linux-x64",
        "architecture": "x64",
        "fileName": "libarea_matrix_core.so",
    },
    "aarch64-unknown-linux-gnu": {
        "platform": "linux",
        "manifest": "apps/linux/AreaMatrix/native-core.manifest.json",
        "rid": "linux-arm64",
        "architecture": "arm64",
        "fileName": "libarea_matrix_core.so",
    },
}
UNUSABLE_PROVENANCE_VALUES = {"", "none", "null", "unavailable", "unknown"}
# Cargo metadata accepts a few legacy slash spellings that are not valid SPDX expressions.
SPDX_NORMALIZATIONS = {
    "MIT/Apache-2.0": "MIT OR Apache-2.0",
    "Unlicense/MIT": "Unlicense OR MIT",
}
EVIDENCE_STATUS = "technical-materials-generated-review-required"
INVENTORY_BASIS = "current-checkout-locked-target-filtered-cargo-and-nuget-metadata"
EVIDENCE_LIMITATIONS = [
    "Cargo components come from the current checkout's cargo metadata --locked --filter-platform output, not artifact inspection.",
    "NuGet components are included only for Windows targets and come from packages.lock.json; the lock file does not provide package license metadata or prove package contents.",
    "The materials do not prove that the artifact was built from the recorded commit or contains no additional components.",
    "The materials do not prove that assets/brand/archive is absent from the packaged artifact.",
    "The materials do not prove signing, notarization, legal approval, or source-offer sufficiency.",
]


class SupplyChainError(RuntimeError):
    """Raised when release supply-chain evidence is incomplete."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_relative_path(root: Path, relative: str) -> Path:
    if not relative or Path(relative).is_absolute():
        raise SupplyChainError("artifact and review paths must be non-empty relative paths")
    # Resolve only after inspecting the lexical path.  Calling resolve() first
    # would erase an in-tree symlink and make a later is_symlink() check
    # ineffective.  Ancestors above the declared root are intentionally not
    # inspected so macOS aliases such as /tmp -> /private/tmp remain usable.
    lexical_root = root.absolute()
    if lexical_root.is_symlink():
        raise SupplyChainError(f"declared root must not be a symlink: {root}")
    lexical_candidate = lexical_root
    for component in Path(relative).parts:
        if component in ("", "."):
            continue
        lexical_candidate /= component
        if lexical_candidate.is_symlink():
            raise SupplyChainError(f"path contains a symlink: {lexical_candidate}")
    resolved_root = root.resolve(strict=True)
    candidate = (resolved_root / relative).resolve(strict=True)
    try:
        candidate.relative_to(resolved_root)
    except ValueError as error:
        raise SupplyChainError(f"path escapes declared root: {relative}") from error
    return candidate


def artifact_identity(path: Path) -> dict[str, Any]:
    if path.is_file():
        return {
            "kind": "file",
            "name": path.name,
            "sha256": sha256_file(path),
            "size": path.stat().st_size,
        }
    if not path.is_dir():
        raise SupplyChainError(f"artifact is not a regular file or directory: {path}")
    return directory_identity(path)


def directory_identity(path: Path) -> dict[str, Any]:
    digest = hashlib.sha256()
    entries: list[dict[str, Any]] = []
    for child in sorted(path.rglob("*")):
        relative = child.relative_to(path).as_posix()
        if child.is_symlink():
            target = os.readlink(child)
            resolved = child.resolve(strict=True)
            try:
                resolved.relative_to(path.resolve())
            except ValueError as error:
                raise SupplyChainError(f"artifact symlink escapes bundle: {relative} -> {target}") from error
            record = {"path": relative, "kind": "symlink", "target": target}
        elif child.is_file():
            record = {
                "path": relative,
                "kind": "file",
                "sha256": sha256_file(child),
                "size": child.stat().st_size,
            }
        elif child.is_dir():
            continue
        else:
            raise SupplyChainError(f"unsupported artifact entry: {relative}")
        encoded = json.dumps(record, sort_keys=True, separators=(",", ":")).encode("utf-8")
        digest.update(encoded + b"\n")
        entries.append(record)
    return {
        "kind": "directory",
        "name": path.name,
        "sha256": digest.hexdigest(),
        "entryCount": len(entries),
        "entries": entries,
    }


def command_output(argv: Sequence[str], *, cwd: Path) -> str:
    process = subprocess.run(
        list(argv),
        cwd=cwd,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if process.returncode != 0:
        detail = (process.stderr or process.stdout).strip()
        raise SupplyChainError(f"command failed ({process.returncode}): {' '.join(argv)}: {detail}")
    return process.stdout


def parse_lock_checksums(path: Path) -> dict[tuple[str, str, str], str]:
    records: dict[tuple[str, str, str], str] = {}
    for block in path.read_text(encoding="utf-8").split("[[package]]")[1:]:
        fields: dict[str, str] = {}
        for key in ("name", "version", "source", "checksum"):
            match = re.search(rf'^\s*{key}\s*=\s*"([^"]+)"', block, re.MULTILINE)
            if match:
                fields[key] = match.group(1)
        if all(key in fields for key in ("name", "version", "source", "checksum")):
            records[(fields["name"], fields["version"], fields["source"])] = fields["checksum"]
    return records


def normalize_license_expression(value: str) -> str:
    expression = value.strip()
    normalized = SPDX_NORMALIZATIONS.get(expression, expression)
    if "/" in normalized:
        raise SupplyChainError(f"Cargo package license is not a valid SPDX expression: {value}")
    return normalized


def license_material_paths(root: Path) -> list[Path]:
    try:
        license_root = safe_relative_path(root, "licenses")
    except SupplyChainError as error:
        raise SupplyChainError("repository license directory is missing or is a symlink") from error
    if not license_root.is_dir() or license_root.is_symlink():
        raise SupplyChainError("repository license directory is missing or is a symlink")
    entries = list(license_root.rglob("*"))
    if any(path.is_symlink() for path in entries):
        raise SupplyChainError("repository license directory must contain regular files only")
    paths = sorted(path for path in entries if path.is_file())
    if not paths or any(not path.is_file() for path in entries if not path.is_dir()):
        raise SupplyChainError("repository license directory must contain regular files only")
    return paths


def cargo_components(root: Path, targets: Sequence[str]) -> list[dict[str, Any]]:
    packages: dict[tuple[str, str, str | None], dict[str, Any]] = {}
    for target in targets:
        output = command_output(
            [
                "cargo",
                "metadata",
                "--locked",
                "--format-version",
                "1",
                "--filter-platform",
                target,
                "--manifest-path",
                "core/Cargo.toml",
            ],
            cwd=root,
        )
        metadata = json.loads(output)
        resolved_ids = {node["id"] for node in metadata["resolve"]["nodes"]}
        for package in metadata["packages"]:
            if package["id"] not in resolved_ids:
                continue
            key = (package["name"], package["version"], package.get("source"))
            packages[key] = package
    checksums = parse_lock_checksums(root / "core/Cargo.lock")
    return [component_record(package, checksums, root) for package in sorted(packages.values(), key=package_key)]


def release_components(root: Path, targets: Sequence[str]) -> list[dict[str, Any]]:
    components = cargo_components(root, targets)
    if any(
        target in NATIVE_RELEASE_TARGETS
        and NATIVE_RELEASE_TARGETS[target]["platform"] == "windows"
        for target in targets
    ):
        components.extend(nuget_components(root))
    return sorted(components, key=lambda item: str(item.get("purl", "")))


def nuget_components(root: Path) -> list[dict[str, Any]]:
    lock_path = root / "apps/windows/AreaMatrix/packages.lock.json"
    try:
        data = json.loads(lock_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SupplyChainError("Windows packages.lock.json is missing or invalid") from error
    if data.get("version") != 1 or not isinstance(data.get("dependencies"), dict):
        raise SupplyChainError("Windows packages.lock.json has an unsupported schema")

    packages: dict[str, dict[str, Any]] = {}
    for framework, entries in data["dependencies"].items():
        if not isinstance(framework, str) or not isinstance(entries, dict):
            raise SupplyChainError("Windows packages.lock.json has an invalid dependency group")
        for name, locked in entries.items():
            if not isinstance(name, str) or not isinstance(locked, dict):
                raise SupplyChainError("Windows packages.lock.json has an invalid package record")
            resolved = locked.get("resolved")
            content_hash = locked.get("contentHash")
            dependency_type = locked.get("type")
            if not isinstance(resolved, str) or not resolved:
                raise SupplyChainError(f"NuGet package lacks resolved version: {name}")
            if not isinstance(content_hash, str) or not content_hash:
                raise SupplyChainError(f"NuGet package lacks contentHash: {name} {resolved}")
            if dependency_type not in {"Direct", "Transitive"}:
                raise SupplyChainError(f"NuGet package has invalid dependency type: {name} {resolved}")
            key = name.casefold()
            existing = packages.setdefault(
                key,
                {
                    "name": name,
                    "version": resolved,
                    "contentHash": content_hash,
                    "frameworks": set(),
                    "dependencyTypes": set(),
                },
            )
            if existing["version"] != resolved or existing["contentHash"] != content_hash:
                raise SupplyChainError(f"NuGet package lock drift across target groups: {name}")
            existing["frameworks"].add(framework)
            existing["dependencyTypes"].add(dependency_type)
    return [nuget_component_record(package) for package in sorted(packages.values(), key=lambda item: item["name"].casefold())]


def nuget_component_record(package: dict[str, Any]) -> dict[str, Any]:
    try:
        digest = base64.b64decode(package["contentHash"], validate=True)
    except (ValueError, TypeError) as error:
        raise SupplyChainError(
            f"NuGet package contentHash is not valid base64: {package['name']} {package['version']}"
        ) from error
    if len(digest) != 64:
        raise SupplyChainError(
            f"NuGet package contentHash is not SHA-512: {package['name']} {package['version']}"
        )
    name = str(package["name"])
    version = str(package["version"])
    lower_name = name.lower()
    return {
        "type": "library",
        "name": name,
        "version": version,
        "licenses": [{"expression": "NOASSERTION"}],
        "purl": f"pkg:nuget/{name}@{version}",
        "hashes": [{"alg": "SHA-512", "content": digest.hex()}],
        "externalReferences": [
            {
                "type": "distribution",
                "url": f"https://api.nuget.org/v3-flatcontainer/{lower_name}/{version}/{lower_name}.{version}.nupkg",
            }
        ],
        "properties": [
            {"name": "areamatrix:ecosystem", "value": "nuget"},
            {
                "name": "areamatrix:dependencyTypes",
                "value": ",".join(sorted(package["dependencyTypes"])),
            },
            {
                "name": "areamatrix:targetFrameworks",
                "value": ",".join(sorted(package["frameworks"])),
            },
            {
                "name": "areamatrix:licenseEvidence",
                "value": "not-present-in-packages-lock; qualified review required",
            },
        ],
    }


def package_key(package: dict[str, Any]) -> tuple[str, str, str]:
    return package["name"], package["version"], package.get("source") or ""


def component_record(
    package: dict[str, Any],
    checksums: dict[tuple[str, str, str], str],
    root: Path,
) -> dict[str, Any]:
    license_expression = package.get("license")
    if not isinstance(license_expression, str) or not license_expression:
        raise SupplyChainError(f"Cargo package lacks license expression: {package['name']} {package['version']}")
    license_expression = normalize_license_expression(license_expression)
    source = package.get("source")
    record: dict[str, Any] = {
        "type": "library",
        "name": package["name"],
        "version": package["version"],
        "licenses": [{"expression": license_expression}],
        "purl": f"pkg:cargo/{package['name']}@{package['version']}",
    }
    if source:
        record["externalReferences"] = [{"type": "distribution", "url": source}]
        checksum = checksums.get((package["name"], package["version"], source))
        if source.startswith("registry+") and not checksum:
            raise SupplyChainError(f"registry package lacks Cargo.lock checksum: {package['name']} {package['version']}")
        if checksum:
            record["hashes"] = [{"alg": "SHA-256", "content": checksum}]
    else:
        record["externalReferences"] = [{"type": "vcs", "url": repository_source(root)}]
    if package.get("repository"):
        record["externalReferences"].append({"type": "vcs", "url": package["repository"]})
    return record


def repository_source(root: Path) -> str:
    commit = command_output(["git", "rev-parse", "HEAD"], cwd=root).strip()
    remote = command_output(["git", "remote", "get-url", "origin"], cwd=root).strip()
    return f"{remote}@{commit}"


def validate_native_release_targets(root: Path, targets: Sequence[str]) -> None:
    requested = [NATIVE_RELEASE_TARGETS[target] for target in targets if target in NATIVE_RELEASE_TARGETS]
    unsupported = [
        target
        for target in targets
        if ("windows" in target or "linux" in target) and target not in NATIVE_RELEASE_TARGETS
    ]
    if unsupported:
        raise SupplyChainError(f"unsupported native release target: {', '.join(sorted(unsupported))}")
    if not requested:
        return

    expected_commit = command_output(["git", "rev-parse", "HEAD"], cwd=root).strip()
    manifests: dict[str, dict[str, Any]] = {}
    for spec in requested:
        manifest_relative = str(spec["manifest"])
        if manifest_relative not in manifests:
            manifests[manifest_relative] = load_native_release_manifest(
                root,
                manifest_relative,
                expected_commit,
            )
        manifest = manifests[manifest_relative]
        matching = [
            artifact
            for artifact in manifest["artifacts"]
            if artifact.get("rid") == spec["rid"]
            and artifact.get("architecture") == spec["architecture"]
            and artifact.get("fileName") == spec["fileName"]
        ]
        if len(matching) != 1:
            raise SupplyChainError(
                f"native release manifest must contain exactly one {spec['rid']} {spec['fileName']} artifact"
            )


def load_native_release_manifest(root: Path, relative: str, expected_commit: str) -> dict[str, Any]:
    resolved_root = root.resolve(strict=True)
    path = safe_relative_path(root, relative)
    if path.is_symlink() or not path.is_file():
        raise SupplyChainError(f"native release manifest is not a regular file: {relative}")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise SupplyChainError(f"native release manifest is unreadable or invalid: {relative}") from error
    if not isinstance(data, dict) or data.get("schemaVersion") != 1 or data.get("status") != "approved":
        raise SupplyChainError(f"native release manifest is not approved: {relative}")
    if data.get("sourceCommit") != expected_commit or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", expected_commit):
        raise SupplyChainError(f"native release manifest is not bound to the current commit: {relative}")
    for field in ("buildCommand", "license", "sbom"):
        value = data.get(field)
        if not isinstance(value, str) or value.strip().lower() in UNUSABLE_PROVENANCE_VALUES:
            raise SupplyChainError(f"native release manifest has unusable {field}: {relative}")
    if data["license"] != "../../../LICENSE" or not (root / "LICENSE").is_file():
        raise SupplyChainError(f"native release manifest license material is not bound to LICENSE: {relative}")
    sbom_relative = Path(data["sbom"])
    if sbom_relative.is_absolute() or ".." in sbom_relative.parts:
        raise SupplyChainError(f"native release manifest SBOM path is unsafe: {relative}")
    sbom_path = safe_relative_path(
        resolved_root,
        (path.parent / sbom_relative).relative_to(resolved_root).as_posix(),
    )
    if sbom_path.is_symlink() or not sbom_path.is_file():
        raise SupplyChainError(f"native release manifest SBOM is missing: {relative}")

    artifacts = data.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        raise SupplyChainError(f"native release manifest has no release artifacts: {relative}")
    seen: set[tuple[str, str, str]] = set()
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            raise SupplyChainError(f"native release manifest artifact is invalid: {relative}")
        rid = artifact.get("rid")
        architecture = artifact.get("architecture")
        file_name = artifact.get("fileName")
        sha256 = artifact.get("sha256")
        key = (str(rid), str(architecture), str(file_name))
        if (
            not isinstance(rid, str)
            or not isinstance(architecture, str)
            or not isinstance(file_name, str)
            or Path(file_name).name != file_name
            or not isinstance(sha256, str)
            or not re.fullmatch(r"[0-9a-f]{64}", sha256)
            or key in seen
        ):
            raise SupplyChainError(f"native release manifest artifact is invalid or duplicated: {relative}")
        binary_relative = (
            path.parent / "runtimes" / rid / "native" / file_name
        ).relative_to(resolved_root).as_posix()
        binary = safe_relative_path(resolved_root, binary_relative)
        if binary.is_symlink() or not binary.is_file() or sha256_file(binary) != sha256:
            raise SupplyChainError(f"native release artifact is missing or hash-mismatched: {binary_relative}")
        seen.add(key)
    return data


def generated_at() -> str:
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    timestamp = datetime.fromtimestamp(int(epoch), timezone.utc) if epoch else datetime.now(timezone.utc)
    return timestamp.isoformat().replace("+00:00", "Z")


def parse_timestamp(value: Any, field: str) -> datetime:
    if not isinstance(value, str) or not value:
        raise SupplyChainError(f"{field} must be a non-empty ISO-8601 timestamp")
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        timestamp = datetime.fromisoformat(normalized)
    except ValueError as error:
        raise SupplyChainError(f"{field} must be a valid ISO-8601 timestamp") from error
    if timestamp.tzinfo is None:
        raise SupplyChainError(f"{field} must include a timezone")
    return timestamp.astimezone(timezone.utc)


def load_brand_provenance(root: Path) -> tuple[dict[str, Any], str]:
    path = root / "assets/brand/provenance.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 1 or data.get("brand") != "AreaMatrix":
        raise SupplyChainError("brand provenance release policy is missing or invalid")
    policy = data.get("releasePolicy")
    if not isinstance(policy, dict):
        raise SupplyChainError("brand provenance release policy is missing or invalid")
    if policy.get("includedRoot") != "assets/brand/final" or policy.get("excludedRoots") != ["assets/brand/archive"]:
        raise SupplyChainError("brand archive must be excluded from release materials")
    if data.get("releaseEligible") is not False:
        raise SupplyChainError("brand provenance must remain release-ineligible")
    wordmark = data.get("wordmarkInput", {})
    required_wordmark = ("version", "source", "upstreamCommit", "license", "licenseFile", "sha256", "outlinePath", "outlineSha256")
    if not isinstance(wordmark, dict) or not all(wordmark.get(key) for key in required_wordmark):
        raise SupplyChainError("wordmark provenance lacks version, source, license, or input hash")
    if wordmark.get("sha256") != EXPECTED_INTER_INPUT_SHA256:
        raise SupplyChainError("wordmark provenance input hash does not match recorded evidence")
    if not re.fullmatch(r"[0-9a-f]{40}", str(wordmark["upstreamCommit"])):
        raise SupplyChainError("wordmark provenance upstream commit is not a full Git SHA")
    source_url = urlparse(str(wordmark["source"]))
    if source_url.scheme != "https" or source_url.hostname != "github.com":
        raise SupplyChainError("wordmark provenance source must be an HTTPS GitHub URL")
    if (
        wordmark.get("source") != EXPECTED_INTER_UPSTREAM_SOURCE
        or wordmark.get("upstreamCommit") != EXPECTED_INTER_UPSTREAM_COMMIT
    ):
        raise SupplyChainError("wordmark provenance upstream source or commit is not approved")
    if wordmark.get("sourceArtifact") != EXPECTED_INTER_SOURCE_ARTIFACT:
        raise SupplyChainError("wordmark provenance source artifact coordinates are not approved")
    license_path = safe_relative_path(root, str(wordmark["licenseFile"]))
    if license_path.is_symlink() or not license_path.is_file():
        raise SupplyChainError("wordmark provenance license file is not a regular repository file")
    license_hash = wordmark.get("licenseSha256")
    if not isinstance(license_hash, str) or not re.fullmatch(r"[0-9a-f]{64}", license_hash):
        raise SupplyChainError("wordmark provenance license hash is missing or malformed")
    if sha256_file(license_path) != license_hash:
        raise SupplyChainError("wordmark provenance license hash does not match the repository file")
    outline = root / "assets/brand/wordmark-outlines.json"
    if wordmark.get("outlinePath") != "assets/brand/wordmark-outlines.json" or outline.is_symlink() or not outline.is_file():
        raise SupplyChainError("wordmark outline provenance path is invalid")
    if wordmark.get("outlineSha256") != sha256_file(outline):
        raise SupplyChainError("wordmark outline hash does not match provenance")
    archive_root = root / "assets/brand/archive"
    archive_assets = data.get("archiveAssets")
    if not archive_root.is_dir() or archive_root.is_symlink() or not isinstance(archive_assets, list):
        raise SupplyChainError("brand archive provenance inventory is missing")
    if len(archive_assets) != 16:
        raise SupplyChainError("brand archive provenance must contain exactly 16 entries")
    seen: set[str] = set()
    for item in archive_assets:
        if not isinstance(item, dict):
            raise SupplyChainError("brand archive provenance entry is invalid")
        relative = item.get("path")
        if not isinstance(relative, str) or not relative.startswith("assets/brand/archive/"):
            raise SupplyChainError(f"brand archive provenance path is invalid: {relative}")
        file_path = safe_relative_path(root, relative)
        if file_path.is_symlink() or not file_path.is_file() or relative in seen:
            raise SupplyChainError(f"brand archive provenance file is invalid: {relative}")
        if item.get("status") != "evidence-blocked" or not re.fullmatch(r"[0-9a-f]{64}", str(item.get("sha256", ""))):
            raise SupplyChainError(f"brand archive provenance evidence is incomplete: {relative}")
        if sha256_file(file_path) != item["sha256"]:
            raise SupplyChainError(f"brand archive provenance hash mismatch: {relative}")
        seen.add(relative)
    actual = {
        path.relative_to(root).as_posix()
        for path in archive_root.rglob("*")
        if path.is_file() and not path.is_symlink()
    }
    if seen != actual:
        raise SupplyChainError("brand archive provenance inventory does not match repository files")
    return data, sha256_file(path)


def build_sbom(
    release: str,
    artifact: dict[str, Any],
    components: list[dict[str, Any]],
    targets: Sequence[str],
    timestamp: str,
) -> dict[str, Any]:
    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, artifact['sha256'])}",
        "version": 1,
        "metadata": {
            "timestamp": timestamp,
            "properties": [
                {"name": "areamatrix:evidenceStatus", "value": EVIDENCE_STATUS},
                {"name": "areamatrix:inventoryBasis", "value": INVENTORY_BASIS},
                {"name": "areamatrix:cargoTargets", "value": ",".join(sorted(targets))},
                {"name": "areamatrix:limitations", "value": json.dumps(EVIDENCE_LIMITATIONS)},
            ],
            "component": {
                "type": "application",
                "name": artifact["name"],
                "version": release,
                "hashes": [{"alg": "SHA-256", "content": artifact["sha256"]}],
            },
        },
        "components": components,
    }


def build_source_offer(
    root: Path,
    release: str,
    artifact: dict[str, Any],
    components: list[dict[str, Any]],
    targets: Sequence[str],
    license_materials: Sequence[str] = (),
) -> dict[str, Any]:
    result = {
        "schemaVersion": 1,
        "release": release,
        "artifactSha256": artifact["sha256"],
        "status": EVIDENCE_STATUS,
        "inventoryBasis": INVENTORY_BASIS,
        "cargoTargets": sorted(targets),
        "limitations": EVIDENCE_LIMITATIONS,
        "projectSource": repository_source(root),
        "cargoLockSha256": sha256_file(root / "core/Cargo.lock"),
        "licenseMaterials": sorted(license_materials),
        "components": [
            {
                "name": item["name"],
                "version": item["version"],
                "licenses": item["licenses"],
                "sources": item.get("externalReferences", []),
            }
            for item in components
        ],
        "legalReviewComplete": False,
    }
    if any(str(item.get("purl", "")).startswith("pkg:nuget/") for item in components):
        result["nugetLockSha256"] = sha256_file(root / "apps/windows/AreaMatrix/packages.lock.json")
    return result


def notices_text(
    root: Path,
    release: str,
    artifact: dict[str, Any],
    components: list[dict[str, Any]],
    targets: Sequence[str],
) -> str:
    base = (root / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8").rstrip()
    lines = [base, "", "## Current-Checkout Locked Dependency Metadata", ""]
    lines.append(f"Release: `{release}`  ")
    lines.append(f"Artifact SHA-256: `{artifact['sha256']}`")
    lines.append(f"Cargo targets: `{', '.join(sorted(targets))}`")
    lines.extend(["", "| Ecosystem | Component | Version | License |", "|---|---|---:|---|"])
    for item in components:
        license_expression = item["licenses"][0]["expression"].replace("|", "\\|")
        ecosystem = "NuGet" if str(item.get("purl", "")).startswith("pkg:nuget/") else "Cargo"
        lines.append(f"| {ecosystem} | `{item['name']}` | `{item['version']}` | `{license_expression}` |")
    lines.extend(
        [
            "",
            "This table is derived from the current checkout's locked, target-filtered Cargo metadata and, for Windows targets, packages.lock.json; it is not an inspection of the artifact contents.",
            "NuGet NOASSERTION entries mean the lock file contains no license expression; they require package metadata readback and qualified license review before distribution.",
            "It does not establish artifact-to-commit provenance, absence of additional components or archived brand assets, signing, notarization, legal approval, or source-offer sufficiency.",
            "",
        ]
    )
    return "\n".join(lines)


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def prepare_bundle_output(output: Path) -> None:
    """Require a fresh regular directory so stale evidence cannot be uploaded."""
    if output.exists():
        if output.is_symlink() or not output.is_dir():
            raise SupplyChainError("bundle output must be a regular directory")
        if any(output.iterdir()):
            raise SupplyChainError("bundle output directory must be empty")
        return
    output.mkdir(parents=True, exist_ok=False)


def copy_license_materials(root: Path, output: Path) -> list[str]:
    materials: list[str] = []
    for source in license_material_paths(root):
        relative = source.relative_to(root).as_posix()
        destination = output / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(source.read_bytes())
        materials.append(relative)
    return sorted(materials)


def generate_bundle(args: argparse.Namespace) -> int:
    artifact_root = Path(args.artifact_root)
    artifact_path = safe_relative_path(artifact_root, args.artifact_relative)
    validate_native_release_targets(ROOT, args.cargo_target)
    output = Path(args.output_dir)
    prepare_bundle_output(output)
    artifact = artifact_identity(artifact_path)
    if args.expected_artifact_sha256 and artifact["sha256"] != args.expected_artifact_sha256:
        raise SupplyChainError("artifact hash does not match the expected SHA-256")
    components = release_components(ROOT, args.cargo_target)
    _, provenance_hash = load_brand_provenance(ROOT)
    timestamp = generated_at()

    sbom_path = output / "sbom.cdx.json"
    notices_path = output / "THIRD_PARTY_NOTICES.md"
    source_offer_path = output / "source-offer.json"
    license_materials = copy_license_materials(ROOT, output)
    write_json(sbom_path, build_sbom(args.release, artifact, components, args.cargo_target, timestamp))
    notices_path.write_text(notices_text(ROOT, args.release, artifact, components, args.cargo_target), encoding="utf-8")
    write_json(
        source_offer_path,
        build_source_offer(ROOT, args.release, artifact, components, args.cargo_target, license_materials),
    )

    manifest = {
        "schemaVersion": 1,
        "release": args.release,
        "generatedAt": timestamp,
        "status": EVIDENCE_STATUS,
        "inventoryBasis": INVENTORY_BASIS,
        "limitations": EVIDENCE_LIMITATIONS,
        "repositorySource": repository_source(ROOT),
        "artifact": artifact,
        "cargoTargets": sorted(args.cargo_target),
        "brandProvenanceSha256": provenance_hash,
        "licenseMaterials": license_materials,
        "materials": {
            sbom_path.name: sha256_file(sbom_path),
            notices_path.name: sha256_file(notices_path),
            source_offer_path.name: sha256_file(source_offer_path),
        },
        "legalReviewComplete": False,
    }
    manifest["materials"].update(
        {
            relative: sha256_file(output / relative)
            for relative in license_materials
        }
    )
    manifest_path = output / "release-manifest.json"
    write_json(manifest_path, manifest)
    assert_exact_bundle_inventory(output, set(manifest["materials"]))
    print(f"supply-chain bundle generated for {artifact['name']} ({artifact['sha256']})")
    print(f"release manifest SHA-256: {sha256_file(manifest_path)}")
    print("legal review: PENDING; generation does not approve distribution")
    return 0


def verify_review(review: dict[str, Any], manifest: dict[str, Any], manifest_sha256: str) -> None:
    if review.get("status") != "approved":
        raise SupplyChainError("legal/license review status is not approved")
    if review.get("artifactSha256") != manifest["artifact"]["sha256"]:
        raise SupplyChainError("review record artifact hash does not match release manifest")
    if review.get("release") != manifest["release"]:
        raise SupplyChainError("review record release does not match release manifest")
    if review.get("manifestSha256") != manifest_sha256:
        raise SupplyChainError("review record manifest hash does not match release-manifest.json")
    scope = review.get("scope")
    if not isinstance(scope, list) or len(scope) != len(REQUIRED_REVIEW_SCOPE) or set(scope) != REQUIRED_REVIEW_SCOPE:
        raise SupplyChainError("review record scope must be exactly licenses, notices, and source-offer")
    reviewer = review.get("reviewer")
    if not isinstance(reviewer, str) or not reviewer or "<" in reviewer:
        raise SupplyChainError("review record field is missing or placeholder: reviewer")
    reviewed_at = parse_timestamp(review.get("reviewedAt"), "reviewedAt")
    generated_timestamp = parse_timestamp(manifest.get("generatedAt"), "release manifest generatedAt")
    if reviewed_at < generated_timestamp:
        raise SupplyChainError("reviewedAt predates the generated release manifest")
    evidence_url = review.get("evidenceUrl")
    if not isinstance(evidence_url, str) or "<" in evidence_url:
        raise SupplyChainError("review record field is missing or placeholder: evidenceUrl")
    parsed_evidence_url = urlparse(evidence_url)
    if parsed_evidence_url.scheme != "https" or not parsed_evidence_url.hostname:
        raise SupplyChainError("review record evidenceUrl must be an absolute HTTPS URL")


def verify_manifest_contract(manifest: dict[str, Any]) -> None:
    if manifest.get("schemaVersion") != 1:
        raise SupplyChainError("release manifest schema version is unsupported")
    if manifest.get("status") != EVIDENCE_STATUS or manifest.get("inventoryBasis") != INVENTORY_BASIS:
        raise SupplyChainError("release manifest evidence status or inventory basis is invalid")
    if manifest.get("limitations") != EVIDENCE_LIMITATIONS:
        raise SupplyChainError("release manifest limitations are missing or changed")
    if manifest.get("legalReviewComplete") is not False:
        raise SupplyChainError("generated release manifest must not claim completed legal review")
    materials = manifest.get("materials")
    license_materials = manifest.get("licenseMaterials")
    if not isinstance(license_materials, list) or not license_materials or not all(
        isinstance(name, str) for name in license_materials
    ):
        raise SupplyChainError("release manifest license material inventory is missing or invalid")
    if license_materials != sorted(license_materials) or len(set(license_materials)) != len(license_materials):
        raise SupplyChainError("release manifest license material inventory is missing or unsorted")
    if any(
        not isinstance(name, str)
        or not name.startswith("licenses/")
        or Path(name).is_absolute()
        or ".." in Path(name).parts
        for name in license_materials
    ):
        raise SupplyChainError("release manifest contains an invalid license material path")
    expected_materials = BASE_MATERIALS | set(license_materials)
    if not isinstance(materials, dict) or set(materials) != expected_materials:
        raise SupplyChainError("release manifest material inventory is incomplete or unexpected")
    if any(not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value) for value in materials.values()):
        raise SupplyChainError("release manifest contains a malformed material hash")
    parse_timestamp(manifest.get("generatedAt"), "release manifest generatedAt")


def bundle_inventory(bundle: Path) -> set[str]:
    """Return regular-file and directory entries, rejecting links/special files."""
    entries: set[str] = set()
    for path in bundle.rglob("*"):
        relative = path.relative_to(bundle).as_posix()
        if path.is_symlink():
            raise SupplyChainError(f"bundle entry must not be a symlink: {relative}")
        if not path.is_file() and not path.is_dir():
            raise SupplyChainError(f"bundle entry is not a regular file or directory: {relative}")
        entries.add(relative)
    return entries


def expected_bundle_inventory(materials: set[str]) -> set[str]:
    expected = set(materials) | {"release-manifest.json"}
    for material in list(expected):
        parent = Path(material).parent
        while parent != Path("."):
            expected.add(parent.as_posix())
            parent = parent.parent
    return expected


def assert_exact_bundle_inventory(bundle: Path, materials: set[str]) -> None:
    inventory = bundle_inventory(bundle)
    expected = expected_bundle_inventory(materials)
    if inventory != expected:
        unexpected = sorted(inventory - expected)
        missing = sorted(expected - inventory)
        raise SupplyChainError(
            f"bundle inventory does not match release manifest (unexpected={unexpected}, missing={missing})"
        )


def verify_brand_provenance(manifest: dict[str, Any], root: Path = ROOT) -> None:
    _, current_hash = load_brand_provenance(root)
    if current_hash != manifest.get("brandProvenanceSha256"):
        raise SupplyChainError("brand provenance no longer matches the generated release manifest")


def verify_bundle(args: argparse.Namespace) -> int:
    raw_bundle = Path(args.bundle_dir)
    if raw_bundle.is_symlink() or not raw_bundle.is_dir():
        raise SupplyChainError("bundle root must be a regular directory")
    bundle = raw_bundle.resolve(strict=True)
    manifest_path = safe_relative_path(bundle, "release-manifest.json")
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise SupplyChainError("release manifest must be a regular file")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    verify_manifest_contract(manifest)
    assert_exact_bundle_inventory(bundle, set(manifest["materials"]))
    artifact_path = safe_relative_path(Path(args.artifact_root), args.artifact_relative)
    current_artifact = artifact_identity(artifact_path)
    if current_artifact["sha256"] != manifest["artifact"]["sha256"]:
        raise SupplyChainError("artifact hash no longer matches the generated release manifest")
    for name, expected in manifest.get("materials", {}).items():
        raw_path = bundle / name
        if raw_path.is_symlink():
            raise SupplyChainError(f"supply-chain material must not be a symlink: {name}")
        path = safe_relative_path(bundle, name)
        if path.is_symlink() or not path.is_file():
            raise SupplyChainError(f"supply-chain material is not a regular file: {name}")
        if sha256_file(path) != expected:
            raise SupplyChainError(f"supply-chain material hash mismatch: {name}")
    verify_brand_provenance(manifest)
    review_root = Path(args.review_record_root)
    review_path = safe_relative_path(review_root, args.review_record_relative)
    review = json.loads(review_path.read_text(encoding="utf-8"))
    verify_review(review, manifest, sha256_file(manifest_path))
    print(f"supply-chain materials and external review record are technically bound ({manifest['artifact']['sha256']})")
    print("release approval remains blocked on package inspection, provenance, signing, notarization, and qualified legal decision")
    return 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)
    generate = commands.add_parser("generate")
    generate.add_argument("--artifact-root", required=True)
    generate.add_argument("--artifact-relative", required=True)
    generate.add_argument("--release", required=True)
    generate.add_argument("--output-dir", required=True)
    generate.add_argument("--expected-artifact-sha256")
    generate.add_argument(
        "--cargo-target",
        action="append",
        default=[],
        required=True,
        help="Target triple included in the release artifact; repeat for universal artifacts",
    )
    verify = commands.add_parser("verify")
    verify.add_argument("--bundle-dir", required=True)
    verify.add_argument("--artifact-root", required=True)
    verify.add_argument("--artifact-relative", required=True)
    verify.add_argument("--review-record-root", required=True)
    verify.add_argument("--review-record-relative", required=True)
    return root


def main(argv: Sequence[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.command == "generate":
            return generate_bundle(args)
        return verify_bundle(args)
    except (OSError, ValueError, KeyError, json.JSONDecodeError, SupplyChainError) as error:
        print(f"supply-chain gate: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
