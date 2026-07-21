# 构建与运行

> 详解 AreaMatrix 的构建流水线：Rust core → universal staticlib → Swift bindings → Xcode app。
>
> 阅读时长：约 5 分钟。

---

## 总览

```mermaid
flowchart LR
    UDL[area_matrix.udl]
    RS[Rust 源码]
    UDL --> Scaffold[build.rs<br/>uniffi scaffolding]
    Scaffold --> Cargo
    RS --> Cargo[cargo build]
    Cargo --> ARM[libarea_matrix_core.a aarch64]
    Cargo --> X86[libarea_matrix_core.a x86_64]
    ARM --> Lipo[lipo merge]
    X86 --> Lipo
    Lipo --> Universal[Universal staticlib]
    UDL --> BindGen[uniffi-bindgen]
    BindGen --> SwiftFile[area_matrix.swift]
    BindGen --> Header[area_matrixFFI.h]
    Universal --> XcodeBuild
    SwiftFile --> XcodeBuild
    Header --> XcodeBuild
    XcodeBuild[xcodebuild] --> App[AreaMatrix.app]
```

---

## Core 构建入口

`./dev build core` 是仓库根目录 `./dev` 的 CLI 子命令，不是独立脚本文件。
根入口 `dev` 先进入 `scripts.task_loop.console`；非交互子命令再由 console 转交
`scripts.dev_tools.cli`。构建实现位于 `scripts/dev_tools/build.py`。

```bash
./dev build core --help
```

当前子命令执行以下步骤：

1. 检查 `cargo`、`rustc`、`lipo`、`core/Cargo.toml`、`core/area_matrix.udl` 和 `core/build.rs`。
2. 确认当前 host 是 macOS Rust host。
3. 构建 `aarch64-apple-darwin` 与 `x86_64-apple-darwin` 两个 target。
4. 用 `lipo` 合并 `apps/macos/AreaMatrix/Bridge/Generated/libarea_matrix_core.a`。
5. 使用 host dylib 与 `core/area_matrix.udl` 生成 Swift bindings。

默认输出目录 `apps/macos/AreaMatrix/Bridge/Generated/` 是 `.gitignore` 忽略的本地生成产物目录，
用于检查 universal staticlib 与最新 bindings。当前 Xcode 工程消费的 tracked bindings 位于
`apps/macos/AreaMatrix/Bridge/UniFFI/`，并直接链接 `core/target/aarch64-apple-darwin/<profile>/libarea_matrix_core.a`。

常用参数：

```bash
./dev build core
./dev build core --profile debug
./dev build core --out-dir /tmp/areamatrix-generated
./dev build core --deployment-target 14.0
```

---

## Cargo.toml 模板

`core/Cargo.toml`：

```toml
[package]
name = "area_matrix_core"
version = "0.1.0"
edition = "2021"
rust-version = "1.75"
license = "PolyForm-Noncommercial-1.0.0"
publish = false

[workspace]
resolver = "2"

[lib]
name = "area_matrix_core"
crate-type = ["rlib", "staticlib", "cdylib"]

[dependencies]
uniffi = { version = "0.28", features = ["build"] }
rusqlite = { version = "0.31", features = ["bundled", "chrono", "serde_json"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
serde_yaml = "0.9"
thiserror = "1"
sha2 = "0.10"
walkdir = "2"
chrono = { version = "0.4", features = ["serde"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
unicode-normalization = "0.1"
regex = "1"
trash = "5"
uuid = { version = "1", features = ["v4"] }

[build-dependencies]
uniffi = { version = "0.28", features = ["build"] }

[dev-dependencies]
tempfile = "3"
pretty_assertions = "1"
```

---

## build.rs

`core/build.rs`：

```rust
fn main() {
    uniffi::generate_scaffolding("./area_matrix.udl").expect("generate UniFFI scaffolding");
}
```

---

## Xcode 集成

当前 `apps/macos/AreaMatrix.xcodeproj` 已配置好 Core 静态库和 tracked UniFFI bindings：

- Build Phase `Build Core Static Library` 构建 `core/target/aarch64-apple-darwin/$(AREAMATRIX_CORE_PROFILE)/libarea_matrix_core.a`。
- `LIBRARY_SEARCH_PATHS` 指向 `$(SRCROOT)/../../core/target/aarch64-apple-darwin/$(AREAMATRIX_CORE_PROFILE)`。
- `OTHER_LDFLAGS` 使用 `-larea_matrix_core`。
- Swift source 引用 `AreaMatrix/Bridge/UniFFI/area_matrix.swift`。
- Bridging header 引用 `Bridge/UniFFI/area_matrixFFI.h`。

