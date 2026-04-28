# 2-2/task-02: iCloud Coordination

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

实现 iCloud Drive 仓库检测、NSFileCoordinator 包装和占位符文件下载提示。

## 核对清单

1. 检测资料库是否位于 iCloud Drive。
2. 关键 IO 通过平台层协调，不让 Core 依赖 Apple API。
3. 占位符文件按需触发下载或给出友好错误。
4. iCloud 错误进入统一错误展示。

## 完成标准

- iCloud 仓库能完成基础浏览和导入。
- Core 仍保持平台无关。

## 验证

```bash
xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```

