# S4-IOS-07 files-import - iOS Files 导入确认

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-IOS-07
> 页面类型：iOS sheet  
> 页面文件：`S4-IOS-07-files-import.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：iOS 移动端。
- **建议目录**：`apps/ios/AreaMatrix/Features/Import/FilesImportReviewSheet.swift`。
- **建议组件**：`FilesImportReviewSheet`、`FilesImportPreviewList`、`MobileConflictSummary`、`ImportProgressView`。
- **实现边界**：这是从 Files app 或系统 document picker 选中项目后的确认 sheet，不实现 Share Extension，也不在选择完成前写入 repo。

## 页面背景

用户在移动端资料库点击 `+` -> `Import from Files`，从 Files app 选择一个或多个文件后，需要确认文件、目标分类和冲突策略。iOS 端默认复制到 repo，不提供原地索引作为 Stage 4 MVP 能力。

入口：`S4-IOS-02 mobile-library` 的 `Import from Files`。  
退出：导入成功返回 `S4-IOS-02 mobile-library` 并显示结果 toast；取消返回资料库；权限或 iCloud 错误进入 `S4-IOS-06 icloud-permission`；Replace 二次确认进入 `S4-X-09 replace-confirm`。

## 页面功能

- 展示从 Files app 选择的文件数量、名称、来源位置和总大小。
- 允许选择目标分类，默认使用自动建议或最近分类。
- 单文件可编辑导入文件名；多文件显示命名规则，不逐项编辑。
- 仅提供 `Copy into repository`，不显示 `Move` 或 `Index in place`。
- 检测重复内容、同名冲突、不可读、iCloud 占位符未下载。
- 默认冲突策略为安全策略：重复内容 `Skip duplicate`，同名不同内容 `Keep both`。
- 显示导入进度和结果，失败时保留可重试状态。

## 布局与内容

使用 iOS 原生 sheet，iPhone 为中高 sheet，iPad 可为 form sheet。不要出现桌面表格或三栏布局。

标题区：
- 标题：`Import from Files`
- 左上角：`Cancel`
- 右上角：`Import`

来源区：
- 单文件：文件图标、文件名、来源位置、大小。
- 多文件：`5 items selected`、总大小、前 3 个文件名预览。
- iCloud 占位符：行内徽标 `In iCloud`。

目标区：
- 字段：`Target category`
- 默认值：自动建议分类；无法建议时为 `Inbox`。
- 单文件字段：`File name`
- 保存方式只读行：`Copy into repository`

冲突区：
- 重复内容：显示 `Duplicate content`，默认 `Skip duplicate`。
- 同名不同内容：显示 `Name conflict`，默认 `Keep both` 并展示自动编号预览。
- Replace 选项如展示，必须标为危险，并在应用前进入 `S4-X-09 replace-confirm`。

底部状态：
- 加载：`Reading selected files...`
- 导入：`Copying files...`、`Writing metadata...`
- 成功：`Imported 5 items`
- 失败：显示失败项数量和 `Retry failed`

底部按钮：
- `Cancel`
- 主按钮：`Import`

## 状态与规则

- 默认状态：文件读取完成后，`Import` 可用，冲突策略自动选择安全默认值。
- 未选择文件：显示空态 `Choose files to import.`，`Import` 禁用。
- 加载态：读取文件、检测 iCloud 占位符、计算 hash 或分类建议时显示 `Reading selected files...`，`Import` 临时禁用。
- 错误态：文件不可读、iCloud 下载失败、目标分类不可写或导入失败时显示失败原因，并保留可恢复动作。
- 文件名为空或非法：`Import` 禁用，显示字段级错误。
- 文件不可读：保留在列表中并标为 `Unreadable`，允许跳过其余文件。
- iCloud 占位符未下载：显示 `Download needed`，提供 `Try download`；失败进入 `S4-IOS-06`。
- 目标分类不可写：`Import` 禁用，提供 `Choose another category`。
- 导入中：禁止再次选择文件；若 Core 不支持取消，`Cancel` 改为 `Close when done`。
- 导入失败：不删除源文件，不留下最终目录半成品。

## 交互

1. 点击 `Import from Files` 打开系统 document picker。
2. 用户选中文件后进入本 sheet，先做只读预览和冲突检测。
3. 用户可修改目标分类和单文件文件名。
4. 点击 `Import` 后执行事务式导入，显示分阶段进度。
5. 如选择 Replace，先进入 `S4-X-09 replace-confirm`，确认后再执行。
6. 成功后回到 `S4-IOS-02 mobile-library`，toast 动作为 `View imported files`。
7. 用户取消时不写入 repo，也不删除 Files app 中的源文件。

## 数据与依赖

- iOS document picker / SwiftUI file importer。
- security scoped access for selected files。
- iCloud placeholder 状态与下载触发能力。
- Core transactional import API。
- Duplicate/name conflict detection。
- 分类建议和最近分类。

## 验收清单

- 单文件、多文件、iCloud 占位符、不可读文件都能展示预览。
- 默认保存方式只复制到 repo，不移动源文件。
- 同名冲突默认 `Keep both`，重复内容默认 `Skip duplicate`。
- Replace 必须进入 `S4-X-09` 二次确认。
- iCloud 下载失败能进入权限/恢复页。
- 导入成功后资料库列表立即可见新文件。
- VoiceOver 能读出文件名、状态、目标分类和 `Import` 禁用原因。

## 来源

- 来源类型：组合来源。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-06-files-import.md` 的 iOS 最小导入与浏览目标。
- 组合来源：`docs/ux/drag-import-flow.md`、`docs/ux/dedup-conflict.md`、`docs/adr/0006-icloud-support.md`。
- 推导说明：Files app 选择后的移动端确认 sheet 依据现有 iOS 平台能力推导，且遵守不移动、不删除、不覆盖用户文件的不变量。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [移动端资料库浏览](S4-IOS-02-mobile-library.md)
- [iCloud 权限提示](S4-IOS-06-icloud-permission.md)
- [Replace 二次确认](S4-X-09-replace-confirm.md)
- [逐页 UI 开发规格索引](../README.md)
