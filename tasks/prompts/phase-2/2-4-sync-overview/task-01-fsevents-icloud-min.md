# 2-4/task-01: FSEvents 与 iCloud 最小闭环

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

实现 macOS watcher 最小闭环：去抖、InFlight 过滤、iCloud placeholder 提示和外部变化同步。

## 绑定

- UX 页面：S1-09, S1-10, S1-13, S1-25
- Core 能力：C1-17, C1-18, C1-19, C1-21

## 核对清单

1. FSEvents 只在 macOS app 层实现，Core 不依赖 macOS API。
2. 去抖和 InFlight 过滤避免把应用自身写入误判为外部变化。
3. Created/Renamed/Removed 事件传给真实 Core sync。
4. iCloud placeholder 进入 S1-25 最小处理。

## 完成标准

- 外部新增、重命名、删除能反映到列表和日志。
- iCloud 占位符不导致静默失败或误删除。
- watcher 相关高风险路径有测试或可复现实验记录。

## 验证

```bash
xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
cd core
cargo test --workspace sync
```
