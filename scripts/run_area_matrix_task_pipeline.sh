#!/usr/bin/env bash

set -euo pipefail

# AreaMatrix task pipeline runner
#
# Flow:
# 1. Execute copy-ready prompt (implementation).
# 2. Execute verify-ready prompt (read-only verification).
# 3. If verification fails, repeat the same task.
# 4. Only move forward after verification pass.
# 5. Record timestamped logs and progress for easy monitoring.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-"$(cd "$SCRIPT_DIR/.." && pwd)"}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
STATE_TOOL="${STATE_TOOL:-$ROOT_DIR/scripts/task_loop_state.py}"

MODEL="${MODEL:-gpt-5.5}"
MODEL_REASONING_EFFORT="${MODEL_REASONING_EFFORT:-xhigh}"
CODEX_BIN="${CODEX_BIN:-}"
CODEX_BIN_RESOLVED=""

COPY_ROOT="${COPY_ROOT:-$ROOT_DIR/tasks/prompts/_shared/copy-ready}"
VERIFY_ROOT="${VERIFY_ROOT:-$ROOT_DIR/tasks/prompts/_shared/verify-ready}"
PROGRESS_FILE="${PROGRESS_FILE:-$ROOT_DIR/tasks/prompts/_shared/progress.json}"

# 兼容旧版本脚本的纯文本完成记录；新进度统一写入 PROGRESS_FILE。
STATE_FILE="${STATE_FILE:-$ROOT_DIR/.codex/task-loop-state.txt}"
LOG_ROOT="${LOG_ROOT:-$ROOT_DIR/.codex/task-loop-logs}"
RUN_SUMMARY_ROOT="${RUN_SUMMARY_ROOT:-$ROOT_DIR/.codex/task-loop-runs}"
PROGRESS_BACKUP_ROOT="${PROGRESS_BACKUP_ROOT:-$ROOT_DIR/.codex/task-loop-progress-backups}"
LOCK_DIR="${LOCK_DIR:-$ROOT_DIR/.codex/task-loop-lock}"

# 0 表示无限重试.
MAX_RETRIES="${MAX_RETRIES:-0}"
# 0 表示不限制任务数.
MAX_TASKS="${MAX_TASKS:-0}"

# 可选从某个 task 开始，例如 phase-1/1-1-task-01.
START_FROM="${START_FROM:-}"

# 风险门禁：默认只拦截 Mission-Critical。可设为 high / mission-critical / none。
RISK_GATE="${RISK_GATE:-mission-critical}"
# 风险策略：pause / skip / allow。
RISK_POLICY="${RISK_POLICY:-pause}"

# 仅运行指定 phase，例如 --phase phase-1.
TARGET_PHASES=()

PHASES=(phase-0 phase-1 phase-2 phase-3 phase-4)

TOTAL_TASKS=0
DONE_TASKS=0
RETRY_TOTAL=0

FAILURE_CONTEXT_LINES="${FAILURE_CONTEXT_LINES:-200}"
DRY_RUN="${DRY_RUN:-0}"
DRY_RUN_COPY_PREVIEW_LINES="${DRY_RUN_COPY_PREVIEW_LINES:-80}"
DRY_RUN_VERIFY_PREVIEW_LINES="${DRY_RUN_VERIFY_PREVIEW_LINES:-40}"
DRY_RUN_RESULT="${DRY_RUN_RESULT:-PASS}"
DRY_RUN_MAX_ATTEMPTS="${DRY_RUN_MAX_ATTEMPTS:-10}"

STATUS_ONLY=0
RESUME_FAILED=0
RESUME_STALE=0
CLEAR_STALE=0
RESET_PROGRESS=0

RUN_ID=""
SESSION_LOG_ROOT=""
RUN_SUMMARY_FILE=""
LOCK_ACQUIRED=0
ORIGINAL_COMMAND=""

timestamp() {
  date '+%F %T'
}

log_event() {
  local level="$1"
  shift
  local msg="$*"
  echo "[ $(timestamp) ] [$level] $msg"
}

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/run_area_matrix_task_pipeline.sh [options]

Options:
  --dry-run                 仅模拟执行，不调用 codex（默认 0）
  --clear-stale             清理无活进程且未完成的 in_progress 记录
  --help, -h                输出帮助
  --resume-failed           从 progress.json 中第一个 failed task 恢复
  --resume-stale            从 progress.json 中第一个 stale in_progress task 恢复
  --reset-progress          备份并清空 progress.json，从 0 开始
  --risk-gate <level>       风险门禁范围：mission-critical/high/none
  --risk-policy <policy>    风险命中策略：pause/skip/allow
  --start-from <label>      从某个 task 开始，例如 phase-1/1-1-task-01
  --status                  输出任务循环状态，不执行任务
  --max-tasks <n>           最多执行 n 个 task（0 表示不限制）
  --phase <phase>           仅运行指定 phase，可重复使用；默认 phase-0..phase-4

