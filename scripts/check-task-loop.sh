#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$ROOT_DIR"
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
  ROOT_DIR="$ROOT_DIR" \
  RUNNER="$ROOT_DIR/scripts/run_area_matrix_task_pipeline.sh" \
  PIPELINE="$ROOT_DIR/tasks/prompts/_shared/prompt_pipeline.py" \
  PROGRESS_FILE="$TMP_DIR/$prefix/progress.json" \
  LOG_ROOT="$TMP_DIR/$prefix/logs" \
  RUN_SUMMARY_ROOT="$TMP_DIR/$prefix/runs" \
  PROGRESS_BACKUP_ROOT="$TMP_DIR/$prefix/backups" \
  LOCK_DIR="$TMP_DIR/$prefix/lock" \
  CONTROL_DIR="$TMP_DIR/$prefix/control" \
  CONSOLE_LOG_ROOT="$TMP_DIR/$prefix/console" \
  "$@"
}

init_temp_git_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" branch -M main
  git -C "$repo" config user.email "task-loop-check@example.invalid"
  git -C "$repo" config user.name "AreaMatrix Task Loop Check"
  printf '.codex/task-loop-lock/\n.codex/task-loop-tmp/\n.codex/task-loop-control/\n' > "$repo/.gitignore"
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
bash -n dev.sh scripts/run_area_matrix_task_pipeline.sh scripts/check-task-loop.sh
"$PYTHON_BIN" -m py_compile scripts/task_loop_state.py scripts/task_loop_git.py

log "repo health"
bash scripts/check-skills.sh
"$PYTHON_BIN" tasks/prompts/_shared/prompt_pipeline.py doctor >/dev/null

log "real status is readable"
bash scripts/run_area_matrix_task_pipeline.sh --status > "$TMP_DIR/status.out"
grep -q 'stale_in_progress:' "$TMP_DIR/status.out" || fail "status output missing stale_in_progress"
grep -q 'drain_requested:' "$TMP_DIR/status.out" || fail "status output missing drain_requested"
./dev.sh status > "$TMP_DIR/dev-status.out"
grep -q 'AreaMatrix Task Loop 控制台' "$TMP_DIR/dev-status.out" || fail "dev status header missing"
grep -q '进程快照' "$TMP_DIR/dev-status.out" || fail "dev status process snapshot missing"

log "dev console dry-run foreground command choices"
mkdir -p "$TMP_DIR/dev-foreground"
run_with_temp_state dev-foreground \
  env DEV_SH_EXECUTION_MODE=foreground DEV_SH_GIT_CHECKPOINT=off DEV_SH_MAX_TASKS=1 DEV_SH_DRY_RUN=1 DEV_SH_DRY_RUN_RESULT=PASS \
  ./dev.sh start > "$TMP_DIR/dev-foreground/out.txt" 2>&1
grep -q 'GIT_CHECKPOINT=off' "$TMP_DIR/dev-foreground/out.txt" || fail "dev foreground did not apply git mode"
grep -q -- '--max-tasks 1' "$TMP_DIR/dev-foreground/out.txt" || fail "dev foreground did not apply max tasks"
assert_json_expr "$TMP_DIR/dev-foreground/progress.json" 'data["tasks"]["0-1/task-01"]["status"] == "completed"'

log "dev console dry-run background command choices"
mkdir -p "$TMP_DIR/dev-background"
run_with_temp_state dev-background \
  env DEV_SH_EXECUTION_MODE=background DEV_SH_GIT_CHECKPOINT=off DEV_SH_MAX_TASKS=1 DEV_SH_DRY_RUN=1 DEV_SH_DRY_RUN_RESULT=PASS DEV_SH_STOP_AFTER=0-1/task-01 \
  ./dev.sh start > "$TMP_DIR/dev-background/out.txt" 2>&1
grep -q '已后台启动：pid=' "$TMP_DIR/dev-background/out.txt" || fail "dev background did not start"
grep -q -- '--stop-after 0-1/task-01' "$TMP_DIR/dev-background/out.txt" || fail "dev background did not apply stop-after"
bg_pid="$(sed -n 's/已后台启动：pid=//p' "$TMP_DIR/dev-background/out.txt" | head -n 1)"
for _ in $(seq 1 30); do
  if [ -f "$TMP_DIR/dev-background/progress.json" ] && \
    "$PYTHON_BIN" - "$TMP_DIR/dev-background/progress.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(1)
entry = data.get("tasks", {}).get("0-1/task-01", {})
raise SystemExit(0 if entry.get("status") == "completed" else 1)
PY
  then
    break
  fi
  sleep 0.2
done
assert_json_expr "$TMP_DIR/dev-background/progress.json" 'data["tasks"]["0-1/task-01"]["status"] == "completed"'
find "$TMP_DIR/dev-background/console" -type f -name '*.log' | grep -q . || fail "dev background console log missing"

log "dev console blocks duplicate live runner"
mkdir -p "$TMP_DIR/dev-live/lock"
printf '%s\n' "$$" > "$TMP_DIR/dev-live/lock/pid"
printf '%s\n' "live-run" > "$TMP_DIR/dev-live/lock/run_id"
printf '%s\n' "run" > "$TMP_DIR/dev-live/lock/operation"
printf '%s\n' "now" > "$TMP_DIR/dev-live/lock/started_at"
if run_with_temp_state dev-live \
  env DEV_SH_EXECUTION_MODE=foreground DEV_SH_GIT_CHECKPOINT=off DEV_SH_MAX_TASKS=1 DEV_SH_DRY_RUN=1 \
  ./dev.sh start > "$TMP_DIR/dev-live/out.txt" 2>&1; then
  fail "dev console unexpectedly allowed duplicate live runner"
