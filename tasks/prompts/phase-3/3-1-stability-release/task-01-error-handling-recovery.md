# 3-1/task-01: 错误处理与 Recovery 打磨

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-3.md`

## 范围

补齐 CoreError 到 UI 的提示、启动 recovery 结果展示和关键失败路径重试。

## 核对清单

1. 所有 CoreError 有用户可理解提示。
2. 启动 recovery 有结果摘要和可追踪日志。
3. iCloud、权限、重复文件、冲突文件都有明确 UI。
4. 失败路径不吞错误。

## 完成标准

- 常见错误不再只显示底层异常。
- recovery 流程可复现、可验证。

## 验证

```bash
cd core
cargo test --workspace recovery
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```

