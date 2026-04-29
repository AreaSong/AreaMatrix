# 4-3/task-02: C4-02 mobile-repo-connect

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 iOS 端连接已有仓库的 Core 合同和最小 UI 闭环。

## 绑定

- Core 能力：C4-02 mobile-repo-connect
- UX 页面：S4-IOS-01

## 核对清单

1. iOS 端可选择或授权访问仓库位置。
2. 连接前执行 repository validation，不自动接管非仓库目录。
3. 权限不足、iCloud 未下载、版本不兼容都返回结构化错误。
4. 成功连接后能读取仓库配置和基础统计。

## 完成标准

- S4-IOS-01 完成真实连接、失败说明和重试闭环。
- 连接流程不移动、不覆盖用户文件。

## 验证

```bash
./scripts/check-all.sh
```

