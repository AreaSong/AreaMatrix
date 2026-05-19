# Verify-ready: Implement `./dev backlog show`

本次是只读验收，禁止修改文件。

## 验收目标

确认 `./dev backlog show` 已实现且可复制使用：

- `./dev backlog show <package>` 能展示 package README 或任务索引。
- `./dev backlog show <package> --task N --mode copy` 能打印对应 copy-ready prompt。
- `./dev backlog show <package> --task N --mode verify` 能打印对应 verify-ready prompt。
- 未知 package、越界 task、缺少 mode、缺失文件都有非零退出和清晰错误。
- 命令不执行 prompt，不写 live queue 或 progress。

## 必须读取

1. `AGENTS.md`
2. `tasks/backlog/README.md`
3. `tasks/backlog/prompts/dev-backlog-tooling/README.md`
4. `scripts/dev_tools/cli.py`
5. `scripts/dev_tools/backlog.py`
6. `scripts/dev_tools/test_backlog_tools.py`
7. `scripts/dev_tools/common.py`

## 只读检查

```bash
git diff --name-only
python3 -m py_compile scripts/dev_tools/*.py scripts/task_loop/*.py
python3 -m unittest scripts.dev_tools.test_backlog_tools
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

- 正常 show 输出应包含目标 markdown prompt 的原文标题。
- 错误用例应返回非零；若 shell 继续执行，请记录退出码。
- `git status --short` 中不应出现由 show/list 命令运行产生的新变化。
- 实现不得调用 `./task-loop`、`codex exec`、Git checkpoint、promotion apply 或 progress 写入。

## 判定

若 show 命令会执行 prompt、写文件、影响 progress 或启动 runner，判定不通过。
若 task 映射不稳定或没有测试覆盖，判定不通过。
若验证命令无法运行，说明原因并判定为 blocked。
