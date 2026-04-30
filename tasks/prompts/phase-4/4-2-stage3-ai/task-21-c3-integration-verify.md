# 4-2/task-21: stage3-ai integration verify

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

integration

## 范围

验收 stage3-ai 的 Core 能力和 UX 页面是否按 control map 形成闭环。

## 绑定

- 阶段能力：C3
- 阶段页面：S3

## 核对清单

1. 逐项检查该阶段 capability、page spec、control map、实现和验证证据。
2. 任一原子任务未完成则阶段不通过。
3. 不新增未列出的功能。

## 完成标准

- 阶段闭环具备可证明证据。

## 验证

```bash
./scripts/check-all.sh
```
