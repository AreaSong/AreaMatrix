# 0-2/task-05: Core smoke test

> 共享规则：`workflow/versions/v1-mvp/execution/_shared/audit-rules.md`
> 任务切片规则：`workflow/versions/v1-mvp/execution/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

Core smoke test。

## 绑定

- 无特定 UX/Core 绑定；工程骨架或稳定性任务。

## 核对清单

1. 创建最小 smoke test。
2. 测试只验证工程骨架可编译。
3. 不伪造任何 C1 能力通过。

## 完成标准

- `cargo test --workspace` 通过。

## 验证

```bash
cd core && cargo test --workspace
```
