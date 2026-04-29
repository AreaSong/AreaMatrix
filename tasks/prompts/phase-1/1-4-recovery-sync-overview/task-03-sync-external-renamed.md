# 1-4/task-03: C1-18 sync-external-renamed

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现外部重命名事件同步，更新 DB 路径与名称并写 change log。

## 绑定

- Core 能力：C1-18 sync-external-renamed
- UX 页面：S1-09, S1-13

## 核对清单

1. `sync_external_changes(kind=Renamed)` 能更新 `files.path/current_name`。
2. change log 保留 old/new path 信息。
3. 无法配对 rename 时安全降级为 removed + created。
4. 不主动重命名或移动用户文件。

## 完成标准

- 外部 rename 后 list/detail/log 都显示新名称。
- 重命名冲突或缺失路径有结构化错误或降级路径。
- cursor 推进规则与 created 一致。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace sync_renamed
```
