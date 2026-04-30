# 0-2/task-04: Core 资源占位

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

Core 资源占位。

## 绑定

- 无特定 UX/Core 绑定；工程骨架或稳定性任务。

## 核对清单

1. 创建默认 classifier.yaml 占位。
2. 占位内容明确不能通过分类能力验收。
3. 不实现真实分类规则应用。

## 完成标准

- 资源文件存在且可被后续分类任务读取。

## 验证

```bash
test -f core/resources/classifier.yaml
```
