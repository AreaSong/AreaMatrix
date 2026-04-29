# 4-1/task-18: C2-18 redo-action-log

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 Redo 反馈与历史闭环，补齐 Undo 之后的反向恢复能力。

## 绑定

- Core 能力：C2-18 redo-action-log
- UX 页面：S2-22

## 核对清单

1. 只有成功 Undo 的 AreaMatrix 动作进入 redo stack。
2. 新写操作会清空 redo stack，并让 UI 显示不可 redo 原因。
3. Redo 复用原 action 的安全执行路径和错误处理。
4. Redo 成功或失败都写入可审计状态。

## 完成标准

- S2-22 能展示真实 redo 可用性、执行结果和失败原因。
- Redo 失败不破坏当前 DB 与文件系统状态。

## 验证

```bash
./scripts/check-all.sh
```

