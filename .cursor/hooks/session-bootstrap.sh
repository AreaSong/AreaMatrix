#!/usr/bin/env bash
# sessionStart: inject unfinished plans and dirty-worktree ownership hint (fail-open)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export AREAMATRIX_ROOT="$ROOT"

# Drain stdin; sessionStart payload is not needed beyond fire-and-forget.
cat >/dev/null || true

python3 - <<'PY' || echo "{}"
import json, os, subprocess
from pathlib import Path

root = Path(os.environ["AREAMATRIX_ROOT"])
parts = []

plans_dir = root / ".cursor" / "plans"
plan_names = sorted(p.name for p in plans_dir.glob("*.md")) if plans_dir.is_dir() else []
if plan_names:
    parts.append(
        "unfinished plans in .cursor/plans/: " + ", ".join(plan_names) + "."
    )

try:
    proc = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=root,
        capture_output=True,
        text=True,
        timeout=5,
        check=False,
    )
    dirty = [line for line in (proc.stdout or "").splitlines() if line.strip()]
except Exception:
    dirty = []
if dirty:
    parts.append(
        f"worktree has {len(dirty)} uncommitted change(s); confirm ownership before "
        "including them in this session's scope (they may belong to earlier work)."
    )

out = {}
if parts:
    out["additional_context"] = (
        "AreaMatrix session bootstrap: "
        + " ".join(parts)
        + " Silently run skill areamatrix-session-bootstrap before coding."
    )
print(json.dumps(out))
PY
