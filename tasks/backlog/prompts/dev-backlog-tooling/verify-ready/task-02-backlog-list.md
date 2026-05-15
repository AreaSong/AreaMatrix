# Verify-ready: Implement `./dev backlog list`

本次是只读验收，禁止修改文件。

## 验收目标

确认 `./dev backlog list` 已实现且只读：

- 能列出 `tasks/backlog/prompts/**` 下的 package。
- 输出包含 package slug、标题、copy-ready 数量、verify-ready 数量。
- 输出稳定、可脚本检查。
- 命令不修改任何文件，不写 live queue 或 progress。
- 有回归测试覆盖正常列表和只读边界。

## 必须读取

1. `AGENTS.md`
2. `tasks/backlog/README.md`
3. `tasks/backlog/prompts/dev-backlog-tooling/README.md`
4. `scripts/dev_tools/cli.py`
5. `scripts/dev_tools/backlog.py` if present
6. `scripts/dev_tools/test_backlog_tools.py` if present
7. `scripts/task_loop/actions.py`
8. `scripts/task_loop/self_check.py`

## 只读检查

```bash
git diff --name-only
python3 -m py_compile scripts/dev_tools/*.py scripts/task_loop/*.py
python3 -m unittest scripts.dev_tools.test_backlog_tools
./dev backlog list
git status --short
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
./task-loop check
git diff --check -- scripts/dev_tools scripts/task_loop tasks/backlog
```

## 重点核对

- `./dev backlog list` 运行前后 `git status --short` 不应出现由命令运行产生的新变化。
- 实现不得读取或写入 `tasks/prompts/_shared/progress.json`。
- 实现不得调用 `./task-loop`、`codex exec`、Git checkpoint、promotion apply。

## 判定

若 list 命令会写文件、执行 prompt、影响 progress 或启动 runner，判定不通过。
若没有测试证明列表解析和只读边界，判定不通过。
若验证命令无法运行，说明原因并判定为 blocked。
