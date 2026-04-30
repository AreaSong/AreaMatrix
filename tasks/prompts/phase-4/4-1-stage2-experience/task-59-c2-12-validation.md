# 4-1/task-59: C2-12 validation

> 共享规则：`tasks/prompts/_shared/audit-rules.md`
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

为 C2-12 classifier-correction 补齐测试和验证证据。

## 绑定

- Core 能力：C2-12 classifier-correction
- 能力类型：Classifier
- 阶段：Stage 2 Experience
- Core 步骤：测试验证

## 核对清单

1. 补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。
2. 验证 Core API / UDL / Rust 实现三者一致。
3. 不新增业务功能，只补验证与必要测试 fixture。
4. 记录无法运行的验证及原因。

## 完成标准

- C2-12 有足够测试证明可进入 UI 接入。
- Validation 命令通过或失败原因被明确记录。

## 验证

```bash
./scripts/check-all.sh
```