### 更新 tracked bindings

如果 `core/area_matrix.udl` 的公开接口变更，并且需要提交 Xcode 工程实际消费的 Swift bindings，
先构建包含当前 UniFFI metadata 的 host dylib，再将 bindings 显式生成到 `Bridge/UniFFI/`：

```bash
./dev build core
./dev bindings update --udl core/area_matrix.udl --out-dir apps/macos/AreaMatrix/Bridge/UniFFI
./dev bindings verify
```

`./dev bindings verify` 只在临时目录生成并比较 `area_matrix.swift`、`area_matrixFFI.h` 与
`module.modulemap`，不会改写 tracked bindings。CI 在 Core build 后运行该命令，阻止 UDL、生成器
输出与 Xcode 实际消费的 bindings 漂移。默认生成器固定为 `core/Cargo.lock` 中的 UniFFI 版本；
只有显式设置 `UNIFFI_BINDGEN` 或 `AREAMATRIX_UNIFFI_BINDGEN` 时才覆盖该版本。

### Bridging Header 配置

`apps/macos/AreaMatrix/AreaMatrix-Bridging-Header.h`：

```c
#import "Bridge/UniFFI/area_matrixFFI.h"
#import <sqlite3.h>
```

除 UniFFI 生成头文件外，bridging header 还引入系统 `sqlite3.h`：Swift 平台层的只读
metadata probe 直接以只读方式打开 SQLite，不经过 Core 写路径。

在 Build Settings 中：

- `Objective-C Bridging Header` → `AreaMatrix/AreaMatrix-Bridging-Header.h`
- `Header Search Paths` → `$(SRCROOT)/AreaMatrix/Bridge/UniFFI`
- `Library Search Paths` → `$(SRCROOT)/../../core/target/aarch64-apple-darwin/$(AREAMATRIX_CORE_PROFILE)`
- `Other Linker Flags` → `-larea_matrix_core`

---

## 调试构建

### Debug 配置

```bash
./dev build core --profile debug
```

调试时 `cargo build` 默认 debug，体积大但启动快、含 panic 信息。

### Release 配置（默认）

```bash
./dev build core
```

启用所有优化，体积小。

### 尺寸优化（CI 发布版）

`Cargo.toml` 加：

```toml
[profile.release]
opt-level = "z"
lto = true
codegen-units = 1
strip = true
panic = "abort"
```

---

## 增量构建

### 改 Rust 代码（不动 UDL）

```bash
./dev build core   # ~30s 增量
# 然后 Xcode 自动检测 staticlib 改动并重新链接
```

### 改 UDL

```bash
./dev build core   # ~45s 增量（含 bindings 重生成）
# Xcode 重新编译 area_matrix.swift
```

### 只改 Swift

直接 Xcode ⌘R。

---

## 持续集成

详见 `.github/workflows/core-ci.yml` 和 `.github/workflows/macos-ci.yml`。

CI 在 macos-14 runner 上执行：

1. `cargo fmt --all -- --check`
2. `cargo clippy --all-targets --all-features -- -D warnings`
3. `cargo test --all-features --workspace`
4. `cargo llvm-cov --fail-under-lines 70`
5. `./dev build core`
6. `./dev test macos`
7. `cd apps/macos && swiftformat --lint . --config ../../scripts/dev_tools/swiftformat.conf --exclude AreaMatrix/Bridge/Generated,AreaMatrix/Bridge/UniFFI,DerivedData --cache ignore`
8. `cd apps/macos && swiftlint lint --strict --config ../../scripts/dev_tools/swiftlint.yml --force-exclude . --no-cache`

PR 要全绿才能合并。

---

## 发布构建

面向用户分发的构建必须来自固定且已验证的 commit，并完成 Developer ID 签名、公证、DMG、checksum 和干净 Mac 首启验证。本机构建、ad-hoc 签名或同机 smoke 只能证明工程可运行，不能标记为可分发。

发布工具中的状态、审计和产物探针只用于汇总或读取证据，不能替代真实外部验证。具体发布步骤、凭据边界和回滚要求见 [发布流程](release.md)；历史记录通过 [workflow versions](../../workflow/versions/README.md) 查阅。

### 版本号

更新：

