# S4-IOS-05 mobile-file-detail - 移动端文件详情

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-IOS-05
> 页面类型：iOS detail page  
> 页面文件：`S4-IOS-05-mobile-file-detail.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：iOS 移动端。
- **建议目录**：`apps/ios/AreaMatrix/Features/Detail/MobileFileDetailView.swift`。
- **建议组件**：`MobileFileDetailView`、`FilePreviewHeader`、`MobileMetadataSection`、`MobileChangeLogSection`、`MobileNoteSection`。
- **实现边界**：这是 iOS 文件详情页，承接 Stage 1 Detail 的 Meta、Log、Note 能力，但按移动端单列重排。

## 页面背景

用户在移动端资料库中点开一个文件，需要确认它的路径、分类、导入来源、改动日志和笔记，并能打开或分享文件。移动端详情要强调快速查看和安全操作，不放桌面端复杂多列信息。

入口：`S4-IOS-02 mobile-library` 文件行、导入成功结果、`S4-X-03 sync-conflict-entry`。  
退出：返回资料库列表；打开系统预览；冲突进入 `S4-X-01 sync-conflict`；缺失文件进入 `S4-X-06 missing-file-recovery`。

## 页面功能

- 展示文件基础信息：名称、类型、大小、修改时间、分类路径。
- 展示文件状态：正常、iCloud 占位符、缺失、冲突、导入中。
- 提供系统预览或打开动作。
- 提供分享动作。
- 展示 Meta、Log、Note 三个分段。
- Note 支持编辑和保存，遵守现有笔记写入位置。
- 展示最近变更日志，至少包含导入、重命名、移动、替换。
- 对缺失文件和占位符提供恢复动作。

## 布局与内容

使用 `NavigationStack` 单页。顶部是文件摘要，下面是 segmented control。

导航栏：
- 标题：文件名，长文件名中间截断。
- 右侧菜单：`Open`、`Share`、`Reveal in Files`、`Copy Path`。

文件摘要区：
- 文件图标或 QuickLook 缩略图。
- 文件名。
- 分类路径，例如 `Documents / Reports`。
- 状态徽标：`Available`、`iCloud`、`Missing`、`Conflict`。

分段控件：
- `Meta`
- `Log`
- `Note`

Meta：
- `Relative path`
- `Original source`
- `Size`
- `Modified`
- `Hash`，可折叠或长按复制。
- `Imported at`

Log：
- 时间线列表，显示动作、时间、来源平台。
- 替换或删除相关日志必须有醒目但不大面积红色的标记。

Note：
- 多行编辑框。
- 保存状态：`Saved`、`Saving...`、`Could not save`。
- 空态占位：`Add a note for this file.`

## 状态与规则

- 默认状态：文件可访问且无冲突时选中 `Meta` 分段；`Open`、`Share`、`Copy Path` 可用，`Reveal in Files` 按平台能力显示；Note 显示最近保存内容和 `Saved` 状态。
- 加载态：基础 Meta 加载中显示摘要 skeleton；Log 和 Note 分段可显示局部加载，不阻塞返回。
- 空态：Log 为空时显示 `No changes yet.`；Note 为空时显示 `Add a note for this file.`。
- 错误态：Meta 读取失败时显示可读错误和返回入口；Log 或 Note 单独失败时只影响对应分段，并提供 `Try again`。
- 禁用条件：文件不可访问、占位符未下载、权限不足或当前分段正在保存时，相关打开、分享或保存按钮禁用并展示原因。
- iCloud 占位符：禁用 `Open`，显示 `Download and open`。
- 缺失文件：显示 `File is missing from the repository`，提供 `Locate` 或 `Remove record` 的后续入口，点击后进入 `S4-X-06 missing-file-recovery`。
- 冲突文件：顶部显示黄色 banner `This file has a sync conflict`，提供 `Review`，进入 `S4-X-01 sync-conflict`。
- Note 保存失败：保留用户输入，不丢失草稿。
- 文件名过长：导航标题截断，摘要区完整显示并可复制。
- 多选详情不在本页实现，移动端批量操作另开规格。

## 交互

1. 进入详情先加载基础 Meta，再异步加载 Log 和 Note。
2. 点击 `Open` 调用 QuickLook 或系统文件打开；若是占位符先触发下载。
3. 点击 `Share` 使用系统分享。
4. 切换分段不丢失 Note 草稿；如果未保存，返回时提示保存或放弃。
5. 点击 `Reveal in Files` 打开 Files app 中的目标位置，若系统不支持则隐藏该项。
6. Log 中点击某条替换记录可进入只读详情，不提供直接回滚，除非 Stage 2 Undo 能力在移动端明确实现。

## 数据与依赖

- Core file metadata API。
- Core change log API。
- Note 读写 API。
- iOS QuickLook、ShareLink、Files app reveal 能力。
- iCloud placeholder 下载或状态查询。

## 验收清单

- Meta、Log、Note 三段在 iPhone 宽度下可读且不拥挤。
- iCloud 占位符不能直接打开，必须先显示下载动作。
- Note 保存失败时草稿仍在。
- 缺失文件和冲突文件有明确状态，不当作普通文件展示。
- 分享、打开、复制路径等操作按能力显示或隐藏。
- VoiceOver 能读出状态徽标和分段标题。

## 来源

- 来源类型：组合来源。
- 直接来源：Stage 1 Detail 页面规格。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-07-mobile-detail.md`。
- 组合来源：`docs/ux/ui-states.md`、`docs/ux/dedup-conflict.md`。
- 推导说明：Meta/Log/Note 能力沿用桌面详情，按移动端单列重排；缺失与冲突恢复跳转到 Stage 4 共用页面。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [移动端资料库浏览](S4-IOS-02-mobile-library.md)
- [冲突 Review](S4-X-01-sync-conflict.md)
- [缺失文件恢复](S4-X-06-missing-file-recovery.md)
- [逐页 UI 开发规格索引](../README.md)
