# 2-2/task-03: 重复与同名冲突闭环

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

实现 S1-22 到 S1-24：重复文件、同名不同内容、Replace 二次确认的真实冲突处理 UI。

## 绑定

- UX 页面：S1-22, S1-23, S1-24
- Core 能力：C1-09, C1-10, C1-13, C1-21

## 核对清单

1. DuplicateFile 错误进入重复冲突 UI。
2. Keep Both、Skip、Replace 的 UI 动作与 Core `DuplicateStrategy` 对齐。
3. 同名不同内容默认保留两份并展示自动改名结果。
4. Replace 必须二次确认，不能默认覆盖。

## 完成标准

- 重复冲突和同名冲突都有可复现验证路径。
- UI 展示结果与 Core `FileEntry` / change log 一致。
- 若 Replace 没有二次确认，验收不通过。

## 验证

```bash
xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```
