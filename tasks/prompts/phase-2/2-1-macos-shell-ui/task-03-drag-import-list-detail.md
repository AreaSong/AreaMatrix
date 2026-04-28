# 2-1/task-03: 拖拽导入、列表与详情

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

实现拖拽导入、ImportSheet、文件列表、详情面板和基础操作菜单。

## 核对清单

1. 支持 NSItemProvider 拖入文件。
2. ImportSheet 展示预测分类、目标位置和 Move / Copy / Index。
3. 文件列表支持过滤、排序和选中。
4. 详情面板展示 metadata、change_log、note 和 QuickLook 入口。
5. 上下文菜单支持改名、删除、Finder 显示、复制路径。

## 完成标准

- 拖入到列表或侧栏节点能调用 Core 完成导入。
- UI 不阻塞主线程。

## 验证

```bash
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```

