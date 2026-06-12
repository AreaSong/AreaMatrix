# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Secret scan wrapper for local pre-commit / CI parity.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${ROOT}/.gitleaks.toml"

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "secrets check: SKIP (gitleaks not installed; brew install gitleaks)" >&2
  exit 0
fi

args=(detect --source "${ROOT}" --config "${CONFIG}" --verbose --redact --no-banner)
if [[ "${GITLEAKS_LOG_OPTS:-}" != "" ]]; then
  args+=(--log-opts "${GITLEAKS_LOG_OPTS}" --report-path "${ROOT}/.gitleaks-report.json")
fi

gitleaks "${args[@]}"
