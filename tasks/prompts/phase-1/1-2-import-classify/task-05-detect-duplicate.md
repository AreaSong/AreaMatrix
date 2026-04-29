# 1-2/task-05: C1-09 detect-duplicate

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现导入时的重复 hash 检测与 `DuplicateStrategy` 行为。

## 绑定

- Core 能力：C1-09 detect-duplicate
- UX 页面：S1-22, S1-24

## 核对清单

1. 导入前或导入过程中计算 hash 并查询 active 文件。
2. `Skip` 返回 `DuplicateFile` 且不写最终文件。
3. `KeepBoth` 允许同 hash 两条 active 记录但路径不同。
4. `Overwrite` 需要与删除/替换语义一致并写 change log。

## 完成标准

- 重复文件默认不产生新 active 文件。
- duplicate 错误包含 UI 可展示的 existing path。
- 三种策略均有测试证据。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace duplicate
```
