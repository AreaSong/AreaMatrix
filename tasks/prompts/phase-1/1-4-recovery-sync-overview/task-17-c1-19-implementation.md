# 1-4/task-17: C1-19 sync-external-removed implementation

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

围绕 C1-19 sync-external-removed 完成 implementation。

## 绑定

- Core 能力：C1-19 sync-external-removed

## 核对清单

1. 只处理 C1-19 的 implementation 范围。
2. 读取 manifest 中的 Exact Docs 并以文档为 SSOT。
3. 不实现相邻 C1 能力或 UI 页面。
4. 实现该能力的最小真实路径。
5. 保持依赖方向符合 layered design。

## 完成标准

- C1-19 的 implementation 目标可用证据证明。
- 没有扩展到未绑定能力。

## 验证

```bash
cd core && cargo fmt --all -- --check
cd core && cargo clippy --all-targets --all-features -- -D warnings
cd core && cargo test --workspace sync_external_removed
```
