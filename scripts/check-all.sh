#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${PROJECT_ROOT}/core"
MACOS_PROJECT="${PROJECT_ROOT}/apps/macos/AreaMatrix.xcodeproj"
MACOS_DIR="${PROJECT_ROOT}/apps/macos"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "error: missing required command '${command_name}'." >&2
    exit 127
  fi
}

run_step() {
  echo
  echo "==> $*"
  "$@"
}

require_command cargo
require_command python3

if [[ ! -d "${CORE_DIR}" ]]; then
  echo "error: core crate not found at ${CORE_DIR}." >&2
  exit 1
fi

cd "${PROJECT_ROOT}"
run_step python3 tasks/prompts/_shared/prompt_pipeline.py doctor

cd "${CORE_DIR}"
run_step cargo fmt --all -- --check
run_step cargo clippy --all-targets --all-features -- -D warnings
run_step cargo test --workspace

if [[ ! -d "${MACOS_PROJECT}" ]]; then
  echo
  echo "==> Skipping macOS app checks"
  echo "    ${MACOS_PROJECT} does not exist yet."
  exit 0
fi

cd "${PROJECT_ROOT}"
run_step ./scripts/build-core.sh

echo
echo "==> xcodebuild test"
if command -v xcbeautify >/dev/null 2>&1; then
  xcodebuild test \
    -project apps/macos/AreaMatrix.xcodeproj \
    -scheme AreaMatrix \
    -destination 'platform=macOS,arch=arm64' \
    CODE_SIGNING_ALLOWED=NO \
    | xcbeautify --quiet
else
  xcodebuild test \
    -project apps/macos/AreaMatrix.xcodeproj \
    -scheme AreaMatrix \
    -destination 'platform=macOS,arch=arm64' \
    CODE_SIGNING_ALLOWED=NO
fi

if [[ ! -d "${MACOS_DIR}" ]]; then
  echo "error: expected macOS source directory at ${MACOS_DIR}." >&2
  exit 1
fi

require_command swiftformat
require_command swiftlint

cd "${MACOS_DIR}"
run_step swiftformat --lint .
run_step swiftlint --strict
