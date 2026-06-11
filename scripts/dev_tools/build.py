"""Build and binding generation tools behind ./dev."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from .common import fail, project_root, require_command, require_file, resolve_project_path, run_step

UNIFFI_BINDGEN_WRAPPER = "areamatrix_uniffi_bindgen_wrapper"
UNIFFI_BINDGEN_CRATE = "uniffi_bindgen"


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


def _find_registry_cache_home() -> Path | None:
    for cargo_home in _candidate_cargo_homes():
        if (cargo_home / "registry/cache").is_dir() and (cargo_home / "registry/index").is_dir():
            return cargo_home
    return None


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
    registry.mkdir(parents=True, exist_ok=True)
    (registry / "src").mkdir(parents=True, exist_ok=True)
    _replace_symlink(registry / "cache", source_home / "registry/cache")
    _replace_symlink(registry / "index", source_home / "registry/index")
    return cargo_home


def _write_uniffi_wrapper_crate(wrapper_dir: Path, uniffi_bindgen_source: Path) -> None:
    source_path = str(uniffi_bindgen_source).replace("\\", "\\\\")
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
                'camino = "1.0.8"',
                f'uniffi_bindgen = {{ path = "{source_path}" }}',
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

    uniffi_bindgen_source = _find_crate_source(UNIFFI_BINDGEN_CRATE, version)
    source_home = _find_registry_cache_home()
    if uniffi_bindgen_source is None or source_home is None:
        _fetch_locked_cargo_dependencies(core_dir)
        uniffi_bindgen_source = _find_crate_source(UNIFFI_BINDGEN_CRATE, version)
        source_home = _find_registry_cache_home()
    if uniffi_bindgen_source is None or source_home is None:
        fail(
            "missing 'uniffi-bindgen' and no locked Cargo cache is available for the fallback. "
            "Run `cd core && cargo fetch --locked`, then retry.",
            127,
        )

    tool_root = Path(os.environ.get("AREAMATRIX_UNIFFI_BINDGEN_TOOL_ROOT", "/private/tmp/areamatrix-uniffi-bindgen"))
    wrapper_dir = tool_root / f"wrapper-{version}"
    target_dir = tool_root / "target"
    cargo_home = _prepare_temp_cargo_home(tool_root, source_home)
    _write_uniffi_wrapper_crate(wrapper_dir, uniffi_bindgen_source)

    print()
    print("==> Preparing cached UniFFI bindgen fallback")
    print(f"    version: {version}")
    print(f"    wrapper: {wrapper_dir}")
    proc = run_step(
        ["cargo", "build", "--manifest-path", wrapper_dir / "Cargo.toml", "--quiet"],
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
        return [configured]
    found = shutil.which("uniffi-bindgen")
    if found:
        return [found]
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
        proc = run_step(["cargo", "build", *cargo_profile_args, "--target", target], cwd=core_dir, env=env, check=False)
        if proc.returncode != 0:
            return proc.returncode
    return 0


def _generated_artifacts(core_dir: Path, host_triple: str, target_profile: str) -> tuple[Path, Path, Path]:
    staticlib_arm = core_dir / "target/aarch64-apple-darwin" / target_profile / "libarea_matrix_core.a"
    staticlib_x86 = core_dir / "target/x86_64-apple-darwin" / target_profile / "libarea_matrix_core.a"
    bindgen_library = core_dir / "target" / host_triple / target_profile / "libarea_matrix_core.dylib"
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
    proc = run_step(
        [*bindgen_cmd, "generate", udl_file, "--language", "swift", "--out-dir", out_path, "--lib-file", bindgen_library],
        check=False,
    )
    return proc.returncode


def run_core_build(
    root: Path | None = None,
    *,
    profile: str | None = None,
    out_dir: str | Path | None = None,
    deployment_target: str | None = None,
) -> int:
    root = (root or project_root()).resolve()
    core_dir = root / "core"
    out_path = resolve_project_path(root, out_dir or os.environ.get("OUT_DIR", "apps/macos/AreaMatrix/Bridge/Generated"))
    build_profile = profile or os.environ.get("BUILD_PROFILE", "release")
    macos_target = deployment_target or os.environ.get("MACOSX_DEPLOYMENT_TARGET", "14.0")

    cargo_profile_args, target_profile = _cargo_profile_args(build_profile)
    _require_core_build_inputs(core_dir)
    host_triple = _macos_rust_host()
    if host_triple is None:
        return 1

    _require_rust_target("aarch64-apple-darwin")
    _require_rust_target("x86_64-apple-darwin")
    bindgen_cmd = _uniffi_bindgen_command(core_dir)

    env = {"MACOSX_DEPLOYMENT_TARGET": macos_target}
    print(f"==> Building AreaMatrix core ({build_profile})")
    rc = _build_core_targets(core_dir, cargo_profile_args, env)
    if rc != 0:
        return rc

    out_path.mkdir(parents=True, exist_ok=True)
    staticlib_arm, staticlib_x86, bindgen_library = _generated_artifacts(core_dir, host_triple, target_profile)

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
    out_path.mkdir(parents=True, exist_ok=True)

    print("==> Regenerating Swift bindings")
    proc = run_step([*bindgen_cmd, "generate", bindgen_udl, "--language", "swift", "--out-dir", out_path], check=False)
    if proc.returncode != 0:
        return proc.returncode
    print("==> Done")
    print(f"    udl:    {udl_path}")
    print(f"    swift:  {out_path / 'area_matrix.swift'}")
    print(f"    header: {out_path / 'area_matrixFFI.h'}")
    return 0
