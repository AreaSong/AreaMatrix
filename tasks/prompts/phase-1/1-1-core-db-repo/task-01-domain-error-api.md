# 1-1/task-01: Domain、Error 与 API 边界

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

按 Core API 文档建立 Rust domain 类型、错误类型和 `api.rs` 的对外函数边界。

## 核对清单

1. `CoreError` 覆盖文档错误码并能映射到 UniFFI。
2. `FileEntry / RepoConfig / ImportOptions / Filter / Report` 等类型与 `core-api.md` 对齐。
3. `api.rs` 暴露函数签名，但只实现当前任务必要的基础行为。
4. 所有 `pub` 项有 rustdoc。

## 完成标准

- Rust 类型和 UDL 设计没有明显冲突。
- 基础编译和类型测试通过。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace
```

