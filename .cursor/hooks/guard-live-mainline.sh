#!/usr/bin/env bash
# beforeShellExecution: ask before live-mainline commands (fail-open; list mirrors
# .ai-governance/workflows/cursor-adapter-layer.md)
set -euo pipefail

export HOOK_INPUT="$(cat || true)"

python3 - <<'PY' || echo '{ "permission": "allow" }'
import json, os, re

raw = os.environ.get("HOOK_INPUT") or "{}"
try:
    command = json.loads(raw).get("command") or ""
except json.JSONDecodeError:
    command = ""

GUARDS = [
    (
        re.compile(r"task-loop['\"]?\s+(run|drain|resume-stale|reset-progress|clear-stale)\b"),
        "task-loop live runner control",
    ),
    (
        re.compile(r"workflow\s+promote\b(?=.*\b(approve|apply)\b)"),
        "workflow promotion approve/apply",
    ),
    (
        re.compile(r"\btasks\s+complete\b(?=.*--write\b)"),
        "task completion write",
    ),
    (
        re.compile(r"\bgit\s+push\b(?=.*(--force\b|--force-with-lease\b|\s-f\b))"),
        "force push",
    ),
]

hit = next((label for pattern, label in GUARDS if pattern.search(command)), None)

if hit:
    print(
        json.dumps(
            {
                "permission": "ask",
                "user_message": (
                    f"命中 AreaMatrix live 主线守卫（{hit}）。该命令会改变 live runner、"
                    "promotion、任务进度或远端历史，请确认后再执行。"
                ),
                "agent_message": (
                    f"A hook flagged this command as live-mainline ({hit}). Do not bypass; "
                    "wait for the user's decision and re-check "
                    ".ai-governance/workflows/cursor-adapter-layer.md boundaries."
                ),
            },
            ensure_ascii=False,
        )
    )
else:
    print(json.dumps({"permission": "allow"}))
PY
