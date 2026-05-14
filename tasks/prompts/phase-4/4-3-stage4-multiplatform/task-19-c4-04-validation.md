# 4-3/task-19: C4-04 validation

> 共享规则：`tasks/prompts/_shared/audit-rules.md`
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

为 C4-04 camera-import 补齐测试和验证证据。

## 绑定

- Core 能力：C4-04 camera-import
- 能力类型：iOS Import
- 阶段：Stage 4 Multiplatform
- Core 步骤：测试验证

## 核对清单

1. 补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。
2. 验证 Core API / UDL / Rust 实现三者一致。
3. 不新增业务功能，只补验证与必要测试 fixture。
4. 记录无法运行的验证及原因。

## 完成标准

- C4-04 有足够测试证明可进入 UI 接入。
- Validation 命令通过或失败原因被明确记录。

## 验证

```bash
./dev check task 4-3/task-19
```
