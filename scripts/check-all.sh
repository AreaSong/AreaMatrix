#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${PROJECT_ROOT}/core"
MACOS_DIR="${PROJECT_ROOT}/apps/macos"
MACOS_PROJECT="${MACOS_DIR}/AreaMatrix.xcodeproj"
PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-${TMPDIR:-/tmp}/areamatrix-pycache}"
export PYTHONPYCACHEPREFIX

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    fail "missing required command '${command_name}'."
  fi
}

run_step() {
  echo
  echo "==> $*"
  "$@"
}

run_governance_checks() {
  cd "${PROJECT_ROOT}"

  require_command bash
  require_command git
  require_command python3

  run_step bash scripts/check-governance.sh
  run_step bash scripts/check-skills.sh
  run_step bash scripts/check-task-loop.sh
  run_step python3 tasks/prompts/_shared/prompt_pipeline.py doctor
  run_step git diff --check
}

run_core_checks() {
  require_command cargo

  if [[ ! -f "${CORE_DIR}/Cargo.toml" ]]; then
    fail "core Cargo manifest not found at ${CORE_DIR}/Cargo.toml."
  fi

  cd "${CORE_DIR}"
  run_step cargo fmt --all -- --check
  run_step cargo clippy --all-targets --all-features -- -D warnings
  run_step cargo test --workspace
}

run_xcode_tests() {
  require_command xcodebuild

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
}

run_swift_checks() {
  require_command swiftformat
  require_command swiftlint

  cd "${MACOS_DIR}"
  run_step swiftformat --lint .
  run_step swiftlint --strict
}

run_macos_checks() {
  if [[ ! -d "${MACOS_DIR}" ]]; then
    echo
    echo "==> Skipping macOS checks"
    echo "    ${MACOS_DIR} does not exist yet."
    return
  fi

  if [[ -d "${MACOS_PROJECT}" ]]; then
    run_xcode_tests
  else
    echo
    echo "==> Skipping Xcode build and test"
    echo "    ${MACOS_PROJECT} does not exist yet."
  fi

  run_swift_checks
}

main() {
  run_governance_checks
  run_core_checks
  run_macos_checks
}

main "$@"
