# 技术栈

> 记录 AreaMatrix 当前实际使用的语言、框架、依赖、构建工具和平台边界。
>
> 阅读时长：约 5 分钟。

---

## 产品组成

| 层 | 技术 |
|---|---|
| Core | Rust 2021，minimum rust-version 1.75 |
| DB | SQLite / rusqlite bundled，WAL |
| FFI | UniFFI 0.28，UDL + staticlib/cdylib |
| macOS | Swift、SwiftUI、AppKit、CoreServices |
| 构建 | Cargo、Xcode project、仓库根 `./dev` |
| CI | GitHub Actions macOS runner |

macOS deployment target 和 Xcode build settings 以
`apps/macos/AreaMatrix.xcodeproj/project.pbxproj` 为准。app `Info.plist` 由 Xcode 生成。

## Rust 依赖

当前 `core/Cargo.toml` 直接依赖：

| Crate | 版本线 | 用途 |
|---|---|---|
| `uniffi` | 0.28 | FFI scaffolding/bindings |
| `rusqlite` | 0.31 | bundled SQLite、chrono、JSON |
| `serde` / `serde_json` / `serde_yaml` | 1 / 1 / 0.9 | DTO、JSON、YAML |
| `thiserror` | 1 | CoreError |
| `sha2` | 0.10 | SHA-256 |
| `walkdir` | 2 | tree/reindex 遍历 |
| `chrono` | 0.4 | 时间戳 |
| `tracing` | 0.1 | Core 结构化 event 与 span |
| `tracing-subscriber` | 0.3 | Core 进程级 subscriber、过滤与结构化事件层 |
| `unicode-normalization` | 0.1 | 搜索/分类文本归一化 |
| `regex` | 1 | 查询和规则处理 |
| `trash` | 5 | 系统 Trash |
| `uuid` | 1，v4 | token、staging、diagnostics 名称 |

dev dependency 为 `tempfile` 和 `pretty_assertions`。仓库当前没有 Criterion、Tokio 或 Reqwest。

新增依赖必须走 [dependency policy](../development/dependency-policy.md)，不能根据未来设想提前引入。

## Apple 框架

手写 Swift 当前使用 Foundation、SwiftUI、AppKit、CoreServices、Combine 等系统能力，具体 import 以源码为
准。FSEventStream、NSWorkspace、Pasteboard、security bookmark 和 window probing 都
留在平台层。

手写 Swift 通过平台 observability sink 接入 `OSLog` / signpost，并同时维护有界内存、rolling JSONL、incident 和
诊断包。OSLog 只服务 Apple 开发工具，不是便携诊断包的源事实。

macOS target 当前没有第三方 Swift Package。新增 Swift Package 或其他外部依赖必须走
[dependency policy](../development/dependency-policy.md) 的准入、许可证和供应链检查。

## 构建与绑定

```bash
./dev build core
./dev bindings verify
xcodebuild -project apps/macos/AreaMatrix.xcodeproj \
  -scheme AreaMatrix \
  -destination 'platform=macOS,arch=arm64' \
  build CODE_SIGNING_ALLOWED=NO
```

Core 构建目标包括 `rlib`、`staticlib` 和 `cdylib`。macOS 使用 universal Rust static library 和 tracked
Swift/C bindings。

## 数据与运行时

- SQLite bundled，写连接使用 WAL、foreign keys、busy timeout。
- Core 同步 API 由 Swift bridge/model 移出 main actor。
- Core 不安装通用 async runtime。
- Core observability 使用两个专用 std thread 与有界队列隔离 delivery/callback；Swift 使用 actor 与有界 ingress
  交付平台 sink，这不等于引入 Tokio 或通用任务 runtime。
- AI provider/network runtime 使用专用显式模块和环境/配置合同，不进入普通本地文件路径。
- 默认无远程 telemetry 或自动 diagnostics upload。

## 工具链

- Rust stable + rustfmt + clippy。
- Xcode / `xcodebuild`。
- SwiftLint、SwiftFormat。
- cargo-llvm-cov（CI coverage）。
- Python 3（`./dev`、workflow、治理和 release 工具）。

## Related

- [overview.md](overview.md)
- [layered-design.md](layered-design.md)
- [ffi-design.md](ffi-design.md)
- [../development/build.md](../development/build.md)
- [../development/dependency-policy.md](../development/dependency-policy.md)
- [../development/ci-governance.md](../development/ci-governance.md)
