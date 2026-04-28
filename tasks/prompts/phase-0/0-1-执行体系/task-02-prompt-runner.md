# 0-1/task-02: Prompt Runner

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-0.md`

## 范围

建立 `tasks/prompts/` 任务库和手动串行 runner，只输出计划与可复制 prompt，不调用 Codex 自动执行。

## 核对清单

1. `doctor` 校验 task label、依赖、文档路径、允许新增路径和风险标记。
2. `plan` 输出按依赖排序的任务计划。
3. `render` 输出共享规则、任务正文、manifest 和验证要求。
4. `status` 输出任务库概览。
5. Runner 不写产品代码，不调用 `codex exec`。

## 完成标准

- `doctor / plan / render / status` 均可运行。
- 输出内容足够人工复制到新一轮任务中执行。

## 验证

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
python3 tasks/prompts/_shared/prompt_pipeline.py plan --all
python3 tasks/prompts/_shared/prompt_pipeline.py render --task 0-1/task-01
python3 tasks/prompts/_shared/prompt_pipeline.py status
```

