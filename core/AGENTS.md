# AreaMatrix Core Agent Guide

## 定位

- 本目录是 AreaMatrix 的 Rust 核心库。
- Core 层保持平台无关，不依赖 AppKit、SwiftUI、FSEvents 或其他 macOS 专属 API。
- 对外接口以 `../docs/api/core-api.md` 和 `area_matrix.udl` 为准。

## 工作边界

- `src/lib.rs` 只保留模块声明、UniFFI scaffolding 和必要 re-export。
- 业务实现进入对应模块：`api`、`domain`、`error`、`config`、`db`、`classify`、`storage`、`overview`、`tree`、`sync`。
- 不提前实现后续任务未要求的 DB、storage、classify、sync 业务逻辑。

## 高风险约束

- 不删除、移动、覆盖、重命名用户原文件。
- 不在未确认时实现非空目录接管、reindex、staging recovery、DB migration 或外部变化同步。
- 自动生成内容默认只能写入 `.areamatrix/generated/`。

## 验证

- Core 改动后优先运行：

```bash
cargo fmt --all -- --check
cargo test --workspace
```

- 涉及真实业务逻辑后，再补充：

```bash
cargo clippy --all-targets --all-features -- -D warnings
```
