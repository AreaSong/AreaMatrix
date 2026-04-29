# S1-09 main-list - 正常文件列表

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-09
> 页面类型：主窗口
> 页面文件：`S1-09-main-list.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 主窗口三栏
- **建议目录**：`apps/macos/AreaMatrix/Features/MainWindow/`
- **建议组件**：`MainWindowView`、`SidebarTreeView`、`FileListTableView`、`DetailPanelView`
- **实现说明**：这是日常主界面，Tree/List/Detail 联动必须稳定。

## 页面背景

资料库已有文件，用户通过左侧分类树浏览，中间表格查看文件，右侧详情查看元数据、日志和笔记。

## 页面功能

- 浏览分类和目录树。
- 表格展示当前范围文件。
- 支持排序、选中、右键操作。
- 单选更新 Detail，多选进入多选摘要。

## 布局与内容

Toolbar：repo 下拉、当前列表过滤框 `Filter current list`、`Import...`、Settings、状态 `Synced` 或 `Idle`。

Sidebar 示例：

- `inbox 3`
- `docs 42`
  - `contracts`
  - `reports`
  - `references`
- `code 18`
- `design 12`
- `finance 9`
- `media 27`

List 标题：`docs`，旁边显示 `42 files`。

表格列：

- Name
- Category / Path
- Size
- Modified
- Imported
- Status

示例行：

- `2026Q1_合同_客户A.pdf | docs/contracts | 1.2 MB | Apr 28, 2026 | Apr 28, 2026 | OK`
- `research-notes.md | docs/references | 84 KB | Apr 27, 2026 | Apr 27, 2026 | OK`

## 状态与规则

- 默认状态：启动后按 `imported_at desc` 排序，默认无 List selection，Detail 为空态。
- 默认排序：`imported_at desc`。
- 当前列表过滤只作用于已加载的当前分类列表；Stage 1 不查询整个资料库，也不做跨字段检索。
- 外部重命名时依靠 fileId 保持选中。
- 删除或移动导致选中项消失时，Detail 显示 moved/missing 提示。
- 无选中时禁用单文件 Rename / Change Category / Delete；多选时隐藏这些单文件右键入口，进入 `S1-15 detail-multi`。
- repo 只读、List loading 或导入队列锁定当前文件时，禁用写操作，保留 Show in Finder / Copy Path。

## 交互

- 选中 Tree 节点：List loading -> ready，Detail 清空。
- 单击 List 行：Detail 显示 Meta。
- 多选 List 行：Detail 进入 `S1-15 detail-multi`。
- 点击 Toolbar `Import...` 打开文件选择；选择单文件进入 `S1-17 import-single-sheet`，选择多个文件进入 `S1-18 import-batch-sheet`，选择文件夹进入 `S1-19 import-folder-sheet`。
- 右键单行：`Show in Finder`、`Rename...`、`Change Category...`、`Delete...`、`Copy Path`。
- `Rename...` 打开 `S1-33 file-rename-sheet`。
- `Change Category...` 打开 `S1-35 change-category-sheet`。
- `Delete...` 打开 `S1-34 file-delete-confirm`；不得直接删除。

## 数据与依赖

- `buildTree`。
- `list_files` / pagination。
- FSEvents 回流通知。

## 验收清单

- 切换分类后列表和 Detail 状态正确。
- 外部重命名不丢选中。
- 表格列和排序可用。
- 单文件 Rename / Change Category / Delete 都进入对应确认页。

## 来源

- `docs/ux/ui-states.md#主界面布局ascii`（直接）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-15 detail-multi](S1-15-detail-multi.md)
- [S1-16 drag-hover](S1-16-drag-hover.md)
- [S1-17 import-single-sheet](S1-17-import-single-sheet.md)
- [S1-18 import-batch-sheet](S1-18-import-batch-sheet.md)
- [S1-19 import-folder-sheet](S1-19-import-folder-sheet.md)
- [S1-33 file-rename-sheet](S1-33-file-rename-sheet.md)
- [S1-34 file-delete-confirm](S1-34-file-delete-confirm.md)
- [S1-35 change-category-sheet](S1-35-change-category-sheet.md)
