# Copy-ready: Implement `./dev backlog list`

你在 `.` 工作。本任务实现只读的 backlog package 列表命令。

## 目标

实现：

```bash
./dev backlog list
```

输出当前 `tasks/backlog/prompts/**` 下可用 package 的 slug、标题、任务数量，以及 copy-ready / verify-ready 文件数量。该命令只读，不执行 prompt。

## 非目标

- 不实现 `show`。
- 不执行 copy-ready 或 verify-ready prompt。
- 不修改 `tasks/prompts/**`。
- 不写 progress、logs、run summaries、runner lock、checkpoint。
- 不接入第二套 runner 或 promotion 机制。

## Source of Truth

- Backlog package boundary: `tasks/backlog/README.md`
- Existing package shape: `tasks/backlog/prompts/*/{README.md,copy-ready,verify-ready}`
- Dev tool dispatcher: `scripts/dev_tools/cli.py`
- Shared helpers: `scripts/dev_tools/common.py`
- Console passthrough behavior: `scripts/task_loop/console.py` and `scripts/task_loop/actions.py`

## Owner / Landing

- Owner: `areamatrix-workflow-planning`
- Primary landing: `scripts/dev_tools/backlog.py` if a new helper module is useful
- CLI landing: `scripts/dev_tools/cli.py`
- Tests landing: `scripts/dev_tools/test_*`
- Docs landing: `tasks/backlog/README.md` only if command usage needs to be discoverable now

## 先读

1. `AGENTS.md`
2. `tasks/backlog/README.md`
3. `tasks/backlog/prompts/codex-native-area-vibe-optimization/README.md`
4. `tasks/backlog/prompts/vibe-skills-absorption/README.md`
5. `tasks/backlog/prompts/dev-backlog-tooling/README.md`
6. `scripts/dev_tools/cli.py`
7. `scripts/dev_tools/common.py`
8. `scripts/dev_tools/test_build_tools.py`
9. `scripts/dev_tools/test_workflow_hardening.py`
10. `scripts/task_loop/actions.py`
11. `scripts/task_loop/self_check.py`

## 允许修改

- `scripts/dev_tools/**`
- `scripts/task_loop/**` only if needed for passthrough registry or self-check
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

1. 新增或复用 `scripts/dev_tools/backlog.py`，用 `pathlib` 读取 package 目录，不用 ad hoc shell。
2. `list` 只扫描 `tasks/backlog/prompts/*`，只接受同时具备 `README.md` 且至少一个 prompt 子目录的 package。
3. 输出稳定排序，建议按 package slug 字典序或 README 中显式顺序；选择一种并写入测试。
4. 统计：
   - package slug
   - README 第一行标题
   - `copy-ready/*.md` 数量
   - `verify-ready/*.md` 数量
5. 对空 package root 给出清晰提示和非零返回，除非 repo 当前确实有 package。
6. 确保命令不写文件；实现中不得调用 `write_text`、`mkdir`、`unlink`、`rename`、`subprocess` 执行 runner 或 `codex exec`。
7. 加最小回归测试，覆盖正常列表和只读行为。

## Rollback / Blocked

- 若发现 `./dev backlog` 已存在，优先补测试和文档，不重复实现。
- 若必须改 live queue 才能统计 package，停止并标记 blocked。
- 若控制台 passthrough 阻塞 `./dev backlog list`，先补 registry/passthrough，再继续。

## 验证

```bash
python3 -m py_compile scripts/dev_tools/*.py scripts/task_loop/*.py
python3 -m unittest scripts.dev_tools.test_backlog_tools
./dev backlog list
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
./task-loop check
git diff --check -- scripts/dev_tools scripts/task_loop tasks/backlog
```

汇报时说明输出示例、测试结果、只读保证和未触碰 `tasks/prompts/**`。
