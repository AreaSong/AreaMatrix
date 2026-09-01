# 开发环境搭建

> 从零搭建 AreaMatrix 开发环境的完整步骤。预计耗时 30-60 分钟。
>
> 阅读时长：约 5 分钟。

---

## 系统要求

- macOS 14 Sonoma 或更高版本
- 至少 20 GB 可用磁盘空间（Xcode + Rust + 缓存）
- 网络连接（拉依赖）

---

## 第 1 步：基础工具

### Xcode

从 App Store 安装 Xcode 15+。安装后启动一次接受协议：

```bash
sudo xcodebuild -license accept
```

验证：

```bash
xcodebuild -version
# Xcode 15.4
```

### Command Line Tools

```bash
xcode-select --install
```

### Homebrew

按 Homebrew 官方安装页执行安装命令。

---

## 第 2 步：Rust 工具链

### 安装 Rust

从 [rustup 官方安装说明](https://rustup.rs/)下载适合当前平台与架构的 `rustup-init`，并按同一发布的
官方校验信息核对下载文件后再执行。不要把网络响应直接通过管道交给 shell。安装 `rustup` 后，固定安装
仓库声明的工具链和组件：

```bash
rustup toolchain install 1.88.0 \
  --profile minimal \
  --component rustfmt \
  --component clippy \
  --component llvm-tools-preview
rustup default 1.88.0
```

验证：

```bash
rustc --version  # rustc 1.88.0
cargo --version
```

### 安装 macOS targets

```bash
rustup target add aarch64-apple-darwin
rustup target add x86_64-apple-darwin
```

### Rust 工具组件

```bash
rustup component add rustfmt clippy llvm-tools-preview
```

---

## 第 3 步：UniFFI 工具

不需要手工安装 `uniffi-bindgen` CLI：uniffi 0.28 起该独立 crate 不再发布可执行文件，
`cargo install uniffi-bindgen` 已不可用。`./dev build core` 生成 Swift bindings 时，
`scripts/dev_tools/build.py` 会按 `core/Cargo.lock` 锁定的 UniFFI 版本构建并缓存一个
bindgen wrapper，保证生成器与 scaffolding 版本一致，因此这一步没有额外操作。

构建脚本不接受 `UNIFFI_BINDGEN` 或 `AREAMATRIX_UNIFFI_BINDGEN` 外部可执行文件覆盖。这样可以避免
未经登记的生成器污染 Swift/C bindings；需要升级生成器时必须先更新 `core/Cargo.lock`，再由受审的
locked wrapper 生成。

---

## 第 4 步：可选但推荐的工具

```bash
# Swift 格式化和检查
brew install swiftformat swiftlint xcbeautify

# Rust 实用工具：项目构建不依赖这些全局安装。CI 使用 workflow 中固定的版本；本机若需要额外工具，
# 请通过组织批准的包管理流程安装并记录版本、来源与校验值，不要把浮动的 cargo install 作为发布前提。
```

---

## 第 5 步：克隆仓库

```bash
git clone https://github.com/AreaSong/AreaMatrix.git
cd AreaMatrix
```

---

## 第 6 步：构建 Rust 核心

```bash
./dev build core-sdk
```

这个 CLI 子命令在隔离的 `.build/cargo/sdk/` lane 中构建 Rust，并在 fingerprint cache 中生成：

1. macOS arm64/x86_64 universal staticlib
2. iOS device arm64 staticlib
3. iOS simulator arm64/x86_64 universal staticlib
4. `uniffi-bindgen` Swift/C bindings
5. `.build/core-sdk/current/AreaMatrixCoreFFI.xcframework` 与 Swift Package

`Bridge/Generated/` 是 `.gitignore` 忽略的生成产物目录。当前 Xcode 工程实际消费的 tracked
bindings 位于 `apps/macos/AreaMatrix/Bridge/UniFFI/`，构建参数、Xcode 集成和 binding 更新方式见
[build.md](build.md)。

---

## 第 7 步：打开 Xcode 项目

```bash
open apps/macos/AreaMatrix.xcodeproj
```

或者只用命令行：

```bash
xcodebuild -project apps/macos/AreaMatrix.xcodeproj \
  -scheme AreaMatrix \
  -destination 'platform=macOS,arch=arm64' \
  build
```

---

## 第 8 步：运行单元测试

### Rust 侧

```bash
cd core
cargo test --locked --workspace --all-features
```

### macOS 侧

```bash
xcodebuild test \
  -project apps/macos/AreaMatrix.xcodeproj \
  -scheme AreaMatrix \
  -destination 'platform=macOS,arch=arm64' \
  | xcbeautify
```

---

## 验证全流程

```bash
# 全套构建 + 测试 + lint
./dev check all
```

如果需要手动拆开检查：

```bash
# Rust
cd core
cargo fmt --all -- --check
cargo clippy --locked --all-targets --all-features -- -D warnings
cargo test --locked --workspace
cd ..

# Swift（与 ./dev check 使用的命令一致，避免把生成绑定卷进检查）
cd apps/macos
swiftformat --lint . --config ../../scripts/dev_tools/swiftformat.conf \
  --exclude AreaMatrix/Bridge/Generated,AreaMatrix/Bridge/UniFFI,DerivedData --cache ignore
swiftlint lint --strict --config ../../scripts/dev_tools/swiftlint.yml --force-exclude . --no-cache
cd ../..
```

---

## 第 9 步：首次运行

1. 在 Xcode 中按 ⌘R 运行
2. 应用启动 → 首次启动向导
3. 选择资料库路径（建议用临时目录测试）：`~/AreaMatrix-dev/`
4. 空目录会初始化默认分类 + DB；非空目录会进入接管流程并先建立索引
5. 拖一个测试文件验证基础功能

---

## 第 10 步：开发循环

| 改动类型 | 怎么重建 |
|---|---|
| 改 Rust 业务代码（不改 UDL） | `./dev build core-sdk && Xcode rebuild` |
| 改 Rust 接口（改 UDL） | 构建 CoreSDK，更新 tracked bindings，再运行 `./dev bindings verify` |
| 只改 Swift 代码 | Xcode ⌘R 即可 |
| 只改 SQL schema | 加 migration 文件（不要改 schema.sql v1） |

`./dev test macos` 默认复用 `.build/derived-data/macos-tests/`，因此重复定向测试可以增量编译。
只有需要验证完全隔离环境时才使用 `--temporary-derived-data`；显式 `--derived-data-path` 适合 CI
或并行任务。Cargo 验证命令应使用 `.build/cargo/validation/`，不要复用 CoreSDK 的
`.build/cargo/sdk/`。

---

## 常见问题

### Q1: `linker error` / `library not found`

**原因**：`.build/core-sdk/current/AreaMatrixCoreFFI.xcframework` 尚未生成、指纹缓存不完整，或
Xcode Frameworks 引用失效。

**修复**：

```bash
./dev build core-sdk
# 然后 Xcode → Product → Clean Build Folder（⇧⌘K）
```

### Q2: Xcode 找不到 Swift bindings

**原因**：bindings 没生成或没被 Xcode 项目引用。

**修复**：

```bash
ls apps/macos/AreaMatrix/Bridge/UniFFI/
# Xcode 应引用：area_matrix.swift / area_matrixFFI.h / module.modulemap
```

如果 `core/area_matrix.udl` 刚修改过，先按 [build.md](build.md) 的 tracked bindings 更新命令重生
`Bridge/UniFFI/` 后再 Clean Build Folder。

### Q3: `cargo test` 失败 with rusqlite linking issue

**原因**：bundled feature 没启用。

**修复**：检查 `core/Cargo.toml`：

```toml
rusqlite = { version = "0.31", features = ["bundled", "chrono", "serde_json"] }
```

### Q4: 运行时 SQLite 报 `database is locked`

**原因**：多个进程同时打开 DB。

**修复**：检查是不是开了两个 AreaMatrix 实例；或 Spotlight 索引冲突 → 加排除规则：

```bash
sudo mdutil -d ~/AreaMatrix-dev
```

### Q5: 生成 Swift bindings 时报 bindgen 相关错误

**原因**：构建脚本按 `core/Cargo.lock` 锁定版本构建缓存 bindgen wrapper，依赖本地 Cargo
registry 缓存可用；或者 `UNIFFI_BINDGEN` / `AREAMATRIX_UNIFFI_BINDGEN` 指向了版本不匹配的
bindgen。

**修复**：

```bash
# 补齐锁定依赖缓存后重试
cd core && cargo fetch --locked && cd ..
# 若设置过 UNIFFI_BINDGEN / AREAMATRIX_UNIFFI_BINDGEN，先取消或指向匹配版本
./dev build core
```

---

## 推荐编辑器

### VS Code（推荐用于 Rust）

扩展：

- rust-lang.rust-analyzer
- vadimcn.vscode-lldb（调试）
- tamasfe.even-better-toml

### Xcode（推荐用于 Swift）

主用 Xcode 编辑 SwiftUI（实时预览体验最佳）。

### Cursor / Zed（备选）

也都可用，rust-analyzer 通用。

---

## Cargo 工程结构

当前 `core/Cargo.toml` 是 `area_matrix_core` 单 crate 的 manifest，并在同一文件中声明
Cargo workspace resolver：

```toml
[package]
name = "area_matrix_core"
version = "0.1.0"
edition = "2021"

[workspace]
resolver = "2"

[lib]
name = "area_matrix_core"
crate-type = ["rlib", "staticlib", "cdylib"]
```

如果未来拆成多 crate，再同步更新 `core/Cargo.toml`、本文档和构建脚本。

---

## 下一步

- 阅读 [build.md](build.md) 了解构建流程细节
- 阅读 [coding-standards.md](coding-standards.md) 了解编码规范
- 阅读 [git-workflow.md](git-workflow.md) 了解分支管理

---

## Related

- [build.md](build.md)
- [coding-standards.md](coding-standards.md)
- [testing.md](testing.md)
- [troubleshooting.md](troubleshooting.md)
- [observability.md](observability.md)
- [performance.md](performance.md)
- [../architecture/tech-stack.md](../architecture/tech-stack.md)
