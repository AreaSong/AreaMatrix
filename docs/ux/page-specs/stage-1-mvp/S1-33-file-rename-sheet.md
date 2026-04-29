# S1-33 file-rename-sheet - 单文件重命名

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-33
> 页面类型：文件操作
> 页面文件：`S1-33-file-rename-sheet.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 主窗口文件操作 sheet。
- **建议目录**：`apps/macos/AreaMatrix/Features/FileActions/RenameFileSheet.swift`。
- **建议组件**：`RenameFileSheet`、`FilenameValidationMessage`。
- **实现说明**：只处理单文件重命名；不做批量重命名，不改分类，不覆盖同名文件。

## 页面背景

用户在文件列表或详情页对一个已索引文件选择 Rename。页面目标是让用户修改文件名，同时明确失败、冲突和取消都不会改变原文件。

入口：`S1-09 main-list` 行右键 `Rename...`，或 `S1-12 detail-meta` 的文件操作菜单。
退出：重命名成功回到 `S1-09 main-list` 并保持 fileId 选中；Cancel 返回入口页；失败留在本 sheet。

## 页面功能

- 显示当前文件名和所在相对目录。
- 输入新文件名。
- 即时校验空值、非法字符、未变化、同目录同名冲突。
- 成功后写入 change_log 并刷新 List / Detail。

## 布局与内容

标题：`Rename File`

文件摘要：
- `Current name`: `合同.pdf`
- `Location`: `docs/contracts/`
- `Storage mode`: `Copy` / `Move` / `Index-only`

输入区：
- 标签：`New name`
- 输入框默认选中文件名主体：`合同`
- 扩展名默认保留：`.pdf`
- 帮助文案：`Only the file name changes. Category and notes stay attached to this file.`

底部按钮：`Cancel`、主按钮 `Rename`。

## 状态与规则

- 默认状态：`Rename` 禁用，直到新文件名与当前文件名不同且合法。
- 空名称：显示 `File name is required`，禁用 `Rename`。
- 非法字符：显示 `File name cannot contain ":"`，禁用 `Rename`。
- 同目录已有同名文件：显示 `A file with this name already exists in docs/contracts`，禁用 `Rename`，提供 `Show existing file`。
- Index-only 文件：只更新索引中的显示名和 change_log；不移动来源文件，文案必须说明这一点。
- 只读 repo 或文件不可写：禁用 `Rename`，显示权限恢复入口。

## 交互

1. 打开 sheet 时焦点在 `New name`，默认选中文件主体，不选扩展名。
2. 用户输入时即时校验并更新错误文案。
3. `Cancel` 关闭 sheet，不写文件、不写 DB。
4. `Rename` 调用单文件重命名动作，执行中按钮显示 `Renaming...` 并防重复点击。
5. 成功后关闭 sheet，List 行就地更新，Detail Meta 和 Log 刷新。
6. 失败时保留输入内容，显示可复制错误，用户可修改后重试或 Cancel。

## 数据与依赖

- 当前 `fileId`、相对路径、存储模式。
- 文件名合法性校验。
- 同目录冲突检查。
- 单文件 rename API。
- change_log 写入与 List 刷新通知。

## 验收清单

- 重命名不改变分类、笔记和 fileId。
- 空名、非法字符、同名冲突都会禁用 `Rename`。
- Cancel 不发生任何文件系统或 DB 写入。
- 成功后 change_log 出现 rename 记录。
- Index-only 文件不会移动源文件。

## 来源

- `docs/roadmap/stage-1-mvp.md#功能完整性`（直接）。
- `docs/ux/ui-states.md#三件套之间的联动契约`（组合）。
- `AGENTS.md` 中高风险文件操作边界（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-09 main-list](S1-09-main-list.md)
- [S1-12 detail-meta](S1-12-detail-meta.md)
