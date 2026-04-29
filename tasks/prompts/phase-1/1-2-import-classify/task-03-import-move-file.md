# 1-2/task-03: C1-07 import-move-file

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现单文件 Move 导入闭环，支撑设置中的默认存储模式。

## 绑定

- Core 能力：C1-07 import-move-file
- UX 页面：S1-17, S1-20, S1-21, S1-26

## 核对清单

1. `import_file(mode=Moved)` 成功后源路径不存在、最终路径存在。
2. 移动过程使用 staging 或等价可恢复保护。
3. `files.storage_mode=Moved` 且 `source_path` 保留。
4. 失败时不丢源文件。

## 完成标准

- Move 模式端到端测试覆盖成功和失败回滚。
- 与 Copy 模式共享分类、冲突、change log 语义。
- 没有直接覆盖已有目标文件。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace import_move_file
```
