# 1-4/task-04: C1-19 sync-external-removed

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现外部删除事件同步，软标记 DB 状态并保留可追溯日志。

## 绑定

- Core 能力：C1-19 sync-external-removed
- UX 页面：S1-09, S1-11, S1-13

## 核对清单

1. `sync_external_changes(kind=Removed)` 将对应文件标记为 deleted 或等价状态。
2. 默认列表不再显示已删除文件。
3. 写入 `change_log.deleted`。
4. 不删除任何额外文件。

## 完成标准

- 外部删除后 list/detail/log 行为与文档一致。
- 重复 remove 或路径已不存在幂等处理。
- cursor 推进规则清晰且有测试。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace sync_removed
```
