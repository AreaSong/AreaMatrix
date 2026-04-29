#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${PROJECT_ROOT}/core"
OUT_DIR="${OUT_DIR:-${PROJECT_ROOT}/apps/macos/AreaMatrix/Bridge/Generated}"
BUILD_PROFILE="${BUILD_PROFILE:-release}"
MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"

case "${BUILD_PROFILE}" in
  release)
    CARGO_PROFILE_ARGS=(--release)
    TARGET_PROFILE="release"
    ;;
  debug)
    CARGO_PROFILE_ARGS=()
    TARGET_PROFILE="debug"
    ;;
  *)
    echo "error: BUILD_PROFILE must be 'release' or 'debug'." >&2
    exit 2
    ;;
esac

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "error: missing required command '${command_name}'." >&2
    exit 127
  fi
}

require_command cargo
require_command rustc
require_command uniffi-bindgen

if [[ ! -d "${CORE_DIR}" ]]; then
  echo "error: core crate not found at ${CORE_DIR}." >&2
  exit 1
fi

HOST_TRIPLE="$(rustc -vV | sed -n 's/^host: //p')"
case "${HOST_TRIPLE}" in
  aarch64-apple-darwin | x86_64-apple-darwin)
    ;;
  *)
    echo "error: update-bindings.sh must run on a macOS Rust host." >&2
    echo "       got host triple: ${HOST_TRIPLE}" >&2
    exit 2
    ;;
esac

export MACOSX_DEPLOYMENT_TARGET

echo "==> Building host cdylib for Swift bindings (${BUILD_PROFILE})"
cd "${CORE_DIR}"
cargo build "${CARGO_PROFILE_ARGS[@]}" --target "${HOST_TRIPLE}"

mkdir -p "${OUT_DIR}"

echo "==> Regenerating Swift bindings"
uniffi-bindgen generate \
  --library "target/${HOST_TRIPLE}/${TARGET_PROFILE}/libarea_matrix_core.dylib" \
  --language swift \
  --out-dir "${OUT_DIR}"

echo "==> Done"
echo "    swift:  ${OUT_DIR}/area_matrix.swift"
echo "    header: ${OUT_DIR}/area_matrixFFI.h"