Env vars:
  MODEL:                     默认 gpt-5.5
  MODEL_REASONING_EFFORT:    默认 xhigh
  CODEX_BIN:                 Codex CLI 路径；默认自动查找 codex 或 Codex.app 内置 CLI
  RISK_GATE:                 mission-critical/high/none，默认 mission-critical
  RISK_POLICY:               pause/skip/allow，默认 pause
  MAX_RETRIES:               0 表示无限重试，默认 0
  MAX_TASKS:                 0 表示不限制，默认 0
  START_FROM:                e.g. phase-1/1-1-task-01 或 1-1/task-01
  DRY_RUN:                   1/0，默认 0
  DRY_RUN_RESULT:            PASS/FAIL，用于 dry-run 的验收结果（默认 PASS）
  DRY_RUN_MAX_ATTEMPTS:      dry-run 下失败时最多重试次数（默认 10）
  DRY_RUN_COPY_PREVIEW_LINES: dry-run 时预览 copy prompt 行数
  DRY_RUN_VERIFY_PREVIEW_LINES: dry-run 时预览 verify prompt 行数
  FAILURE_CONTEXT_LINES:      提取 verify 反馈行数（默认 200）
  PYTHON_BIN:                Python 解释器，默认 python3
  STATE_TOOL:                task-loop state helper，默认 scripts/task_loop_state.py
  LOG_ROOT:                  日志根目录
  RUN_SUMMARY_ROOT:           运行摘要目录，默认 .codex/task-loop-runs
  PROGRESS_BACKUP_ROOT:       progress 备份目录，默认 .codex/task-loop-progress-backups
  LOCK_DIR:                  运行锁目录，默认 .codex/task-loop-lock
  PROGRESS_FILE:             统一进度文件，默认 tasks/prompts/_shared/progress.json
  STATE_FILE:                旧版完成记录文件，仅兼容读取

When RISK_POLICY=allow:
  - 脚本会向 copy prompt 注入用户已授权静默执行的上下文。
  - High/Mission-Critical task 仍需记录风险、验证与回滚，但不再停下来等人工确认。
USAGE
}

ensure_run_id() {
  if [ -z "$RUN_ID" ]; then
    local base_run_id
    base_run_id="$(date '+%Y%m%d_%H%M%S')"
    RUN_ID="$base_run_id"
    if [ -e "$LOG_ROOT/$RUN_ID" ] || [ -e "$RUN_SUMMARY_ROOT/$RUN_ID" ]; then
      RUN_ID="${base_run_id}_$$"
    fi
  fi
}

default_progress_file() {
  printf '%s\n' "$ROOT_DIR/tasks/prompts/_shared/progress.json"
}

state_tool() {
  "$PYTHON_BIN" "$STATE_TOOL" "$@"
}

should_write_progress() {
  if [ "$DRY_RUN" != "1" ]; then
    return 0
  fi

  # Dry-run must not mutate the real queue by accident. Tests can still pass a
  # temporary PROGRESS_FILE to validate the progress writer end to end.
  [ "$PROGRESS_FILE" != "$(default_progress_file)" ]
}

init_run_paths() {
  ensure_run_id
  mkdir -p "$(dirname "$PROGRESS_FILE")"
  mkdir -p "$LOG_ROOT"
  mkdir -p "$RUN_SUMMARY_ROOT"
  SESSION_LOG_ROOT="$LOG_ROOT/$RUN_ID"
  RUN_SUMMARY_FILE="$RUN_SUMMARY_ROOT/$RUN_ID/summary.json"
  mkdir -p "$SESSION_LOG_ROOT"
  mkdir -p "$(dirname "$RUN_SUMMARY_FILE")"
}

