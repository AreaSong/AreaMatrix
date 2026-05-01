#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/update-bindings.sh --udl <path> --out-dir <directory>

Regenerates UniFFI Swift bindings from an explicit UDL file into an explicit
output directory. Generated product bindings are intentionally left untracked
unless the caller chooses to review and commit them separately.

Example:
  scripts/update-bindings.sh \
    --udl core/area_matrix.udl \
    --out-dir apps/macos/AreaMatrix/Bridge/Generated
USAGE
}

fail() {
  echo "error: $1" >&2
  exit "${2:-1}"
}

resolve_project_path() {
  local input_path="$1"

  case "${input_path}" in
    /*) printf '%s\n' "${input_path}" ;;
    *) printf '%s\n' "${PROJECT_ROOT}/${input_path}" ;;
  esac
}

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    fail "missing required command '${command_name}'." 127
  fi
}

UDL_PATH=""
OUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --udl)
      [[ $# -ge 2 ]] || fail "--udl requires a path." 2
      UDL_PATH="$2"
      shift 2
      ;;
    --out-dir | --output-dir)
      [[ $# -ge 2 ]] || fail "$1 requires a directory." 2
      OUT_DIR="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument '$1'." 2
      ;;
  esac
done

[[ -n "${UDL_PATH}" ]] || fail "missing required --udl <path>." 2
[[ -n "${OUT_DIR}" ]] || fail "missing required --out-dir <directory>." 2

UDL_PATH="$(resolve_project_path "${UDL_PATH}")"
OUT_DIR="$(resolve_project_path "${OUT_DIR}")"

[[ -f "${UDL_PATH}" ]] || fail "UDL file not found at ${UDL_PATH}."
if [[ -e "${OUT_DIR}" && ! -d "${OUT_DIR}" ]]; then
  fail "output path exists but is not a directory: ${OUT_DIR}."
fi

require_command uniffi-bindgen
mkdir -p "${OUT_DIR}"

echo "==> Regenerating Swift bindings"
uniffi-bindgen generate \
  "${UDL_PATH}" \
  --language swift \
  --out-dir "${OUT_DIR}"

echo "==> Done"
echo "    udl:    ${UDL_PATH}"
echo "    swift:  ${OUT_DIR}/area_matrix.swift"
echo "    header: ${OUT_DIR}/area_matrixFFI.h"
