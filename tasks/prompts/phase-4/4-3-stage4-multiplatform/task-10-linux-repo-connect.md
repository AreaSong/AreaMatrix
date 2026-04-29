# 4-3/task-10: C4-10 linux-repo-connect

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 Linux 桌面端选择和连接仓库的基础闭环。

## 绑定

- Core 能力：C4-10 linux-repo-connect
- UX 页面：S4-LNX-01

## 核对清单

1. 支持选择已有仓库并执行 validation。
2. 本地目录建议、权限不足、符号链接和挂载点风险有明确提示。
3. 不自动初始化或接管非仓库目录。
4. 连接成功后可读取配置、分类和基础文件统计。

## 完成标准

- S4-LNX-01 完成真实连接和错误恢复。
- Linux 文件系统差异不会破坏 Core 跨平台语义。

## 验证

```bash
./scripts/check-all.sh
```

