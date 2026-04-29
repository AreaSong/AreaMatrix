# 4-3/task-21: C4-21 replace-confirm-cross-platform

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现跨平台 replace confirm 合同，保护所有覆盖型写入。

## 绑定

- Core 能力：C4-21 replace-confirm-cross-platform
- UX 页面：S4-X-09

## 核对清单

1. 所有可能覆盖用户文件的操作必须先生成 replace plan。
2. replace plan 明确旧文件、新文件、hash、路径、影响记录和回滚提示。
3. 用户确认后才执行覆盖，取消后不修改最终目录。
4. 执行失败时可恢复 staging 或保持旧文件可用。

## 完成标准

- S4-X-09 覆盖所有平台的替换确认闭环。
- 禁止任何平台绕过 replace confirm 直接覆盖用户文件。

## 验证

```bash
./scripts/check-all.sh
```

