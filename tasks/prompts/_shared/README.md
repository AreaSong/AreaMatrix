# Prompt Shared Runtime

本目录承载 AreaMatrix prompt 任务库的共享材料。

## 文件

- `audit-rules.md`：所有任务共用的执行与验收规则。
- `engineering-quality-rules.md`：所有任务共用的工程质量门禁。
- `dependency-graph.md`：批次依赖图。
- `manifests/`：每个 phase 的精确任务边界。
- `prompt_pipeline.py`：手动串行 runner。

## 常用命令

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
python3 tasks/prompts/_shared/prompt_pipeline.py plan --all
python3 tasks/prompts/_shared/prompt_pipeline.py next
python3 tasks/prompts/_shared/prompt_pipeline.py render --task 0-2/task-01
python3 tasks/prompts/_shared/prompt_pipeline.py verify --task 0-2/task-01
python3 tasks/prompts/_shared/prompt_pipeline.py verify --phase phase-0
python3 tasks/prompts/_shared/prompt_pipeline.py mark --task 0-2/task-01 --status completed
python3 tasks/prompts/_shared/prompt_pipeline.py status
```

## 约束

- Runner 不调用 `codex exec`。
- `render` 是执行模式，可以改文件。
- `verify` 是验收模式，禁止改文件。
- copy-ready / verify-ready 都必须读取工程质量规则和 `docs/development/coding-standards.md`。
- verify-ready / phase-verify 会内嵌 validation-driver 关键规则，并明确 repo-local skill 路径。
- `mark` 只记录人工进度，不代表自动验收。