- `core/Cargo.toml` 的 `version`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj` 的 `MARKETING_VERSION` /
  `CURRENT_PROJECT_VERSION`；app `Info.plist` 由 Xcode 生成
- `CHANGELOG.md` 的 `[Unreleased]` 段落改为 `[x.y.z] - YYYY-MM-DD`

### 签名 + 公证（用户分发版）

```bash
# 1. 构建 release
./dev build core
xcodebuild -project apps/macos/AreaMatrix.xcodeproj \
  -scheme AreaMatrix \
  -configuration Release \
  -derivedDataPath build/

# 2. Code sign
codesign --deep --force \
  --options runtime \
  --sign "Developer ID Application: <your name>" \
  --entitlements apps/macos/AreaMatrix/AreaMatrix.entitlements \
  build/Build/Products/Release/AreaMatrix.app

# 3. 打包 + 公证
ditto -c -k --keepParent build/Build/Products/Release/AreaMatrix.app AreaMatrix.zip
xcrun notarytool submit AreaMatrix.zip \
  --keychain-profile "AC_PASSWORD" \
  --wait

# 4. Stapler
xcrun stapler staple build/Build/Products/Release/AreaMatrix.app

# 5. 制作 DMG（可选）
hdiutil create -volname "AreaMatrix" -srcfolder build/Build/Products/Release/AreaMatrix.app \
  -ov -format UDZO AreaMatrix-x.y.z.dmg
```

详见 [release.md](release.md)。

---

## 故障排查

### 缺少 macOS universal build Rust target

错误：`missing Rust target 'x86_64-apple-darwin'`。

`./dev build core` 和 `./dev check all` 会构建 `aarch64-apple-darwin` 与
`x86_64-apple-darwin` 两个 staticlib 后用 `lipo` 合并 universal library；缺少任一
target 都不能把 macOS checks 视为通过。

```bash
rustup target add x86_64-apple-darwin
./dev check all
```

若 `rustup target add` 失败，先修复本机 Rust toolchain / registry cache 后重试；不得把缺失
target 的 macOS universal build 视为通过。补齐 target 后还需确保 `swiftformat` 与
`swiftlint` 在 PATH 中，否则 `./dev check all` 会继续在 Swift lint gate 失败。

当前 Codex sandbox 的已知阻断形态：

- 默认 `rustup target add x86_64-apple-darwin` 可能在 component 下载或缓存清理时失败。
- 使用临时 `RUSTUP_HOME` 复核时，若无法解析 `static.rust-lang.org`，说明当前环境不能补齐
  Rust target。
- `brew install swiftformat swiftlint` 需要 Homebrew prefix 与 cache 可写；若 `/opt/homebrew`
  或 `~/Library/Caches/Homebrew` 不可写，不能在本环境补齐 SwiftFormat / SwiftLint。

这些都属于发布工具链阻断。记录阻断可以作为 release checklist 证据，但不能替代
`./dev check all` 通过。

### `lipo` 失败：`fat file already exists`

```bash
rm -f apps/macos/AreaMatrix/Bridge/Generated/libarea_matrix_core.a
./dev build core
```

### `uniffi-bindgen` 版本不匹配

错误：`scaffolding generated by uniffi 0.28.x but bindgen is 0.27.x`。

默认机制下生成器版本锁定为 `core/Cargo.lock` 中的 UniFFI 版本，不会漂移。出现该错误说明
`UNIFFI_BINDGEN` / `AREAMATRIX_UNIFFI_BINDGEN` 指向了版本不匹配的 bindgen：取消该环境变量
回到默认机制，或改为指向匹配版本，然后重跑 `./dev build core`。

### Xcode 报 `module 'area_matrix' not found`

`area_matrix.swift` 没被加进 target。检查 Xcode 项目导航中文件是否在 AreaMatrix target 下。

### SQLite busy / locked

Core 可写连接已设置 WAL 和 5 秒 `busy_timeout`。持续锁冲突时先确认没有同时运行的 AreaMatrix、测试进程
或手工 `sqlite3` 会话。不要对正在运行的资料库执行会写入的 SQLite 命令；需要人工检查时先退出应用并
保留 `index.db`、WAL 和 SHM。

---

## Related

- [setup.md](setup.md)
- [release.md](release.md)
- [troubleshooting.md](troubleshooting.md)
- [../architecture/ffi-design.md](../architecture/ffi-design.md)
- [../api/uniffi-recipes.md](../api/uniffi-recipes.md)
