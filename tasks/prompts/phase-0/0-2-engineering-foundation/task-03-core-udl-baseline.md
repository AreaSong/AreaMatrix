# 0-2/task-03: Core UDL 基线

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

Core UDL 基线。

## 绑定

- 无特定 UX/Core 绑定；工程骨架或稳定性任务。

## 核对清单

1. 创建 UniFFI 最小 UDL 与 build.rs。
2. 只暴露版本/smoke 级 API 或文档已有基线。
3. 不新增未规划业务接口。

## 完成标准

- UDL 与 core-api 方向一致。
- 后续 C1 API 有明确落点。

## 验证

```bash
cd core && cargo test --workspace
```
