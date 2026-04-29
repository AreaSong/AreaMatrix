# 4-1/task-15: C2-15 classifier-rule-editor

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现分类规则列表、编辑、删除能力，支撑设置页规则编辑器。

## 绑定

- Core 能力：C2-15 classifier-rule-editor
- UX 页面：S2-19

## 核对清单

1. 支持 list/update/delete classifier rules。
2. 编辑或删除规则前可进入 impact preview。
3. 删除规则不自动移动历史文件。
4. 配置更新失败回滚旧配置。

## 完成标准

- 常见规则编辑流程可端到端验收。
- 不引入复杂脚本/插件规则。

## 验证

```bash
./scripts/check-all.sh
```
