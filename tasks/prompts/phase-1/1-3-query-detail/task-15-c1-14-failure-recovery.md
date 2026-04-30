# 1-3/task-15: C1-14 read-write-note failure-recovery

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

围绕 C1-14 read-write-note 完成 failure-recovery。

## 绑定

- Core 能力：C1-14 read-write-note

## 核对清单

1. 只处理 C1-14 的 failure-recovery 范围。
2. 读取 manifest 中的 Exact Docs 并以文档为 SSOT。
3. 不实现相邻 C1 能力或 UI 页面。
4. 覆盖写 note 失败、权限错误、DB/sidecar 不一致和重复写入路径。
5. 确保旧笔记内容不被破坏，且 `change_log` 只在成功写入后成立。
6. 不得删除、覆盖或移动未确认的用户文件。

## 完成标准

- C1-14 的 failure-recovery 目标可用证据证明。
- 没有扩展到未绑定能力。

## 验证

```bash
cd core && cargo fmt --all -- --check
cd core && cargo clippy --all-targets --all-features -- -D warnings
cd core && cargo test --workspace read_write_note
```
