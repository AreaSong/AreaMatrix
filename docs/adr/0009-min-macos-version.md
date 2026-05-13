# ADR-0009: 最低 macOS 版本 14 Sonoma

> macOS 端最低支持 macOS 14 Sonoma；macOS 13 及以下不支持。
>
> 状态：Accepted
> 日期：2026-04-26
> 影响范围：apps/macos / 文档 / 发布说明
> 关联 ADR：[0001 桌面技术栈](0001-tech-stack.md)、[0006 iCloud](0006-icloud-support.md)

## 上下文

需要为 macOS 端选定最低支持版本。涉及多重权衡：

- **SwiftUI 能力**：macOS 14 引入了 `Inspector`、增强 `NavigationSplitView`、改进的 List 性能等
- **iCloud / FSEvents API**：较新 API 在旧版 macOS 行为可能不同
- **测试矩阵**：每多支持一版 OS = 多一份测试 + 兼容性维护成本
- **目标用户群覆盖率**：太新 = 损失用户、太旧 = 维护成本高
- **macOS 升级特点**：相比 Windows / Android 用户更新激进，最近 3 版覆盖率通常 > 80%

发布时间预计 Stage 2（2027 H1）公开，那时 macOS 16 已发布。

## 决定

**最低支持 macOS 14.0 Sonoma**（2023 年发布）。

具体配置：

```xml
<!-- AreaMatrix/Info.plist -->
<key>LSMinimumSystemVersion</key>
<string>14.0</string>
```

```bash
# Xcode project: macOS Deployment Target = 14.0
```

```rust
// ./dev build core: MACOSX_DEPLOYMENT_TARGET=14.0
```

不向 macOS 13 及以下提供构建。Stage 2 公开发布后，**每年 WWDC 后**（即 macOS 17 发布时）评估是否提升至 macOS 15 / 16。

## 理由

1. **SwiftUI 14 大幅成熟**：
   - `NavigationSplitView` 三栏布局 macOS 14 才稳定
   - `Inspector` modifier 提供右侧详情面板
   - List 性能与上下文菜单 14 起更可靠
   - 13 上仍有诸多需要 AppKit fallback 的场景
2. **官方覆盖率高**：发布时（2027 H1）macOS 14 + 15 + 16 累计预期覆盖 > 90%
3. **小团队不背技术债**：往下兼容一版（13 Ventura）至少多 30% UI fallback 代码
4. **Apple 自身策略**：Apple 一般支持最近 3 版安全更新，14 在 2026-2027 仍受官方支持
5. **iCloud Drive API**：14 起 NSFileCoordinator 与 placeholder 行为更稳定

## 考虑过的备选

### A. 最低 macOS 12 Monterey（2021）

- 优点：覆盖更多老用户（包括仍在用 Intel Mac 的用户）
- 缺点：
  - SwiftUI List 性能差，要写 AppKit fallback
  - Inspector / NavigationSplitView 不可用，要自己造
  - 双倍 UI 测试工作量
- **为什么没选**：维护成本远超用户增量

### B. 最低 macOS 13 Ventura（2022）

- 优点：覆盖 Sonoma 之前一代用户
- 缺点：
  - `NavigationSplitView` 部分 API 不稳定
  - `Inspector` 缺失，需要自己实现
  - 仍要写不少版本判断代码
- **为什么没选**：边际收益小，14 是分水岭

### C. 最低 macOS 15 Sequoia（2024）

- 优点：能用最新 API
- 缺点：
  - 发布时（2027）刚 macOS 16，14 仍是大盘主力之一，过早抛弃
  - 用户基数损失明显
- **为什么没选**：太激进，没必要

### D. 最低 macOS 16（2026）

- 优点：API 集合最新
- 缺点：发布时刚出 1-2 年，覆盖率仍然较低
- **为什么没选**：等不起

### E. 双版本支持（13 + 14+）

- 优点：覆盖率最大
- 缺点：维护两套 UI 路径
- **为什么没选**：小团队负担不起

## 后果

### 正面

- 单一 UI 代码路径，维护简单
- 能用 macOS 14+ 全部 SwiftUI 新能力
- iCloud / FSEvents 行为更稳定
- 2-3 人小团队能 hold 住测试矩阵

### 负面 / 代价

- **失去 macOS 13 及以下用户**：约 10-20% 潜在用户群
  - 缓解：用 GitHub Discussions 收集需求，必要时考虑社区版兼容
- **CI 矩阵需要 macOS 14**：GitHub Actions `macos-14` runner 即可（已可用）
- **每年要重审支持窗口**：WWDC 后 / 新 macOS 发布后

### 风险

- 老 Mac 用户感觉被抛弃 → 在 README 显著标注 + 提供说明
- macOS 17 改变 SwiftUI / FSEvents 行为 → CI 在 beta 跑测试 + 提前调整
- Apple 提前停止 macOS 14 安全更新 → 同步提升最低版本

## 何时重审

- **每年 WWDC 后** + 新版 macOS 发布后：评估是否提升至最近 3 版 - 1
- macOS 14 用户占活跃用户 < 5% → 提升最低版本
- 新 macOS 提供必须用的 API（如完全替代当前实现） → 评估提升以使用新 API
- 加 Linux / Windows 支持时，macOS 不动

## Related

- [../architecture/tech-stack.md](../architecture/tech-stack.md)
- [../development/setup.md](../development/setup.md)
- [0001-tech-stack.md](0001-tech-stack.md)
- [0006-icloud-support.md](0006-icloud-support.md)
