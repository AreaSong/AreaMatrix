# 4-3/task-08: C4-08 cloud-permission-state

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现移动端 iCloud/Files 权限与可用性状态检测。

## 绑定

- Core 能力：C4-08 cloud-permission-state
- UX 页面：S4-IOS-06

## 核对清单

1. 返回容器授权、文件可读写、占位状态和同步风险。
2. 权限拒绝、账户未登录、文件未下载、空间不足有独立状态。
3. UI 能引导用户去系统设置或重试授权。
4. 状态检测不得修改仓库文件。

## 完成标准

- S4-IOS-06 展示真实云权限状态和修复路径。
- 权限不足时禁止继续执行导入或写操作。

## 验证

```bash
./scripts/check-all.sh
```

