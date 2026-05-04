#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$SCRIPT_DIR}"
RUNNER="${RUNNER:-$ROOT_DIR/scripts/run_area_matrix_task_pipeline.sh}"
PIPELINE="${PIPELINE:-$ROOT_DIR/tasks/prompts/_shared/prompt_pipeline.py}"
PROGRESS_FILE="${PROGRESS_FILE:-$ROOT_DIR/tasks/prompts/_shared/progress.json}"
LOCK_DIR="${LOCK_DIR:-$ROOT_DIR/.codex/task-loop-lock}"
LOG_ROOT="${LOG_ROOT:-$ROOT_DIR/.codex/task-loop-logs}"
RUN_SUMMARY_ROOT="${RUN_SUMMARY_ROOT:-$ROOT_DIR/.codex/task-loop-runs}"
PROGRESS_BACKUP_ROOT="${PROGRESS_BACKUP_ROOT:-$ROOT_DIR/.codex/task-loop-progress-backups}"
CONTROL_DIR="${CONTROL_DIR:-$ROOT_DIR/.codex/task-loop-control}"
CONSOLE_LOG_ROOT="${CONSOLE_LOG_ROOT:-$ROOT_DIR/.codex/task-loop-console}"

timestamp() {
  date '+%Y%m%d_%H%M%S'
}

pause() {
  printf '\n按 Enter 返回菜单...'
  read -r _
}

line_count() {
  awk 'NF { count++ } END { print count + 0 }'
}

runner_processes() {
  ps -axo pid=,ppid=,stat=,command= | awk '/[r]un_area_matrix_task_pipeline\.sh/ { print }'
}

codex_processes() {
  ps -axo pid=,ppid=,stat=,command= | awk '/[c]odex exec/ { print }'
}

repo_codex_processes() {
  local root_pattern
  root_pattern="$(printf '%s' "$ROOT_DIR" | sed 's/[.[\*^$()+?{}|\\]/\\&/g')"
  ps -axo pid=,ppid=,stat=,command= | awk -v root="$root_pattern" '/[c]odex exec/ && $0 ~ root { print }'
}

print_banner() {
  if [ -t 1 ] && [ -n "${TERM:-}" ]; then
    clear
  fi
  cat <<'EOF'
============================================================
        AreaMatrix Task Loop 控制台
============================================================
EOF
}

