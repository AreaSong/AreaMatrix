# 0-2/task-13: foundation integration verify

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

integration

## 范围

foundation integration verify。

## 绑定

- 无特定 UX/Core 绑定；工程骨架或稳定性任务。

## 核对清单

1. 验收 core crate、脚本、CI、macOS shell 是否形成可执行底座。
2. 确认没有提前实现 C1 或 S1 业务闭环。
3. 记录无法运行的构建命令。

## 完成标准

- 底座足以进入 Phase 1。
- doctor、cargo smoke、脚本语法检查均有证据。

## 验证

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
cd core && cargo test --workspace
```
