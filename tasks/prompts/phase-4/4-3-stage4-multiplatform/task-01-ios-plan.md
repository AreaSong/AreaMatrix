# 4-3/task-01: iOS 端规划与最小实现

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

Stage 4 粗粒度任务：复用 Rust core，规划并实现 iOS 端最小闭环。

## 核对清单

1. iOS UI 按移动端重设，不照搬 macOS 三栏。
2. 与 macOS 共用 core 和 iCloud 仓库模型。
3. 支持拍照、分享面板和基础浏览。
4. iOS 特有权限和文件访问边界明确。

## 完成标准

- iOS 端可完成最小导入与浏览。

## 验证

```bash
./scripts/check-all.sh
```