confirm() {
  local prompt="$1"
  local answer
  printf '%s [y/N] ' "$prompt"
  read -r answer
  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

live_lock_pid() {
  if [ -f "$LOCK_DIR/pid" ]; then
    tr -d '[:space:]' < "$LOCK_DIR/pid"
  fi
}

is_pid_alive() {
  local pid="$1"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

live_runner_active() {
  local pid
  pid="$(live_lock_pid)"
  [ -d "$LOCK_DIR" ] && is_pid_alive "$pid"
}

status_output() {
  PROGRESS_FILE="$PROGRESS_FILE" \
  LOG_ROOT="$LOG_ROOT" \
  RUN_SUMMARY_ROOT="$RUN_SUMMARY_ROOT" \
  PROGRESS_BACKUP_ROOT="$PROGRESS_BACKUP_ROOT" \
  LOCK_DIR="$LOCK_DIR" \
  CONTROL_DIR="$CONTROL_DIR" \
  bash "$RUNNER" --status 2>/dev/null || true
}

print_status_compact() {
  local output
  output="$(status_output)"

  printf '%s\n' "$output" | awk '
    /^- lock:/ ||
    /^- lock_alive:/ ||
    /^- lock_pid:/ ||
    /^- lock_run_id:/ ||
    /^- lock_command:/ ||
    /^- drain_requested:/ ||
    /^- latest_log_dir:/ ||
    /^- completed:/ ||
    /^- in_progress:/ ||
    /^- failed:/ ||
    /^- blocked:/ ||
    /^- stale_in_progress:/ ||
    /^- recent_in_progress:/ ||
    /^- recent_failed:/ ||
    /^- recent_blocked:/ ||
    /^- recent_stale_in_progress:/ ||
    /^- first task:/ ||
    /^  - pending:/ ||
    /^  - completed:/ ||
    /^  - in_progress:/ { print }
  '
}

show_processes() {
  local runner_ps repo_codex_ps codex_ps
  runner_ps="$(runner_processes || true)"
  repo_codex_ps="$(repo_codex_processes || true)"
  codex_ps="$(codex_processes || true)"

  printf '\n进程快照\n'
  printf -- '- task-loop runner: %s\n' "$(printf '%s\n' "$runner_ps" | line_count)"
  printf -- '- AreaMatrix codex exec: %s\n' "$(printf '%s\n' "$repo_codex_ps" | line_count)"
  printf -- '- host codex exec: %s\n' "$(printf '%s\n' "$codex_ps" | line_count)"

  if [ -n "$runner_ps" ]; then
    printf '\nrunner:\n%s\n' "$runner_ps"
  fi
  if [ -n "$repo_codex_ps" ]; then
    printf '\nAreaMatrix codex exec:\n%s\n' "$repo_codex_ps"
  fi
  if [ -n "$codex_ps" ]; then
    printf '\nhost codex exec:\n%s\n' "$codex_ps"
  fi
}

show_latest_task_details() {
  python3 - "$PROGRESS_FILE" "$RUN_SUMMARY_ROOT" <<'PY'
import json
import sys
from pathlib import Path

progress_file = Path(sys.argv[1])
run_root = Path(sys.argv[2])

def read_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default

data = read_json(progress_file, {"tasks": {}})
tasks = data.get("tasks", {})
interesting = []
for label, value in tasks.items():
    if isinstance(value, dict) and value.get("status") in {"in_progress", "failed", "blocked"}:
        interesting.append((value.get("updated_at", ""), label, value))
interesting.sort(reverse=True)

print("\n当前任务")
if interesting:
    _, label, entry = interesting[0]
    print(f"- label: {label}")
    print(f"- status: {entry.get('status', 'unknown')}")
    print(f"- attempts: {entry.get('attempts', 0)}")
    print(f"- note: {entry.get('note', '')}")
    if entry.get("copy_log"):
        print(f"- copy_log: {entry['copy_log']}")
    if entry.get("verify_log"):
        print(f"- verify_log: {entry['verify_log']}")
    if entry.get("git_checkpoint_status"):
        print(f"- git_checkpoint_status: {entry['git_checkpoint_status']}")
    if entry.get("git_push_status"):
        print(f"- git_push_status: {entry['git_push_status']}")
else:
    print("- none")

index = read_json(run_root / "index.json", {"runs": []})
runs = [item for item in index.get("runs", []) if isinstance(item, dict)]
print("\n最近 run")
for item in runs[:5]:
    print(
        f"- {item.get('run_id', 'unknown')} "
        f"status={item.get('status', '')} "
        f"completed={item.get('completed', 0)} "
        f"retries={item.get('retries', 0)} "
        f"start_from={item.get('start_from', '')} "
        f"stop_after={item.get('stop_after', '')}"
    )
PY
}

show_latest_failure_summary() {
  local latest_verify
  latest_verify="$(find "$ROOT_DIR/.codex/task-loop-logs" -type f -name '*-verify-attempt-*.log' 2>/dev/null | sort | tail -n 1 || true)"
  printf '\n最近 verify 摘要\n'
  if [ -z "$latest_verify" ]; then
    printf '- 暂无 verify 日志。\n'
    return 0
  fi
  printf -- '- log: %s\n' "$latest_verify"
  tail -n 60 "$latest_verify" | sed -n '/VERIFY_RESULT/,$!p' | tail -n 40
  tail -n 5 "$latest_verify" | grep -E 'VERIFY_RESULT:' || true
}

show_recovery_hints() {
  local output
  output="$(status_output)"
  printf '\n恢复建议\n'
  if printf '%s\n' "$output" | grep -q 'stale_in_progress: [1-9]'; then
    printf -- '- 存在 stale：优先选菜单 2 或运行 ./dev.sh resume-stale。\n'
  fi
  if printf '%s\n' "$output" | grep -q '^- failed: '; then
    printf -- '- 存在 failed：先看最近 verify 摘要，再选菜单 3 或 ./dev.sh resume-failed。\n'
  fi
  if printf '%s\n' "$output" | grep -q '^- blocked: '; then
    printf -- '- 存在 blocked：检查风险门禁，确认后用 allow 模式从对应 task 继续。\n'
  fi
  if live_runner_active; then
    printf -- '- 当前已有 live runner；不要启动第二个。需要停机请选菜单 5 请求优雅收尾。\n'
  fi
  if git -C "$ROOT_DIR" status --short | grep -q .; then
    printf -- '- 工作区非干净；commit/push checkpoint 模式启动前会被 Git gate 拦截。可先查看 git status。\n'
  fi
}

show_status() {
  print_banner
  PROGRESS_FILE="$PROGRESS_FILE" \
  LOG_ROOT="$LOG_ROOT" \
  RUN_SUMMARY_ROOT="$RUN_SUMMARY_ROOT" \
  PROGRESS_BACKUP_ROOT="$PROGRESS_BACKUP_ROOT" \
  LOCK_DIR="$LOCK_DIR" \
  CONTROL_DIR="$CONTROL_DIR" \
  bash "$RUNNER" --status
  show_processes
  show_latest_task_details
  show_latest_failure_summary
  show_recovery_hints
}

guard_no_live_runner() {
  if ! live_runner_active; then
    return 0
  fi
  print_banner
  printf '已有 live runner，已阻止启动第二个 runner。\n\n'
  print_status_compact
  show_processes
  printf '\n可选操作：\n'
  printf '  ./dev.sh drain   请求当前 task 完成并 checkpoint 后停止\n'
  printf '  ./dev.sh status  查看详细状态和日志\n'
  return 1
}

choose_execution_mode() {
  if [ "${DEV_SH_EXECUTION_MODE:-}" = "foreground" ] || [ "${DEV_SH_EXECUTION_MODE:-}" = "background" ]; then
    printf '%s\n' "$DEV_SH_EXECUTION_MODE"
    return 0
  fi
  if [ ! -t 0 ]; then
    printf 'background\n'
    return 0
  fi
  printf '\n执行方式：\n' >&2
  printf '  1) 后台运行\n' >&2
  printf '  2) 前台运行\n' >&2
  printf '> ' >&2
  local answer
  read -r answer
  case "$answer" in
    2|foreground)
      printf 'foreground\n'
      ;;
    *)
      printf 'background\n'
      ;;
  esac
}

