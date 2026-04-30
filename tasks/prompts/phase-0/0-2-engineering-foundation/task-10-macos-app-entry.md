# 0-2/task-10: macOS App entry 空壳

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

macOS App entry 空壳。

## 绑定

- 无特定 UX/Core 绑定；工程骨架或稳定性任务。

## 核对清单

1. 创建 SwiftUI App entry 与根视图占位。
2. 只呈现空壳状态。
3. 不接入真实 Core。

## 完成标准

- App shell 可编译。

## 验证

```bash
xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
```
