#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  if [ "${KEEP_TASK_LOOP_CHECK_TMP:-0}" != "1" ]; then
    rm -rf "$TMP_DIR"
  else
    printf 'kept temp dir: %s\n' "$TMP_DIR"
  fi
}
trap cleanup EXIT

log() {
  printf '[check-task-loop] %s\n' "$*"
}

fail() {
  printf '[check-task-loop] FAIL: %s\n' "$*" >&2
  printf '[check-task-loop] temp dir: %s\n' "$TMP_DIR" >&2
  exit 1
}

assert_json_expr() {
  local file="$1"
  local expr="$2"
  "$PYTHON_BIN" - "$file" "$expr" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
expr = sys.argv[2]
data = json.loads(path.read_text(encoding="utf-8"))
safe_builtins = {"len": len}
if not eval(expr, {"__builtins__": safe_builtins}, {"data": data}):
    raise SystemExit(f"assertion failed: {expr}")
PY
}

assert_ignored() {
  local path="$1"
  git -C "$ROOT_DIR" check-ignore -q "$path" || fail "expected ignored: $path"
}

assert_not_ignored() {
  local path="$1"
  if git -C "$ROOT_DIR" check-ignore -q "$path"; then
    fail "expected tracked/not ignored: $path"
  fi
}

run_with_temp_state() {
  local prefix="$1"
  shift
  PROGRESS_FILE="$TMP_DIR/$prefix/progress.json" \
  LOG_ROOT="$TMP_DIR/$prefix/logs" \
  RUN_SUMMARY_ROOT="$TMP_DIR/$prefix/runs" \
  PROGRESS_BACKUP_ROOT="$TMP_DIR/$prefix/backups" \
  LOCK_DIR="$TMP_DIR/$prefix/lock" \
  "$@"
}

init_temp_git_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" branch -M main
  git -C "$repo" config user.email "task-loop-check@example.invalid"
  git -C "$repo" config user.name "AreaMatrix Task Loop Check"
  printf '.codex/task-loop-lock/\n.codex/task-loop-tmp/\n' > "$repo/.gitignore"
  printf 'baseline\n' > "$repo/README.md"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "initial"
}

write_json_file() {
  local path="$1"
  local json="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$json" > "$path"
}

cd "$ROOT_DIR"

log "static checks"
bash -n scripts/run_area_matrix_task_pipeline.sh scripts/check-task-loop.sh
"$PYTHON_BIN" -m py_compile scripts/task_loop_state.py scripts/task_loop_git.py

log "repo health"
bash scripts/check-skills.sh
"$PYTHON_BIN" tasks/prompts/_shared/prompt_pipeline.py doctor >/dev/null

log "real status is readable"
bash scripts/run_area_matrix_task_pipeline.sh --status > "$TMP_DIR/status.out"
grep -q 'stale_in_progress:' "$TMP_DIR/status.out" || fail "status output missing stale_in_progress"

log "dry-run PASS writes temp progress, logs, summary, and index"
mkdir -p "$TMP_DIR/pass"
run_with_temp_state pass \
  env DRY_RUN=1 DRY_RUN_RESULT=PASS MAX_RETRIES=1 \
  bash scripts/run_area_matrix_task_pipeline.sh --phase phase-0 --max-tasks 1 > "$TMP_DIR/pass/out.txt"
assert_json_expr "$TMP_DIR/pass/progress.json" 'data["tasks"]["0-1/task-01"]["status"] == "completed"'
pass_summary="$(find "$TMP_DIR/pass/runs" -type f -name summary.json | head -n 1)"
[ -n "$pass_summary" ] || fail "missing PASS summary"
assert_json_expr "$pass_summary" 'data["status"] == "completed" and data["totals"]["completed_in_run"] == 1'
assert_json_expr "$TMP_DIR/pass/runs/index.json" 'data["runs"][0]["status"] == "completed" and data["runs"][0]["completed"] == 1'
[ ! -d "$TMP_DIR/pass/lock" ] || fail "lock dir not released after PASS dry-run"

log "stale status and clear use only temp progress"
mkdir -p "$TMP_DIR/stale"
cat > "$TMP_DIR/stale/progress.json" <<'JSON'
{
  "tasks": {
    "0-1/task-01": {
      "attempts": 1,
      "copy_log": "/tmp/missing-copy.log",
      "note": "fake stale",
      "risk": "Medium",
      "run_id": "missing-run",
      "status": "in_progress",
      "verify_log": "/tmp/missing-verify.log"
    }
  },
  "version": 1
}
JSON
run_with_temp_state stale bash scripts/run_area_matrix_task_pipeline.sh --status > "$TMP_DIR/stale/status.out"
grep -q 'stale_in_progress: 1' "$TMP_DIR/stale/status.out" || fail "stale status was not detected"
run_with_temp_state stale bash scripts/run_area_matrix_task_pipeline.sh --clear-stale > "$TMP_DIR/stale/clear.out"
assert_json_expr "$TMP_DIR/stale/progress.json" 'data["tasks"] == {}'
find "$TMP_DIR/stale/backups" -type f -name 'progress-before-clear-stale-*.json' | grep -q . || fail "clear-stale backup missing"

