"""Build and binding generation tools behind ./dev."""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path

from .artifacts import cargo_lane_lock, cargo_target_dir
from .common import ToolError, fail, project_root, require_command, require_file, resolve_project_path, run_step

UNIFFI_BINDGEN_WRAPPER = "areamatrix_uniffi_bindgen_wrapper"
UNIFFI_BINDGEN_CRATE = "uniffi_bindgen"
UNIFFI_CONFIG_NAME = "uniffi.toml"
DEFAULT_BINDINGS_UDL = "core/area_matrix.udl"
DEFAULT_TRACKED_BINDINGS_DIR = "apps/macos/AreaMatrix/Bridge/UniFFI"
DEFAULT_IOS_BINDINGS_DIR = "apps/ios/Carea_matrixFFI"
DEFAULT_IOS_APP_ROOT = "apps/ios/AreaMatrix"
BINDING_ARTIFACTS = (
    ("area_matrix.swift", "area_matrix.swift"),
    ("area_matrixFFI.h", "area_matrixFFI.h"),
    ("area_matrixFFI.modulemap", "module.modulemap"),
)
UNIFFI_FN_FUNC_RE = re.compile(r"\buniffi_area_matrix_core_fn_func_[A-Za-z0-9_]+\b")
MODULEMAP_HEADER_RE = re.compile(r'header\s+"([^"]+)"')


