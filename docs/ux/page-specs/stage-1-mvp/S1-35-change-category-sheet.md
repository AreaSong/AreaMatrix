# S1-35 change-category-sheet - 单文件改分类

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-35
> 页面类型：文件操作
> 页面文件：`S1-35-change-category-sheet.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 主窗口文件操作 sheet。
- **建议目录**：`apps/macos/AreaMatrix/Features/FileActions/ChangeCategorySheet.swift`。
- **建议组件**：`ChangeCategorySheet`、`TargetPathPreview`。
- **实现说明**：只处理单文件跨分类移动；Stage 1 不提供多选改分类。

## 页面背景

用户想把一个文件从当前分类移动到另一个分类。页面必须预览最终位置，避免同名冲突和误移动。

入口：`S1-09 main-list` 行右键 `Change Category...`，或 `S1-12 detail-meta` 操作菜单。
退出：成功回到 `S1-09 main-list` 并定位新位置；Cancel 返回入口页；失败留在本 sheet。

## 页面功能

- 显示当前分类和目标分类。
- 预览目标相对路径。
- 处理目标路径冲突。
- 成功后写入 change_log 并刷新 Tree / List / Detail。

## 布局与内容

标题：`Change Category`

文件摘要：
- `Name`: `合同.pdf`
- `Current category`: `docs/contracts`
- `Storage mode`: `Copy` / `Move` / `Index-only`

目标区：
- 下拉：`Target category`
- 默认值：当前 Tree selection 以外的最近常用分类，若无则为 `inbox`
- 路径预览：`Will move to docs/contracts/合同.pdf`

冲突说明区：
- 无冲突：`No conflict at target location`
- 自动编号：`Target name exists. AreaMatrix will use 合同 (2).pdf`
- 无法自动编号：`Cannot create a safe target name. Rename the file first.`

底部按钮：`Cancel`、主按钮 `Change Category`。

## 状态与规则

- 默认状态：显示当前分类、目标分类下拉、目标路径预览和 Cancel / Change Category。
- 目标分类等于当前分类时禁用 `Change Category`。
- 目标路径不可写时禁用主按钮，显示权限恢复入口。
- 目标同名且可安全自动编号时，必须预览最终名称。
- 自动编号失败时禁用主按钮，并提供 `Rename first` 入口到 `S1-33 file-rename-sheet`。
- Index-only 文件只更新分类元数据和 change_log，不移动源文件；页面必须显示说明。
- 确认前不移动、不重命名、不删除任何文件。
- 空态不适用：本 sheet 只在已有单文件 fileId 时打开；缺失上下文按错误态返回来源页。
- 加载态：目标路径预检或同名冲突检查中显示 `Checking destination...`，禁用 Change Category。

## 交互

1. 用户选择目标分类后，立即更新路径预览和冲突状态。
2. `Cancel` 关闭 sheet，不写文件、不写 DB。
3. `Rename first` 打开 `S1-33 file-rename-sheet`，完成后回到本 sheet。
4. `Change Category` 执行动作，执行中显示 `Moving...` 并防重复点击。
5. 成功后 Tree 计数更新，List 跳转到目标分类并高亮该文件。
6. 失败时显示错误、`Retry` 和 `Collect Diagnostics...`；诊断不包含用户文件内容。

## 可访问性

- 当前分类、目标分类、目标路径和冲突状态必须有字段标签。
- 自动编号预览和 Index-only 说明需要文本读出。
- Cancel、Rename first、Change Category、Retry 均可通过键盘访问。

## 数据与依赖

- 当前 `fileId`、当前分类、存储模式。
- 分类列表和最近使用分类。
- 目标路径 resolver。
- 单文件 change-category API。
- change_log 写入和 Tree/List 刷新通知。

## 验收清单

- 改分类前能看到最终目标路径。
- 同名冲突不会覆盖目标文件。
- Index-only 改分类不移动源文件。
- Cancel 不发生任何写入。
- 成功后新位置可见且 change_log 有记录。

## 来源

- `docs/roadmap/stage-1-mvp.md#功能完整性`（直接）。
- `docs/product/prd.md#场景-4外部修改也不丢`（组合）。
- `AGENTS.md` 中文件移动和覆盖安全边界（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-09 main-list](S1-09-main-list.md)
- [S1-12 detail-meta](S1-12-detail-meta.md)
- [S1-33 file-rename-sheet](S1-33-file-rename-sheet.md)
