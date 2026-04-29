# 2-2/task-02: 批量与文件夹导入进度闭环

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

实现多文件和文件夹递归导入确认、队列进度与结果摘要。Core 可由 Swift 队列多次调用单文件导入。

## 绑定

- UX 页面：S1-18, S1-19, S1-20, S1-21
- Core 能力：C1-05, C1-06, C1-08, C1-09, C1-13

## 核对清单

1. 多文件和文件夹导入 sheet 展示数量、风险和存储模式。
2. 队列逐项调用真实 Core，不用静态进度条。
3. 成功、跳过、失败结果可汇总展示。
4. 取消或失败不会留下 UI 认为成功的假状态。

## 完成标准

- 至少覆盖多文件 Copy 导入和文件夹递归导入的 UI 流程。
- 结果摘要与实际导入数量一致。
- mock 进度不能通过最终验收。

## 验证

```bash
xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```
