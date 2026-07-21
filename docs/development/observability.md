# 可观测性与诊断

> 记录 AreaMatrix 当前日志能力、metadata diagnostics 和脱敏导出边界。
>
> 阅读时长：约 6 分钟。

---

## 当前结论

AreaMatrix 目前没有完整的跨 Rust/Swift 日志管线：

- Core `init_logging(level)` 只校验 `trace/debug/info/warn/error`，不安装 tracing subscriber。
- Cargo 包含 `tracing` 与 `tracing-subscriber`，部分 Core 路径会发出 tracing event，但应用没有接线到文件或
  Swift。
- 手写 Swift 源当前不使用 `OSLog.Logger`。
- 没有 rolling log file、JSON formatter、FFI `LogSink`、in-memory ring buffer、
  `dump_recent_logs` 或 debug signal API。

因此文档和支持流程不能假设 `.areamatrix/logs/` 一定存在或包含完整运行日志。

## Logging API

```text
init_logging(level) -> validate level only
```

非法 level 返回 `CoreError::Config`。`CoreBridge.initializeLogging` 当前不可用，不能把调用成功当作 subscriber
已初始化的证据。

Advanced/About 设置中的“打开日志目录”只尝试打开 `<repo>/.areamatrix/logs/` 已存在目录；它不创建目录，
也不启动日志写入。

## Repository diagnostics

`create_diagnostics_snapshot(repoPath)` 创建 AreaMatrix-owned metadata snapshot：

```text
<repo>/.areamatrix/diagnostics/
└── index-<timestamp>-<uuid>.db
    ├── optional -wal companion
    └── optional -shm companion
```

实现边界：

- 主 DB 使用 create-new 目标和 buffered copy。
- 写入后 flush + `sync_all`。
- WAL/SHM 在存在时复制；复制期间消失会作为 warning，而不是伪造成功。
- snapshot 路径必须保持在 `.areamatrix/` 内。
- 不复制用户文件正文，不上传网络。

`repair_metadata` 可在修复前保留 snapshot，然后执行 DB integrity/foreign-key 检查。full rescan 需要重建 DB
时使用临时 replacement DB；安装失败恢复旧 DB。

## About diagnostics

About 页面可以在用户确认隐私提示后导出脱敏文本：

```text
~/Library/Application Support/AreaMatrix/Diagnostics/
└── about-diagnostics-<timestamp>-<uuid>/about-diagnostics.txt
```

报告包含 app version、Core version、schema version 和版本问题摘要，并明确：

- 排除用户文件内容。
- 原始文件路径已脱敏。
- 不自动上传。

该报告不是 repository DB snapshot，也不是完整应用日志包。

## 其他诊断状态

平台 watcher、local model、搜索解析和页面恢复会返回 display-safe diagnostics/status DTO。这些状态用于 UI
解释当前能力和恢复动作，不应包含 API key、用户文件正文或未脱敏路径。

## 隐私与支持边界

- diagnostics 导出必须由用户主动触发。
- repository snapshot 只包含 metadata DB 及 SQLite companions，仍可能包含用户路径、文件名、tags 和
  notes，应按敏感本地数据处理。
- About diagnostics 默认脱敏且不含用户内容。
- 当前没有自动上传、远程 crash reporter 或 telemetry。
- 分享 diagnostics 前应明确目标、保留周期和删除方式。

## 新增日志体系的门禁

未来接入 subscriber、OSLog、file sink 或远程上报时，必须先定义：

- owner、数据分类和默认关闭/开启策略。
- 路径、文件名、note、AI 内容和 secret 的 redaction。
- rotation、保留、删除和磁盘成本。
- Rust/Swift 边界、线程和 backpressure。
- 用户同意、导出与关闭路径。
- 单测、隐私 review、依赖和供应链评估。

在这些合同落地前，不得把 tracing 依赖等同于已实现的日志产品。

## Related

- [recovery.md](recovery.md)
- [troubleshooting.md](troubleshooting.md)
- [../architecture/data-model.md](../architecture/data-model.md)
- [../architecture/migration.md](../architecture/migration.md)
- [../product/privacy.md](../product/privacy.md)
