# 4-3/task-16: C4-16 sync-conflict-resolve

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现跨设备同步冲突的人工解决闭环。

## 绑定

- Core 能力：C4-16 sync-conflict-resolve
- UX 页面：S4-X-01, S4-X-03

## 核对清单

1. 支持保留当前、保留外部、另存副本和忽略本次等策略。
2. 每个策略都必须展示会影响的文件和 DB 记录。
3. 解决操作写入 change log，并可在失败时回滚或恢复。
4. 禁止默认覆盖用户文件。

## 完成标准

- 冲突解决必须经过明确确认，并产生可审计记录。
- 解决后多平台读取到一致状态。

## 验证

```bash
./scripts/check-all.sh
```

