# 技术栈与选型理由

> AreaMatrix 选择 **Rust 核心库 + SwiftUI macOS 原生 UI + UniFFI 桥接** 的组合。本文给出每个选择的理由、考虑过的备选、什么时候应该重新审视。
>
> 阅读时长：约 7 分钟。

---

## 总览

| 层 | 技术 | 版本约束 |
|---|---|---|
| 核心库语言 | Rust | 1.75+ stable |
| 元数据存储 | SQLite | 通过 rusqlite bundled |
| FFI 桥接 | UniFFI | 0.28+ |
| 平台 / UI | SwiftUI + AppKit | macOS 14 Sonoma+ |
| Swift 工具链 | Xcode 15+ | Swift 5.9+ |
| 构建脚本 | Bash | macOS 自带 |
| CI | GitHub Actions | macos-14 runner |
| 包管理（构建期） | cargo + Xcode SPM | - |

---

## 1. 核心库选择 Rust

### 决策

业务逻辑（文件操作、分类、SQLite 访问、资料库概览生成）全部用 Rust 实现，编译为平台静态库（`staticlib` + `cdylib`）。

### 理由

1. **跨平台核心**：编译到 macOS / Windows / Linux / iOS / Android 都可行
2. **零运行时**：不带 GC，不带虚拟机，启动快、内存稳定
3. **IO 性能**：文件操作、哈希计算、SQLite 访问对比 Python/Node 有 3-5 倍优势
4. **类型系统强**：业务规则用 enum/struct + Result 表达，编译期捕获大量错误
5. **可移植 binding**：UniFFI 自动生成 Swift / Kotlin / Python 绑定，未来扩端零成本
6. **生态成熟**：rusqlite / serde / tokio / sha2 / walkdir 都是工业级

### 考虑过的备选

| 备选 | 为什么不选 |
|---|---|
| Swift 原生（不抽核心库） | 扩到 Windows / Linux 时业务代码全部重写 |
| C++ | 工程化和内存安全相比 Rust 退步明显 |
| Go | FFI 复杂、GC 不可控、binding 不成熟 |
| Kotlin Multiplatform | macOS 端体验需要 Compose Desktop 或重写 SwiftUI |
| Python | 性能不达标、打包成桌面应用麻烦 |

### 何时重新审视

- 团队全面转向其他语言生态
- 业务复杂度大幅下降，跨平台不再重要
- Rust 工具链遇到无法绕过的阻塞（极小概率）

详见 [../adr/0001-tech-stack.md](../adr/0001-tech-stack.md)。

---

## 2. UI 选择 SwiftUI（macOS 14+）

### 决策

macOS 端 UI 用 SwiftUI 实现，最低支持 macOS 14 Sonoma。

### 理由

1. **100% 原生体验**：Drag & Drop / Quick Look / Dark Mode / VoiceOver / Spotlight 集成都最舒服
2. **未来复用 iOS**：SwiftUI 在 macOS 与 iOS 之间复用率约 70%，未来上 iOS 工作量小
3. **macOS 14+ 的 API 显著好于 13**：`@Observable` 宏、新树状图组件、`Inspector`、新 Toolbar、async sequence binding，这些 API 让代码量减少 30%+
4. **Apple 持续投入**：SwiftUI 是 Apple 长期方向，技术债风险最小

### 考虑过的备选

| 备选 | 为什么不选 |
|---|---|
| AppKit（Cocoa） | 代码量大、心智负担重、不利于未来 iOS 复用 |
| Tauri 2 + React | WebView 体验略次于原生，与"做精一个 macOS 工具"的定位不匹配 |
| Electron | 包体大、内存高、与原生体验差距大 |
| Flutter Desktop | 桌面端不够成熟、文件系统集成弱 |
| Qt / PySide6 | UI 不够 Apple 风格、打包复杂 |
| egui / Iced | UI 库太少，做不出产品级界面 |

### 何时重新审视

- macOS 14 之前的版本占比再次成为问题（不太可能，2027 年只会更少）
- SwiftUI 出现重大设计回退（极小概率）
- 团队主力放弃 macOS 优先策略

详见 [../adr/0009-min-macos-version.md](../adr/0009-min-macos-version.md)。

---

## 3. FFI 桥接选择 UniFFI

### 决策

Rust 与 Swift 的跨语言调用通过 UniFFI 0.28+ 实现，UDL（UniFFI Definition Language）描述接口。

### 理由

1. **工业级验证**：Firefox iOS、Bitwarden、Signal、Matrix Rust SDK 都在用
2. **跨语言扩展性**：未来加 Kotlin（Android）/ Python binding 几乎零成本
3. **类型支持完备**：基本类型、struct、enum、Result、Option、Vec 全覆盖
4. **错误处理清晰**：UniFFI Error enum 自动映射到 Swift `throws`
5. **维护方背书**：Mozilla 长期维护

### 考虑过的备选

| 备选 | 为什么不选 |
|---|---|
| swift-bridge | 只服务 Swift，未来扩 Kotlin 时还要换工具 |
| cbindgen + 手写 Swift wrapper | 工作量大、易出错 |
| Swift Package Manager Rust binding | 不成熟 |
| FlatBuffers / Protobuf 序列化 | 适合大数据流，不适合频繁的小调用 |