is_pid_alive() {
  local pid="$1"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

lock_pid() {
  if [ -f "$LOCK_DIR/pid" ]; then
    tr -d '[:space:]' < "$LOCK_DIR/pid"
  fi
}

acquire_lock() {
  local operation="$1"
  ensure_run_id
  mkdir -p "$(dirname "$LOCK_DIR")"

  if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_ACQUIRED=1
  else
    local pid
    pid="$(lock_pid)"
    if is_pid_alive "$pid"; then
      log_event ERROR "task loop lock is held by live pid=$pid"
      log_event ERROR "lock_dir=$LOCK_DIR"
      return 9
    fi
    log_event WARN "removing stale task loop lock: $LOCK_DIR"
    rm -rf "$LOCK_DIR"
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
      log_event ERROR "failed to acquire task loop lock: $LOCK_DIR"
      return 9
    fi
    LOCK_ACQUIRED=1
  fi

  printf '%s\n' "$$" > "$LOCK_DIR/pid"
  printf '%s\n' "$RUN_ID" > "$LOCK_DIR/run_id"
  printf '%s\n' "$operation" > "$LOCK_DIR/operation"
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$LOCK_DIR/started_at"
  printf '%s\n' "${ORIGINAL_COMMAND:-$0}" > "$LOCK_DIR/command"
}

release_lock() {
  if [ "$LOCK_ACQUIRED" != "1" ]; then
    return 0
  fi

  local pid
  pid="$(lock_pid)"
  if [ "$pid" = "$$" ]; then
    rm -rf "$LOCK_DIR"
  fi
  LOCK_ACQUIRED=0
}

reset_progress() {
  local output
  output="$(state_tool reset-progress --progress-file "$PROGRESS_FILE" --backup-root "$PROGRESS_BACKUP_ROOT")"
  while IFS= read -r line; do
    [ -n "$line" ] && log_event INFO "$line"
  done <<< "$output"
}

first_stale_task() {
  state_tool first-stale --progress-file "$PROGRESS_FILE" --lock-dir "$LOCK_DIR"
}

clear_stale_tasks() {
  local output
  output="$(state_tool clear-stale --progress-file "$PROGRESS_FILE" --lock-dir "$LOCK_DIR" --backup-root "$PROGRESS_BACKUP_ROOT")"
  while IFS= read -r line; do
    [ -n "$line" ] && log_event INFO "$line"
  done <<< "$output"
}

init_run_summary() {
  if [ -z "$RUN_SUMMARY_FILE" ]; then
    return 0
  fi

  local dry_run_flag=()
  if [ "$DRY_RUN" = "1" ]; then
    dry_run_flag=(--dry-run)
  fi

  state_tool init-summary \
    --summary-file "$RUN_SUMMARY_FILE" \
    --run-id "$RUN_ID" \
    --root-dir "$ROOT_DIR" \
    --model "$MODEL" \
    --model-reasoning-effort "$MODEL_REASONING_EFFORT" \
    "${dry_run_flag[@]}" \
    --codex-bin "$CODEX_BIN_RESOLVED" \
    --risk-gate "$RISK_GATE" \
    --risk-policy "$RISK_POLICY" \
    --max-retries "$MAX_RETRIES" \
    --max-tasks "$MAX_TASKS" \
    --start-from "$START_FROM" \
    --progress-file "$PROGRESS_FILE" \
    --log-root "$SESSION_LOG_ROOT" \
    --copy-root "$COPY_ROOT" \
    --verify-root "$VERIFY_ROOT" \
    --phases "${target_phases[*]}" \
    --total-tasks "$TOTAL_TASKS"
}

record_task_summary() {
  local label="$1"
  local phase="$2"
  local task_name="$3"
  local status="$4"
  local attempt="$5"
  local risk="$6"
  local copy_log="$7"
  local verify_log="$8"
  local note="$9"

  if [ -z "$RUN_SUMMARY_FILE" ]; then
    return 0
  fi

  state_tool record-summary \
    --summary-file "$RUN_SUMMARY_FILE" \
    --label "$label" \
    --phase "$phase" \
    --task-name "$task_name" \
    --status "$status" \
    --attempts "$attempt" \
    --risk "$risk" \
    --copy-log "$copy_log" \
    --verify-log "$verify_log" \
    --note "$note" \
    --completed "$DONE_TASKS" \
    --retries "$RETRY_TOTAL"
}

finalize_run_summary() {
  local status="$1"
  local exit_code="$2"
  local note="${3:-}"

  if [ -z "$RUN_SUMMARY_FILE" ] || [ ! -f "$RUN_SUMMARY_FILE" ]; then
    return 0
  fi

  state_tool finalize-summary \
    --summary-file "$RUN_SUMMARY_FILE" \
    --run-summary-root "$RUN_SUMMARY_ROOT" \
    --status "$status" \
    --exit-code "$exit_code" \
    --note "$note" \
    --completed "$DONE_TASKS" \
    --retries "$RETRY_TOTAL"
}

cleanup() {
  local exit_code=$?
  if [ -n "$RUN_SUMMARY_FILE" ] && [ -f "$RUN_SUMMARY_FILE" ]; then
    if [ "$exit_code" -eq 0 ]; then
      finalize_run_summary "completed" "$exit_code"
    else
      finalize_run_summary "failed" "$exit_code"
    fi
  fi
  release_lock
}

trap cleanup EXIT

task_name_to_label() {
  local task_name="$1"
  local batch="${task_name%-task-*}"
  local number="${task_name##*-task-}"
  echo "$batch/task-$number"
}

label_to_task_ref() {
  local label="$1"
  local batch="${label%/task-*}"
  local number="${label##*/task-}"
  local phase_number="${batch%%-*}"
  echo "phase-$phase_number/$batch-task-$number"
}

normalize_task_ref() {
  local value="$1"
  case "$value" in
    phase-[0-9]/*-task-[0-9]*)
      task_name_to_label "${value#*/}"
      ;;
    [0-9]*-[0-9]*/task-[0-9]*)
      echo "$value"
      ;;
    [0-9]*-[0-9]*-task-[0-9]*)
      task_name_to_label "$value"
      ;;
    *)
      echo "$value"
      ;;
  esac
}

validate_runtime_options() {
  case "$RISK_GATE" in
    high|mission-critical|none)
      ;;
    *)
      log_event ERROR "RISK_GATE must be high, mission-critical, or none"
      return 1
      ;;
  esac

  case "$RISK_POLICY" in
    pause|skip|allow)
      ;;
    *)
      log_event ERROR "RISK_POLICY must be pause, skip, or allow"
      return 1
      ;;
  esac
}

