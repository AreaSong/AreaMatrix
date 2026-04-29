# 4-3/task-17: C4-17 platform-capabilities

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现平台能力矩阵，让 UI 知道当前平台支持和限制哪些功能。

## 绑定

- Core 能力：C4-17 platform-capabilities
- UX 页面：S4-X-02

## 核对清单

1. 返回 watcher、share extension、camera import、cloud provider、文件预览等能力 flags。
2. 不支持能力必须带原因和替代路径。
3. UI 依据能力矩阵隐藏、禁用或降级功能。
4. 能力矩阵不替代权限检测和真实操作校验。

## 完成标准

- S4-X-02 平台差异页面由真实 capability 数据驱动。
- 各平台不会展示不可用却可点击的关键操作。

## 验证

```bash
./scripts/check-all.sh
```

