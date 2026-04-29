# 2-3/task-03: 单文件操作闭环

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

实现 S1-33 到 S1-35：Rename、Delete/Remove from Index、Change Category 的 UI 闭环。

## 绑定

- UX 页面：S1-33, S1-34, S1-35
- Core 能力：C1-22, C1-23, C1-24, C1-10, C1-21

## 核对清单

1. Rename sheet 使用真实 `rename_file`。
2. Delete/Remove from Index 区分 Trash 与索引移除。
3. Change Category 调用真实 `move_to_category` 并展示目标路径预览。
4. Cancel 不产生任何写入，失败状态可重试。

## 完成标准

- 操作成功后 List/Detail/Log 刷新。
- Indexed 文件路径安全边界符合页面规格。
- 危险操作缺少确认时验收不通过。

## 验证

```bash
xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```
