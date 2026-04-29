# 4-3/task-18: C4-18 missing-file-recovery

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现跨平台文件缺失恢复入口，处理 DB 有记录但文件不可读的情况。

## 绑定

- Core 能力：C4-18 missing-file-recovery
- UX 页面：S4-X-06

## 核对清单

1. 区分文件被删除、路径变化、云占位、权限不足和磁盘未挂载。
2. 提供重新定位、标记缺失、等待同步和移除索引等策略。
3. 移除索引必须二次确认，不删除用户文件。
4. 恢复操作写入 change log。

## 完成标准

- S4-X-06 能完成真实缺失文件诊断与恢复。
- 不把缺失文件恢复误当作普通删除。

## 验证

```bash
./scripts/check-all.sh
```

