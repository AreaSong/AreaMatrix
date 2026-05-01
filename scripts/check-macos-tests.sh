#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_ROOT}/apps/macos/AreaMatrix.xcodeproj"
SCHEME="${XCODE_SCHEME:-AreaMatrix}"
TEST_BUNDLE_NAME="${XCODE_TEST_BUNDLE_NAME:-AreaMatrixTests.xctest}"
DEFAULT_ARCH="$(uname -m)"
DESTINATION="${XCODE_DESTINATION:-platform=macOS,arch=${DEFAULT_ARCH}}"
KEEP_DERIVED_DATA="${KEEP_DERIVED_DATA:-0}"

if [[ -n "${DERIVED_DATA_PATH:-}" ]]; then
  DERIVED_DATA_DIR="${DERIVED_DATA_PATH}"
  CREATED_DERIVED_DATA=0
else
  DERIVED_DATA_DIR="$(mktemp -d "${TMPDIR:-/tmp}/areamatrix-xcode-tests.XXXXXX")"
  CREATED_DERIVED_DATA=1
fi

XCODEBUILD_TEST_LOG="${XCODEBUILD_TEST_LOG:-${DERIVED_DATA_DIR}/xcodebuild-test.log}"
XCODEBUILD_BUILD_LOG="${XCODEBUILD_BUILD_LOG:-${DERIVED_DATA_DIR}/xcodebuild-build-for-testing.log}"

cleanup() {
  if [[ "${CREATED_DERIVED_DATA}" == "1" && "${KEEP_DERIVED_DATA}" != "1" ]]; then
    rm -rf "${DERIVED_DATA_DIR}"
  fi
}
trap cleanup EXIT

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

run_xcodebuild_test() {
  xcodebuild test \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -destination "${DESTINATION}" \
    -derivedDataPath "${DERIVED_DATA_DIR}" \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | tee "${XCODEBUILD_TEST_LOG}"
}

run_build_for_testing() {
  xcodebuild build-for-testing \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -destination "${DESTINATION}" \
    -derivedDataPath "${DERIVED_DATA_DIR}" \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | tee "${XCODEBUILD_BUILD_LOG}"
}

is_testmanagerd_sandbox_failure() {
  grep -Eq 'testmanagerd\.control|Failed to establish communication with the test runner' \
    "${XCODEBUILD_TEST_LOG}" &&
    grep -Eiq 'sandbox' "${XCODEBUILD_TEST_LOG}"
}

find_test_bundle() {
  local products_dir="${DERIVED_DATA_DIR}/Build/Products"
  local default_bundle="${products_dir}/Debug/${TEST_BUNDLE_NAME}"

  if [[ -d "${default_bundle}" ]]; then
    printf '%s\n' "${default_bundle}"
    return 0
  fi

  find "${products_dir}" -type d -name "${TEST_BUNDLE_NAME}" -print -quit 2>/dev/null
}

run_xctest_bundle() {
  local test_bundle="$1"
  local products_dir
  local app_macos_dir

  products_dir="$(dirname "${test_bundle}")"
  app_macos_dir="${products_dir}/${SCHEME}.app/Contents/MacOS"

  [[ -d "${test_bundle}" ]] || fail "test bundle not found at ${test_bundle}."
  [[ -d "${app_macos_dir}" ]] || fail "app binary directory not found at ${app_macos_dir}."

  echo
  echo "==> xcrun xctest ${test_bundle}"
  env \
    DYLD_LIBRARY_PATH="${app_macos_dir}:${DYLD_LIBRARY_PATH:-}" \
    DYLD_FRAMEWORK_PATH="${products_dir}:${DYLD_FRAMEWORK_PATH:-}" \
    xcrun xctest "${test_bundle}"
}

main() {
  require_command xcodebuild
  require_command xcrun

  [[ -d "${PROJECT_PATH}" ]] || fail "Xcode project not found at ${PROJECT_PATH}."

  mkdir -p "${DERIVED_DATA_DIR}"

  echo "==> xcodebuild test"
  if run_xcodebuild_test; then
    echo "macOS tests: xcodebuild test passed."
    return
  fi

  if ! is_testmanagerd_sandbox_failure; then
    fail "xcodebuild test failed for a non-sandbox reason. See ${XCODEBUILD_TEST_LOG}."
  fi

  echo
  echo "==> xcodebuild test was blocked by local sandboxed testmanagerd access."
  echo "    Reusing the built XCTest bundle for direct XCTest execution."

  local test_bundle
  test_bundle="$(find_test_bundle)"
  if [[ -z "${test_bundle}" ]]; then
    echo
    echo "==> xcodebuild build-for-testing"
    run_build_for_testing
    test_bundle="$(find_test_bundle)"
  fi

  if [[ -z "${test_bundle}" ]]; then
    fail "unable to locate ${TEST_BUNDLE_NAME} under ${DERIVED_DATA_DIR}."
  fi

  run_xctest_bundle "${test_bundle}"
  echo "macOS tests: xcrun xctest passed after xcodebuild test sandbox block."
}

main "$@"
