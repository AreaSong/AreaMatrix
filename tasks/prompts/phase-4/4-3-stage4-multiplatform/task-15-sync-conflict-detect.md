# 4-3/task-15: C4-15 sync-conflict-detect

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现跨设备同步冲突检测能力，先检测和展示，不自动合并。

## 绑定

- Core 能力：C4-15 sync-conflict-detect
- UX 页面：S4-X-01, S4-X-03

## 核对清单

1. 检测同一路径多版本、外部改名、删除后重现和 metadata 分歧。
2. 冲突项包含文件路径、候选版本、来源、时间和风险说明。
3. 检测结果不自动移动、删除或覆盖文件。
4. 冲突状态可被多平台入口一致读取。

## 完成标准

- S4-X-01/S4-X-03 能展示真实冲突列表和详情。
- 未解决冲突不会被静默当作成功同步。

## 验证

```bash
./scripts/check-all.sh
```

