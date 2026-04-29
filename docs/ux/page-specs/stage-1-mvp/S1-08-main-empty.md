# S1-08 main-empty - 空资料库主窗口

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-08
> 页面类型：主窗口
> 页面文件：`S1-08-main-empty.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 主窗口三栏
- **建议目录**：`apps/macos/AreaMatrix/Features/MainWindow/`
- **建议组件**：`MainWindowView`、`SidebarTreeView`、`FileListEmptyView`、`DetailEmptyView`
- **实现说明**：repo 已打开但没有文件；主窗口结构要完整呈现。

## 页面背景

用户刚完成初始化，资料库还没有任何文件。页面不能空白，要明确告诉用户下一步是拖入文件或点击 Import。

## 页面功能

- 显示默认分类树。
- 显示空列表引导。
- 显示空详情提示。
- 支持拖拽导入和 Import 按钮。

## 布局与内容

Toolbar：

- repo 名称下拉：`AreaMatrix ▾`
- 当前列表过滤框：placeholder `Filter current list`
- `Import...`
- Settings 图标按钮
- 状态：`Idle`

Sidebar：

- `inbox 0`
- `docs 0`
- `code 0`
- `design 0`
- `finance 0`
- `media 0`

默认选中 `inbox`。

List 空态：

```text
这里还没有文件
把文件拖到这里，AreaMatrix 会自动分类、命名并记录改动。
```

按钮：`Import...`

Detail 空态：

```text
选择一个文件查看详情
文件的元数据、改动时间线和伴生笔记会显示在这里。
```

## 状态与规则

- Tree 为 ready，List 为 empty，Detail 为 empty。
- 整个 List 空态区域是 drop zone。
- 当前列表过滤框可显示但结果为空；它只过滤当前已加载列表，不查询全库、不跨字段检索。
- 默认选中 `inbox`；无文件时 Detail 写操作禁用。
- Import sheet 打开时主窗口底层写操作禁用，但拖拽 hover 仍按 sheet 外层处理。

## 交互

- 点击 Import 打开文件选择；选择单文件进入 `S1-17 import-single-sheet`，选择多个文件进入 `S1-18 import-batch-sheet`，选择文件夹进入 `S1-19 import-folder-sheet`。
- 拖入文件进入 `S1-16 drag-hover`。
- 切换 Sidebar 分类，List 仍显示对应分类空态。

## 数据与依赖

- `open_repo` 成功结果。
- `buildTree` 默认分类。
- 当前分类文件查询返回空。

## 验收清单

- 空库不显示空白窗口。
- 默认分类和计数可见。
- Import 和拖拽入口可用。

## 来源

- `docs/ux/ui-states.md#空态listempty规范`（直接）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-16 drag-hover](S1-16-drag-hover.md)
- [S1-17 import-single-sheet](S1-17-import-single-sheet.md)
- [S1-18 import-batch-sheet](S1-18-import-batch-sheet.md)
- [S1-19 import-folder-sheet](S1-19-import-folder-sheet.md)
