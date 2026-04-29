# 4-3/task-13: C4-13 desktop-import-flow

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 Windows/Linux 桌面端导入闭环，复用 Core 事务式导入能力。

## 绑定

- Core 能力：C4-13 desktop-import-flow
- UX 页面：S4-WIN-05, S4-LNX-05

## 核对清单

1. 支持拖拽或文件选择导入单文件、多文件和目录。
2. 分类、重复、命名冲突、replace confirm 和失败恢复复用 Core 语义。
3. 导入进度、取消、失败结果和重试可展示。
4. 平台路径分隔符和权限差异被测试覆盖。

## 完成标准

- S4-WIN-05 和 S4-LNX-05 完成真实导入闭环。
- 失败导入不留下最终目录半成品。

## 验证

```bash
./scripts/check-all.sh
```

