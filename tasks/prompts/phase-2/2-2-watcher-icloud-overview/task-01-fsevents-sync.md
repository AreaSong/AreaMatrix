# 2-2/task-01: FSEvents 与外部变化同步

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

实现 FSWatcher、Debouncer、InFlightTracker，并把外部变化同步到 Core。

## 核对清单

1. FSEventStream 监听资料库根。
2. 200ms debounce 合并事件。
3. InFlightTracker 过滤应用自身写入。
4. 外部 create / rename / delete / modify 调用 `sync_external_changes`。
5. UI 在 Core 同步后刷新。

## 完成标准

- Finder 中的外部改动能在 UI 中回流。
- 应用自身导入不会被重复处理。

## 验证

```bash
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```

