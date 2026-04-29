# 4-3/task-14: C4-14 onedrive-risk-state

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 Windows OneDrive 路径风险识别与提示能力。

## 绑定

- Core 能力：C4-14 onedrive-risk-state
- UX 页面：S4-WIN-03

## 核对清单

1. 检测 OneDrive 路径、占位文件、同步状态和潜在冲突风险。
2. 风险提示不阻塞只读浏览，但阻止危险写入或要求确认。
3. 提供转移仓库、等待同步、手动 rescan 等可操作建议。
4. 检测过程不修改用户文件。

## 完成标准

- S4-WIN-03 可展示真实 OneDrive 风险状态。
- 高风险写操作前有明确保护。

## 验证

```bash
./scripts/check-all.sh
```

