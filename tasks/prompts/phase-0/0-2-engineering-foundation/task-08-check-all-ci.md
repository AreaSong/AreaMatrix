# 0-2/task-08: check-all 与 CI

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

check-all 与 CI。

## 绑定

- 无特定 UX/Core 绑定；工程骨架或稳定性任务。

## 核对清单

1. 创建 check-all 聚合脚本。
2. 校准 core-ci 与 macos-ci。
3. CI 不绕过 doctor。

## 完成标准

- 脚本语法检查通过。
- doctor 仍通过。

## 验证

```bash
bash -n scripts/check-all.sh
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
```
