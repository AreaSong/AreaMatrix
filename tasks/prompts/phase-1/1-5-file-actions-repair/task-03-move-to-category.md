# 1-5/task-03: C1-24 move-to-category

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现单文件改分类 Core 能力，含目标路径冲突安全处理。

## 绑定

- Core 能力：C1-24 move-to-category
- UX 页面：S1-35

## 核对清单

1. `move_to_category` 校验目标分类存在。
2. Copy/Move 文件安全移动到目标分类目录。
3. Indexed 文件只更新分类元数据。
4. 目标同名不覆盖，按冲突规则生成安全名称。

## 完成标准

- 成功后 Tree/List/Detail 可查到新位置。
- 同名冲突、未知分类、Indexed 文件均有测试。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace move_to_category
```
