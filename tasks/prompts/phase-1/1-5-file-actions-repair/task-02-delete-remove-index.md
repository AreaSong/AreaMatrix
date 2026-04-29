# 1-5/task-02: C1-23 delete-remove-index

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现单文件 Move to Trash 与 Remove from Index Core 能力。

## 绑定

- Core 能力：C1-23 delete-remove-index
- UX 页面：S1-34

## 核对清单

1. Copy/Move 删除默认进入系统 Trash。
2. Indexed/Missing 的 Remove from Index 不删除源文件。
3. 删除或移除记录写入 change_log。
4. 失败时不清空笔记、不误删其他文件。

## 完成标准

- Delete 与 Remove from Index 行为可通过测试区分。
- Trash 不可用、文件缺失、权限失败有结构化错误。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace delete_remove_index
```
