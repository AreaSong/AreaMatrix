# Copy-ready: Backlog Read-only Tests and Docs

你在 `/Users/as/Ai-Project/project/AreaMatrix` 工作。本任务收口 `./dev backlog` 的测试、文档和 dev console 可发现性。

## 目标

确保 `./dev backlog list/show` 成为可长期维护的只读工具：

- 有回归测试覆盖 list/show、错误用例、只读行为。
- `tasks/backlog/README.md` 写清命令用途和边界。
- `./dev` 控制台 help/tools 或 passthrough 注册中可以发现 backlog 命令。
- `./task-loop check` 能覆盖相关注册或至少不被新命令破坏。

## 非目标

- 不新增执行器。
- 不新增 progress、checkpoint、runner state。
- 不修改 `tasks/prompts/**`。
- 不自动复制、执行或验收 prompt。
- 不把 backlog package promotion 成 live queue。

## Source of Truth

- Backlog boundary: `tasks/backlog/README.md`
- Runtime boundary: `.ai-governance/workflows/prompt-task-runtime.md`
- Console registry: `scripts/task_loop/actions.py`
- Console self-check: `scripts/task_loop/self_check.py`
- Dev tool implementation and tests from tasks 02-03

## Owner / Landing

- Owner: `areamatrix-workflow-planning`
- Test landing: `scripts/dev_tools/test_backlog_tools.py` and, if needed, `scripts/task_loop/self_check.py`
- Console landing: `scripts/task_loop/actions.py` and locale files only if needed
- Docs landing: `tasks/backlog/README.md`

## 先读

1. `AGENTS.md`
2. `tasks/backlog/README.md`
3. `.ai-governance/workflows/prompt-task-runtime.md`
4. `scripts/dev_tools/backlog.py`
5. `scripts/dev_tools/test_backlog_tools.py`
6. `scripts/task_loop/actions.py`
7. `scripts/task_loop/self_check.py`
8. `scripts/task_loop/locales/en.json`
9. `scripts/task_loop/locales/zh.json`
10. `scripts/task_loop/locales/mixed.json`

## 允许修改

- `scripts/dev_tools/**`
- `scripts/task_loop/**`
- `tasks/backlog/README.md`
- `tasks/backlog/prompts/dev-backlog-tooling/**`

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- `workflow/versions/**`
- `/Users/as/Ai-Project/project/Vibe-Skills/**`
- task-loop runtime state directories

## 执行要求

1. 测试必须覆盖：
   - package discovery
   - `list` 输出
   - `show` package README
   - `show --task --mode copy`
   - `show --task --mode verify`
   - 未知 package
   - 越界 task
   - 缺少 mode
   - 命令运行不写 progress 或 live queue
2. 若新增 console action/help 文案，更新所有 locale 并让 `validate_actions` / `./task-loop check` 通过。
3. 文档必须明确 `./dev backlog` 只读，仅打印 backlog prompt package，不执行、不验收、不 promotion。
4. 不要把 backlog package 加入 `tasks/prompts/_shared` export 或 manifest。
5. 若发现现有测试环境会因为当前脏工作树误判，只记录风险，不通过修改 unrelated 文件绕过。

## Rollback / Blocked

- 若 console locale 改动过大，可先只保留 CLI passthrough，并在文档中说明；但必须保证 `./dev backlog ...` 可运行。
- 若测试发现命令写入 live state，回退该写入路径并重新实现为纯读。
- 若 `./task-loop check` 暴露 unrelated 既有失败，记录具体失败，不扩大修复范围。

## 验证

```bash
python3 -m py_compile scripts/dev_tools/*.py scripts/task_loop/*.py
python3 -m unittest scripts.dev_tools.test_backlog_tools
./dev backlog list
./dev backlog show dev-backlog-tooling --task 1 --mode copy
./dev backlog show dev-backlog-tooling --task 1 --mode verify
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
./task-loop check
git diff --check -- scripts/dev_tools scripts/task_loop tasks/backlog
```

汇报时说明测试覆盖、文档更新、只读证据、未覆盖风险和未触碰 `tasks/prompts/**`。
