# 4-1/task-02: 自定义分类 UX

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

Stage 2 粗粒度任务：分类规则 UI、批量操作、快捷键与命令面板。

## 核对清单

1. 用户可新增、编辑、禁用分类规则。
2. 批量改名、批量标签、批量改分类可撤销或可确认。
3. 命令面板和快捷键不破坏主流程。
4. `classifier.yaml` 与 UI 编辑保持一致。

## 完成标准

- 用户不需要直接编辑 yaml 即可完成常见分类调整。

## 验证

```bash
./scripts/check-all.sh
```

