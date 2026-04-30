# 2-3/task-16: S1-35 page atomic

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

实现 Stage 1 MVP 单页 S1-35。

## 绑定

- UX 页面：S1-35
- Core 能力：C1-24

## 核对清单

1. 只实现 S1-35 对应页面或状态。
2. 页面文案、状态、入口和退出遵循单页规格。
3. 接入真实 Core 时只调用本任务绑定能力；未绑定能力不得 mock 成完成。
4. 不顺手实现相邻页面。

## 完成标准

- S1-35 页面可被真实导航或状态触发。
- 页面验收可回到 page spec、control map 和绑定能力。

## 验证

```bash
xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```
