# 0-2/task-01: Core crate 元数据

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

Core crate 元数据。

## 绑定

- 无特定 UX/Core 绑定；工程骨架或稳定性任务。

## 核对清单

1. 创建最小 Cargo package/workspace 元数据。
2. 依赖版本与技术栈文档一致。
3. 不创建业务模块实现。

## 完成标准

- `core/Cargo.toml` 可被 cargo 读取。
- 没有提前实现产品逻辑。

## 验证

```bash
cd core && cargo metadata --no-deps
```