choose_git_mode() {
  if [ -n "${DEV_SH_GIT_CHECKPOINT:-}" ]; then
    printf '%s\n' "$DEV_SH_GIT_CHECKPOINT"
    return 0
  fi
  if [ ! -t 0 ]; then
    printf 'commit\n'
    return 0
  fi
  printf '\nGit checkpoint：\n' >&2
  printf '  1) 本地 commit（默认）\n' >&2
  printf '  2) commit + push\n' >&2
  printf '  3) off（仅诊断）\n' >&2
  printf '> ' >&2
  local answer
  read -r answer
  case "$answer" in
    2|push)
      printf 'push\n'
      ;;
    3|off)
      printf 'off\n'
      ;;
    *)
      printf 'commit\n'
      ;;
  esac
}

choose_max_tasks() {
  if [ -n "${DEV_SH_MAX_TASKS:-}" ]; then
    printf '%s\n' "$DEV_SH_MAX_TASKS"
    return 0
  fi
  if [ ! -t 0 ]; then
    printf '0\n'
    return 0
  fi
  printf '\n任务数量上限：\n' >&2
  printf '  1) 无限（默认）\n' >&2
  printf '  2) 1 个\n' >&2
  printf '  3) 5 个\n' >&2
  printf '  4) 20 个\n' >&2
  printf '  5) 自定义 N\n' >&2
  printf '> ' >&2
  local answer n
  read -r answer
  case "$answer" in
    2)
      printf '1\n'
      ;;
    3)
      printf '5\n'
      ;;
    4)
      printf '20\n'
      ;;
    5)
      printf 'N=' >&2
      read -r n
      if printf '%s' "$n" | grep -Eq '^[0-9]+$'; then
        printf '%s\n' "$n"
      else
        printf '0\n'
      fi
      ;;
    *)
      printf '0\n'
      ;;
  esac
}

choose_stop_target() {
  if [ -n "${DEV_SH_PHASE:-}" ] || [ -n "${DEV_SH_STOP_AFTER:-}" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    return 0
  fi
  printf '\n停止点：\n' >&2
  printf '  1) 不限制（默认）\n' >&2
  printf '  2) 只跑某个 phase\n' >&2
  printf '  3) 跑到某个 task 后停止\n' >&2
  printf '> ' >&2
  local answer value
  read -r answer
  case "$answer" in
    2)
      printf 'phase=' >&2
      read -r value
      DEV_SH_PHASE="$value"
      ;;
    3)
      printf 'task label=' >&2
      read -r value
      DEV_SH_STOP_AFTER="$value"
      ;;
  esac
  export DEV_SH_PHASE DEV_SH_STOP_AFTER
}

