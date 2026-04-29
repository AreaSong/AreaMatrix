# 4-1/task-06: C2-06 batch-add-tags

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现批量加标签能力，输出逐项结果和 undo token。

## 绑定

- Core 能力：C2-06 batch-add-tags
- UX 页面：S2-09, S2-10

## 核对清单

1. `batch_add_tags` 支持多 file_id 和多 tag。
2. 报告成功、跳过、失败明细。
3. 写入 tags、change log 和 undo action。
4. 部分失败不显示为全成功。

## 完成标准

- 批量加标签不修改文件路径或内容。
- 可撤销项进入 Undo toast/history。

## 验证

```bash
./scripts/check-all.sh
```
