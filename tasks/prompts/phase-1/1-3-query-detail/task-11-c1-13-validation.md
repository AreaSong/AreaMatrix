# 1-3/task-11: C1-13 list-change-log validation

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

围绕 C1-13 list-change-log 完成 validation。

## 绑定

- Core 能力：C1-13 list-change-log

## 核对清单

1. 只处理 C1-13 的 validation 范围。
2. 读取 manifest 中的 Exact Docs 并以文档为 SSOT。
3. 不实现相邻 C1 能力或 UI 页面。
4. 补齐针对该能力的 Rust 测试。
5. 验证成功路径和关键错误路径。

## 完成标准

- C1-13 的 validation 目标可用证据证明。
- 没有扩展到未绑定能力。

## 验证

```bash
cd core && cargo fmt --all -- --check
cd core && cargo clippy --all-targets --all-features -- -D warnings
cd core && cargo test --workspace list_change_log
```
