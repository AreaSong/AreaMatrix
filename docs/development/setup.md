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

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

---

## 第 2 步：Rust 工具链

### 安装 Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
source "$HOME/.cargo/env"
```

验证：

```bash
rustc --version  # rustc 1.75.0 或更高
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

UniFFI 通过 cargo 直接构建，不需额外安装。但需要安装 `uniffi-bindgen` CLI：

```bash
cargo install uniffi-bindgen --locked
```

验证：

```bash
uniffi-bindgen --version
```

---

## 第 4 步：可选但推荐的工具

```bash
# Swift 格式化和检查
brew install swiftformat swiftlint xcbeautify

# Rust 实用工具
cargo install cargo-watch       # 文件改动自动重建
cargo install cargo-llvm-cov    # 覆盖率
cargo install cargo-edit        # cargo add/rm/upgrade
```

---

## 第 5 步：克隆仓库

```bash
git clone https://github.com/<your-org>/AreaMatrix.git
cd AreaMatrix
```

---

## 第 6 步：构建 Rust 核心

```bash
./scripts/build-core.sh
```

这个脚本做了：

1. `cargo build --release --target aarch64-apple-darwin`
2. `cargo build --release --target x86_64-apple-darwin`
3. `lipo` 合并为 universal staticlib
4. `uniffi-bindgen` 生成 Swift bindings
5. 拷贝到 `apps/macos/AreaMatrix/Bridge/Generated/`

如果脚本不存在（仓库初始阶段），见 [build.md](build.md) 手动步骤。

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
cargo test --workspace --all-features
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
./scripts/check-all.sh
```

如果脚本不存在：

```bash
# Rust
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace
cd ..

# Swift
cd apps/macos
swiftformat --lint .
swiftlint --strict
cd ../..
```

---

## 第 9 步：首次运行

1. 在 Xcode 中按 ⌘R 运行
2. 应用启动 → 首次启动向导
3. 选择资料库路径（建议用临时目录测试）：`~/AreaMatrix-dev/`
4. 创建后会自动初始化 6 个分类目录 + DB
5. 拖一个测试文件验证基础功能

---

## 第 10 步：开发循环

| 改动类型 | 怎么重建 |
|---|---|
| 改 Rust 业务代码（不改 UDL） | `./scripts/build-core.sh && Xcode rebuild` |
| 改 Rust 接口（改 UDL） | 同上（脚本会重新生成 bindings） |
| 只改 Swift 代码 | Xcode ⌘R 即可 |
| 只改 SQL schema | 加 migration 文件（不要改 schema.sql v1） |

---

## 常见问题

### Q1: `linker error` / `library not found`

**原因**：Bridge/Generated/ 中的 staticlib 路径错。

**修复**：

```bash
./scripts/build-core.sh
# 然后 Xcode → Product → Clean Build Folder（⇧⌘K）
```

### Q2: Xcode 找不到 Swift bindings

**原因**：bindings 没生成或没被 Xcode 项目引用。

**修复**：

```bash
ls apps/macos/AreaMatrix/Bridge/Generated/
# 应有：area_matrix.swift / area_matrixFFI.h / libarea_matrix_core.a
```

如果文件存在但 Xcode 没识别 → 在 Xcode 项目导航中右键 → Add Files To...

### Q3: `cargo test` 失败 with rusqlite linking issue

**原因**：bundled feature 没启用。

**修复**：检查 `core/Cargo.toml`：

```toml
rusqlite = { version = "0.31", features = ["bundled", "chrono"] }
```

### Q4: 运行时 SQLite 报 `database is locked`

**原因**：多个进程同时打开 DB。

**修复**：检查是不是开了两个 AreaMatrix 实例；或 Spotlight 索引冲突 → 加排除规则：

```bash
sudo mdutil -d ~/AreaMatrix-dev
```

### Q5: `cargo install uniffi-bindgen` 失败

**原因**：UniFFI 需要从对应版本编译 bindgen，要与 `core/Cargo.toml` 中的 `uniffi` 版本一致。

**修复**：

```bash
# 假设 Cargo.toml 中是 uniffi = "0.28"
cargo install uniffi-bindgen --version 0.28
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

## Cargo 工作区结构

`core/Cargo.toml` 是 workspace：

```toml
[workspace]
members = ["area_matrix_core"]
resolver = "2"

[workspace.dependencies]
serde = { version = "1", features = ["derive"] }
# ...
```

子 crate `area_matrix_core` 是 staticlib + cdylib。

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
