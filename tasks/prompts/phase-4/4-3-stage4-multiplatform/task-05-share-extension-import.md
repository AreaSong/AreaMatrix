# 4-3/task-05: C4-05 share-extension-import

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 iOS Share Extension 导入合同，用于从系统分享入口导入文件。

## 绑定

- Core 能力：C4-05 share-extension-import
- UX 页面：S4-IOS-04

## 核对清单

1. 支持单文件和多文件 share payload。
2. Extension 与主 App 的导入队列状态可同步。
3. 权限、空间不足、文件类型不支持和重复文件有明确错误态。
4. Extension 超时或被系统终止时可恢复或清理 staging。

## 完成标准

- S4-IOS-04 可完成真实分享导入和结果反馈。
- Share Extension 不绕过导入事务和隐私规则。

## 验证

```bash
./scripts/check-all.sh
```

