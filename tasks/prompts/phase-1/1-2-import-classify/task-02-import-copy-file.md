# 1-2/task-02: C1-06 import-copy-file

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现单文件 Copy 导入闭环：复制源文件、hash、分类、写 DB、写 change log、更新概览。

## 绑定

- Core 能力：C1-06 import-copy-file
- UX 页面：S1-17, S1-18, S1-20, S1-21, S1-09

## 核对清单

1. `import_file(mode=Copied)` 不改变源文件。
2. 导入使用 staging，成功后原子落到最终路径。
3. `files`、`change_log` 和文件系统最终状态一致。
4. 失败路径不留下 active 半成品。

## 完成标准

- 成功后 `list_files` 能查到新文件，`list_changes` 能查到 imported 记录。
- 源文件 hash 与目标文件 hash 一致。
- Copy 模式单文件端到端测试通过。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace import_copy_file
```
