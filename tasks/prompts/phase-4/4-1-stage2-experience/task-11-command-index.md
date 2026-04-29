# 4-1/task-11: C2-11 command-index

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现命令面板数据索引，按当前 selection context 返回可执行命令。

## 绑定

- Core 能力：C2-11 command-index
- UX 页面：S2-15

## 核对清单

1. 命令列表按上下文过滤。
2. Smart List、文件候选、最近命令可发现。
3. 危险动作只返回入口，不绕过确认页。
4. 不支持或无权限动作禁用或解释。

## 完成标准

- Cmd+K 不绕过高风险确认。
- 命令索引不修改文件或 DB，除可选 recent command。

## 验证

```bash
./scripts/check-all.sh
```
