# 4-3/task-20: C4-20 repository-settings-cross-platform

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现跨平台仓库设置读取和安全更新合同。

## 绑定

- Core 能力：C4-20 repository-settings-cross-platform
- UX 页面：S4-X-08

## 核对清单

1. 设置页读取仓库路径、版本、分类规则、同步状态和平台能力。
2. 可更新的设置必须经过校验并写入配置。
3. 高风险设置变更需要确认和回滚说明。
4. 不同平台不可用设置显示禁用原因。

## 完成标准

- S4-X-08 由真实仓库配置和平台能力驱动。
- 设置变更不破坏已有仓库和其他平台读取能力。

## 验证

```bash
./scripts/check-all.sh
```

