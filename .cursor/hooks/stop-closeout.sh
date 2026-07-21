#!/usr/bin/env bash
# stop: one-shot closeout nudge when tracked source surfaces are dirty (fail-open)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export AREAMATRIX_ROOT="$ROOT"
export HOOK_INPUT="$(cat || true)"

python3 - <<'PY' || echo "{}"
import json, os, subprocess
from pathlib import Path

raw = os.environ.get("HOOK_INPUT") or "{}"
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    print("{}")
    raise SystemExit(0)

if data.get("status") not in (None, "completed"):
    print("{}")
    raise SystemExit(0)

if int(data.get("loop_count") or 0) > 0:
    print("{}")
    raise SystemExit(0)

root = Path(os.environ["AREAMATRIX_ROOT"])
try:
    proc = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=root,
        capture_output=True,
        text=True,
        timeout=5,
        check=False,
    )
    porcelain = proc.stdout or ""
except Exception:
    print("{}")
    raise SystemExit(0)

paths = []
for line in porcelain.splitlines():
    if len(line) < 4:
        continue
    entry = line[3:].strip()
    if " -> " in entry:
        entry = entry.split(" -> ", 1)[1]
    paths.append(entry)

WATCHED = ("core/", "apps/", "docs/", "workflow/", "scripts/", ".ai-governance/", ".codex/skills-src/")

def interesting(p: str) -> bool:
    return p.startswith(WATCHED) or p in ("AGENTS.md", "README.md", "README.zh-CN.md")

if any(interesting(p) for p in paths):
    print(
        json.dumps(
            {
                "followup_message": (
                    "工作区在受关注目录仍有未提交改动。先用 git status 确认哪些改动属于本次会话；"
                    "属于本次的按 skill areamatrix-closeout 静默收口（验证、doc-sync、plans、canvas、AAR），"
                    "不属于本次的向用户说明归属即可，勿要求用户手打斜杠。"
                )
            },
            ensure_ascii=False,
        )
    )
else:
    print("{}")
PY
