# Verify-ready: Backlog Read-only Tests and Docs

本次是只读验收，禁止修改文件。

## 验收目标

确认 `./dev backlog` 已具备长期维护所需的测试、文档和可发现性：

- list/show 正常路径和错误路径有测试。
- 命令运行不写 progress、live queue、logs、run summaries、runner lock 或 checkpoint。
- `tasks/backlog/README.md` 说明了 `./dev backlog` 的用途和边界。
- `./dev backlog ...` 能从当前根 `dev` 入口运行。
- `./task-loop check` 没有被新增命令破坏。

## 必须读取

1. `AGENTS.md`
2. `tasks/backlog/README.md`
3. `.ai-governance/workflows/prompt-task-runtime.md`
4. `scripts/dev_tools/backlog.py`
5. `scripts/dev_tools/test_backlog_tools.py`
6. `scripts/dev_tools/cli.py`
7. `scripts/task_loop/actions.py`
8. `scripts/task_loop/self_check.py`
9. `scripts/task_loop/locales/en.json`
10. `scripts/task_loop/locales/zh.json`
11. `scripts/task_loop/locales/mixed.json`

## 只读检查

```bash
git diff --name-only
python3 -m py_compile scripts/dev_tools/*.py scripts/task_loop/*.py
python3 -m unittest scripts.dev_tools.test_backlog_tools
./dev backlog list
./dev backlog show dev-backlog-tooling
./dev backlog show dev-backlog-tooling --task 1 --mode copy
./dev backlog show dev-backlog-tooling --task 1 --mode verify
./dev backlog show missing-package
./dev backlog show dev-backlog-tooling --task 999 --mode copy
git status --short
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
./task-loop check
git diff --check -- scripts/dev_tools scripts/task_loop tasks/backlog
```

## 重点核对

- `tasks/backlog/README.md` 必须说清：只读打印，不执行，不写 progress，不进入 `./task-loop`。
- 测试不能只测 happy path；必须包含错误路径。
- 运行命令后不应产生新的 runtime state 变更。
- `tasks/prompts/**` 不应因为本任务出现改动。

## 判定

若测试或文档缺少只读边界，判定不通过。
若新增命令破坏 `./task-loop check`，判定不通过。
若验证命令无法运行，说明原因并判定为 blocked。
