# 1-3/task-02: C1-12 get-file-detail

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现单文件详情查询，供详情元数据和多选摘要消费。

## 绑定

- Core 能力：C1-12 get-file-detail
- UX 页面：S1-12, S1-15

## 核对清单

1. `get_file` 按 file_id 返回完整 `FileEntry`。
2. 不存在、已删除或 repo 未初始化时返回结构化错误。
3. 字段与 `docs/api/core-api.md` 和 UDL 一致。
4. 查询不修改 DB 或文件系统。

## 完成标准

- Detail UI 所需字段无需再从 path 反推。
- `FileNotFound` 和正常返回均有测试。
- 与 `list_files` 返回同一条记录时字段一致。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace get_file
```
