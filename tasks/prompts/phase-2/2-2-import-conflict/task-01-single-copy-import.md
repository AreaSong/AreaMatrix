# 2-2/task-01: 单文件 Copy 导入闭环

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

实现拖入单文件、分类预览、导入确认和 Copy 导入真实闭环。

## 绑定

- UX 页面：S1-16, S1-17, S1-20, S1-21
- Core 能力：C1-05, C1-06, C1-11, C1-13

## 核对清单

1. 拖拽 hover 使用真实文件路径和分类预览。
2. 单文件导入 sheet 显示建议分类、目标位置和存储模式。
3. 确认后调用 `import_file(mode=Copied)`。
4. 导入完成刷新列表和导入结果摘要。

## 完成标准

- 源文件保留，目标文件进入资料库，列表可见。
- 导入结果可从 Core 返回和 change log 证明。
- 验收时若导入只是 UI 状态变化，没有文件/DB 结果，判定不通过。

## 验证

```bash
xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```
