# 2-3/task-01: 详情、日志与笔记闭环

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

实现 S1-12 到 S1-15：文件元数据详情、改动时间线、伴生笔记和多选摘要。

## 绑定

- UX 页面：S1-12, S1-13, S1-14, S1-15
- Core 能力：C1-11, C1-12, C1-13, C1-14

## 核对清单

1. 选中文件后详情从 `get_file` 读取。
2. 时间线从 `list_changes` 读取。
3. 笔记从 `read_note/write_note` 读写并有保存失败状态。
4. 多选摘要不假造不存在的批量功能。

## 完成标准

- 导入文件后可查看真实元数据、日志和笔记。
- 写笔记后刷新仍能读取，且 change log 可见。
- 详情数据不得是静态示例。

## 验证

```bash
xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```
