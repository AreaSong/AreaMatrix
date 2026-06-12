# Copy-ready: Implement `./dev backlog show`

你在 `.` 工作。本任务实现只读的 backlog prompt 打印命令。

## 目标

实现：

```bash
./dev backlog show <package>
./dev backlog show <package> --task 1 --mode copy
./dev backlog show <package> --task 1 --mode verify
```

`show <package>` 打印 package README 或任务索引；带 `--task` 和 `--mode` 时打印对应 copy-ready 或 verify-ready prompt 的完整文本，方便用户另开对话使用。

## 非目标

- 不执行 prompt。
- 不自动进入验收。
- 不修改 `tasks/prompts/**`。
- 不写 progress、logs、run summaries、runner lock、checkpoint。
- 不提供 promotion/apply。

## Source of Truth

- Package shape: `tasks/backlog/prompts/<package>/README.md`
- Prompt files: `tasks/backlog/prompts/<package>/copy-ready/*.md` and `verify-ready/*.md`
- Existing list implementation from task 02
- Dev dispatcher: `scripts/dev_tools/cli.py`

## Owner / Landing

- Owner: `areamatrix-workflow-planning`
- Primary landing: `scripts/dev_tools/backlog.py`
- CLI landing: `scripts/dev_tools/cli.py`
- Tests landing: `scripts/dev_tools/test_backlog_tools.py`
- Docs landing: `tasks/backlog/README.md`

## 先读

1. `AGENTS.md`
2. `tasks/backlog/README.md`
3. `tasks/backlog/prompts/dev-backlog-tooling/README.md`
4. `scripts/dev_tools/cli.py`
5. `scripts/dev_tools/backlog.py`
6. `scripts/dev_tools/test_backlog_tools.py`
7. `scripts/dev_tools/common.py`

## 允许修改

- `scripts/dev_tools/**`
- `scripts/task_loop/**` only if needed for command discoverability
- `tasks/backlog/README.md`
- `tasks/backlog/prompts/dev-backlog-tooling/**`

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- `workflow/versions/**`
- `../Vibe-Skills/**`
- task-loop runtime state directories

## 执行要求

1. 复用 task 02 的 package discovery，不复制一套不同逻辑。
2. `show <package>` 默认打印 package README，并附简短任务索引；如果只打印 README，也必须在文档中说明如何查看具体 task。
3. `--task N` 使用 README 表格顺序或文件名排序映射到任务，必须稳定且有测试。
4. `--mode` 只允许 `copy` 或 `verify`，分别映射到 `copy-ready` 和 `verify-ready`。
5. 当指定 `--task` 时，缺少 `--mode` 应返回非零并提示可选值，避免误打印错误 prompt。
6. 未知 package、越界 task、缺失 prompt 文件必须返回非零。
7. 输出必须是原始 markdown 文本，不加会破坏复制的包装符；可以在错误输出中提示路径。
8. 实现保持只读，不调用 runner、codex、Git、promotion 或 progress API。

## Rollback / Blocked

- 若 task 编号无法从现有 package 稳定推导，停止并先补 package README 规则。
- 若必须改 live queue 才能定位 prompt，停止并标记 blocked。
- 若 task 02 未完成或 list 逻辑不稳定，先返回修复 task 02。

## 验证

```bash
python3 -m py_compile scripts/dev_tools/*.py scripts/task_loop/*.py
python3 -m unittest scripts.dev_tools.test_backlog_tools
./dev backlog show dev-backlog-tooling
./dev backlog show dev-backlog-tooling --task 1 --mode copy
./dev backlog show dev-backlog-tooling --task 1 --mode verify
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
./task-loop check
git diff --check -- scripts/dev_tools scripts/task_loop tasks/backlog
```

汇报时说明 task 映射规则、错误语义、只读保证和未触碰 `tasks/prompts/**`。
