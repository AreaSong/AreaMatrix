# 2-2/task-10: S1-18 page integration verify

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

integration

## 范围

验收 S1-18 import-batch-sheet 的整页多功能闭环。

## 绑定

- UX 页面：S1-18 import-batch-sheet
- 页面能力：C1-05, C1-06, C1-09
- 页面功能任务：2-2/task-07, 2-2/task-08, 2-2/task-09

## 核对清单

1. 逐项验收本页所有 page-feature task 是否完成。
2. 检查页面状态、入口、退出、错误态和 CoreBridge 调用是否能串成完整页面闭环。
3. 移除本页无法通过最终验收的 mock、fixture 或硬编码状态。
4. 不新增本页未在 control map 中声明的功能。

## 完成标准

- S1-18 页面可以按 page spec 和 control map 完整验收。
- 页面声明的所有 Core 能力都已真实接入或有明确阻塞证据。

## 验证

```bash
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```
