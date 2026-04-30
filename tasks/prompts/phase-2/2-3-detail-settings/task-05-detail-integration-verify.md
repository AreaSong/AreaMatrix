# 2-3/task-05: detail integration verify

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

integration

## 范围

detail integration verify。

## 绑定

- 集成验收页面：S1-12, S1-13, S1-14, S1-15
- 集成验收能力：C1-11, C1-12, C1-13, C1-14

## 核对清单

1. 只做已完成页面和能力之间的 wiring/验收补齐。
2. 移除本闭环内无法通过最终验收的 mock。
3. 不得新增未列出的页面或 Core 能力。

## 完成标准

- 该闭环可以按用户路径走通。
- 失败项有明确证据和阻塞记录。

## 验证

```bash
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```
