# 4-1/task-12: C2-12 classifier-correction

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现分类快速纠错，纠正单文件分类但不直接保存全局规则。

## 绑定

- Core 能力：C2-12 classifier-correction
- UX 页面：S2-16

## 核对清单

1. `correct_file_category` 更新单文件分类。
2. Remember rule 只生成规则草稿，不直接应用大面积规则。
3. 目标冲突按安全移动规则处理。
4. 写入 change log 和可选 undo action。

## 完成标准

- 纠错和保存规则流程分离。
- 不覆盖目标目录已有文件。

## 验证

```bash
./scripts/check-all.sh
```
