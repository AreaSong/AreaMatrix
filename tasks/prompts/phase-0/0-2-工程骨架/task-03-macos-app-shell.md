# 0-2/task-03: macOS App 空壳

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-0.md`

## 范围

创建 `apps/macos/` 下 SwiftUI App 的最小空壳，为后续 UI、Bridge、Watcher 留出目录。

## 核对清单

1. Xcode project、scheme、target 名称统一为 `AreaMatrix`。
2. 创建 `App / Bridge / Watcher / Adapters / Models / Views / Logging / Resources` 目录。
3. `AreaMatrixApp.swift` 能启动一个最小主窗口。
4. 暂不直接调用 Core，Bridge 只保留空实现或明确 TODO。

## 完成标准

- Xcode 工程能解析，空应用能 build。
- 未提前实现拖拽、列表、Watcher、iCloud 等后续功能。

## 验证

```bash
xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
```

