# Verify-ready: Dev Backlog Command Boundary

本次是只读验收，禁止修改文件。

## 验收目标

确认 `./dev backlog` 的设计边界已经清晰且只读：

- 命令只读取 `tasks/backlog/prompts/**`。
- 命令不执行 prompt，不启动 `./task-loop`，不调用 `codex exec`。
- 命令不写 `tasks/prompts/**`、`tasks/prompts/_shared/progress.json`、logs、run summaries、runner lock 或 checkpoint。
- 已核对 `dev`、`scripts/task_loop/console.py`、`scripts/task_loop/actions.py`、`scripts/dev_tools/cli.py` 的真实入口关系。
- 后续实现任务有明确 landing、错误语义和验证命令。

## 必须读取

1. `AGENTS.md`
2. `tasks/backlog/README.md`
3. `workflow/AGENTS.md`
4. `workflow/README.md`
5. `tasks/prompts/README.md`
6. `.ai-governance/workflows/prompt-task-runtime.md`
7. `dev`
8. `scripts/task_loop/console.py`
9. `scripts/task_loop/actions.py`
10. `scripts/dev_tools/cli.py`
11. 本 prompt 包 `README.md`
12. `tasks/backlog/prompts/dev-backlog-tooling/copy-ready/task-01-backlog-command-boundary.md`

## 只读检查

```bash
git diff --name-only
rg -n "backlog|tasks/backlog|tasks/prompts|progress|task-loop|codex exec|checkpoint|read-only|只读" tasks/backlog scripts/dev_tools scripts/task_loop
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- tasks/backlog scripts/dev_tools scripts/task_loop
```

## 判定

若设计允许 `./dev backlog` 写 live queue、progress、logs、checkpoint 或执行 prompt，判定不通过。
若没有核对 `./dev` 真实入口关系，判定不通过。
若验证命令无法运行，说明原因并判定为 blocked。
