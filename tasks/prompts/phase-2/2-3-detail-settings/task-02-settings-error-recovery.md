# 2-3/task-02: 设置、错误与恢复闭环

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

实现 S1-26 到 S1-32 的 Stage 1 设置、错误映射和恢复入口。

## 绑定

- UX 页面：S1-26, S1-27, S1-28, S1-29, S1-30, S1-31, S1-32
- Core 能力：C1-04, C1-05, C1-16, C1-20, C1-21

## 核对清单

1. 设置页读写真实 `RepoConfig`。
2. 分类设置至少能验证当前规则和 preview 结果。
3. 高级页提供 recovery/reindex/diagnostic 入口，但不提前实现 Stage 2+ 功能。
4. 每个 CoreError 都有 AppError 用户文案。

## 完成标准

- 修改默认存储模式或 overview 输出后能持久化。
- 错误恢复 UI 可展示 recovery report。
- 关于页使用真实 `get_version`。

## 验证

```bash
xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```
