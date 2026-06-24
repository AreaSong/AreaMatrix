# AreaMatrix Core Agent Guide

## 定位

- 本目录是 AreaMatrix 的 Rust 核心库工程根。
- `Cargo.toml` 必须声明真实 package / workspace 元数据和 Cargo 可识别的 lib target。
- Core 层保持平台无关，不依赖 AppKit、SwiftUI、FSEvents 或其他 macOS 专属 API。
- Core 已进入实现态；对外接口、UDL、Rust 实现和测试都按当前仓库真实状态维护。
- 对外 Core API 变化必须先对齐 `../docs/api/core-api.md`，再同步 `area_matrix.udl`、Rust 实现和平台桥接。

## 工作边界

- `src/lib.rs` 保持轻量：只放 crate 文档、module declaration 和必要 re-export，不堆业务逻辑。
- `src/api/` 是 UniFFI 对外门面目录：按 surface 拆分公开函数，保留函数名与 UDL 合同一致，不在这里堆业务流程、SQL 或复杂文件操作。
- 业务能力放在对应模块中，优先沿用现有模块边界和测试命名模式。
- `area_matrix.udl` 是 Swift / 其他平台桥接的接口合同；新增、删除或重命名公开函数时必须与 `../docs/api/core-api.md` 保持一致。
- `build.rs` 负责 UniFFI scaffolding，当前从 `./area_matrix.udl` 生成；不要改成已不存在的 `src/area_matrix.udl` 路径。
- `tests/**` 承载 Core API 合同、实现、失败恢复、验证和集成回归；新增能力优先补匹配粒度的测试。
- `resources/**`、DB schema、migration、staging、recovery、sync、import、reindex 等文件安全边界按根 `AGENTS.md` 的高风险规则处理。

## 高风险约束

- 不删除、移动、覆盖、重命名用户原文件。
- 不在未确认时实现非空目录接管、reindex、staging recovery、DB migration 或外部变化同步。
- 自动生成内容默认只能写入 `.areamatrix/generated/`。

## 验证

- Core 文档或低风险元数据改动可至少运行：

```bash
cd core && cargo metadata --no-deps
```

- Rust Core 行为、API、UDL 或测试改动按影响面运行：

```bash
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace
```

- Prompt task 内的 Core 改动优先使用 task-scoped gate：

```bash
./dev check task <label>
```

- 若改动影响 Swift bridge 或生成物，同步运行对应 `./dev build core` / `./dev bindings update` 检查，并说明无法运行的原因。
