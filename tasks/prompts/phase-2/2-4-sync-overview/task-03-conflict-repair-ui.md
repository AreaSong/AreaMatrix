# 2-4/task-03: iCloud 冲突列表与 DB 修复 UI

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

实现 S1-36 iCloud 冲突列表和 S1-37 DB 修复确认，接入真实 Core 状态。

## 绑定

- UX 页面：S1-36, S1-37
- Core 能力：C1-25, C1-26, C1-16, C1-21

## 核对清单

1. iCloud 冲突列表调用真实 conflict provider。
2. 列表页不自动删除或移动冲突副本。
3. DB repair 页面未确认前不能运行 full rescan。
4. 修复进度、成功、失败和诊断导出状态可见。

## 完成标准

- S1-36/S1-37 不再是悬空页面。
- 用户文件安全边界与 AGENTS 高风险规则一致。
- mock 冲突列表或 mock repair report 不能通过最终验收。

## 验证

```bash
xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
cd core
cargo test --workspace icloud_conflicts metadata_repair
```
