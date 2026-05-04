"""Build and binding generation tools behind ./dev."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from .common import fail, project_root, require_command, require_file, resolve_project_path, run_step


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

    if build_profile == "release":
        cargo_profile_args = ["--release"]
        target_profile = "release"
    elif build_profile == "debug":
        cargo_profile_args = []
        target_profile = "debug"
    else:
        fail("BUILD_PROFILE must be 'release' or 'debug'.")

    for command in ["cargo", "lipo", "rustc", "uniffi-bindgen"]:
        require_command(command)
    if not core_dir.is_dir():
        fail(f"core crate not found at {core_dir}.")
    require_file(core_dir / "Cargo.toml", "Core Cargo manifest")
    require_file(core_dir / "area_matrix.udl", "UniFFI definition")
    require_file(core_dir / "build.rs", "UniFFI scaffolding build script")

    host_triple = _host_triple()
    if host_triple not in {"aarch64-apple-darwin", "x86_64-apple-darwin"}:
        print("error: ./dev build core must run on a macOS Rust host.", file=os.sys.stderr)
        print(f"       got host triple: {host_triple}", file=os.sys.stderr)
        return 1

    _require_rust_target("aarch64-apple-darwin")
    _require_rust_target("x86_64-apple-darwin")

    env = {"MACOSX_DEPLOYMENT_TARGET": macos_target}
    print(f"==> Building AreaMatrix core ({build_profile})")
    for target in ["aarch64-apple-darwin", "x86_64-apple-darwin"]:
        proc = run_step(["cargo", "build", *cargo_profile_args, "--target", target], cwd=core_dir, env=env, check=False)
        if proc.returncode != 0:
            return proc.returncode

    out_path.mkdir(parents=True, exist_ok=True)
    staticlib_arm = core_dir / "target/aarch64-apple-darwin" / target_profile / "libarea_matrix_core.a"
    staticlib_x86 = core_dir / "target/x86_64-apple-darwin" / target_profile / "libarea_matrix_core.a"
    universal_staticlib = out_path / "libarea_matrix_core.a"
    bindgen_library = core_dir / "target" / host_triple / target_profile / "libarea_matrix_core.dylib"

    require_file(staticlib_arm, "aarch64 static library")
    require_file(staticlib_x86, "x86_64 static library")
    require_file(bindgen_library, "host dylib for UniFFI binding generation")

    print()
    print("==> Creating universal static library")
    universal_staticlib.unlink(missing_ok=True)
    proc = run_step(["lipo", "-create", staticlib_arm, staticlib_x86, "-output", universal_staticlib], check=False)
    if proc.returncode != 0:
        return proc.returncode

    print()
    print("==> Generating Swift bindings")
    proc = run_step(
        ["uniffi-bindgen", "generate", "--library", bindgen_library, "--language", "swift", "--out-dir", out_path],
        check=False,
    )
    if proc.returncode != 0:
        return proc.returncode

    print("==> Done")
    print(f"    staticlib: {universal_staticlib}")
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

    require_command("uniffi-bindgen")
    out_path.mkdir(parents=True, exist_ok=True)

    print("==> Regenerating Swift bindings")
    proc = run_step(["uniffi-bindgen", "generate", udl_path, "--language", "swift", "--out-dir", out_path], check=False)
    if proc.returncode != 0:
        return proc.returncode
    print("==> Done")
    print(f"    udl:    {udl_path}")
    print(f"    swift:  {out_path / 'area_matrix.swift'}")
    print(f"    header: {out_path / 'area_matrixFFI.h'}")
    return 0

