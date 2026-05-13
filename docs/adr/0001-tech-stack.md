# ADR-0001: 桌面技术栈选型

> 选择 **SwiftUI（macOS 14+）+ Rust 核心库 + UniFFI** 作为 AreaMatrix 的桌面技术栈。
>
> 状态：Accepted
> 日期：2026-04-26
> 影响范围：core / macos-app / 全部下游 platform
> 关联 ADR：[0002 FFI 工具](0002-uniffi-vs-others.md)、[0009 最低 macOS 版本](0009-min-macos-version.md)

## 上下文

AreaMatrix 是一个本地优先的资料管理桌面应用，首发目标是 macOS，后续要扩展到 Windows / Linux / iOS / Android。需求约束：

- **原生体验优先**：用户预期是 Finder / Apple Notes 级别的流畅度和细节
- **本地数据安全**：纯本地，不依赖云端
- **后期跨端复用**：未来加 Windows / Linux 时不应推翻现有架构
- **小团队可维护**：MVP 阶段单人或 2-3 人开发
- **性能敏感**：大量文件 IO、hash 计算、FSEvents 监听

## 决定

采用 **"Core + Shell" 分层架构**：

- **Core**：用 Rust 实现所有平台无关的逻辑（DB、文件 IO、分类、hash、FSEvents 抽象）
- **Shell**：每个平台用最原生的 UI 框架
  - macOS：SwiftUI（macOS 14 Sonoma 起）
  - 未来 iOS：SwiftUI
  - 未来 Android：Jetpack Compose
  - 未来 Windows：WinUI 3 或 WPF
  - 未来 Linux：GTK / Qt（待评估）
- **桥接层**：UniFFI 自动生成 Rust ↔ Swift / Kotlin / Python bindings

## 理由

1. **后端代码 80% 复用**：Rust core 在所有平台共用，避免每端重写文件操作 / DB / 分类逻辑
2. **前端 100% 原生**：每端用各自最擅长的 UI 框架，体验和性能都最优
3. **Rust 的天然优势**：
   - 内存安全，无 GC，IO 密集场景表现稳定
   - 跨平台编译成熟（aarch64 + x86_64 macOS、Linux、Windows、iOS、Android 均支持）
   - 生态完备：rusqlite / serde / tokio 都开箱即用
4. **SwiftUI 在 macOS 14+ 已成熟**：Sonoma 起 List / Sidebar / Drag-drop API 完整，足以覆盖 MVP
5. **避开 Web 框架陷阱**：Electron / Tauri 都被排除（详见 [备选](#考虑过的备选)）

## 考虑过的备选

### A. Electron + Node.js + React/Vue

- 优点：单语言（JS）全栈、生态最丰富、跨端最快
- 缺点：
  - 内存占用高（最小 100MB+）
  - 启动慢
  - 与 macOS 原生体验有差距（动画、控件、字体渲染）
  - 长期被认为"不够 Mac"
- **为什么没选**：与"原生体验优先"原则不符

### B. Tauri + Rust + 前端 Web

- 优点：包小、Rust 后端、跨平台
- 缺点：
  - UI 仍是 Web（HTML/CSS）
  - macOS 端用 WKWebView 渲染，文件拖拽 / 触控板手势 / 上下文菜单都要适配
  - 与 SwiftUI 原生差距明显
- **为什么没选**：仍是 Web 渲染，本质上是更轻的 Electron

### C. 纯 SwiftUI（不用 Rust core）

- 优点：单语言、无 FFI 复杂度、Apple 生态最顺
- 缺点：
  - 后续 Windows / Linux / Android 要重写所有后端
  - Swift 在非 Apple 平台支持差（Swift on Linux 可用但生态弱）
  - DB / hash / 分类逻辑会重复 3-4 遍
- **为什么没选**：违反"后期跨端复用"

### D. C++/Qt

- 优点：跨平台 UI 一致、性能好
- 缺点：
  - macOS 上 Qt 控件总是"差一点"
  - 现代 C++ 团队熟练度不如 Rust
  - 内存安全靠人工，资料管理类应用 IO 高频，bug 风险大
- **为什么没选**：用户体验和安全性都不如 Rust + 原生 UI

### E. Flutter

- 优点：单 codebase 跨端、Dart 易上手
- 缺点：
  - 桌面端 macOS 体验仍是 Material 风格，与 Mac 原生差距大
  - 文件系统 / FSEvents 这类系统集成需要写 Native plugin，不省事
- **为什么没选**：移动端尚可，桌面端体验有差距

## 后果

### 正面

- 后端逻辑写一遍多端用，维护成本低
- 每端 UI 都是 native，用户体验顶配
- Rust 强类型 + 编译期检查，IO 密集场景下 bug 少
- 长期演进路径清晰（加平台 = 加 Shell + UniFFI binding）

### 负面 / 代价

- **跨语言调试复杂度**：Rust ↔ Swift 出错时栈跟踪不连贯，要工具配合
- **构建链复杂**：`./dev build core` + UniFFI binding gen + Xcode 集成，CI 配置多
- **学习成本**：开发者既要懂 Rust 又要懂 SwiftUI（招人范围窄）
- **FFI 边界设计需谨慎**：传值贵 → 需要批量 API、避免高频小调用
- **每加一个平台**仍要写整套 Shell（不是真"零成本"跨端）

### 风险

- UniFFI 还在 0.x 版本，未来可能有破坏性变更（缓解：版本锁定 + ADR 0002 评估替代）
- SwiftUI 早期版本 bug 较多（缓解：限定 macOS 14+，并保留 AppKit 兜底通路）
- Rust 编译慢（缓解：sccache + 增量构建）

## 何时重审

- UniFFI 出现严重维护问题（>6 月不更新 / 重大 bug 不修）→ 评估 swift-bridge 替代
- macOS 用户量增长后，发现 SwiftUI 仍有不可绕过的痛点 → 评估 AppKit 重写关键视图
- 加第二个平台（Windows）时，重新评估整体方案是否仍是最优
- Rust core 编译时间 > 2 分钟（在 M 系列芯片上）→ 引入更激进的 caching 策略

## Related

- [../architecture/tech-stack.md](../architecture/tech-stack.md)
- [../architecture/layered-design.md](../architecture/layered-design.md)
- [0002-uniffi-vs-others.md](0002-uniffi-vs-others.md)
- [0009-min-macos-version.md](0009-min-macos-version.md)