def _host_triple() -> str:
    proc = subprocess.run(["rustc", "-vV"], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if proc.returncode != 0:
        fail(f"rustc -vV failed:\n{proc.stderr}", proc.returncode)
    for line in proc.stdout.splitlines():
        if line.startswith("host: "):
            return line.split("host: ", 1)[1].strip()
    fail("unable to read Rust host triple from rustc -vV.")
    raise AssertionError("unreachable")


def _require_rust_target(target_triple: str) -> None:
    if subprocess.run(["which", "rustup"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False).returncode != 0:
        return
    proc = subprocess.run(["rustup", "target", "list", "--installed"], text=True, stdout=subprocess.PIPE, check=False)
    if proc.returncode != 0:
        fail("unable to list installed Rust targets.", proc.returncode)
    if target_triple not in {line.strip() for line in proc.stdout.splitlines()}:
        print(f"error: missing Rust target '{target_triple}'.", file=os.sys.stderr)
        print(f"       install it with: rustup target add {target_triple}", file=os.sys.stderr)
        raise SystemExit(1)


def _locked_crate_version(core_dir: Path, crate_name: str) -> str | None:
    lockfile = core_dir / "Cargo.lock"
    if not lockfile.is_file():
        return None

    current_name: str | None = None
    for raw_line in lockfile.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if line == "[[package]]":
            current_name = None
            continue
        if line.startswith("name = "):
            current_name = line.split("=", 1)[1].strip().strip('"')
            continue
        if current_name == crate_name and line.startswith("version = "):
            return line.split("=", 1)[1].strip().strip('"')
    return None


def _locked_crate_checksum(core_dir: Path, crate_name: str) -> str | None:
    lockfile = core_dir / "Cargo.lock"
    if not lockfile.is_file():
        return None

    current_name: str | None = None
    for raw_line in lockfile.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if line == "[[package]]":
            current_name = None
            continue
        if line.startswith("name = "):
            current_name = line.split("=", 1)[1].strip().strip('"')
            continue
        if current_name == crate_name and line.startswith("checksum = "):
            return line.split("=", 1)[1].strip().strip('"')
    return None


def _lock_package_records(lockfile: Path) -> dict[tuple[str, str, str | None, str | None], tuple[str, ...]]:
    """Read the generated Cargo.lock package graph without adding a TOML dependency."""

    if not lockfile.is_file():
        return {}

    records: dict[tuple[str, str, str | None, str | None], tuple[str, ...]] = {}
    current: dict[str, str | None] | None = None
    dependencies: list[str] = []
    in_dependencies = False

    def flush() -> None:
        if current is None or current.get("name") is None or current.get("version") is None:
            return
        key = (
            str(current["name"]),
            str(current["version"]),
            current.get("source"),
            current.get("checksum"),
        )
        records[key] = tuple(dependencies)

    for raw_line in lockfile.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if line == "[[package]]":
            flush()
            current = {}
            dependencies = []
            in_dependencies = False
            continue
        if current is None:
            continue
        if line == "dependencies = [":
            in_dependencies = True
            continue
        if in_dependencies:
            if line == "]":
                in_dependencies = False
            elif line.startswith('"') and line.endswith('",'):
                dependencies.append(line[1:-2])
            continue
        match = re.match(r'^(name|version|source|checksum) = "([^"]+)"$', line)
        if match:
            current[match.group(1)] = match.group(2)
    flush()
    return records


def _verify_wrapper_lock(wrapper_dir: Path, core_dir: Path) -> None:
    core_records = _lock_package_records(core_dir / "Cargo.lock")
    wrapper_records = _lock_package_records(wrapper_dir / "Cargo.lock")
    if not core_records or not wrapper_records:
        fail("unable to read generated Cargo.lock package records for the UniFFI wrapper.")

    for key, dependencies in wrapper_records.items():
        if key[0] == UNIFFI_BINDGEN_WRAPPER:
            continue
        if key not in core_records:
            fail(
                "UniFFI wrapper selected a package outside core/Cargo.lock: "
                f"{key[0]} {key[1]} ({key[3] or 'path/source package'})."
            )
        if dependencies != core_records[key]:
            fail(f"UniFFI wrapper package graph differs from core/Cargo.lock: {key[0]} {key[1]}.")


def _wrapper_registry_closure(core_dir: Path) -> list[tuple[str, str, str | None, str | None]]:
    """Return the registry packages reachable from the synthetic wrapper roots."""

    records = _lock_package_records(core_dir / "Cargo.lock")
    if not records:
        fail("unable to read core/Cargo.lock package records for the UniFFI wrapper.")

    by_name: dict[str, list[tuple[str, str, str | None, str | None]]] = {}
    for key in records:
        if key[2] is not None:
            by_name.setdefault(key[0], []).append(key)

    pending: list[tuple[str, str, str | None, str | None]] = []
    for root_name in ("camino", UNIFFI_BINDGEN_CRATE):
        root_version = _locked_crate_version(core_dir, root_name)
        roots = [key for key in by_name.get(root_name, []) if key[1] == root_version]
        if len(roots) != 1:
            fail(f"core/Cargo.lock has no registry package for wrapper dependency '{root_name}'.")
        pending.extend(roots)

    seen: set[tuple[str, str, str | None, str | None]] = set()
    closure: list[tuple[str, str, str | None, str | None]] = []
    while pending:
        key = pending.pop()
        if key in seen:
            continue
        seen.add(key)
        dependencies = records[key]
        closure.append(key)
        for dependency in dependencies:
            name, separator, version = dependency.partition(" ")
            candidates = by_name.get(name, [])
            if separator:
                candidates = [candidate for candidate in candidates if candidate[1] == version]
            if len(candidates) != 1:
                fail(
                    "core/Cargo.lock has an ambiguous wrapper dependency: "
                    f"{dependency} required by {key[0]} {key[1]}."
                )
            pending.append(candidates[0])
    return closure


def _locked_uniffi_bindgen_version(core_dir: Path) -> str | None:
    return _locked_crate_version(core_dir, UNIFFI_BINDGEN_CRATE) or _locked_crate_version(core_dir, "uniffi")


def _candidate_cargo_homes() -> list[Path]:
    homes: list[Path] = []
    configured = os.environ.get("CARGO_HOME")
    if configured:
        homes.append(Path(configured).expanduser())
    homes.append(Path.home() / ".cargo")

    deduped: list[Path] = []
    for home in homes:
        if home not in deduped:
            deduped.append(home)
    return deduped


def _find_crate_source(crate_name: str, version: str) -> Path | None:
    for cargo_home in _candidate_cargo_homes():
        registry_src = cargo_home / "registry/src"
        for candidate in sorted(registry_src.glob(f"*/{crate_name}-{version}")) if registry_src.is_dir() else []:
            if (candidate / "Cargo.toml").is_file():
                return candidate
    return None


def _find_crate_archive(cargo_home: Path, crate_name: str, version: str) -> Path | None:
    matches = sorted((cargo_home / "registry/cache").glob(f"*/{crate_name}-{version}.crate"))
    return matches[0] if len(matches) == 1 else None


def _find_verified_registry_package(
    crate_name: str,
    version: str,
    checksum: str,
    preferred_home: Path | None = None,
) -> tuple[Path, Path] | None:
    """Find a source/archive pair that both match Cargo.lock's checksum."""

    homes = [preferred_home] if preferred_home is not None else []
    homes.extend(home for home in _candidate_cargo_homes() if home not in homes)
    package_name = f"{crate_name}-{version}"
    for cargo_home in homes:
        registry_src = cargo_home / "registry/src"
        if (
            cargo_home.is_symlink()
            or _symlink_ancestor(registry_src, cargo_home) is not None
            or not registry_src.is_dir()
        ):
            continue
        for source in sorted(registry_src.glob(f"*/{package_name}")):
            archive = cargo_home / "registry/cache" / source.parent.name / f"{package_name}.crate"
            if (
                _symlink_ancestor(source, cargo_home) is not None
                or _symlink_ancestor(archive, cargo_home) is not None
                or not (source / "Cargo.toml").is_file()
            ):
                continue
            registry_id = source.parent.name
            if not archive.is_file() or _sha256(archive) != checksum:
                continue
            try:
                _verify_registry_source(source, archive, checksum)
            except (OSError, tarfile.TarError, ToolError):
                continue
            return source, archive
    return None


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(64 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _verify_registry_source(source: Path, archive: Path, expected_checksum: str) -> None:
    """Verify the cached unpacked crate against Cargo.lock's archive checksum."""

    if _sha256(archive) != expected_checksum:
        fail(f"Cargo registry archive checksum mismatch: {archive}.")
    if archive.stat().st_nlink > 1:
        fail(f"Cargo registry archive must not be multiply linked: {archive}.")
    if source.is_symlink() or not source.is_dir():
        fail(f"Cargo registry source is not a regular directory: {source}.")

    archive_files: dict[str, str] = {}
    archive_root: str | None = None
    with tarfile.open(archive, mode="r:*") as tar:
        for member in tar.getmembers():
            member_path = Path(member.name)
            if member_path.is_absolute() or ".." in member_path.parts:
                fail(f"unsafe path in Cargo registry archive: {member.name}")
            if not member_path.parts:
                fail(f"invalid Cargo registry archive member: {member.name}")
            if archive_root is None:
                archive_root = member_path.parts[0]
            elif archive_root != member_path.parts[0]:
                fail(f"multiple roots in Cargo registry archive: {member.name}")
            if archive_root != source.name:
                fail(f"unexpected Cargo registry archive root: {archive_root}")
            if member.issym() or member.islnk():
                fail(f"links are not accepted in Cargo registry archive: {member.name}")
            if not member.isfile() and not member.isdir():
                fail(f"unsupported entry in Cargo registry archive: {member.name}")
            if member.isfile():
                relative = "/".join(member_path.parts[1:])
                if not relative:
                    fail(f"invalid Cargo registry archive member: {member.name}")
                if relative in archive_files:
                    fail(f"duplicate Cargo registry archive member: {member.name}")
                extracted = tar.extractfile(member)
                if extracted is None:
                    fail(f"unable to read Cargo registry archive member: {member.name}")
                archive_files[relative] = hashlib.sha256(extracted.read()).hexdigest()

    source_files: dict[str, str] = {}
    for path in source.rglob("*"):
        if path.is_symlink():
            fail(f"links are not accepted in Cargo registry source: {path}")
        if not path.is_file() and not path.is_dir():
            fail(f"unsupported entry in Cargo registry source: {path}")
        if path.is_file():
            if path.stat().st_nlink > 1:
                fail(f"Cargo registry source file must not be multiply linked: {path}")
            relative = path.relative_to(source).as_posix()
            if relative == ".cargo-ok":
                continue
            source_files[relative] = _sha256(path)
    if source_files != archive_files:
        fail(f"Cargo registry source does not match its locked archive: {source}")


def _find_registry_cache_home() -> Path | None:
    for cargo_home in _candidate_cargo_homes():
        cache = cargo_home / "registry/cache"
        index = cargo_home / "registry/index"
        if cargo_home.is_symlink() or _symlink_ancestor(cache, cargo_home) is not None:
            continue
        if cargo_home.is_symlink() or _symlink_ancestor(index, cargo_home) is not None:
            continue
        if cache.is_symlink() or index.is_symlink():
            continue
        if cache.is_dir() and index.is_dir():
            return cargo_home
    return None


def _symlink_ancestor(path: Path, stop: Path | None = None) -> Path | None:
    current = path
    while True:
        if current.is_symlink():
            return current
        if stop is not None and current == stop:
            return None
        parent = current.parent
        if parent == current:
            return None
        current = parent


def _replace_symlink(link: Path, target: Path) -> None:
    if link.is_symlink():
        if link.readlink() == target:
            return
        link.unlink()
    elif link.exists():
        fail(f"temporary Cargo path exists but is not a symlink: {link}.")
    link.symlink_to(target)


def _prepare_temp_cargo_home(tool_root: Path, source_home: Path) -> Path:
    cargo_home = tool_root / "cargo-home"
    registry = cargo_home / "registry"
    if tool_root.is_symlink():
        fail(f"temporary Cargo home path must not be a symlink: {tool_root}")
    for path in (cargo_home, registry):
        link = _symlink_ancestor(path, tool_root)
        if link is not None:
            fail(f"temporary Cargo home path must not contain a symlink: {link}")
    registry.mkdir(parents=True, exist_ok=True)
    (registry / "src").mkdir(parents=True, exist_ok=True)
    for directory in (registry / "cache", registry / "index"):
        if directory.is_symlink():
            fail(f"temporary Cargo registry path must not be a symlink: {directory}")
        elif directory.exists() and not directory.is_dir():
            fail(f"temporary Cargo registry path is not a directory: {directory}")
        directory.mkdir(parents=True, exist_ok=True)
        link = _symlink_ancestor(directory, tool_root)
        if link is not None:
            fail(f"temporary Cargo registry path must not contain a symlink: {link}")

    if source_home.is_symlink():
        fail(f"Cargo registry home must not be a symlink: {source_home}")
    source_index = source_home / "registry/index"
    if _symlink_ancestor(source_index, source_home) is not None or source_index.is_symlink() or not source_index.is_dir():
        fail(f"Cargo registry index is not a regular directory: {source_index}")
    if any(path.is_symlink() for path in source_index.rglob("*")):
        fail(f"Cargo registry index contains an unsupported link: {source_index}")
    destination_index = registry / "index"
    if any(path.is_symlink() for path in destination_index.rglob("*")):
        fail(f"temporary Cargo registry index contains an unsupported link: {destination_index}")
    shutil.copytree(source_index, destination_index, dirs_exist_ok=True, symlinks=False)
    return cargo_home


def _copy_verified_crate_source(cargo_home: Path, source: Path, archive: Path, checksum: str) -> Path:
    """Place a verified source and archive at the exact registry paths Cargo will use."""

    registry_id = source.parent.name
    destination = cargo_home / "registry/src" / registry_id / source.name
    link = _symlink_ancestor(destination.parent, cargo_home)
    if link is not None:
        fail(f"temporary Cargo source path must not contain a symlink: {link}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        fail(f"temporary Cargo source path must not be a symlink: {destination}")
    if destination.exists():
        _verify_registry_source(destination, archive, checksum)
    else:
        shutil.copytree(source, destination, symlinks=False)
        _verify_registry_source(destination, archive, checksum)

    archive_destination = cargo_home / "registry/cache" / registry_id / archive.name
    link = _symlink_ancestor(archive_destination.parent, cargo_home)
    if link is not None:
        fail(f"temporary Cargo archive path must not contain a symlink: {link}")
    archive_destination.parent.mkdir(parents=True, exist_ok=True)
    if archive_destination.is_symlink() or (archive_destination.exists() and not archive_destination.is_file()):
        fail(f"temporary Cargo archive path is not a regular file: {archive_destination}")
    if archive_destination.exists():
        if _sha256(archive_destination) != checksum:
            fail(f"temporary Cargo archive checksum mismatch: {archive_destination}")
    else:
        shutil.copy2(archive, archive_destination)
    return destination


def _copy_verified_registry_closure(cargo_home: Path, core_dir: Path, source_home: Path) -> None:
    """Copy and verify every registry package used by the synthetic wrapper."""

    for key in _wrapper_registry_closure(core_dir):
        crate_name, version, source, checksum = key
        if source is None or checksum is None:
            fail(f"wrapper dependency is not a checksummed registry package: {crate_name} {version}.")
        package = _find_verified_registry_package(crate_name, version, checksum, source_home)
        if package is None:
            fail(f"missing verified Cargo registry package: {crate_name} {version}.")
        _copy_verified_crate_source(cargo_home, package[0], package[1], checksum)


def _write_uniffi_wrapper_crate(
    wrapper_dir: Path, uniffi_bindgen_version: str, camino_version: str
) -> None:
    src_dir = wrapper_dir / "src"
    src_dir.mkdir(parents=True, exist_ok=True)
    (wrapper_dir / "Cargo.toml").write_text(
        "\n".join(
            [
                "[package]",
                f'name = "{UNIFFI_BINDGEN_WRAPPER}"',
                'version = "0.1.0"',
                'edition = "2021"',
                "",
                "[dependencies]",
                f'camino = "={camino_version}"',
                f'uniffi_bindgen = {{ version = "={uniffi_bindgen_version}", default-features = false }}',
                "",
            ]
        ),
        encoding="utf-8",
    )
    (src_dir / "main.rs").write_text(
        "\n".join(
            [
                "use camino::Utf8PathBuf;",
                "use std::{env, error::Error, io, path::PathBuf};",
                "use uniffi_bindgen::bindings::SwiftBindingGenerator;",
                "",
                "fn fail(message: impl Into<String>) -> Box<dyn Error> {",
                "    io::Error::new(io::ErrorKind::InvalidInput, message.into()).into()",
                "}",
                "",
                "fn take_flag_value(args: &mut Vec<String>, flag: &str) -> Result<String, Box<dyn Error>> {",
                "    let index = args",
                "        .iter()",
                "        .position(|value| value == flag)",
                "        .ok_or_else(|| fail(format!(\"missing required flag: {flag}\")))?;",
                "    if index + 1 >= args.len() {",
                "        return Err(fail(format!(\"missing value for flag: {flag}\")));",
                "    }",
                "    let value = args.remove(index + 1);",
                "    args.remove(index);",
                "    Ok(value)",
                "}",
                "",
                "fn utf8_path(value: String, label: &str) -> Result<Utf8PathBuf, Box<dyn Error>> {",
                "    Utf8PathBuf::from_path_buf(PathBuf::from(&value))",
                "        .map_err(|_| fail(format!(\"{label} is not valid UTF-8: {value}\")))",
                "}",
                "",
                "fn run() -> Result<(), Box<dyn Error>> {",
                "    let mut args = env::args().skip(1).collect::<Vec<_>>();",
                "    if args.first().map(String::as_str) != Some(\"generate\") {",
                "        return Err(fail(\"expected command: generate\"));",
                "    }",
                "    args.remove(0);",
                "    if args.is_empty() || args[0].starts_with(\"--\") {",
                "        return Err(fail(\"missing UDL path\"));",
                "    }",
                "    let udl_path = utf8_path(args.remove(0), \"UDL path\")?;",
                "    let language = take_flag_value(&mut args, \"--language\")?;",
                "    if language != \"swift\" {",
                "        return Err(fail(format!(\"unsupported language: {language}\")));",
                "    }",
                "    let out_dir = utf8_path(take_flag_value(&mut args, \"--out-dir\")?, \"out dir\")?;",
                "    let lib_file = utf8_path(take_flag_value(&mut args, \"--lib-file\")?, \"lib file\")?;",
                "    if !args.is_empty() {",
                "        return Err(fail(format!(\"unsupported arguments: {}\", args.join(\" \"))));",
                "    }",
                "    uniffi_bindgen::generate_bindings(",
                "        &udl_path,",
                "        None,",
                "        SwiftBindingGenerator,",
                "        Some(&out_dir),",
                "        Some(&lib_file),",
                "        None,",
                "        false,",
                "    )?;",
                "    Ok(())",
                "}",
                "",
                "fn main() {",
                "    if let Err(error) = run() {",
                "        eprintln!(\"error: {error}\");",
                "        std::process::exit(1);",
                "    }",
                "}",
                "",
            ]
        ),
        encoding="utf-8",
    )


def _write_wrapper_lock(wrapper_dir: Path, core_dir: Path, cargo_home: Path) -> None:
    source = (core_dir / "Cargo.lock").read_text(encoding="utf-8")
    sections = re.split(r"(?m)(?=^\[\[package\]\]$)", source)
    if not sections or re.search(r"(?m)^version\s*=\s*\d+\s*$", sections[0]) is None:
        fail("core/Cargo.lock has an invalid package table.")
    closure = set(_wrapper_registry_closure(core_dir))
    selected: list[str] = []
    for section in sections[1:]:
        fields: dict[str, str] = {}
        for field in ("name", "version", "source", "checksum"):
            match = re.search(rf"^\s*{field}\s*=\s*\"([^\"]+)\"", section, re.MULTILINE)
            if match:
                fields[field] = match.group(1)
        key = (fields.get("name"), fields.get("version"), fields.get("source"), fields.get("checksum"))
        if key in closure:
            selected.append(section.strip())
    if len(selected) != len(closure):
        fail("core/Cargo.lock is missing a package required by the UniFFI wrapper.")
    root_entry = '''[[package]]
name = "areamatrix_uniffi_bindgen_wrapper"
version = "0.1.0"
dependencies = [
 "camino",
 "uniffi_bindgen",
]
'''
    lock_text = sections[0].rstrip() + "\n\n" + root_entry.rstrip() + "\n\n" + "\n\n".join(selected) + "\n"
    (wrapper_dir / "Cargo.lock").write_text(lock_text, encoding="utf-8")
    metadata_command = [
        "cargo",
        "metadata",
        "--locked",
        "--offline",
        "--manifest-path",
        wrapper_dir / "Cargo.toml",
        "--format-version",
        "1",
    ]
    metadata_env = os.environ.copy()
    metadata_env.update({"CARGO_HOME": str(cargo_home), "CARGO_NET_OFFLINE": "true"})
    proc = subprocess.run(
        [str(part) for part in metadata_command],
        cwd=wrapper_dir,
        env=metadata_env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        detail = (proc.stderr or "").strip()
        suffix = f": {detail}" if detail else ""
        fail(f"unable to derive a locked UniFFI wrapper graph from core/Cargo.lock{suffix}", proc.returncode)
    _verify_wrapper_lock(wrapper_dir, core_dir)


def _fetch_locked_cargo_dependencies(core_dir: Path) -> None:
    print()
    print("==> Fetching locked Cargo dependencies for UniFFI bindgen fallback")
    proc = run_step(["cargo", "fetch", "--locked"], cwd=core_dir, check=False)
    if proc.returncode != 0:
        fail("unable to fetch locked Cargo dependencies for UniFFI bindgen fallback.", proc.returncode)


def _build_cached_uniffi_bindgen(core_dir: Path) -> list[str]:
    version = _locked_uniffi_bindgen_version(core_dir)
    if version is None:
        fail("unable to determine locked UniFFI bindgen version from core/Cargo.lock.")

    source_home = _find_registry_cache_home()
    if source_home is None:
        _fetch_locked_cargo_dependencies(core_dir)
        source_home = _find_registry_cache_home()
    if source_home is None:
        fail(
            "missing locked Cargo registry cache for the fallback. "
            "Run `cd core && cargo fetch --locked`, then retry.",
            127,
        )
    camino_version = _locked_crate_version(core_dir, "camino")
    if camino_version is None:
        fail("unable to determine locked camino version from core/Cargo.lock.")

    tool_root = Path(os.environ.get("AREAMATRIX_UNIFFI_BINDGEN_TOOL_ROOT", "/private/tmp/areamatrix-uniffi-bindgen"))
    wrapper_dir = tool_root / f"wrapper-{version}"
    target_dir = tool_root / "target"
    cargo_home = _prepare_temp_cargo_home(tool_root, source_home)
    _copy_verified_registry_closure(cargo_home, core_dir, source_home)
    _write_uniffi_wrapper_crate(wrapper_dir, version, camino_version)
    _write_wrapper_lock(wrapper_dir, core_dir, cargo_home)

    print()
    print("==> Preparing cached UniFFI bindgen fallback")
    print(f"    version: {version}")
    print(f"    wrapper: {wrapper_dir}")
    proc = run_step(
        [
            "cargo",
            "build",
            "--locked",
            "--offline",
            "--manifest-path",
            wrapper_dir / "Cargo.toml",
            "--quiet",
        ],
        env={
            "CARGO_HOME": str(cargo_home),
            "CARGO_NET_OFFLINE": "true",
            "CARGO_TARGET_DIR": str(target_dir),
            "CARGO_ENCODED_RUSTFLAGS": "",
            "RUSTFLAGS": "",
        },
        check=False,
    )
    if proc.returncode != 0:
        fail("unable to build cached UniFFI bindgen fallback.", proc.returncode)

    binary = target_dir / "debug" / UNIFFI_BINDGEN_WRAPPER
    require_file(binary, "cached UniFFI bindgen fallback")
    return [str(binary)]


def _uniffi_bindgen_command(core_dir: Path) -> list[str]:
    configured = os.environ.get("UNIFFI_BINDGEN") or os.environ.get("AREAMATRIX_UNIFFI_BINDGEN")
    if configured:
        fail(
            "UNIFFI_BINDGEN/AREAMATRIX_UNIFFI_BINDGEN overrides are disabled; "
            "use the locked registry wrapper generated by ./dev build core."
        )
    return _build_cached_uniffi_bindgen(core_dir)


def _cargo_profile_args(build_profile: str) -> tuple[list[str], str]:
    if build_profile == "release":
        return ["--release"], "release"
    if build_profile == "debug":
        return [], "debug"
    fail("BUILD_PROFILE must be 'release' or 'debug'.")
    raise AssertionError("unreachable")


def _require_core_build_inputs(core_dir: Path) -> None:
    for command in ["cargo", "lipo", "rustc"]:
        require_command(command)
    if not core_dir.is_dir():
        fail(f"core crate not found at {core_dir}.")
    require_file(core_dir / "Cargo.toml", "Core Cargo manifest")
    require_file(core_dir / "area_matrix.udl", "UniFFI definition")
    require_file(core_dir / UNIFFI_CONFIG_NAME, "UniFFI binding configuration")
    require_file(core_dir / "build.rs", "UniFFI scaffolding build script")


def _macos_rust_host() -> str | None:
    host_triple = _host_triple()
    if host_triple not in {"aarch64-apple-darwin", "x86_64-apple-darwin"}:
        print("error: ./dev build core must run on a macOS Rust host.", file=os.sys.stderr)
        print(f"       got host triple: {host_triple}", file=os.sys.stderr)
        return None
    return host_triple


def _build_core_targets(core_dir: Path, cargo_profile_args: list[str], env: dict[str, str]) -> int:
    for target in ["aarch64-apple-darwin", "x86_64-apple-darwin"]:
        proc = run_step(
            ["cargo", "build", "--locked", *cargo_profile_args, "--target", target],
            cwd=core_dir,
            env=env,
            check=False,
        )
        if proc.returncode != 0:
            return proc.returncode
    return 0


def _generated_artifacts(target_dir: Path, host_triple: str, target_profile: str) -> tuple[Path, Path, Path]:
    staticlib_arm = target_dir / "aarch64-apple-darwin" / target_profile / "libarea_matrix_core.a"
    staticlib_x86 = target_dir / "x86_64-apple-darwin" / target_profile / "libarea_matrix_core.a"
    bindgen_library = target_dir / host_triple / target_profile / "libarea_matrix_core.dylib"
    return staticlib_arm, staticlib_x86, bindgen_library


def _core_package_name(core_dir: Path) -> str:
    manifest = core_dir / "Cargo.toml"
    in_package = False
    for raw_line in manifest.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if line == "[package]":
            in_package = True
            continue
        if line.startswith("["):
            in_package = False
            continue
        if in_package and line.startswith("name = "):
            return line.split("=", 1)[1].strip().strip('"')
    fail("unable to determine core package name from core/Cargo.toml.")
    raise AssertionError("unreachable")


def _prepare_udl_bindgen_crate(core_dir: Path) -> Path:
    udl_file = core_dir / "area_matrix.udl"
    require_file(udl_file, "Core UniFFI UDL")
    config_file = core_dir / UNIFFI_CONFIG_NAME
    require_file(config_file, "Core UniFFI binding configuration")

    tool_root = Path(os.environ.get("AREAMATRIX_UNIFFI_BINDGEN_TOOL_ROOT", "/private/tmp/areamatrix-uniffi-bindgen"))
    crate_dir = tool_root / "udl-crate"
    src_dir = crate_dir / "src"
    src_dir.mkdir(parents=True, exist_ok=True)
    (crate_dir / "Cargo.toml").write_text(
        "\n".join(
            [
                "[package]",
                f'name = "{_core_package_name(core_dir)}"',
                'version = "0.1.0"',
                'edition = "2021"',
                "",
            ]
        ),
        encoding="utf-8",
    )
    link = src_dir / "area_matrix.udl"
    _replace_symlink(link, udl_file)
    _replace_symlink(crate_dir / UNIFFI_CONFIG_NAME, config_file)
    return link


def _bindgen_udl_path(udl_path: Path, core_dir: Path) -> Path:
    if udl_path.resolve() == (core_dir / "area_matrix.udl").resolve():
        return _prepare_udl_bindgen_crate(core_dir)
    return udl_path


def _create_universal_staticlib(out_path: Path, staticlib_arm: Path, staticlib_x86: Path) -> int:
    universal_staticlib = out_path / "libarea_matrix_core.a"
    require_file(staticlib_arm, "aarch64 static library")
    require_file(staticlib_x86, "x86_64 static library")

    print()
    print("==> Creating universal static library")
    universal_staticlib.unlink(missing_ok=True)
    proc = run_step(["lipo", "-create", staticlib_arm, staticlib_x86, "-output", universal_staticlib], check=False)
    return proc.returncode


def _generate_swift_bindings(bindgen_cmd: list[str], core_dir: Path, bindgen_library: Path, out_path: Path) -> int:
    require_file(bindgen_library, "host dylib for UniFFI binding generation")
    udl_file = _bindgen_udl_path(core_dir / "area_matrix.udl", core_dir)

    print()
    print("==> Generating Swift bindings")
    return _run_swift_bindgen(bindgen_cmd, udl_file, bindgen_library, out_path)


def _run_swift_bindgen(
    bindgen_cmd: list[str],
    udl_file: Path,
    bindgen_library: Path,
    out_path: Path,
) -> int:
    require_file(bindgen_library, "host dylib for UniFFI binding generation")
    proc = run_step(
        [
            *bindgen_cmd,
            "generate",
            udl_file,
            "--language",
            "swift",
            "--out-dir",
            out_path,
            "--lib-file",
            bindgen_library,
        ],
        check=False,
    )
    return proc.returncode


def _bindings_bindgen_library(
    core_dir: Path,
    profile: str | None = None,
    *,
    target_dir: Path | None = None,
) -> Path:
    build_profile = profile or os.environ.get("BUILD_PROFILE", "release")
    _, target_profile = _cargo_profile_args(build_profile)
    host_triple = _macos_rust_host()
    if host_triple is None:
        fail("Swift binding generation requires a macOS Rust host.")
    resolved_target_dir = target_dir or cargo_target_dir(core_dir.parent, lane="sdk")
    _, _, bindgen_library = _generated_artifacts(resolved_target_dir, host_triple, target_profile)
    if not bindgen_library.is_file():
        fail(
            f"host dylib for UniFFI binding generation not found at {bindgen_library}. "
            "Run `./dev build core` first."
        )
    return bindgen_library


def _copy_binding_artifacts(generated_dir: Path, tracked_dir: Path) -> None:
    tracked_dir.mkdir(parents=True, exist_ok=True)
    for generated_name, tracked_name in BINDING_ARTIFACTS:
        source = generated_dir / generated_name
        require_file(source, f"generated Swift binding artifact '{generated_name}'")
        shutil.copy2(source, tracked_dir / tracked_name)


def _replace_generated_swift_template(
    source: str,
    old: str,
    new: str,
    *,
    expected_count: int,
    label: str,
) -> str:
    actual_count = source.count(old)
    if actual_count != expected_count:
        fail(
            f"UniFFI Swift concurrency compatibility expected {expected_count} {label} template(s), "
            f"found {actual_count}. Review the pinned generator templates before updating bindings."
        )
    return source.replace(old, new)


def _apply_swift_concurrency_compatibility(source: str) -> str:
    if "private enum InitializationResult" not in source:
        return source

    callback_protocol = re.compile(r"(public protocol [A-Za-z0-9_]+) : AnyObject \{")
    callback_count = len(callback_protocol.findall(source))
    if callback_count == 0:
        fail("UniFFI Swift concurrency compatibility found no callback protocols in a complete binding.")
    source = callback_protocol.sub(r"\1 : AnyObject, Sendable {", source)
    source = _replace_generated_swift_template(
        source,
        "fileprivate class UniffiHandleMap<T> {",
        "fileprivate final class UniffiHandleMap<T: Sendable>: @unchecked Sendable {",
        expected_count=1,
        label="handle-map class",
    )
    source = _replace_generated_swift_template(
        source,
        "    static var vtable: ",
        "    nonisolated(unsafe) static var vtable: ",
        expected_count=callback_count,
        label="callback vtable",
    )
    source = _replace_generated_swift_template(
        source,
        "    fileprivate static var handleMap = ",
        "    fileprivate static let handleMap = ",
        expected_count=callback_count,
        label="callback handle-map",
    )
    source = _replace_generated_swift_template(
        source,
        "private var initializationResult: InitializationResult = {",
        "private let initializationResult: InitializationResult = {",
        expected_count=1,
        label="initialization result",
    )
    source = _replace_generated_swift_template(
        source,
        "    var count: Int {\n        get {\n            map.count\n        }\n    }",
        "    var count: Int {\n        lock.withLock { map.count }\n    }",
        expected_count=1,
        label="handle-map count accessor",
    )
    return source


def _normalize_binding_artifacts(generated_dir: Path) -> None:
    for generated_name, _ in BINDING_ARTIFACTS:
        path = generated_dir / generated_name
        require_file(path, f"generated Swift binding artifact '{generated_name}'")
        source = path.read_text(encoding="utf-8")
        if generated_name == "area_matrix.swift":
            source = _apply_swift_concurrency_compatibility(source)
        lines = source.splitlines()
        while lines and not lines[-1].strip():
            lines.pop()
        path.write_text("\n".join(line.rstrip() for line in lines) + "\n", encoding="utf-8")


def _binding_drift(generated_dir: Path, tracked_dir: Path) -> list[str]:
    drift: list[str] = []
    for generated_name, tracked_name in BINDING_ARTIFACTS:
        generated = generated_dir / generated_name
        tracked = tracked_dir / tracked_name
        require_file(generated, f"generated Swift binding artifact '{generated_name}'")
        if not tracked.is_file() or generated.read_bytes() != tracked.read_bytes():
            drift.append(tracked_name)
    return drift


def _extract_uniffi_fn_func_symbols(text: str) -> set[str]:
    return set(UNIFFI_FN_FUNC_RE.findall(text))


def _ios_core_ffi_sources(ios_app_root: Path) -> list[Path]:
    return sorted(ios_app_root.rglob("*CoreFFI.swift"))


def _ios_bindings_subset_issues(
    generated_header: Path,
    ios_bindings_dir: Path,
    ios_app_root: Path,
) -> list[str]:
    """Validate iOS subset bindings without requiring a full byte-identical header.

    Rules:
    - every `fn_func_*` in the tracked iOS header must exist in the regenerated header
    - every `fn_func_*` used by `*CoreFFI.swift` must exist in the tracked iOS header
    - `module.modulemap` must point at an existing header file beside itself
    """
    issues: list[str] = []
    ios_header = ios_bindings_dir / "area_matrixFFI.h"
    modulemap = ios_bindings_dir / "module.modulemap"
    if not ios_header.is_file():
        issues.append(f"missing iOS header: {ios_header}")
        return issues
    if not modulemap.is_file():
        issues.append(f"missing iOS modulemap: {modulemap}")
        return issues

    modulemap_text = modulemap.read_text(encoding="utf-8")
    header_refs = MODULEMAP_HEADER_RE.findall(modulemap_text)
    if not header_refs:
        issues.append(f"iOS modulemap does not declare a header: {modulemap}")
    for header_name in header_refs:
        header_path = ios_bindings_dir / header_name
        if not header_path.is_file():
            issues.append(f"iOS modulemap header missing: {header_path}")

    generated_symbols = _extract_uniffi_fn_func_symbols(
        generated_header.read_text(encoding="utf-8")
    )
    ios_symbols = _extract_uniffi_fn_func_symbols(ios_header.read_text(encoding="utf-8"))
    stale = sorted(ios_symbols - generated_symbols)
    if stale:
        preview = ", ".join(stale[:5])
        suffix = "" if len(stale) <= 5 else f" (+{len(stale) - 5} more)"
        issues.append(
            "iOS header contains symbols absent from regenerated UniFFI header: "
            f"{preview}{suffix}"
        )

    used_symbols: set[str] = set()
    for source in _ios_core_ffi_sources(ios_app_root):
        used_symbols.update(
            _extract_uniffi_fn_func_symbols(source.read_text(encoding="utf-8"))
        )
    missing = sorted(used_symbols - ios_symbols)
    if missing:
        preview = ", ".join(missing[:5])
        suffix = "" if len(missing) <= 5 else f" (+{len(missing) - 5} more)"
        issues.append(
            "iOS *CoreFFI.swift uses symbols missing from tracked iOS header: "
            f"{preview}{suffix}"
        )
    return issues


def _run_core_build_unlocked(
    root: Path | None = None,
    *,
    profile: str | None = None,
    out_dir: str | Path | None = None,
    deployment_target: str | None = None,
    cargo_lane: str = "sdk",
    target_dir: str | Path | None = None,
) -> int:
    root = (root or project_root()).resolve()
    core_dir = root / "core"
    out_path = resolve_project_path(root, out_dir or os.environ.get("OUT_DIR", "apps/macos/AreaMatrix/Bridge/Generated"))
    build_profile = profile or os.environ.get("BUILD_PROFILE", "release")
    macos_target = deployment_target or os.environ.get("MACOSX_DEPLOYMENT_TARGET", "14.0")
    resolved_target_dir = cargo_target_dir(root, lane=cargo_lane, configured=target_dir)

    cargo_profile_args, target_profile = _cargo_profile_args(build_profile)
    _require_core_build_inputs(core_dir)
    host_triple = _macos_rust_host()
    if host_triple is None:
        return 1

    _require_rust_target("aarch64-apple-darwin")
    _require_rust_target("x86_64-apple-darwin")
    bindgen_cmd = _uniffi_bindgen_command(core_dir)

    env = {
        "CARGO_TARGET_DIR": str(resolved_target_dir),
        "MACOSX_DEPLOYMENT_TARGET": macos_target,
    }
    print(f"==> Building AreaMatrix core ({build_profile})")
    print(f"    Cargo lane: {cargo_lane}")
    print(f"    target dir: {resolved_target_dir}")
    rc = _build_core_targets(core_dir, cargo_profile_args, env)
    if rc != 0:
        return rc

    out_path.mkdir(parents=True, exist_ok=True)
    staticlib_arm, staticlib_x86, bindgen_library = _generated_artifacts(
        resolved_target_dir,
        host_triple,
        target_profile,
    )

    rc = _create_universal_staticlib(out_path, staticlib_arm, staticlib_x86)
    if rc != 0:
        return rc
    rc = _generate_swift_bindings(bindgen_cmd, core_dir, bindgen_library, out_path)
    if rc != 0:
        return rc

    print("==> Done")
    print(f"    staticlib: {out_path / 'libarea_matrix_core.a'}")
    print(f"    swift:     {out_path / 'area_matrix.swift'}")
    print(f"    header:    {out_path / 'area_matrixFFI.h'}")
    return 0


def run_core_build(
    root: Path | None = None,
    *,
    profile: str | None = None,
    out_dir: str | Path | None = None,
    deployment_target: str | None = None,
    cargo_lane: str = "sdk",
    target_dir: str | Path | None = None,
    acquire_cargo_lock: bool = True,
) -> int:
    """Build Core while serializing Cargo producers that share one lane."""

    root = (root or project_root()).resolve()
    if not acquire_cargo_lock:
        return _run_core_build_unlocked(
            root,
            profile=profile,
            out_dir=out_dir,
            deployment_target=deployment_target,
            cargo_lane=cargo_lane,
            target_dir=target_dir,
        )

    operation = f"core-build:{profile or os.environ.get('BUILD_PROFILE', 'release')}"
    with cargo_lane_lock(root, lane=cargo_lane, operation=operation):
        return _run_core_build_unlocked(
            root,
            profile=profile,
            out_dir=out_dir,
            deployment_target=deployment_target,
            cargo_lane=cargo_lane,
            target_dir=target_dir,
        )


def _core_build_inputs(core_dir: Path) -> list[Path]:
    inputs = [
        core_dir / "Cargo.toml",
        core_dir / "Cargo.lock",
        core_dir / "build.rs",
        core_dir / "area_matrix.udl",
        core_dir / UNIFFI_CONFIG_NAME,
    ]
    for directory in (core_dir / "src", core_dir / "resources"):
        if directory.is_dir():
            inputs.append(directory)
            inputs.extend(path for path in sorted(directory.rglob("*")) if path.is_file())
    return inputs


def _escape_makefile_path(path: Path) -> str:
    return str(path).replace("\\", "\\\\").replace(" ", "\\ ").replace("#", "\\#").replace("$", "$$")


def _write_core_dependency_file(dependency_file: Path, output: Path, core_dir: Path) -> None:
    dependency_file.parent.mkdir(parents=True, exist_ok=True)
    dependencies = " ".join(_escape_makefile_path(path) for path in _core_build_inputs(core_dir))
    dependency_file.write_text(f"{_escape_makefile_path(output)}: {dependencies}\n", encoding="utf-8")


def _run_xcode_core_build_unlocked(
    root: Path | None = None,
    *,
    profile: str | None = None,
    target: str = "aarch64-apple-darwin",
    target_dir: str | Path | None = None,
    dependency_file: str | Path | None = None,
    deployment_target: str | None = None,
) -> int:
    """Build the single Rust slice consumed by Xcode without generating bindings."""

    root = (root or project_root()).resolve()
    core_dir = root / "core"
    build_profile = profile or os.environ.get("BUILD_PROFILE", "debug")
    cargo_profile_args, target_profile = _cargo_profile_args(build_profile)
    resolved_target_dir = cargo_target_dir(root, lane="xcode", configured=target_dir)
    macos_target = deployment_target or os.environ.get("MACOSX_DEPLOYMENT_TARGET", "14.0")

    for command in ("cargo", "rustc"):
        require_command(command)
    _require_core_build_inputs(core_dir)
    _require_rust_target(target)

    env = {
        "CARGO_TARGET_DIR": str(resolved_target_dir),
        "MACOSX_DEPLOYMENT_TARGET": macos_target,
    }
    print(f"==> Building AreaMatrix core for Xcode ({build_profile}, {target})")
    print(f"    target dir: {resolved_target_dir}")
    proc = run_step(
        ["cargo", "build", "--locked", *cargo_profile_args, "--target", target],
        cwd=core_dir,
        env=env,
        check=False,
    )
    if proc.returncode != 0:
        return proc.returncode

    output = resolved_target_dir / target / target_profile / "libarea_matrix_core.a"
    require_file(output, f"{target} static library")
    if dependency_file:
        dependency_path = Path(dependency_file)
        if not dependency_path.is_absolute():
            dependency_path = root / dependency_path
        _write_core_dependency_file(dependency_path, output, core_dir)
    print(f"    staticlib: {output}")
    return 0


def run_xcode_core_build(
    root: Path | None = None,
    *,
    profile: str | None = None,
    target: str = "aarch64-apple-darwin",
    target_dir: str | Path | None = None,
    dependency_file: str | Path | None = None,
    deployment_target: str | None = None,
) -> int:
    """Build a diagnostic Apple Rust slice with an explicit xcode-lane single-flight lock."""

    root = (root or project_root()).resolve()
    operation = f"xcode-core:{profile or os.environ.get('BUILD_PROFILE', 'debug')}:{target}"
    with cargo_lane_lock(root, lane="xcode", operation=operation):
        return _run_xcode_core_build_unlocked(
            root,
            profile=profile,
            target=target,
            target_dir=target_dir,
            dependency_file=dependency_file,
            deployment_target=deployment_target,
        )


def run_bindings_update(root: Path | None, udl: str | Path, out_dir: str | Path) -> int:
    root = (root or project_root()).resolve()
    udl_path = resolve_project_path(root, udl)
    out_path = resolve_project_path(root, out_dir)
    if not udl_path.is_file():
        fail(f"UDL file not found at {udl_path}.")
    if out_path.exists() and not out_path.is_dir():
        fail(f"output path exists but is not a directory: {out_path}.")

    bindgen_cmd = _uniffi_bindgen_command(root / "core")
    bindgen_udl = _bindgen_udl_path(udl_path, root / "core")
    bindgen_library = _bindings_bindgen_library(root / "core")

    print("==> Regenerating Swift bindings")
    with tempfile.TemporaryDirectory(prefix="areamatrix-bindings-update-") as temp_dir:
        generated_dir = Path(temp_dir)
        rc = _run_swift_bindgen(bindgen_cmd, bindgen_udl, bindgen_library, generated_dir)
        if rc != 0:
            return rc
        _normalize_binding_artifacts(generated_dir)
        _copy_binding_artifacts(generated_dir, out_path)
    print("==> Done")
    print(f"    udl:    {udl_path}")
    print(f"    swift:  {out_path / 'area_matrix.swift'}")
    print(f"    header: {out_path / 'area_matrixFFI.h'}")
    print(f"    module: {out_path / 'module.modulemap'}")
    return 0


def run_bindings_verify(
    root: Path | None = None,
    udl: str | Path = DEFAULT_BINDINGS_UDL,
    tracked_dir: str | Path = DEFAULT_TRACKED_BINDINGS_DIR,
    *,
    ios_bindings_dir: str | Path = DEFAULT_IOS_BINDINGS_DIR,
    ios_app_root: str | Path = DEFAULT_IOS_APP_ROOT,
    verify_ios_subset: bool | None = None,
) -> int:
    root = (root or project_root()).resolve()
    udl_path = resolve_project_path(root, udl)
    tracked_path = resolve_project_path(root, tracked_dir)
    require_file(udl_path, "Core UniFFI UDL")
    if not tracked_path.is_dir():
        fail(f"tracked bindings directory not found at {tracked_path}.")

    ios_bindings_path = resolve_project_path(root, ios_bindings_dir)
    ios_app_path = resolve_project_path(root, ios_app_root)
    if verify_ios_subset is None:
        verify_ios_subset = ios_bindings_path.is_dir()

    core_dir = root / "core"
    bindgen_cmd = _uniffi_bindgen_command(core_dir)
    bindgen_udl = _bindgen_udl_path(udl_path, core_dir)
    bindgen_library = _bindings_bindgen_library(core_dir)

    with tempfile.TemporaryDirectory(prefix="areamatrix-bindings-verify-") as temp_dir:
        generated_dir = Path(temp_dir)
        rc = _run_swift_bindgen(bindgen_cmd, bindgen_udl, bindgen_library, generated_dir)
        if rc != 0:
            return rc
        _normalize_binding_artifacts(generated_dir)
        drift = _binding_drift(generated_dir, tracked_path)
        ios_issues: list[str] = []
        if verify_ios_subset:
            ios_issues = _ios_bindings_subset_issues(
                generated_dir / "area_matrixFFI.h",
                ios_bindings_path,
                ios_app_path,
            )

    if drift or ios_issues:
        print("bindings verify: FAILED", file=os.sys.stderr)
        for name in drift:
            print(f"- tracked binding differs: {tracked_path / name}", file=os.sys.stderr)
        for issue in ios_issues:
            print(f"- iOS subset verify: {issue}", file=os.sys.stderr)
        if drift:
            print(
                "Run `./dev bindings update --udl core/area_matrix.udl "
                "--out-dir apps/macos/AreaMatrix/Bridge/UniFFI` after reviewing the Core API / UDL change.",
                file=os.sys.stderr,
            )
        if ios_issues:
            print(
                "iOS uses a curated header subset under apps/ios/Carea_matrixFFI; "
                "refresh area_matrixFFI.h symbols and *CoreFFI.swift shims against the regenerated header.",
                file=os.sys.stderr,
            )
        return 1

    if verify_ios_subset:
        print("bindings verify: PASS (macOS full + iOS subset)")
    else:
        print("bindings verify: PASS")
    return 0
