# 4-3/task-19: C4-19 manual-rescan

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现跨平台手动重新扫描仓库能力。

## 绑定

- Core 能力：C4-19 manual-rescan
- UX 页面：S4-X-07

## 核对清单

1. 支持 dry-run 预览新增、删除、改名和冲突数量。
2. 执行 rescan 时按事务记录 DB 变化和 change log。
3. 大仓库 rescan 有进度、取消和恢复语义。
4. 不在未确认时修改或删除用户文件。

## 完成标准

- S4-X-07 完成预览、确认、执行、失败恢复闭环。
- 手动 rescan 可作为 watcher 不可用时的替代路径。

## 验证

```bash
./scripts/check-all.sh
```

