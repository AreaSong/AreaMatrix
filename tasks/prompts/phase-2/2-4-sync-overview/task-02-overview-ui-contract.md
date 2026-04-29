# 2-4/task-02: 自动概览 UI 合同闭环

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

把自动概览生成能力接入设置和导入后刷新，确保 UI 不暗示会覆盖用户 README。

## 绑定

- UX 页面：S1-21, S1-27, S1-30
- Core 能力：C1-20, C1-04, C1-06

## 核对清单

1. 设置页展示 overview 输出策略并持久化。
2. 导入后 generated overview 的成功或失败状态有可理解反馈。
3. UI 文案明确默认写 `.areamatrix/generated/`。
4. 不提供覆盖 `README.md` 的按钮或暗示。

## 完成标准

- generated overview 文件可通过真实导入或设置触发更新。
- S1-27/S1-30 与 ADR 中的 README 边界一致。
- 如果 UI 允许覆盖 README，验收不通过。

## 验证

```bash
xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
cd core
cargo test --workspace overview
```
