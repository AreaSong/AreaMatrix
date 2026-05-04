# AreaMatrix macOS Agent Guide

## 定位

- 本目录是 AreaMatrix 的 SwiftUI macOS 原生应用。
- macOS 层负责 UI、平台适配、CoreBridge、watcher 和系统能力封装。
- Phase 0 只允许维护可编译空壳，不实现真实产品闭环。

## 边界

- SwiftUI 视图只做展示和用户交互，不直接做文件 IO。
- 平台能力放在 Swift 平台层；Core 层仍保持平台无关。
- CoreBridge 是 Swift 调用 Core 的唯一入口，后续不得让视图直接调用 UniFFI 生成代码。
- `Bridge/Generated/` 是生成产物目录，不手写业务代码。

## 高风险约束

- 不移动、删除、覆盖或重命名用户原文件。
- 不在本目录实现 FSEvents、iCloud、导入、接管或真实 Core 写操作，除非任务明确要求。
- 不用 mock 或静态数据伪装真实闭环验收通过。

## 验证

macOS 改动后优先运行：

```bash
xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
bash scripts/check-macos-tests.sh
```

`scripts/check-macos-tests.sh` 会先执行标准 `xcodebuild test`；只有明确遇到
本地 `testmanagerd` sandbox 通信限制时，才用 `xcrun xctest` 执行同一 XCTest
bundle。普通编译、链接或断言失败仍然算失败。
