# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Secret scan wrapper for local pre-commit / CI parity.
#
# Default (diff): scan uncommitted changes and commits ahead of origin/main only.
# History (maintainer): AREAMATRIX_GITLEAKS_MODE=history GITLEAKS_LOG_OPTS="--all" ./dev check secrets
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${ROOT}/.gitleaks.toml"
MODE="${AREAMATRIX_GITLEAKS_MODE:-diff}"
UPSTREAM="${AREAMATRIX_GITLEAKS_BASE:-origin/main}"

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "secrets check: SKIP (gitleaks not installed; brew install gitleaks)" >&2
  exit 0
fi

gitleaks_common=(--config "${CONFIG}" --redact --no-banner)

scan_history() {
  local log_opts="${GITLEAKS_LOG_OPTS:---all}"
  echo "secrets check: history mode (log-opts=${log_opts})" >&2
  echo "secrets check: expect path-leak noise in old commits; use diff mode before commit" >&2
  local args=(detect --source "${ROOT}" "${gitleaks_common[@]}" --log-opts "${log_opts}")
  if [[ "${log_opts}" == "--all" ]]; then
    args+=(--report-path "${ROOT}/.gitleaks-report.json")
  fi
  gitleaks "${args[@]}"
}

scan_diff() {
  local scanned=0

  if ! git -C "${ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "secrets check: FAILED (not a git repository)" >&2
    return 1
  fi

  if ! git -C "${ROOT}" diff --quiet || ! git -C "${ROOT}" diff --cached --quiet; then
    echo "secrets check: scanning uncommitted changes" >&2
    gitleaks protect --source "${ROOT}" "${gitleaks_common[@]}"
    scanned=1
  fi

  if git -C "${ROOT}" rev-parse "${UPSTREAM}" >/dev/null 2>&1; then
    local base head
    base="$(git -C "${ROOT}" merge-base HEAD "${UPSTREAM}")"
    head="$(git -C "${ROOT}" rev-parse HEAD)"
    if [[ "${base}" != "${head}" ]]; then
      echo "secrets check: scanning commits ${base}..HEAD (vs ${UPSTREAM})" >&2
      gitleaks detect --source "${ROOT}" "${gitleaks_common[@]}" --log-opts "${base}..HEAD"
      scanned=1
    fi
  elif [[ "$(git -C "${ROOT}" rev-parse HEAD)" != "$(git -C "${ROOT}" hash-object -t tree /dev/null 2>/dev/null || echo "")" ]]; then
    echo "secrets check: scanning HEAD (no ${UPSTREAM} ref)" >&2
    gitleaks detect --source "${ROOT}" "${gitleaks_common[@]}" --log-opts "HEAD"
    scanned=1
  fi

  if [[ "${scanned}" -eq 0 ]]; then
    echo "secrets check: nothing to scan (clean tree, no commits ahead of ${UPSTREAM})" >&2
  fi
  return 0
}

case "${MODE}" in
  history | all)
    scan_history
    ;;
  diff | *)
    scan_diff
    ;;
esac
