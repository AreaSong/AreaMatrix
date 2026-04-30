# Verify-ready Prompts

AreaMatrix 的验收 prompt 可以由 runner 动态生成，也可以导出为本目录下的静态文件。

## 动态生成单任务验收 prompt

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py verify --task 0-2/task-01
```

## 生成阶段验收 prompt

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py verify --phase phase-0
```

## 导出静态验收 prompt

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py export --phase phase-1
python3 tasks/prompts/_shared/prompt_pipeline.py export --all
```

导出后文件按 phase 存放：

```text
tasks/prompts/_shared/verify-ready/phase-1/1-1-task-01.md
```

验收时直接打开对应文件，复制整段 verify-ready prompt 给 Codex。验收 prompt 是只读模式，不能边验边修。

## 验收模式规则

- 禁止修改文件。
- 禁止边验边修。
- 必须逐项验收 task 核对清单。
- 必须逐项验收 task 完成标准。
- 必须检查 manifest 边界是否被完整覆盖。
- 无法证明通过则判定不通过。
- 任一 task 不通过，则阶段验收不通过。