### 何时重新审视

- UniFFI 长期不更新或停止维护
- 项目对 Swift 闭包 / SwiftUI binding 等高级 Swift 类型有强需求

详见 [../adr/0002-uniffi-vs-others.md](../adr/0002-uniffi-vs-others.md)。

---

## 4. 元数据存储选择 SQLite

### 决策

通过 `rusqlite` crate 的 `bundled` feature 嵌入 SQLite 3，存储所有元数据。

### 理由

1. **单文件部署**：整个 DB 是一个 `.db` 文件，便于备份、迁移、调试
2. **零依赖**：bundled 模式编译进 Rust 库，用户无需装 SQLite
3. **ACID 完整**：事务保证、WAL 模式、外键约束齐全
4. **生态完整**：迁移工具、ORM 选项、调试工具丰富
5. **性能足够**：单机场景下，SQLite 在 10 万级数据上性能优秀

### 考虑过的备选

| 备选 | 为什么不选 |
|---|---|
| 纯 JSON 文件 | 没有事务、写并发难处理、查询性能差 |
| RocksDB / sled | KV 模型不适合关系数据 |
| DuckDB | 偏分析查询，事务弱 |
| 自定义二进制格式 | 不必要的复杂度 |

### 何时重新审视

- 单库超过 100 万文件且查询性能成为问题（极不可能用户场景）
- 需要原生网络同步（已有 iCloud 协议覆盖大多数需求）

详见 [data-model.md](data-model.md)。

---

## 5. Rust 关键依赖

### 直接依赖（在 Cargo.toml 中固定）

| Crate | 版本 | 用途 |
|---|---|---|
| `uniffi` | 0.28+ | FFI 桥接 |
| `rusqlite` | 0.31+ (bundled) | SQLite 访问 |
| `serde` | 1.x | 序列化 |
| `serde_json` | 1.x | JSON |
| `serde_yaml` | 0.9+ | classifier.yaml |
| `thiserror` | 1.x | 错误派生 |
| `sha2` | 0.10+ | SHA256 |
| `walkdir` | 2.x | 目录遍历 |
| `chrono` | 0.4+ (serde) | 时间戳 |
| `tracing` | 0.1+ | 结构化日志 |
| `tracing-subscriber` | 0.3+ | 日志输出 |

### 不直接引入但保留余量

- `tokio`：当前同步 IO 已足够；如果未来 AI 调用 / 网络密集再引入 async runtime
- `reqwest`：留给 Stage 3 AI 集成
- `regex`：classifier 关键词匹配如复杂化时引入

### 依赖审查原则

- 每个新增依赖必须在 PR 中说明：用途、许可证（须兼容 PolyForm-NC）、维护状态
- 拒绝引入未维护超过 1 年的 crate
- 拒绝引入许可证为 GPL/AGPL/SSPL 的 crate

---

## 6. Swift 关键依赖

### 系统框架（macOS 14+）

| 框架 | 用途 |
|---|---|
| SwiftUI | UI |
| Foundation | 基础类型 |
| AppKit | NSItemProvider / NSFileCoordinator / NSSavePanel |
| CoreServices | FSEventStream |
| Combine | 局部用于 store 更新流 |
| OSLog | 结构化日志 |

### 第三方依赖（通过 SPM）

MVP 阶段**不引入**任何第三方 Swift 包，全部用系统框架实现。Stage 2+ 视需要再引入。

---

## 7. 工具链与构建

### 必装

- macOS 14+
- Xcode 15+（含 Command Line Tools）
- Rust 1.75+ stable，targets：`aarch64-apple-darwin` + `x86_64-apple-darwin`
- 包：`cargo install uniffi-bindgen` 或对应 build-deps

### 可选

- `cargo-llvm-cov`（覆盖率）
- `cargo-watch`（开发时自动重建）
- `swiftformat` / `swiftlint`（Swift 规范）
- `xcbeautify`（让 xcodebuild 输出可读）

详见 [../development/setup.md](../development/setup.md)。

---

## 8. 版本支持策略

| 平台 / 工具 | 当前最低 | 支持理由 |
|---|---|---|
| macOS | 14.0 Sonoma | 用最新 SwiftUI API；2026 年覆盖率已 ≥ 80% |
| Xcode | 15.0 | 配合 macOS 14 SDK |
| Rust | 1.75 stable | uniffi 0.28+ 需要的 trait bound |
| SQLite | 3.40+ (bundled in rusqlite) | 不主动升级 |

### 升级节奏

- macOS 最低版本：每年 WWDC 后视情况上调一次（一般滞后官方 1-2 个版本）
- Rust：跟 stable，不强制最新
- 依赖：每 6 个月统一升级一次（除非有安全 issue）

---

## Related

- [overview.md](overview.md)
- [layered-design.md](layered-design.md)
- [ffi-design.md](ffi-design.md)
- [data-model.md](data-model.md)
- [../adr/0001-tech-stack.md](../adr/0001-tech-stack.md)
- [../adr/0002-uniffi-vs-others.md](../adr/0002-uniffi-vs-others.md)
- [../adr/0009-min-macos-version.md](../adr/0009-min-macos-version.md)
