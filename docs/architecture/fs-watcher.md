# 文件监听与外部变化同步

> 记录 macOS FSEvents watcher、cursor、事件合并、Core 同步、恢复和 iCloud 文件安全边界。
>
> 阅读时长：约 8 分钟。

---

## 职责分层

```mermaid
flowchart LR
    fsevents["FSEventStream"]
    watcher["MainExternalCreatedFileWatcher"]
    tracker["InFlightFileChangeTracker"]
    relay["External change relay"]
    model["Current repository model"]
    bridge["CoreExternalChangesSyncing"]
    core["sync_external_changes"]

    fsevents --> watcher
    tracker --> watcher
    watcher --> relay
    relay --> model
    model --> bridge
    bridge --> core
```

- Swift 平台层启动和停止 FSEventStream。
- watcher 处理 flags、路径归一化、200ms 合并和 InFlight 过滤。
- 当前资料库 model 保留待处理事件并以单批调用 Core。
- Core 读取 metadata/hash，更新 DB、change log、overview 和 cursor。
- Core 不启动 FSEvents，也不调用 macOS API。

## 启动与 cursor

watcher 启动前调用 `get_fs_event_cursor(repoPath)`：

- 有 cursor：从该 event ID 启动 FSEventStream。
- 无 cursor：不从 `SinceNow` 静默开始，而是请求用户可见的全量重扫。
- cursor 读取或 stream 启动失败：进入 watcher startup error。

重扫请求记录当前 `FSEventsGetCurrentEventId()` 作为 resume seed。用户确认并完成重扫后，应用通过 `set_fs_event_cursor` 写入该 seed，再重新打开资料库和 watcher。

正常事件批次不由 Swift 额外写 cursor；Core 在成功完成 DB batch 和 overview 后写入最大 event ID。

## FSEventStream 配置

当前 flags：

- `FileEvents`
- `UseCFTypes`
- `WatchRoot`
- `NoDefer`

stream latency 为 0.2 秒，回调投递到 main dispatch queue。

当前不使用 `UseExtendedData`，不依赖 inode 字段配对 rename，也没有 HealthMonitor 静默定时器。

## 恢复 flags

| Flag | 行为 |
|---|---|
| `RootChanged` | 停止 stream，清空 pending，要求重新连接资料库路径 |
| `MustScanSubDirs` | 停止 stream，要求全量重扫 |
| `UserDropped` | 停止 stream，要求全量重扫 |
| `KernelDropped` | 停止 stream，要求全量重扫 |
| `EventIdsWrapped` | 停止 stream，要求全量重扫 |
| `HistoryDone` | 只作为历史重放边界，不生成文件事件 |

任一无法保证历史完整性的 flag 都不能继续推进 cursor。

## 事件归一化

watcher 忽略：

- 目录事件。
- 无效或超出 `Int64` 的 event ID。
- 资料库外路径。
- `.areamatrix` 及其子路径。
- 只有恢复/边界 flag、没有文件语义的事件。

文件事件映射：

| FSEvents flags | 路径状态 | Core kind |
|---|---|---|
| `ItemRenamed` | 新路径存在 | `Renamed` |
| `ItemRenamed` | 路径不存在 | `Removed` |
| `ItemRemoved` | 路径不存在 | `Removed` |
| `ItemCreated` | 文件存在 | `Created` |
| `ItemModified` | 文件存在 | `Modified` |

同一路径在窗口内的 flags 合并，event ID 取最大值。flush 前按 event ID、路径排序。

## Rename 配对

Swift 不使用 inode 配对旧路径和新路径。Core 对新路径计算 hash，并在 active rows 中查找唯一候选：

- 唯一候选：更新同一 file ID 的 path、name 和 category。
- 无候选或多个候选：返回 Conflict，不猜测。
- 同批出现旧路径 Removed 和新路径 Renamed 时，Core 在配对成功后抑制同一 file ID 的 soft delete。
- 跨分类移动同时更新 category，并刷新来源与目标分类概览。

Core 不执行物理 rename；它只登记 Finder、终端或同步工具已经完成的外部变化。

## Modified

`Modified` 对已登记文件重新读取 size 和 SHA-256：

- hash/size 未变化：幂等跳过。
- 内容变化：更新 metadata 并写 `external_modified` change log。
- 路径存在但没有 active row：按外部 create 登记。

Core 只读取用户明确存在的本地文件；不修改文件正文。

## InFlight 过滤

AreaMatrix 自身文件动作在平台层标记 `(repoPath, relativePath)`：

- actor 内使用引用计数，支持嵌套 mark/unmark。
- 每次 mark 或剩余引用 unmark 后刷新过期时间。
- 默认 TTL 为 60 秒，防止异常路径永久屏蔽外部变化。
- 只过滤匹配路径，不丢弃同批其他路径。

InFlight 过滤是反馈回路保护，不替代 Core 幂等和事务。

## 200ms 合并

watcher 在收到事件后启动可取消的 200ms flush task。新事件到达时重置等待：

- 同一路径只保留合并结果。
- 不同路径全部保留。
- flush 后一次性发布信号列表。
- 当前资料库 model 再合并同路径的较新 event ID，并以单个 Core batch 提交。

## Core 提交顺序

`sync_external_changes`：

1. 校验整批 event ID 和路径。
2. 规划 Created、Renamed、Removed、Modified。
3. 在一个 SQLite 事务中写 files 和 change_log。
4. 更新所有受影响分类和 root overview。
5. 单独持久化批次最大 cursor。

DB 事务失败时 metadata 和 change log 全部回滚，cursor 不推进。overview 或 cursor 失败时 cursor 仍不推进；下一次重放必须安全。

## iCloud placeholder

- watcher 只观察路径和 FSEvents metadata。
- Core 发现 placeholder marker 时返回 `ICloudPlaceholder`。
- watcher 和 Core 都不触发下载。
- `Download & retry` 属于用户触发的 macOS 平台动作。
- placeholder 错误不推进 cursor，也不删除 marker、原文件或 conflicted copy。

## RootChanged 与重扫

`RootChanged` 进入重新连接错误，不自动猜测新路径。

重扫进入已有 DB repair / reindex 确认界面：

- 清空该资料库的 pending watcher events。
- 显示需要全量重扫的原因。
- 用户确认后运行现有 reindex/recovery 合同。
- 完成后写入预先记录的 resume seed。

该流程不得移动、删除、重命名或覆盖用户文件。

## 验证重点

- 从已有 cursor 启动；无 cursor 请求重扫。
- dropped/wrapped flags 全部停止 stream 并请求重扫。
- RootChanged 进入重新连接。
- HistoryDone 不产生业务事件。
- burst 合并保持不同路径并按 event ID 排序。
- InFlight 引用计数、TTL 和逐路径过滤正确。
- 单批进入 Core，DB 失败保持原子，overview 失败不推进 cursor。
- rename、modified、removed 和跨分类概览均可重放。
- iCloud placeholder 不发生隐式下载或用户文件写入。

## Related

- [source-of-truth.md](source-of-truth.md)
- [concurrency.md](concurrency.md)
- [transactional-import.md](transactional-import.md)
- [../api/core-api.md](../api/core-api.md)
- [../development/recovery.md](../development/recovery.md)
