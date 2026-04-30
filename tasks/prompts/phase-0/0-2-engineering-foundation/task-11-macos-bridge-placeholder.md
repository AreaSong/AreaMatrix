# 0-2/task-11: macOS Bridge placeholder

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

macOS Bridge placeholder。

## 绑定

- 无特定 UX/Core 绑定；工程骨架或稳定性任务。

## 核对清单

1. 创建 CoreBridge 占位层。
2. Bridge 方法只声明后续接入边界。
3. 不得用 mock 通过后续真实闭环验收。

## 完成标准

- Bridge 编译通过。
- 占位状态在任务汇报中可识别。

## 验证

```bash
xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
```
