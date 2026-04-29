# 4-3/task-12: C4-12 platform-watcher-status

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 Windows/Linux 文件监听状态展示合同。

## 绑定

- Core 能力：C4-12 platform-watcher-status
- UX 页面：S4-WIN-04, S4-LNX-04

## 核对清单

1. 返回监听是否启用、最后事件时间、积压数量和错误原因。
2. Windows、Linux 平台监听能力差异通过 capability flags 表达。
3. 监听不可用时可提示手动 rescan。
4. 监听状态展示不直接修改 DB 或文件系统。

## 完成标准

- S4-WIN-04 和 S4-LNX-04 展示真实 watcher 状态。
- 平台差异不会被包装成通用成功。

## 验证

```bash
./scripts/check-all.sh
```

