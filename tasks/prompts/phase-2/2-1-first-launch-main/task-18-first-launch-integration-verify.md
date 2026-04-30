# 2-1/task-18: first-launch integration verify

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

integration

## 范围

验收 first-launch 闭环中的页面、Core 能力和导航/状态 wiring。

## 绑定

- 集成验收页面：S1-01, S1-02, S1-03, S1-04, S1-05, S1-06, S1-07
- 集成验收能力：C1-04, C1-01, C1-03, C1-21, C1-02, C1-16

## 核对清单

1. 只做已完成页面和能力之间的 wiring/验收补齐。
2. 检查本闭环内所有页面的 page integration verify 或 atomic task 已完成。
3. 移除本闭环内无法通过最终验收的 mock。
4. 不得新增未列出的页面或 Core 能力。

## 完成标准

- 该闭环可以按用户路径走通。
- 失败项有明确证据和阻塞记录。

## 验证

```bash
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```