validate_state_tool() {
  if [ ! -f "$STATE_TOOL" ]; then
    log_event ERROR "STATE_TOOL not found: $STATE_TOOL"
    return 1
  fi
  if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    log_event ERROR "PYTHON_BIN not found: $PYTHON_BIN"
    return 1
  fi
}

resolve_codex_bin() {
  if [ -n "$CODEX_BIN" ]; then
    if [ -x "$CODEX_BIN" ]; then
      CODEX_BIN_RESOLVED="$CODEX_BIN"
      return 0
    fi
    log_event ERROR "CODEX_BIN is not executable: $CODEX_BIN"
    return 1
  fi

  if command -v codex >/dev/null 2>&1; then
    CODEX_BIN_RESOLVED="$(command -v codex)"
    return 0
  fi

  if [ -x "/Applications/Codex.app/Contents/Resources/codex" ]; then
    CODEX_BIN_RESOLVED="/Applications/Codex.app/Contents/Resources/codex"
    return 0
  fi

  log_event ERROR "Codex CLI not found. Install it, add it to PATH, or set CODEX_BIN=/path/to/codex."
  return 1
}

task_risk() {
  local prompt_file="$1"
  local risk
  risk="$(sed -n 's/.*风险等级：`\(.*\)`.*/\1/p' "$prompt_file" | head -n 1)"
  if [ -n "$risk" ]; then
    echo "$risk"
  else
    echo "Unspecified"
  fi
}

risk_matches_gate() {
  local risk="$1"
  case "$RISK_GATE" in
    none)
      return 1
      ;;
    mission-critical)
      [ "$risk" = "Mission-Critical" ]
      ;;
    high)
      [ "$risk" = "High" ] || [ "$risk" = "Mission-Critical" ]
      ;;
  esac
}

progress_task_status() {
  local label="$1"
  state_tool task-status --progress-file "$PROGRESS_FILE" --label "$label"
}

mark_task_progress() {
  local label="$1"
  local status="$2"
  local note="$3"
  local copy_log="${4:-}"
  local verify_log="${5:-}"
  local attempts="${6:-0}"
  local risk="${7:-}"

  if ! should_write_progress; then
    return 0
  fi

  state_tool mark-progress \
    --progress-file "$PROGRESS_FILE" \
    --label "$label" \
    --status "$status" \
    --note "$note" \
    --copy-log "$copy_log" \
    --verify-log "$verify_log" \
    --attempts "$attempts" \
    --risk "$risk" \
    --run-id "$RUN_ID"
}

first_failed_task() {
  state_tool first-failed --progress-file "$PROGRESS_FILE"
}

print_loop_status() {
  echo "Task loop status"
  echo "- progress_file: $PROGRESS_FILE"
  echo "- legacy_state_file: $STATE_FILE"
  if [ -f "$STATE_FILE" ]; then
    echo "- legacy_completed_count: $(wc -l < "$STATE_FILE" | tr -d '[:space:]')"
  else
    echo "- legacy_completed_count: 0"
  fi

  state_tool status-fragment --progress-file "$PROGRESS_FILE" --lock-dir "$LOCK_DIR" --log-root "$LOG_ROOT"

  echo
  "$PYTHON_BIN" "$ROOT_DIR/tasks/prompts/_shared/prompt_pipeline.py" status || true
}

handle_risk_gate() {
  local label="$1"
  local risk="$2"
  local copy_log="$3"
  local verify_log="$4"

  if ! risk_matches_gate "$risk"; then
    return 0
  fi

  case "$RISK_POLICY" in
    allow)
      log_event RISK "$label risk=$risk allowed by RISK_POLICY=allow"
      return 0
      ;;
    skip)
      log_event RISK "$label risk=$risk skipped by RISK_POLICY=skip"
      mark_task_progress "$label" "blocked" "风险门禁跳过：risk=$risk gate=$RISK_GATE policy=skip" "$copy_log" "$verify_log" 0 "$risk"
      return 2
      ;;
    pause)
      log_event RISK "$label risk=$risk paused by RISK_POLICY=pause"
      mark_task_progress "$label" "blocked" "风险门禁暂停：risk=$risk gate=$RISK_GATE policy=pause；确认后可用 RISK_POLICY=allow 继续" "$copy_log" "$verify_log" 0 "$risk"
      return 3
      ;;
  esac
}

show_dry_run_stub() {
  local sandbox="$1"
  local output_file="$2"
  local prompt_file="$3"
  local extra_prompt="$4"
  local preview_lines="$5"

  {
    echo "DRY RUN OUTPUT (command not executed)"
    echo "label: $label"
    echo "phase: $phase"
    echo "sandbox: $sandbox"
    echo "model: $MODEL"
    echo "reasoning_effort: $MODEL_REASONING_EFFORT"
    echo "prompt_file: $prompt_file"
    if [ -n "$attempt" ]; then
      echo "attempt: $attempt"
    fi
    echo
    if [ -n "$extra_prompt" ]; then
      echo "--- injected_retry_prompt ---"
      echo "$extra_prompt"
      echo
    fi
    echo "--- prompt_head (${preview_lines} lines) ---"
    sed -n "1,${preview_lines}p" "$prompt_file"
    if [ "$sandbox" = "read-only" ]; then
      echo
      echo "VERIFY_RESULT: ${DRY_RUN_RESULT}"
    fi
  } > "$output_file"
}