log "resume-stale FAIL does not mark completed"
mkdir -p "$TMP_DIR/resume"
cat > "$TMP_DIR/resume/progress.json" <<'JSON'
{
  "tasks": {
    "0-1/task-01": {
      "attempts": 1,
      "copy_log": "/tmp/missing-copy.log",
      "note": "fake stale",
      "risk": "Medium",
      "run_id": "missing-run",
      "status": "in_progress",
      "verify_log": "/tmp/missing-verify.log"
    }
  },
  "version": 1
}
JSON
if run_with_temp_state resume \
  env DRY_RUN=1 DRY_RUN_RESULT=FAIL DRY_RUN_MAX_ATTEMPTS=1 MAX_RETRIES=1 \
  bash scripts/run_area_matrix_task_pipeline.sh --phase phase-0 --resume-stale > "$TMP_DIR/resume/out.txt" 2>&1; then
  fail "resume-stale FAIL path unexpectedly succeeded"
fi
assert_json_expr "$TMP_DIR/resume/progress.json" 'data["tasks"]["0-1/task-01"]["status"] == "failed"'
resume_summary="$(find "$TMP_DIR/resume/runs" -type f -name summary.json | head -n 1)"
[ -n "$resume_summary" ] || fail "missing resume summary"
assert_json_expr "$resume_summary" 'data["status"] == "failed" and data["totals"]["retries"] == 1'
assert_json_expr "$TMP_DIR/resume/runs/index.json" 'data["runs"][0]["status"] == "failed" and data["runs"][0]["retries"] == 1'

log "live lock blocks second runner"
mkdir -p "$TMP_DIR/lockcase/lock"
printf '%s\n' "$$" > "$TMP_DIR/lockcase/lock/pid"
printf '%s\n' "fake-run" > "$TMP_DIR/lockcase/lock/run_id"
printf '%s\n' "run" > "$TMP_DIR/lockcase/lock/operation"
printf '%s\n' "now" > "$TMP_DIR/lockcase/lock/started_at"
if run_with_temp_state lockcase \
  env DRY_RUN=1 \
  bash scripts/run_area_matrix_task_pipeline.sh --phase phase-0 --max-tasks 1 > "$TMP_DIR/lockcase/out.txt" 2>&1; then
  fail "lock conflict unexpectedly allowed a second runner"
fi
grep -q 'task loop lock is held by live pid' "$TMP_DIR/lockcase/out.txt" || fail "lock conflict error missing"

log "git helper preflight and checkpoint"
git_repo="$TMP_DIR/git-helper"
init_temp_git_repo "$git_repo"
"$PYTHON_BIN" scripts/task_loop_git.py preflight \
  --root-dir "$git_repo" \
  --mode commit \
  --branch-policy auto \
  --push-remote origin \
  --push-set-upstream \
  --run-id check001 > "$TMP_DIR/git-helper-preflight.json"
assert_json_expr "$TMP_DIR/git-helper-preflight.json" 'data["status"] == "ok" and data["branch"].startswith("codex/areamatrix-task-loop-check001")'
[ "$(git -C "$git_repo" branch --show-current)" = "codex/areamatrix-task-loop-check001" ] || fail "auto branch was not created"
write_json_file "$git_repo/tasks/prompts/_shared/progress.json" '{"tasks":{"0-1/task-01":{"status":"completed"}},"version":1}'
write_json_file "$git_repo/.codex/task-loop-runs/check001/summary.json" '{"tasks":{"0-1/task-01":{"status":"completed"}},"version":1}'
printf 'implemented\n' > "$git_repo/implemented.txt"
"$PYTHON_BIN" scripts/task_loop_git.py checkpoint \
  --root-dir "$git_repo" \
  --mode commit \
  --label "0-1/task-01" \
  --phase phase-0 \
  --task-name "0-1-task-01" \
  --attempts 1 \
  --run-id check001 \
  --copy-log "$git_repo/.codex/task-loop-logs/check001/phase-0/copy.log" \
  --verify-log "$git_repo/.codex/task-loop-logs/check001/phase-0/verify.log" \
  --progress-file "$git_repo/tasks/prompts/_shared/progress.json" \
  --summary-file "$git_repo/.codex/task-loop-runs/check001/summary.json" > "$TMP_DIR/git-helper-checkpoint.json"
assert_json_expr "$TMP_DIR/git-helper-checkpoint.json" 'data["status"] == "committed" and len(data["commit"]) >= 7'
assert_json_expr "$git_repo/tasks/prompts/_shared/progress.json" 'data["tasks"]["0-1/task-01"]["git_checkpoint_status"] == "committed" and len(data["tasks"]["0-1/task-01"]["git_commit"]) >= 7'
[ -z "$(git -C "$git_repo" status --short)" ] || fail "git checkpoint left dirty worktree"

