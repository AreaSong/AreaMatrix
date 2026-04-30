# 0-2/task-06: build-core 脚本

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

build-core 脚本。

## 绑定

- 无特定 UX/Core 绑定；工程骨架或稳定性任务。

## 核对清单

1. 创建 build-core 脚本。
2. 脚本只封装构建与绑定生成前置检查。
3. 失败时输出可读错误。

## 完成标准

- `bash -n` 通过。

## 验证

```bash
bash -n scripts/build-core.sh
```
