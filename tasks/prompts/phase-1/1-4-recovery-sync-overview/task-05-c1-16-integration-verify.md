# 1-4/task-05: C1-16 recover-on-startup integration-verify

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

integration

## 范围

围绕 C1-16 recover-on-startup 完成 integration-verify。

## 绑定

- Core 能力：C1-16 recover-on-startup
- 集成验收：API / UDL / Rust 实现 / 测试 / UX 消费一致性

## 核对清单

1. 只处理 C1-16 的 integration-verify 范围。
2. 读取 manifest 中的 Exact Docs 并以文档为 SSOT。
3. 不实现相邻 C1 能力或 UI 页面。
4. 交叉检查 capability、control map 和消费页面。
5. 确认无 mock/空壳伪完成。

## 完成标准

- C1-16 的 integration-verify 目标可用证据证明。
- 没有扩展到未绑定能力。

## 验证

```bash
cd core && cargo fmt --all -- --check
cd core && cargo clippy --all-targets --all-features -- -D warnings
cd core && cargo test --workspace recover_on_startup
```
