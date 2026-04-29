# 1-4/task-02: C1-17 sync-external-created

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现外部新增文件事件同步，供 macOS watcher 去抖后调用。

## 绑定

- Core 能力：C1-17 sync-external-created
- UX 页面：S1-09, S1-10, S1-13

## 核对清单

1. `sync_external_changes(kind=Created)` 读取新增文件并写入 `files.origin=External`。
2. 跳过 `.areamatrix/`、generated overview 和忽略规则路径。
3. 写入 change log 和 fs event cursor。
4. cursor 只在事件批次成功处理后推进。

## 完成标准

- 外部新增文件能出现在 list/tree/detail。
- iCloud placeholder 或不可读文件返回结构化错误。
- 不移动、不覆盖新增用户文件。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace sync_created
```
