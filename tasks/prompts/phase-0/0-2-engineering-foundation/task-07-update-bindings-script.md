# 0-2/task-07: update-bindings 脚本

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

update-bindings 脚本。

## 绑定

- 无特定 UX/Core 绑定；工程骨架或稳定性任务。

## 核对清单

1. 创建更新绑定脚本。
2. 脚本明确输入 UDL 和输出目录。
3. 本任务不提交生成的产品绑定。

## 完成标准

- `bash -n` 通过。

## 验证

```bash
python3 -m py_compile scripts/dev_tools/*.py
```
