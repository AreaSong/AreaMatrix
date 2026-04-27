# ADR-0005: 文件系统监听用 FSEventStream

> macOS 端使用 **FSEventStream**（CoreServices）监听仓库目录，配合 200ms 去抖与 InFlight 过滤。
>
> 状态：Accepted
> 日期：2026-04-26
> 影响范围：apps/macos/Watcher / core/sync
> 关联 ADR：[0003 真相源](0003-source-of-truth-strategy.md)、[0006 iCloud](0006-icloud-support.md)

## 上下文

[ADR-0003](0003-source-of-truth-strategy.md) 决定 FS 是文件内容真相源，DB 通过监听 FS 变化保持同步。需要选一个监听机制。要求：

- **覆盖整个仓库目录**（包括子孙目录递归）
- **低 CPU 占用**：用户机器上后台常驻
- **支持持久化游标**：应用退出再启动，能拿到关闭期间的事件
- **不漏事件**：批量操作（unzip 1000 文件）不能丢
- **支持 iCloud Drive 占位符**

## 决定

采用 macOS 原生 **FSEventStream**（CoreServices framework），具体配置：

```swift
let flags: FSEventStreamCreateFlags =
    UInt32(kFSEventStreamCreateFlagFileEvents) |
    UInt32(kFSEventStreamCreateFlagWatchRoot) |
    UInt32(kFSEventStreamCreateFlagNoDefer)

let stream = FSEventStreamCreate(
    nil,
    callback,
    &context,
    [repoPath] as CFArray,
    sinceWhen, // 从 DB 持久化的 last_event_id 恢复
    0.0,       // latency: 立即触发，去抖在应用层做
    flags
)
```

加上：

- **200ms 去抖** 在 Swift 层 `Debouncer` actor 中合并同路径事件
- **InFlightTracker** 过滤应用自己造成的事件
- **DB 持久化** `meta` 表的 `last_event_id`，下次启动从这里恢复

## 理由

1. **macOS 原生 + 内核级**：CPU / 内存占用极低，是 Spotlight、Finder、Time Machine 共用的机制
2. **支持游标恢复**：`sinceWhen` 参数是事件 ID，重启后能拿到关闭期间事件
3. **递归监听免费**：传根目录就行，无需逐级注册
4. **kFSEventStreamCreateFlagFileEvents** 标志能拿到文件级事件（默认是目录级，粒度太粗）
5. **iCloud Drive 兼容**：占位符变化也会触发事件
6. **生态验证**：所有 Mac 上严肃的文件管理工具都用它

## 考虑过的备选

### A. kqueue + kevent

- 优点：跨 BSD 通用、底层
- 缺点：
  - 需要为每个文件描述符注册（递归监听几万文件资源占用大）
  - 不支持跨进程事件合并
  - 不持久化游标
- **为什么没选**：性能差、不支持游标

### B. 轮询（每 N 秒 stat 一次）

- 优点：跨平台、最简单
- 缺点：
  - 大目录下扫描慢（10 万文件需要数秒）
  - 实时性差
  - CPU 占用持续高
- **为什么没选**：用户体验差，不可接受

### C. notify crate（Rust 跨平台）

- 优点：Rust 生态、跨平台抽象
- 缺点：
  - 在 macOS 上底层仍是 FSEvents，但封装层引入额外延迟
  - 不支持游标持久化
  - 对 iCloud 占位符行为没有特化处理
- **为什么没选**：相比直接调用 FSEvents 没有优势，且失去 iCloud 兼容能力

### D. fswatch（开源 CLI 工具）

- 优点：现成可用
- 缺点：
  - 进程外工具，IPC 增加复杂度
  - 用户体验上多一个进程
- **为什么没选**：嵌入应用更可控

### E. macOS Endpoint Security framework

- 优点：内核级、最强大
- 缺点：
  - 需要系统扩展权限（代价巨大）
  - 用于安全软件场景，杀鸡用牛刀
- **为什么没选**：超出需求

## 后果

### 正面

- 实时性好，事件 < 1 秒到达
- CPU 占用 < 1%
- 支持持久化游标，能恢复跨会话事件
- 对 iCloud / Time Machine 等场景兼容性好
- 代码量小（核心 < 200 行 Swift）

### 负面 / 代价

- **平台锁定**：仅 macOS。Linux 用 inotify，Windows 用 ReadDirectoryChangesW，每平台单独实现
- **事件可能合并**：高频小操作时 FSEvents 会自己合并，应用看到的是 "summary"（缓解：拿到事件后用应用层逻辑确认实际状态）
- **kFSEventStreamEventIdSinceNow 的语义**：有时不能 100% 保证不漏（缓解：周期性 reindex 兜底）
- **iCloud 占位符的特殊性**：详见 [ADR-0006](0006-icloud-support.md)
- **InFlight 过滤增加复杂度**：应用自己改 FS 时要标记 + 排除（缓解：[fs-watcher.md](../architecture/fs-watcher.md) 实现统一封装）

### 风险

- macOS 升级后 FSEventStream API 行为变化（历史上 macOS 10.13 → 10.14 有过细节变化）
  - 缓解：CI 在新 macOS beta 跑一次完整测试
- 极端高频场景下事件溢出（缓解：检测溢出标志位 → 触发全量 reindex）
- 用户禁用 Spotlight 索引可能影响 FSEvents（缓解：检测 + 友好提示）

## 何时重审

- 加 Linux 端时，inotify 实现要单独评估（不会影响本 ADR）
- 加 iOS 端时，沙盒模型不同，可能要换方案
- macOS 出现新的更优 API（如 Apple 推出官方 watcher 替代品）
- 性能 profile 显示 Watcher 是瓶颈

## Related

- [../architecture/fs-watcher.md](../architecture/fs-watcher.md)
- [../architecture/source-of-truth.md](../architecture/source-of-truth.md)
- [0003-source-of-truth-strategy.md](0003-source-of-truth-strategy.md)
- [0006-icloud-support.md](0006-icloud-support.md)
