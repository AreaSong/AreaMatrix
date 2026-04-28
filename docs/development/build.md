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

## 完整构建脚本

文件：`scripts/build-core.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${PROJECT_ROOT}/core"
OUT_DIR="${PROJECT_ROOT}/apps/macos/AreaMatrix/Bridge/Generated"
PROFILE="${BUILD_PROFILE:-release}"

echo "==> Building core ($PROFILE)"

cd "${CORE_DIR}"

# 1. 构建两个 target 的 staticlib
cargo build --${PROFILE} --target aarch64-apple-darwin
cargo build --${PROFILE} --target x86_64-apple-darwin

# 2. 创建输出目录
mkdir -p "${OUT_DIR}"

# 3. lipo 合并
lipo -create \
    "target/aarch64-apple-darwin/${PROFILE}/libarea_matrix_core.a" \
    "target/x86_64-apple-darwin/${PROFILE}/libarea_matrix_core.a" \
    -output "${OUT_DIR}/libarea_matrix_core.a"

# 4. 生成 Swift bindings
echo "==> Generating Swift bindings"
uniffi-bindgen generate \
    --library "target/aarch64-apple-darwin/${PROFILE}/libarea_matrix_core.dylib" \
    --language swift \
    --out-dir "${OUT_DIR}"

# 5. 报告
echo "==> Done"
echo "    staticlib: ${OUT_DIR}/libarea_matrix_core.a"
echo "    swift:     ${OUT_DIR}/area_matrix.swift"
echo "    header:    ${OUT_DIR}/area_matrixFFI.h"
```

赋可执行权限：

```bash
chmod +x scripts/build-core.sh
```

---

## Cargo.toml 模板

`core/Cargo.toml`：

```toml
[package]
name = "area_matrix_core"
version = "0.1.0"
edition = "2021"
license = "PolyForm-Noncommercial-1.0.0"
publish = false

[lib]
name = "area_matrix_core"
crate-type = ["staticlib", "cdylib"]

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
    uniffi::generate_scaffolding("./area_matrix.udl").unwrap();
}
```

---

## Xcode 集成

### 添加 staticlib

1. Xcode 项目导航 → 右键项目 → Add Files To "AreaMatrix"
2. 选 `apps/macos/AreaMatrix/Bridge/Generated/libarea_matrix_core.a`
3. Target Membership 勾上 AreaMatrix

### 添加生成的 Swift 文件

1. 同样方式添加 `area_matrix.swift`

### Bridging Header 配置

虽然 Swift 与 Rust 通过自动生成的 `area_matrix.swift` 通信，但 UniFFI 仍需要 C 头：

`apps/macos/AreaMatrix/AreaMatrix-Bridging-Header.h`：

```c
#import "Bridge/Generated/area_matrixFFI.h"
```

在 Build Settings 中：

- `Objective-C Bridging Header` → `AreaMatrix/AreaMatrix-Bridging-Header.h`
- `Header Search Paths` → `$(SRCROOT)/AreaMatrix/Bridge/Generated`
- `Library Search Paths` → `$(SRCROOT)/AreaMatrix/Bridge/Generated`
- `Other Linker Flags` → `-larea_matrix_core`

---

## 调试构建

### Debug 配置

```bash
BUILD_PROFILE=debug ./scripts/build-core.sh
```

调试时 `cargo build` 默认 debug，体积大但启动快、含 panic 信息。

### Release 配置（默认）

```bash
./scripts/build-core.sh
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
./scripts/build-core.sh   # ~30s 增量
# 然后 Xcode 自动检测 staticlib 改动并重新链接
```

### 改 UDL

```bash
./scripts/build-core.sh   # ~45s 增量（含 bindings 重生成）
# Xcode 重新编译 area_matrix.swift
```

### 只改 Swift

直接 Xcode ⌘R。

---

## 持续集成

详见 `.github/workflows/core-ci.yml` 和 `.github/workflows/macos-ci.yml`。

CI 在 macos-14 runner 上执行：

1. `cargo fmt --check`
2. `cargo clippy -- -D warnings`
3. `cargo test --workspace`
4. `cargo llvm-cov --fail-under-lines 70`
5. `./scripts/build-core.sh`
6. `xcodebuild test`
7. `swiftformat --lint`
8. `swiftlint --strict`

PR 要全绿才能合并。

---

## 发布构建（Stage 2 起激活）

### 版本号

更新：

- `core/Cargo.toml` 的 `version`
- `apps/macos/AreaMatrix/Info.plist` 的 `CFBundleShortVersionString` / `CFBundleVersion`
- `CHANGELOG.md` 的 `[Unreleased]` 段落改为 `[x.y.z] - YYYY-MM-DD`

### 签名 + 公证（用户分发版）

```bash
# 1. 构建 release
./scripts/build-core.sh
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

### `lipo` 失败：`fat file already exists`

```bash
rm -f apps/macos/AreaMatrix/Bridge/Generated/libarea_matrix_core.a
./scripts/build-core.sh
```

### `uniffi-bindgen` 版本不匹配

错误：`scaffolding generated by uniffi 0.28.x but bindgen is 0.27.x`。

```bash
cargo install uniffi-bindgen --force --version <匹配 Cargo.toml 的版本>
```

### Xcode 报 `module 'area_matrix' not found`

`area_matrix.swift` 没被加进 target。检查 Xcode 项目导航中文件是否在 AreaMatrix target 下。

### Spotlight 频繁锁 SQLite

```bash
sudo mdutil -d ~/AreaMatrix-dev/.areamatrix/index.db
```

或在用户配置中将 `.areamatrix/` 加到 Spotlight 隐私列表。

---

## Related

- [setup.md](setup.md)
- [release.md](release.md)
- [troubleshooting.md](troubleshooting.md)
- [../architecture/ffi-design.md](../architecture/ffi-design.md)
- [../api/uniffi-recipes.md](../api/uniffi-recipes.md)
