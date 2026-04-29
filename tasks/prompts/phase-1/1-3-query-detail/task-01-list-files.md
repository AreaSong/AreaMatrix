# 1-3/task-01: C1-11 list-files

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现文件列表查询，支撑空库、正常列表、加载态刷新和多选摘要。

## 绑定

- Core 能力：C1-11 list-files
- UX 页面：S1-08, S1-09, S1-10, S1-15

## 核对清单

1. `list_files` 支持 category、include_deleted、时间范围、limit、offset。
2. 默认只返回 active 文件并按 `imported_at DESC` 排序。
3. limit 超上限时 clamp。
4. 空资料库返回空数组。

## 完成标准

- 查询结果与 DB fixture 一致。
- 分页和过滤测试通过。
- 不读取或修改文件系统。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace list_files
```
