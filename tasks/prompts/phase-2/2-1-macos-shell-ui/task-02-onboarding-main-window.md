# 2-1/task-02: Onboarding 与主窗口

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

实现首次启动向导和 `NavigationSplitView` 三栏主窗口。

## 核对清单

1. 首次启动可选择资料库目录。
2. 空目录初始化和非空目录接管流程区分展示。
3. 主窗口包含侧栏、列表、详情三栏。
4. 加载、空状态、错误状态有明确 UI。

## 完成标准

- 用户可以完成首次启动并进入主窗口。
- 非空目录接管不会在 UI 层直接做文件 IO。

## 验证

```bash
xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```

