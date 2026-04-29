# 4-3/task-06: C4-06 files-import

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 iOS Files app 文件导入闭环。

## 绑定

- Core 能力：C4-06 files-import
- UX 页面：S4-IOS-07

## 核对清单

1. 支持从 Files picker 导入单文件、多文件和目录入口。
2. iCloud 占位文件必须先显式处理下载状态。
3. 导入流程复用 classify、duplicate、conflict 和 staging recovery。
4. 导入后移动端列表和详情可立即读取结果。

## 完成标准

- S4-IOS-07 完成真实 Files 导入闭环。
- iCloud 占位与权限失败不会误判为导入完成。

## 验证

```bash
./scripts/check-all.sh
```

