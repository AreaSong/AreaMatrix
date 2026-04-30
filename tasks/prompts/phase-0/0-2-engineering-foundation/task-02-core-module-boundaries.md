# 0-2/task-02: Core 模块边界骨架

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

Core 模块边界骨架。

## 绑定

- 无特定 UX/Core 绑定；工程骨架或稳定性任务。

## 核对清单

1. 创建 api/domain/error/config/db/classify/storage/overview/tree/sync 模块声明。
2. 模块只放边界、占位类型或 smoke 可用代码。
3. 不实现 DB/storage/classify 业务逻辑。

## 完成标准

- `cargo test` 能编译空骨架。
- 模块边界与 layered design 一致。

## 验证

```bash
cd core && cargo test --workspace
```
