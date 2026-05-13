# AreaMatrix Core Agent Guide

## 定位

- 本目录是 AreaMatrix 的 Rust 核心库工程根。
- `Cargo.toml` 必须声明真实 package / workspace 元数据和 Cargo 可识别的最小 lib target。
- Core 层保持平台无关，不依赖 AppKit、SwiftUI、FSEvents 或其他 macOS 专属 API。
- 对外接口在后续 Core API / UDL task 落地时，以 `../docs/api/core-api.md` 和 `area_matrix.udl` 对齐。

## 工作边界

- 执行 `0-2/task-01` 时只维护 crate 元数据；`src/lib.rs` 只能作为 Cargo 最小 lib target，保留 crate 级文档。
- `0-2/task-02` 到达前，不新增模块声明、re-export、业务类型或业务函数。
- `area_matrix.udl`、`build.rs`、`resources/**`、`tests/**` 与业务模块由各自 manifest task 维护。
- 后续任务到达对应 manifest 后，再按该任务边界创建或调整模块、UniFFI、资源或测试。

## 高风险约束

- 不删除、移动、覆盖、重命名用户原文件。
- 不在未确认时实现非空目录接管、reindex、staging recovery、DB migration 或外部变化同步。
- 自动生成内容默认只能写入 `.areamatrix/generated/`。

## 验证

- Cargo metadata task 至少运行：

```bash
cd core && cargo metadata --no-deps
```

- Rust target 存在时同步补充：

```bash
cargo clippy --all-targets --all-features -- -D warnings
cargo fmt --all -- --check
cargo test --workspace
```