dirty_repo="$TMP_DIR/git-dirty"
init_temp_git_repo "$dirty_repo"
printf 'dirty\n' >> "$dirty_repo/README.md"
if "$PYTHON_BIN" scripts/task_loop_git.py preflight \
  --root-dir "$dirty_repo" \
  --mode commit \
  --branch-policy auto \
  --run-id dirty > "$TMP_DIR/git-dirty-preflight.json" 2>&1; then
  fail "dirty git preflight unexpectedly succeeded"
fi
grep -q 'requires a clean worktree' "$TMP_DIR/git-dirty-preflight.json" || fail "dirty preflight error missing"

push_fail_repo="$TMP_DIR/git-push-fail"
init_temp_git_repo "$push_fail_repo"
git -C "$push_fail_repo" checkout -q -b codex/push-fail
write_json_file "$push_fail_repo/tasks/prompts/_shared/progress.json" '{"tasks":{"0-1/task-01":{"status":"completed"}},"version":1}'
write_json_file "$push_fail_repo/.codex/task-loop-runs/pushfail/summary.json" '{"tasks":{"0-1/task-01":{"status":"completed"}},"version":1}'
printf 'push fail\n' > "$push_fail_repo/push-fail.txt"
if "$PYTHON_BIN" scripts/task_loop_git.py checkpoint \
  --root-dir "$push_fail_repo" \
  --mode push \
  --push-remote missing \
  --label "0-1/task-01" \
  --phase phase-0 \
  --task-name "0-1-task-01" \
  --attempts 1 \
  --run-id pushfail \
  --progress-file "$push_fail_repo/tasks/prompts/_shared/progress.json" \
  --summary-file "$push_fail_repo/.codex/task-loop-runs/pushfail/summary.json" > "$TMP_DIR/git-push-fail-checkpoint.json" 2>&1; then
  fail "push failure checkpoint unexpectedly succeeded"
fi
assert_json_expr "$push_fail_repo/tasks/prompts/_shared/progress.json" 'data["tasks"]["0-1/task-01"]["git_checkpoint_status"] == "git_push_failed"'
[ -z "$(git -C "$push_fail_repo" status --short)" ] || fail "push failure checkpoint left dirty worktree"

log "runner git checkpoint with fake codex in temp repo"
runner_repo="$TMP_DIR/runner-git"
init_temp_git_repo "$runner_repo"
mkdir -p "$runner_repo/tasks/prompts/_shared/copy-ready/phase-0"
mkdir -p "$runner_repo/tasks/prompts/_shared/verify-ready/phase-0"
printf '# copy\n风险等级：`Medium`\n' > "$runner_repo/tasks/prompts/_shared/copy-ready/phase-0/0-1-task-01.md"
printf '# verify\n' > "$runner_repo/tasks/prompts/_shared/verify-ready/phase-0/0-1-task-01.md"
git -C "$runner_repo" add .
git -C "$runner_repo" commit -q -m "add prompt fixtures"
fake_codex="$TMP_DIR/fake-codex"
cat > "$fake_codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    --cd)
      cd "$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
input="$(cat)"
mkdir -p "$(dirname "$out")"
if printf '%s' "$input" | grep -q 'VERIFY_RESULT'; then
  printf '验收通过\nVERIFY_RESULT: PASS\n' > "$out"
else
  printf 'copy ok\n' > "$out"
fi
SH
chmod +x "$fake_codex"
ROOT_DIR="$runner_repo" \
STATE_TOOL="$ROOT_DIR/scripts/task_loop_state.py" \
GIT_TOOL="$ROOT_DIR/scripts/task_loop_git.py" \
CODEX_BIN="$fake_codex" \
RISK_POLICY=allow \
MAX_RETRIES=1 \
bash scripts/run_area_matrix_task_pipeline.sh --phase phase-0 --max-tasks 1 > "$TMP_DIR/runner-git-out.txt"
assert_json_expr "$runner_repo/tasks/prompts/_shared/progress.json" 'data["tasks"]["0-1/task-01"]["status"] == "completed" and len(data["tasks"]["0-1/task-01"]["git_commit"]) >= 7'
[ -z "$(git -C "$runner_repo" status --short)" ] || fail "runner git checkpoint left dirty worktree"
case "$(git -C "$runner_repo" branch --show-current)" in
  codex/areamatrix-task-loop-*)
    ;;
  *)
    fail "runner did not auto-create task branch"
    ;;
esac

log "git ignore policy"
assert_ignored ".codex/task-loop-lock/foo"
assert_ignored ".codex/task-loop-tmp/foo"
assert_not_ignored "tasks/prompts/_shared/progress.json"
assert_not_ignored ".codex/task-loop-runs/index.json"
assert_not_ignored ".codex/task-loop-runs/example/summary.json"
assert_not_ignored ".codex/task-loop-progress-backups/progress-before-reset-example.json"
assert_not_ignored ".codex/task-loop-logs/example/phase-0/example.log"

log "OK"