is_task_done() {
  local label="$1"
  local status
  status="$(progress_task_status "$label")"
  if [ "$status" = "completed" ]; then
    return 0
  fi

  if [ -f "$STATE_FILE" ]; then
    local task_ref
    task_ref="$(label_to_task_ref "$label")"
    grep -qxF "$label" "$STATE_FILE" || grep -qxF "$task_ref" "$STATE_FILE"
    return
  fi

  return 1
}

count_done_tasks() {
  state_tool count-completed --progress-file "$PROGRESS_FILE"
}

bootstrap_counts() {
  TOTAL_TASKS=0
  for phase in "${target_phases[@]}"; do
    local copy_phase_dir="$COPY_ROOT/$phase"
    local verify_phase_dir="$VERIFY_ROOT/$phase"
    if [ ! -d "$copy_phase_dir" ] || [ ! -d "$verify_phase_dir" ]; then
      continue
    fi
    while IFS= read -r copy_file; do
      [ -e "$copy_file" ] || continue
      task_name="$(basename "$copy_file" .md)"
      verify_file="$verify_phase_dir/$task_name.md"
      if [ -f "$verify_file" ]; then
        TOTAL_TASKS=$((TOTAL_TASKS + 1))
      fi
    done < <(printf '%s\n' "$copy_phase_dir"/*.md 2>/dev/null | sort -V)
  done

  if [ "$MAX_TASKS" -gt 0 ] && [ "$MAX_TASKS" -lt "$TOTAL_TASKS" ]; then
    TOTAL_TASKS="$MAX_TASKS"
  fi
}

print_launch_header() {
  log_event INFO "AreaMatrix task loop start"
  log_event INFO "MODEL=$MODEL MODEL_REASONING_EFFORT=$MODEL_REASONING_EFFORT"
  if [ -n "$CODEX_BIN_RESOLVED" ]; then
    log_event INFO "CODEX_BIN=$CODEX_BIN_RESOLVED"
  fi
  log_event INFO "DRY_RUN=$DRY_RUN"
  if [ "$DRY_RUN" = "1" ]; then
    log_event INFO "DRY_RUN_RESULT=$DRY_RUN_RESULT"
  fi
  log_event INFO "ROOT_DIR=$ROOT_DIR"
  log_event INFO "COPY_ROOT=$COPY_ROOT"
  log_event INFO "VERIFY_ROOT=$VERIFY_ROOT"
  log_event INFO "PROGRESS_FILE=$PROGRESS_FILE"
  log_event INFO "LEGACY_STATE_FILE=$STATE_FILE"
  log_event INFO "LOG_ROOT=$SESSION_LOG_ROOT"
  log_event INFO "RUN_SUMMARY_FILE=$RUN_SUMMARY_FILE"
  log_event INFO "LOCK_DIR=$LOCK_DIR"
  log_event INFO "RISK_GATE=$RISK_GATE RISK_POLICY=$RISK_POLICY"
  log_event INFO "PHASES=${target_phases[*]}"
  log_event INFO "TOTAL_TASKS=$TOTAL_TASKS"
  if [ -n "$START_FROM" ]; then
    log_event INFO "START_FROM=$START_FROM"
  fi
  if [ "$MAX_TASKS" -gt 0 ]; then
    log_event INFO "MAX_TASKS=$MAX_TASKS"
  fi
}

print_task_progress() {
  local status="$1"
  local task="$2"
  local attempt="$3"
  local copy_log="$4"
  local verify_log="$5"

  local remain_count=$((TOTAL_TASKS - DONE_TASKS))
  local percent=0
  if [ "$TOTAL_TASKS" -gt 0 ]; then
    percent=$((DONE_TASKS * 100 / TOTAL_TASKS))
  fi

  log_event "$status" "task=$task attempt=$attempt"
  log_event "$status" "done=$DONE_TASKS total=$TOTAL_TASKS remain=$remain_count complete=$percent%"
  log_event "$status" "copy_log=$copy_log"
  log_event "$status" "verify_log=$verify_log"
}

run_codex() {
  local prompt_file="$1"
  local output_file="$2"
  local sandbox="$3"
  local extra_prompt="$4"
  local preview_lines="$DRY_RUN_COPY_PREVIEW_LINES"

  mkdir -p "$(dirname "$output_file")"

  if [ "$sandbox" = "read-only" ]; then
    preview_lines="$DRY_RUN_VERIFY_PREVIEW_LINES"
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log_event DRY "simulating codex exec for $prompt_file -> $output_file"
    show_dry_run_stub "$sandbox" "$output_file" "$prompt_file" "$extra_prompt" "$preview_lines"
    return 0
  fi

  mkdir -p "$(dirname "$output_file")"
  if [ -n "$extra_prompt" ]; then
    {
      cat "$prompt_file"
      printf '\n\n%s\n' "$extra_prompt"
    } | "$CODEX_BIN_RESOLVED" exec \
      -m "$MODEL" \
      -c "model_reasoning_effort=$MODEL_REASONING_EFFORT" \
      --full-auto \
      -s "$sandbox" \
      --cd "$ROOT_DIR" \
      -o "$output_file" \
      -
  else
    cat "$prompt_file" | "$CODEX_BIN_RESOLVED" exec \
      -m "$MODEL" \
      -c "model_reasoning_effort=$MODEL_REASONING_EFFORT" \
      --full-auto \
      -s "$sandbox" \
      --cd "$ROOT_DIR" \
      -o "$output_file" \
      -
  fi
}

is_verify_pass() {
  local file="$1"
  grep -qE '^[[:space:]]*VERIFY_RESULT:[[:space:]]*PASS[[:space:]]*$' "$file"
}

extract_verify_feedback() {
  local file="$1"
  local feedback

  feedback="$(tail -n "$FAILURE_CONTEXT_LINES" "$file" 2>/dev/null | sed '/^[[:space:]]*VERIFY_RESULT:/d' | sed '/^[[:space:]]*$/d')"
  if [ -z "$feedback" ]; then
    echo "验收未通过，但 verify 日志未给出明确失败细节。请严格对照该任务 copy-ready 与 verify-ready 的要求重新实现并重试。"
    return
  fi

  echo "$feedback"
}

build_copy_retry_prompt() {
  local label="$1"
  local task_name="$2"
  local attempt="$3"
  local verify_log="$4"
  local feedback
  feedback="$(extract_verify_feedback "$verify_log")"

  cat <<EOF
你正在对同一个任务进行 repair retry（修复重试，第 ${attempt} 次尝试）。任务标签：${label}（文件：${task_name}.md）。
本次重试只允许修复上一次验收失败问题，不要改写任务目标外的范围。
本次重试必须同时修复功能失败、验收证据失败和工程质量失败；重新读取工程质量规则与编码规范。
以下是上一次验收日志里的失败摘要（请直接按这些问题“全部全面修复”）：

${feedback}

修复完成后，重新完整执行本任务实现，再进入该任务验收。
EOF
}

build_silent_approval_prompt() {
  local label="$1"
  local risk="$2"

  if [ "$RISK_POLICY" != "allow" ]; then
    return 0
  fi

  cat <<EOF
自动执行授权上下文：
- 用户已明确授权 AreaMatrix task loop 静默执行当前任务，当前任务标签：${label}，风险等级：${risk}。
- 对 High / Mission-Critical task，仍需在日志中说明影响、风险、验证和回滚，但不要停下来等待人工确认。
- 允许在仓库内修改、创建和运行当前 task 完成所需的文件与验证命令。
- 若验收失败指出 task 直接相关的 Exact Docs、Core API、UDL、manifest 或 README 存在源事实漂移，可在不实现相邻能力、不触碰 Forbidden Touches 的前提下同步修复，并在报告中列出。
- 本授权不允许删除、移动、覆盖真实用户原文件；命中用户文件破坏性操作时仍必须停止并报告。
EOF
}

build_copy_context_prompt() {
  local label="$1"
  local task_name="$2"
  local attempt="$3"
  local risk="$4"
  local verify_log="${5:-}"
  local approval_prompt
  local retry_prompt

  approval_prompt="$(build_silent_approval_prompt "$label" "$risk")"
  if [ "$attempt" -gt 1 ] && [ -n "$verify_log" ]; then
    retry_prompt="$(build_copy_retry_prompt "$label" "$task_name" "$attempt" "$verify_log")"
  else
    retry_prompt=""
  fi

  if [ -n "$approval_prompt" ] && [ -n "$retry_prompt" ]; then
    printf '%s\n\n%s\n' "$approval_prompt" "$retry_prompt"
  elif [ -n "$approval_prompt" ]; then
    printf '%s\n' "$approval_prompt"
  elif [ -n "$retry_prompt" ]; then
    printf '%s\n' "$retry_prompt"
  fi
}

build_phase_filter() {
  if [ "${#TARGET_PHASES[@]}" -eq 0 ]; then
    target_phases=("${PHASES[@]}")
  else
    target_phases=()
    for phase in "${TARGET_PHASES[@]}"; do
      case "$phase" in
        phase-0|phase-1|phase-2|phase-3|phase-4)
          target_phases+=("$phase")
          ;;
        *)
          log_event ERROR "invalid phase: $phase"
          log_event ERROR "only phase-0/1/2/3/4 are supported"
          exit 1
          ;;
      esac
    done
  fi
}

main() {
  ORIGINAL_COMMAND="$0 $*"

  if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    return 0
  fi

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --clear-stale)
        CLEAR_STALE=1
        shift
        ;;
      --resume-failed)
        RESUME_FAILED=1
        shift
        ;;
      --resume-stale)
        RESUME_STALE=1
        shift
        ;;
      --reset-progress)
        RESET_PROGRESS=1
        shift
        ;;
      --risk-gate)
        if [ "$#" -lt 2 ]; then
          log_event ERROR "--risk-gate requires <level>"
          return 1
        fi
        RISK_GATE="$2"
        shift 2
        ;;
      --risk-policy)
        if [ "$#" -lt 2 ]; then
          log_event ERROR "--risk-policy requires <policy>"
          return 1
        fi
        RISK_POLICY="$2"
        shift 2
        ;;
      --start-from)
        if [ "$#" -lt 2 ]; then
          log_event ERROR "--start-from requires <label>"
          return 1
        fi
        START_FROM="$(normalize_task_ref "$2")"
        shift 2
        ;;
      --status)
        STATUS_ONLY=1
        shift
        ;;
      --max-tasks)
        if [ "$#" -lt 2 ] || ! printf '%s' "$2" | grep -Eq '^[0-9]+$'; then
          log_event ERROR "--max-tasks requires non-negative integer"
          return 1
        fi
        MAX_TASKS="$2"
        shift 2
        ;;
      --phase)
        if [ "$#" -lt 2 ]; then
          log_event ERROR "--phase requires <phase>"
          return 1
        fi
        TARGET_PHASES+=("$2")
        shift 2
        ;;
      --help|-h)
        usage
        return 0
        ;;
      --*)
        log_event ERROR "unknown option: $1"
        usage
        return 1
        ;;
      *)
        log_event ERROR "unexpected positional arg: $1"
        usage
        return 1
        ;;
    esac
  done

  if [ "$DRY_RUN" = "1" ]; then
    log_event INFO "DRY RUN mode enabled"
    if [ "$DRY_RUN_RESULT" != "PASS" ] && [ "$DRY_RUN_RESULT" != "FAIL" ]; then
      log_event ERROR "DRY_RUN_RESULT must be PASS or FAIL"
      return 1
    fi
  fi

  if [ -n "$START_FROM" ]; then
    START_FROM="$(normalize_task_ref "$START_FROM")"
  fi

  validate_runtime_options || return 1
  validate_state_tool || return 1

  if [ "$STATUS_ONLY" = "1" ]; then
    print_loop_status
    return 0
  fi

  if [ "$RESET_PROGRESS" = "1" ]; then
    ensure_run_id
    acquire_lock "reset-progress" || return 1
    reset_progress
    return 0
  fi

  if [ "$CLEAR_STALE" = "1" ]; then
    ensure_run_id
    acquire_lock "clear-stale" || return 1
    clear_stale_tasks
    return 0
  fi

  ensure_run_id
  acquire_lock "run" || return 1

  if [ "$DRY_RUN" != "1" ]; then
    resolve_codex_bin || return 1
  fi

  if [ "$RESUME_FAILED" = "1" ]; then
    failed_label="$(first_failed_task)"
    if [ -z "$failed_label" ]; then
      log_event ERROR "no failed task found in $PROGRESS_FILE"
      return 1
    fi
    START_FROM="$failed_label"
    log_event INFO "resume failed task: $START_FROM"
  fi

  if [ "$RESUME_STALE" = "1" ]; then
    stale_label="$(first_stale_task)"
    if [ -z "$stale_label" ]; then
      log_event ERROR "no stale in_progress task found in $PROGRESS_FILE"
      return 1
    fi
    START_FROM="$stale_label"
    log_event INFO "resume stale task: $START_FROM"
  fi

  init_run_paths
  build_phase_filter
  bootstrap_counts
  init_run_summary
  print_launch_header

  if [ -n "$START_FROM" ]; then
    should_start=0
  else
    should_start=1
  fi

  for phase in "${target_phases[@]}"; do
    copy_phase_dir="$COPY_ROOT/$phase"
    verify_phase_dir="$VERIFY_ROOT/$phase"

    if [ ! -d "$copy_phase_dir" ]; then
      log_event WARN "copy phase missing: $copy_phase_dir"
      continue
    fi

    if [ ! -d "$verify_phase_dir" ]; then
      log_event WARN "verify phase missing: $verify_phase_dir"
      continue
    fi

    task_files=()
    while IFS= read -r copy_file; do
      task_files+=("$copy_file")
    done < <(printf '%s\n' "$copy_phase_dir"/*.md 2>/dev/null | sort -V)

    for copy_file in "${task_files[@]}"; do
      [ -e "$copy_file" ] || continue

      task_name="$(basename "$copy_file" .md)"
      label="$(task_name_to_label "$task_name")"
      task_ref="$phase/$task_name"
      verify_file="$verify_phase_dir/$task_name.md"
      risk="$(task_risk "$copy_file")"

      if [ ! -f "$verify_file" ]; then
        log_event ERROR "verify prompt missing for $task_ref"
        log_event ERROR "Path: $verify_file"
        exit 1
      fi

      if [ "$should_start" -eq 0 ]; then
        if [ "$label" = "$START_FROM" ]; then
          should_start=1
        else
          continue
        fi
      fi

      if is_task_done "$label"; then
        log_event SKIP "$label already completed"
        continue
      fi

      if [ "$MAX_TASKS" -gt 0 ] && [ "$DONE_TASKS" -ge "$MAX_TASKS" ]; then
        log_event INFO "reach max tasks cap: $MAX_TASKS"
        log_event INFO "stop execution"
        echo
        log_event INFO "Done tasks done. completed=$DONE_TASKS total=$TOTAL_TASKS retries=$RETRY_TOTAL"
        return 0
      fi

      if handle_risk_gate "$label" "$risk" "" ""; then
        :
      else
        gate_result=$?
        if [ "$gate_result" -eq 2 ]; then
          record_task_summary "$label" "$phase" "$task_name" "blocked" "0" "$risk" "" "" "风险门禁跳过"
          continue
        fi
        record_task_summary "$label" "$phase" "$task_name" "blocked" "0" "$risk" "" "" "风险门禁暂停"
        exit 2
      fi

      attempt=0
      while true; do
        attempt=$((attempt + 1))
        copy_log="$SESSION_LOG_ROOT/$phase/${task_name}-copy-attempt-${attempt}.log"
        verify_log="$SESSION_LOG_ROOT/$phase/${task_name}-verify-attempt-${attempt}.log"

        if [ "$attempt" -gt 1 ]; then
          log_event REPAIR "repair retry $label attempt=$attempt"
          progress_note="修复重试中：attempt=$attempt risk=$risk"
        else
          log_event TASK "start $label"
          progress_note="执行中：attempt=$attempt risk=$risk"
        fi
        log_event TASK "copy prompt -> $copy_log"
        mark_task_progress "$label" "in_progress" "$progress_note" "$copy_log" "$verify_log" "$attempt" "$risk"
        record_task_summary "$label" "$phase" "$task_name" "in_progress" "$attempt" "$risk" "$copy_log" "$verify_log" "$progress_note"

        previous_verify_log=""
        if [ "$attempt" -gt 1 ]; then
          previous_verify_log="$SESSION_LOG_ROOT/$phase/${task_name}-verify-attempt-$((attempt - 1)).log"
        fi
        copy_context_prompt="$(build_copy_context_prompt "$label" "$task_name" "$attempt" "$risk" "$previous_verify_log")"
        run_codex "$copy_file" "$copy_log" "workspace-write" "$copy_context_prompt"

        log_event TASK "verify prompt -> $verify_log"
        verify_suffix="自动任务循环输出要求：
- 保留简明验收报告，尤其是不通过时的失败摘要、阻塞项、文件路径和验证缺口。
- 工程质量不达标时必须写清楚质量阻塞点，供下一轮“全部全面修复”使用。
- 最后一行必须单独输出 VERIFY_RESULT: PASS 或 VERIFY_RESULT: FAIL。
- 不要在最后一行之后输出任何内容。"
        run_codex "$verify_file" "$verify_log" "read-only" "$verify_suffix"

        if is_verify_pass "$verify_log"; then
          mark_task_progress "$label" "completed" "自动执行验收通过：attempt=$attempt" "$copy_log" "$verify_log" "$attempt" "$risk"
          DONE_TASKS=$((DONE_TASKS + 1))
          record_task_summary "$label" "$phase" "$task_name" "completed" "$attempt" "$risk" "$copy_log" "$verify_log" "自动执行验收通过"
          print_task_progress "PASS" "$label" "$attempt" "$copy_log" "$verify_log"
          break
        fi

        RETRY_TOTAL=$((RETRY_TOTAL + 1))
        log_event RETRY "$label failed verify, entering repair retry..."
        record_task_summary "$label" "$phase" "$task_name" "retrying" "$attempt" "$risk" "$copy_log" "$verify_log" "验收失败，下一轮全部全面修复"
        print_task_progress "RETRY" "$label" "$attempt" "$copy_log" "$verify_log"

        if [ "$MAX_RETRIES" -gt 0 ] && [ "$attempt" -ge "$MAX_RETRIES" ]; then
          mark_task_progress "$label" "failed" "达到最大重试次数：MAX_RETRIES=$MAX_RETRIES" "$copy_log" "$verify_log" "$attempt" "$risk"
          record_task_summary "$label" "$phase" "$task_name" "failed" "$attempt" "$risk" "$copy_log" "$verify_log" "达到最大重试次数：MAX_RETRIES=$MAX_RETRIES"
          log_event FAIL "$label reached max retries ($MAX_RETRIES)"
          log_event FAIL "Check logs: $copy_log and $verify_log"
          exit 1
        fi

        if [ "$DRY_RUN" = "1" ] && [ "$DRY_RUN_RESULT" = "FAIL" ] && [ "$attempt" -ge "$DRY_RUN_MAX_ATTEMPTS" ]; then
          mark_task_progress "$label" "failed" "dry-run 达到最大重试次数：DRY_RUN_MAX_ATTEMPTS=$DRY_RUN_MAX_ATTEMPTS" "$copy_log" "$verify_log" "$attempt" "$risk"
          record_task_summary "$label" "$phase" "$task_name" "failed" "$attempt" "$risk" "$copy_log" "$verify_log" "dry-run 达到最大重试次数：DRY_RUN_MAX_ATTEMPTS=$DRY_RUN_MAX_ATTEMPTS"
          log_event FAIL "DRY_RUN stop at max retry attempts: $DRY_RUN_MAX_ATTEMPTS"
          exit 1
        fi
      done
    done
  done

  log_event INFO "All tasks done. completed=$DONE_TASKS total=$TOTAL_TASKS retries=$RETRY_TOTAL"
}

main "$@"
