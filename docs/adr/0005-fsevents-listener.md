# ADR-0005: 文件系统监听使用 FSEventStream

> macOS 平台层使用 FSEventStream 监听资料库，Core 保持平台无关并处理规范化事件。
>
> 阅读时长：约 5 分钟。

---

## 状态

- 状态：Accepted
- 日期：2026-04-26
- 影响范围：`apps/macos/AreaMatrix/PlatformServices`、`core/src/sync`

## 上下文

用户可以在 Finder、终端或同步工具中修改资料库。AreaMatrix 需要递归观察 macOS 文件事件，持久化可恢复
cursor，并避免把应用自身写入再次解释为外部变化。

Core 不能依赖 macOS API，因此 watcher、iCloud 下载和平台 flags 必须留在 Swift 平台层。

## 决定

macOS 使用 CoreServices `FSEventStream`，当前配置：

```swift
let flags = FSEventStreamCreateFlags(
    kFSEventStreamCreateFlagFileEvents |
        kFSEventStreamCreateFlagUseCFTypes |
        kFSEventStreamCreateFlagWatchRoot |
        kFSEventStreamCreateFlagNoDefer
)

let latency: CFTimeInterval = 0.2
```

stream 投递到 main dispatch queue。应用层另使用可取消 Task 做 200ms flush，将同一路径事件合并后提交
Core。

cursor 保存在 SQLite `fs_event_cursor` 表：

- 有 cursor：从该 event ID 启动。
- 无 cursor：要求用户确认全量重扫，不从 `SinceNow` 静默开始。
- `MustScanSubDirs`、`UserDropped`、`KernelDropped`、`EventIdsWrapped`：停止 stream 并请求确认重扫。
- `RootChanged`：停止 stream 并要求重新连接资料库路径。

## 事件边界

- Swift 处理 flags、目录/metadata 过滤、资料库内路径归一化和 InFlight 过滤。
- Core 接收 Created/Renamed/Modified/Removed，不调用 FSEvents。
- Swift 不使用 inode 配对 rename；Core 用唯一 hash 候选判断同一 row。
- iCloud placeholder 不隐式下载；下载和 retry 必须由用户触发的平台动作执行。

每个 FSEvents 回调窗口记录最大 event ID 作为 `cursorWatermark`：

- 有业务 signal 时，每个 signal 携带相同 watermark。
- Core 成功后，Swift 在 watermark 更大时补写 cursor。
- 全部事件被 Swift 过滤时，Swift 直接确认 watermark。
- cursor 写入失败保持失败/pending 状态，不把事件静默丢弃。

## InFlight

应用自身文件动作按 `(repoPath, relativePath)` 标记：

- 引用计数支持嵌套动作。
- 默认 TTL 60 秒。
- 最后一次 unmark 后 count 置 0，但 entry 保留完整 TTL grace，吸收延迟回流。
- InFlight 只是反馈回路保护，Core 幂等和 transaction 仍是最终一致性边界。

## 备选

### kqueue

需要递归维护大量 descriptor，没有持久化 FSEvents cursor，未采用。

### 轮询

跨平台但需要重复全量扫描，实时性和成本不适合作为 macOS 默认 watcher。

### Rust notify 抽象

Core 需要保持平台无关，但 macOS cursor、recovery flags 和 iCloud 路由仍需平台特化。当前直接在 Swift
封装可让这些边界保持显式。

## 后果

正面：

- watcher 平台能力与 Core 业务同步分层清楚。
- cursor、watermark、filtered-only ack 和恢复 flags 可独立测试。
- 不需要为每个子目录注册 watcher。

代价：

- macOS watcher 不能直接复用到其他平台。
- 事件会合并、重复或延迟，必须依赖 Core 幂等和安全重放。
- FSEvents 历史不完整时必须进入用户可见重扫，不能自动假设一致。

## 重审条件

- macOS watcher API 或 deployment target 变化。
- 需要新的跨平台 watcher backend。
- cursor/watermark 恢复合同变化。
- 性能证据表明 watcher/flush 成为瓶颈。

## Related

- [../architecture/fs-watcher.md](../architecture/fs-watcher.md)
- [../architecture/source-of-truth.md](../architecture/source-of-truth.md)
- [0003-source-of-truth-strategy.md](0003-source-of-truth-strategy.md)
- [0006-icloud-support.md](0006-icloud-support.md)