build_runner_command() {
  local mode="$1"
  local git_mode="$2"
  local max_tasks="$3"
  shift 3
  local args=("$@")
  RUNNER_CMD=(
    env
    RISK_POLICY=allow
    MAX_RETRIES=0
    GIT_CHECKPOINT="$git_mode"
    PROGRESS_FILE="$PROGRESS_FILE"
    LOG_ROOT="$LOG_ROOT"
    RUN_SUMMARY_ROOT="$RUN_SUMMARY_ROOT"
    PROGRESS_BACKUP_ROOT="$PROGRESS_BACKUP_ROOT"
    LOCK_DIR="$LOCK_DIR"
    CONTROL_DIR="$CONTROL_DIR"
  )
  if [ "${DEV_SH_DRY_RUN:-0}" = "1" ]; then
    RUNNER_CMD+=(DRY_RUN=1 DRY_RUN_RESULT="${DEV_SH_DRY_RUN_RESULT:-PASS}")
  fi
  RUNNER_CMD+=(bash "$RUNNER")
  if [ "$max_tasks" != "0" ]; then
    RUNNER_CMD+=(--max-tasks "$max_tasks")
  fi
  if [ -n "${DEV_SH_PHASE:-}" ]; then
    RUNNER_CMD+=(--phase "$DEV_SH_PHASE")
  fi
  if [ -n "${DEV_SH_STOP_AFTER:-}" ]; then
    RUNNER_CMD+=(--stop-after "$DEV_SH_STOP_AFTER")
  fi
  if [ "${#args[@]}" -gt 0 ]; then
    RUNNER_CMD+=("${args[@]}")
  fi
  RUNNER_EXECUTION_MODE="$mode"
}

print_command_preview() {
  printf '\n即将执行：'
  printf ' %q' "${RUNNER_CMD[@]}"
  printf '\n'
  printf '执行方式：%s\n' "$RUNNER_EXECUTION_MODE"
}

run_runner_command() {
  mkdir -p "$CONSOLE_LOG_ROOT"
  print_command_preview
  if [ "$RUNNER_EXECUTION_MODE" = "foreground" ]; then
    "${RUNNER_CMD[@]}"
    return
  fi
  local log_file pid
  log_file="$CONSOLE_LOG_ROOT/task-loop-$(timestamp).log"
  nohup "${RUNNER_CMD[@]}" > "$log_file" 2>&1 &
  pid=$!
  printf '%s\n' "$pid" > "$CONSOLE_LOG_ROOT/last-task-loop.pid"
  printf '已后台启动：pid=%s\n' "$pid"
  printf '控制台日志：%s\n' "$log_file"
  printf '任务详细日志仍写入 .codex/task-loop-logs/<run_id>/...\n'
}

start_with_wizard() {
  local action="$1"
  shift
  guard_no_live_runner || return 1
  local execution_mode git_mode max_tasks
  execution_mode="$(choose_execution_mode)"
  git_mode="$(choose_git_mode)"
  max_tasks="$(choose_max_tasks)"
  choose_stop_target
  build_runner_command "$execution_mode" "$git_mode" "$max_tasks" "$@"
  run_runner_command
}

request_drain() {
  if ! live_runner_active; then
    printf '当前没有 live runner，无法请求优雅收尾。\n'
    return 1
  fi
  PROGRESS_FILE="$PROGRESS_FILE" \
  LOG_ROOT="$LOG_ROOT" \
  RUN_SUMMARY_ROOT="$RUN_SUMMARY_ROOT" \
  PROGRESS_BACKUP_ROOT="$PROGRESS_BACKUP_ROOT" \
  LOCK_DIR="$LOCK_DIR" \
  CONTROL_DIR="$CONTROL_DIR" \
  bash "$RUNNER" --request-drain
}

run_health_checks() {
  print_banner
  printf '运行 prompt doctor...\n'
  python3 "$PIPELINE" doctor
  printf '\n运行 task-loop check...\n'
  bash "$ROOT_DIR/scripts/check-task-loop.sh"
}

show_latest_console_log() {
  print_banner
  local latest
  latest="$(find "$CONSOLE_LOG_ROOT" -type f -name '*.log' 2>/dev/null | sort | tail -n 1 || true)"
  if [ -z "$latest" ]; then
    printf '暂无控制台后台日志。\n'
    return 0
  fi
  printf 'latest: %s\n\n' "$latest"
  tail -n 100 "$latest"
}

