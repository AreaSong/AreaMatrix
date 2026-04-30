# 0-2/task-09: macOS Xcode project 空壳

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

macOS Xcode project 空壳。

## 绑定

- 无特定 UX/Core 绑定；工程骨架或稳定性任务。

## 核对清单

1. 创建可打开的 Xcode project 空壳。
2. 不实现页面业务。
3. 项目结构为后续 SwiftUI 页面预留位置。

## 完成标准

- xcodebuild build 可运行或明确记录缺失原因。

## 验证

```bash
xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
```
