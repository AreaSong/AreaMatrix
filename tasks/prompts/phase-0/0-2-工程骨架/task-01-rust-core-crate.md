# 0-2/task-01: Rust Core Crate 骨架

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-0.md`

## 范围

创建 `core/` Rust crate 的最小可验证骨架，为后续 DB、storage、classify、FFI 实现留出模块边界。

## 核对清单

1. `core/Cargo.toml` 依赖与技术栈文档一致。
2. `core/build.rs` 与 UniFFI scaffolding 方向一致。
3. `core/src/lib.rs` 只做模块声明和必要 re-export。
4. 创建 `api / domain / error / config / db / classify / storage / overview / tree / sync` 模块骨架。
5. 创建默认 `resources/classifier.yaml` 占位内容。

## 完成标准

- `cargo test` 至少能在空实现或基础 smoke test 下通过。
- 没有提前实现后续 storage/classify 业务逻辑。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo test --workspace
```

