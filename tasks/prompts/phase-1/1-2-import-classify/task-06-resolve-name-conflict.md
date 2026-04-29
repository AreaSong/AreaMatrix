# 1-2/task-06: C1-10 resolve-name-conflict

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现同名不同内容冲突处理，默认保留两份并生成无冲突文件名。

## 绑定

- Core 能力：C1-10 resolve-name-conflict
- UX 页面：S1-23, S1-24

## 核对清单

1. 目标目录已有同名文件时不覆盖。
2. 自动生成稳定后缀，例如 `_1`、`_2`。
3. DB `path/current_name` 与文件系统最终路径一致。
4. Replace 路径必须可被 UI 二次确认控制，不能作为默认行为。

## 完成标准

- 同名不同 hash 导入后两个文件都保留。
- 自动改名结果出现在 `FileEntry` 与 change log 中。
- 非法文件名返回 `InvalidPath`。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace name_conflict
```
