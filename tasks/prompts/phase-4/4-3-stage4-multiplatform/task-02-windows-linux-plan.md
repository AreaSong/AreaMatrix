# 4-3/task-02: Windows / Linux 端规划

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

Stage 4 粗粒度任务：规划 Windows / Linux 平台适配，复用 Rust core。

## 核对清单

1. Windows 文件监听选择 ReadDirectoryChangesW。
2. Linux 文件监听选择 inotify。
3. UI 技术栈和 binding 策略有 ADR。
4. OneDrive / 本地目录差异与 iCloud 差异分开处理。

## 完成标准

- 多端扩展前的技术路线、风险和验证基线清楚。

## 验证

```bash
./scripts/check-all.sh
```

