# 2-1/task-01: CoreBridge 与 Stores

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

实现 Swift 平台层 `CoreBridge` 和 UI 状态 stores，统一封装 UniFFI 调用。

## 核对清单

1. UI 不直接调用 UniFFI 生成函数。
2. `CoreBridge` 提供 async/throws 风格 API。
3. `RepoStore`、`SettingsStore` 使用 `@Observable`。
4. 错误统一映射为 UI 可展示状态。

## 完成标准

- SwiftUI 视图只依赖 store 或平台封装。
- Bridge 有基础单元测试或 smoke 测试。

## 验证

```bash
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```

