# Verify-ready Prompts

AreaMatrix 的验收 prompt 由 runner 动态生成，不在这里逐个落静态文件。

## 生成单任务验收 prompt

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py verify --task 0-2/task-01
```

## 生成阶段验收 prompt

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py verify --phase phase-0
```

## 验收模式规则

- 禁止修改文件。
- 禁止边验边修。
- 必须逐项验收 task 核对清单。
- 必须逐项验收 task 完成标准。
- 必须检查 manifest 边界是否被完整覆盖。
- 无法证明通过则判定不通过。
- 任一 task 不通过，则阶段验收不通过。

