# 4-1/task-14: C2-14 classifier-impact-preview

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现分类规则影响预览，只读评估规则会影响哪些文件。

## 绑定

- Core 能力：C2-14 classifier-impact-preview
- UX 页面：S2-18

## 核对清单

1. 返回影响数量、样例、冲突和 needs review。
2. 只预览，不写文件、不改分类、不改规则。
3. 影响量超过阈值时提供 warning。
4. 有冲突时禁用批量应用。

## 完成标准

- 预览结果可直接驱动 S2-18。
- 无副作用有测试或验收证据。

## 验证

```bash
./scripts/check-all.sh
```