fi
grep -q '已有 live runner，已阻止启动第二个 runner' "$TMP_DIR/dev-live/out.txt" || fail "dev live guard message missing"

log "drain request requires a live runner"
mkdir -p "$TMP_DIR/drain-no-runner"
if run_with_temp_state drain-no-runner \
  bash scripts/run_area_matrix_task_pipeline.sh --request-drain > "$TMP_DIR/drain-no-runner/out.txt" 2>&1; then
  fail "drain request unexpectedly succeeded without a live runner"
fi
grep -q 'no live task loop lock found' "$TMP_DIR/drain-no-runner/out.txt" || fail "missing no-live-runner drain error"

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

log "drain request stops after current task"
drain_repo="$TMP_DIR/drain-repo"
mkdir -p "$drain_repo/tasks/prompts/_shared/copy-ready/phase-0"
mkdir -p "$drain_repo/tasks/prompts/_shared/verify-ready/phase-0"
for task in 01 02; do
  printf '# copy %s\n风险等级：`Medium`\n' "$task" > "$drain_repo/tasks/prompts/_shared/copy-ready/phase-0/0-1-task-${task}.md"
  printf '# verify %s\n' "$task" > "$drain_repo/tasks/prompts/_shared/verify-ready/phase-0/0-1-task-${task}.md"
done
mkdir -p "$TMP_DIR/drain/control" "$TMP_DIR/drain/lock"
printf '%s\n' "$$" > "$TMP_DIR/drain/lock/pid"
printf '%s\n' "drain-run" > "$TMP_DIR/drain/lock/run_id"
printf '%s\n' "run" > "$TMP_DIR/drain/lock/operation"
printf '%s\n' "now" > "$TMP_DIR/drain/lock/started_at"
RUN_ID=drain-request \
ROOT_DIR="$drain_repo" \
COPY_ROOT="$drain_repo/tasks/prompts/_shared/copy-ready" \
VERIFY_ROOT="$drain_repo/tasks/prompts/_shared/verify-ready" \
STATE_TOOL="$REPO_ROOT/scripts/task_loop_state.py" \
GIT_TOOL="$REPO_ROOT/scripts/task_loop_git.py" \
PROGRESS_FILE="$TMP_DIR/drain/progress.json" \
LOG_ROOT="$TMP_DIR/drain/logs" \
RUN_SUMMARY_ROOT="$TMP_DIR/drain/runs" \
PROGRESS_BACKUP_ROOT="$TMP_DIR/drain/backups" \
LOCK_DIR="$TMP_DIR/drain/lock" \
CONTROL_DIR="$TMP_DIR/drain/control" \
bash scripts/run_area_matrix_task_pipeline.sh --request-drain > "$TMP_DIR/drain/request.out"
grep -q 'request drain for live runner' "$TMP_DIR/drain/request.out" || fail "drain request did not target live runner"
rm -rf "$TMP_DIR/drain/lock"
RUN_ID=drain-run \
ROOT_DIR="$drain_repo" \
COPY_ROOT="$drain_repo/tasks/prompts/_shared/copy-ready" \
VERIFY_ROOT="$drain_repo/tasks/prompts/_shared/verify-ready" \
STATE_TOOL="$REPO_ROOT/scripts/task_loop_state.py" \
GIT_TOOL="$REPO_ROOT/scripts/task_loop_git.py" \
PROGRESS_FILE="$TMP_DIR/drain/progress.json" \
LOG_ROOT="$TMP_DIR/drain/logs" \
RUN_SUMMARY_ROOT="$TMP_DIR/drain/runs" \
PROGRESS_BACKUP_ROOT="$TMP_DIR/drain/backups" \
LOCK_DIR="$TMP_DIR/drain/lock" \
CONTROL_DIR="$TMP_DIR/drain/control" \
DRY_RUN=1 \
DRY_RUN_RESULT=PASS \
MAX_RETRIES=1 \
bash scripts/run_area_matrix_task_pipeline.sh --phase phase-0 > "$TMP_DIR/drain/run.out"
assert_json_expr "$TMP_DIR/drain/progress.json" 'data["tasks"]["0-1/task-01"]["status"] == "completed" and "0-1/task-02" not in data["tasks"]'
drain_summary="$TMP_DIR/drain/runs/drain-run/summary.json"
assert_json_expr "$drain_summary" 'data["status"] == "drained" and data["totals"]["completed_in_run"] == 1'
[ ! -f "$TMP_DIR/drain/control/drain.request" ] || fail "drain request file was not cleared"
grep -q 'drain requested; stop after completed task=0-1/task-01' "$TMP_DIR/drain/run.out" || fail "drain stop log missing"

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
assert_ignored ".codex/task-loop-control/drain.request"
assert_ignored ".codex/task-loop-tmp/foo"
assert_not_ignored "tasks/prompts/_shared/progress.json"
assert_not_ignored ".codex/task-loop-runs/index.json"
assert_not_ignored ".codex/task-loop-runs/example/summary.json"
assert_not_ignored ".codex/task-loop-progress-backups/progress-before-reset-example.json"
assert_not_ignored ".codex/task-loop-logs/example/phase-0/example.log"

log "OK"
