# 1-3/task-01: C1-11 list-files contract-api

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

围绕 C1-11 list-files 完成 contract-api。

## 绑定

- Core 能力：C1-11 list-files

## 核对清单

1. 只处理 C1-11 的 contract-api 范围。
2. 读取 manifest 中的 Exact Docs 并以文档为 SSOT。
3. 不实现相邻 C1 能力或 UI 页面。
4. 更新或校准 Core API / UDL 合同意图。
5. 明确输入、输出、错误码和副作用边界。

## 完成标准

- C1-11 的 contract-api 目标可用证据证明。
- 没有扩展到未绑定能力。

## 验证

```bash
cd core && cargo fmt --all -- --check
cd core && cargo clippy --all-targets --all-features -- -D warnings
cd core && cargo test --workspace list_files
```
