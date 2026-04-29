# 4-3/task-04: C4-04 camera-import

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 iOS 相机拍摄导入闭环，将新照片/视频安全写入仓库。

## 绑定

- Core 能力：C4-04 camera-import
- UX 页面：S4-IOS-03

## 核对清单

1. 相机产物进入 staging 后再事务式导入。
2. 分类、去重、命名冲突和失败回滚复用 Core 导入规则。
3. 用户取消拍摄或权限拒绝不产生半成品文件。
4. 导入结果可在移动资料库和桌面端读取。

## 完成标准

- S4-IOS-03 完成拍摄、导入、进度、失败恢复闭环。
- 失败导入不得留下最终目录半成品。

## 验证

```bash
./scripts/check-all.sh
```