clear_stale() {
  if confirm "确认只清理 stale in_progress 记录？该操作会先备份 progress.json。"; then
    PROGRESS_FILE="$PROGRESS_FILE" \
    LOG_ROOT="$LOG_ROOT" \
    RUN_SUMMARY_ROOT="$RUN_SUMMARY_ROOT" \
    PROGRESS_BACKUP_ROOT="$PROGRESS_BACKUP_ROOT" \
    LOCK_DIR="$LOCK_DIR" \
    CONTROL_DIR="$CONTROL_DIR" \
    bash "$RUNNER" --clear-stale
  else
    printf '已取消。\n'
  fi
}

reset_progress() {
  printf '高风险操作：这会备份并清空 progress.json，从 0 开始。\n'
  printf '请输入 RESET 确认：'
  local answer
  read -r answer
  if [ "$answer" = "RESET" ]; then
    PROGRESS_FILE="$PROGRESS_FILE" \
    LOG_ROOT="$LOG_ROOT" \
    RUN_SUMMARY_ROOT="$RUN_SUMMARY_ROOT" \
    PROGRESS_BACKUP_ROOT="$PROGRESS_BACKUP_ROOT" \
    LOCK_DIR="$LOCK_DIR" \
    CONTROL_DIR="$CONTROL_DIR" \
    bash "$RUNNER" --reset-progress
  else
    printf '已取消。\n'
  fi
}

print_menu() {
  print_banner
  print_status_compact
  show_processes
  cat <<'EOF'

操作：
  1) 刷新详细状态
  2) 从 stale 任务继续
  3) 从 failed 任务继续
  4) 从下一个 pending 继续
  5) 一键优雅收尾（当前 task 完成 + checkpoint 后停止）
  6) 查看最近后台控制台日志
  7) 查看最近 verify 摘要
  8) 运行 doctor + task-loop 自检

  9) 清理 stale in_progress（会备份 progress）
  10) 重置 progress 从 0 开始（需输入 RESET）

  h) 帮助    q) 退出
EOF
}

print_help() {
  print_banner
  cat <<'EOF'
常用理解：
- stale 继续：用于关机、强停、断电后恢复半截任务。
- 优雅收尾：用于 runner 正在执行时，请求它做完当前 task、完成 verify 和 Git checkpoint 后停止。
- Git 默认：commit；需要上传时启动向导里选择 commit + push。
- 任务数默认：无限；启动向导可选 1、5、20 或自定义。
- 已有 live runner 时，控制台会阻止启动第二个 runner。

快捷命令：
  ./dev.sh status
  ./dev.sh compact
  ./dev.sh resume-stale
  ./dev.sh resume-failed
  ./dev.sh start
  ./dev.sh drain
  ./dev.sh logs
  ./dev.sh verify-summary
  ./dev.sh check
EOF
}

interactive_loop() {
  while true; do
    print_menu
    printf '\n> '
    local choice
    read -r choice
    case "$choice" in
      1|"")
        show_status
        pause
        ;;
      2)
        start_with_wizard "resume-stale" --resume-stale || true
        pause
        ;;
      3)
        start_with_wizard "resume-failed" --resume-failed || true
        pause
        ;;
      4)
        start_with_wizard "start" || true
        pause
        ;;
      5)
        request_drain || true
        pause
        ;;
      6)
        show_latest_console_log
        pause
        ;;
      7)
        print_banner
        show_latest_failure_summary
        pause
        ;;
      8)
        run_health_checks
        pause
        ;;
      9)
        clear_stale
        pause
        ;;
      10)
        reset_progress
        pause
        ;;
      h|help)
        print_help
        pause
        ;;
      q|quit|exit|0)
        return 0
        ;;
      *)
        printf '未知选项：%s\n' "$choice"
        pause
        ;;
    esac
  done
}

main() {
  case "${1:-}" in
    ""|menu)
      interactive_loop
      ;;
    status)
      show_status
      ;;
    compact)
      print_banner
      print_status_compact
      show_processes
      ;;
    processes|ps)
      show_processes
      ;;
    resume-stale)
      start_with_wizard "resume-stale" --resume-stale
      ;;
    resume-failed)
      start_with_wizard "resume-failed" --resume-failed
      ;;
    start)
      start_with_wizard "start"
      ;;
    drain)
      request_drain
      ;;
    logs)
      show_latest_console_log
      ;;
    verify-summary)
      print_banner
      show_latest_failure_summary
      ;;
    check)
      run_health_checks
      ;;
    help|-h|--help)
      print_help
      ;;
    *)
      printf '未知命令：%s\n\n' "$1" >&2
      print_help
      return 1
      ;;
  esac
}

main "$@"
