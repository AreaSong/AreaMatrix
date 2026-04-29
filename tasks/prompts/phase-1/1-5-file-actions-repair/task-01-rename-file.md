# 1-5/task-01: C1-22 rename-file

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现单文件重命名 Core 能力，保证 DB、文件系统和 change_log 一致。

## 绑定

- Core 能力：C1-22 rename-file
- UX 页面：S1-33

## 核对清单

1. `rename_file` 校验空名、非法字符、同名冲突。
2. Copy/Move 文件安全 rename，Indexed 文件只更新索引显示名。
3. 不改变 file_id、分类、标签、笔记。
4. 写入 rename change_log。

## 完成标准

- 正常 rename、非法名称、同名冲突、Indexed rename 都有测试。
- 成功后 `get_file`、`list_files`、`list_changes` 状态一致。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace rename_file
```
