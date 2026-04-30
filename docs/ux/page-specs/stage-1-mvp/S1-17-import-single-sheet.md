# S1-17 import-single-sheet - 单文件导入确认

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-17
> 页面类型：导入
> 页面文件：`S1-17-import-single-sheet.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 导入流程
- **建议目录**：`apps/macos/AreaMatrix/Features/Import/`
- **建议组件**：`ImportSheet`、`SingleFileImportView`、`StorageModePicker`、`ClassificationPicker`
- **实现说明**：这是 macOS sheet。点击 Import 前不得发生最终文件系统变更。

## 页面背景

用户拖入或选择 1 个文件后，需要确认 AreaMatrix 的分类建议、命名建议、存储模式和冲突预检结果。

入口：`S1-16 drag-hover` drop 单文件、File -> Import... 选择单文件、或 Dock 图标导入单文件。
退出：Cancel 返回来源主窗口且不写文件；Import 进入 `S1-20 import-progress`；iCloud placeholder 可 Download & retry / Cancel / Switch to local repo。

## 页面功能

- 展示文件预览信息。
- 展示并允许修改建议分类。
- 展示并允许编辑建议命名。
- 选择 Copy / Move / Index-only。
- 展示冲突状态或进入冲突处理区域，并按高级设置决定是否显示 Replace。

## 布局与内容

Sheet 标题：`导入 1 个文件`

文件信息区：

- 图标：文件类型图标，如 PDF。
- 文件名：`合同.pdf`
- 大小：`1.2 MB`
- 来源：`~/Downloads/合同.pdf`

建议分类：

- 标签：`建议分类`
- 下拉：`docs`
- 链接：`为什么？`

建议命名：

- 输入框：`2026Q1_合同_客户A.pdf`

存储模式：

- `Copy`（默认）
- `Move`
- `Index-only`

冲突区：正常显示 `冲突：无`。

iCloud placeholder 区，仅文件尚未下载时显示：

```text
文件尚未从 iCloud 下载。需要下载后才能导入或计算 hash。
```

按钮：`Download & retry`、`Switch to local repo...`。

底部按钮：`Cancel`、`Import`。

## 状态与规则

- 默认状态：preview/hash/conflict precheck 完成且无阻断错误时，`Import` 可用，默认存储模式为 Copy。
- Copy：说明保留原文件。
- Move：说明源文件会从原位置移走。
- Index-only：说明不复制，只记录引用路径；源文件移动后会缺失。
- 文件名非法：输入框下方显示错误或自动修正提示。
- 目标同名：显示冲突预告，进入 `S1-23 conflict-name`。
- hash 重复：进入 `S1-22 conflict-duplicate`。
- `allowReplaceDuringImport=false` 时，冲突区域的 `replaceOptionVisibility=hidden`，不得显示 Replace。
- `allowReplaceDuringImport=true` 且 Trash 可用时，冲突区域的 `replaceOptionVisibility=enabled`，Replace 仍必须进入 `S1-24 replace-confirm`；确认成功后回到本 sheet 并显示 `Replace confirmed`。
- `allowReplaceDuringImport=true` 但 Trash 不可用时，冲突区域的 `replaceOptionVisibility=disabled`，显示 `Replace requires system Trash`。
- preview / hash / conflict precheck 未完成时禁用 `Import`，按钮旁显示当前检查项。
- 目标目录不可写、文件不可读或来源文件已消失时禁用 `Import`，并提供 `Retry preview` 或 `Cancel`。
- iCloud placeholder：禁用 `Import`，显示 `Download & retry` / `Cancel` / `Switch to local repo...`；不得静默跳过。
- iCloud 下载中：显示下载进度，禁用 `Import` 和重复 `Download & retry`，保留 `Cancel`。
- iCloud 下载失败：留在本 sheet，显示错误原因和 `Download & retry` / `Switch to local repo...`；不写文件、不写 DB。
- 空态不适用：本 sheet 只在已有单文件输入时打开；来源文件消失按错误态处理。
- 本页没有直接危险按钮；Replace 只在冲突子区域开启并进入 `S1-24 replace-confirm`。

## 交互

- 分类下拉可覆盖 classifier 推荐。
- 点击 `为什么？` 显示规则解释 popover。
- Cancel 关闭 sheet，不做任何文件系统变更。
- Import 进入 `S1-20 import-progress`；若当前策略为 Replace，必须已有 `Replace confirmed` 标记，否则禁用 Import。
- `Download & retry` 触发协调读取或平台下载，成功后重新执行 preview/hash/conflict precheck。
- `Switch to local repo...` 关闭 sheet 并进入 `S1-02 choose-path` / `S1-03 validate-path` 的换资料库路径流程；不修改当前 repo，直到新 repo 成功打开。
- 禁用状态下按 Enter 不触发导入；错误文本必须说明原因。

## 可访问性

- 文件信息、建议分类、建议命名和存储模式都需要明确标签。
- Import 禁用原因必须是文本，不能只依赖按钮 disabled 外观。
- `为什么？` popover、Cancel、Import、Download & retry 均可通过键盘访问。

## 数据与依赖

- UI import preview adapter：由 Swift 平台层整合 source file metadata、Core `predict_category`、hash/duplicate precheck、target path resolution；若 Core 缺少独立 preview API，不得靠口头约定补齐。
- classifier 预测结果和解释。
- target path resolve。
- conflict preview adapter：基于 Core duplicate/conflict error shape 或 capability spec 生成 `OK` / `DUP` / `NAME` / `ICLOUD` / `ERROR` 状态。
- `allowReplaceDuringImport` settings value。
- Trash availability for Replace。
- iCloud placeholder detection and download state。
- iCloud download state comes from Swift platform layer / NSFileCoordinator; Core only receives ready local files.
- source route，用于 Cancel 或 Switch local 后返回/切换。

## 验收清单

- 默认存储模式为 Copy。
- 分类和命名都可修改。
- Cancel 不写文件。
- 冲突在确认前可见。
- Replace 默认隐藏；只有高级设置开启且 Trash 可用时才进入二次确认路径，确认后仍需点击最终 Import。
- Import 禁用条件可被手工验证。
- iCloud placeholder 不会静默导入或跳过，必须先下载成功或取消/切换本地 repo。

## 来源

- `docs/ux/drag-import-flow.md#importsheet单文件版核心`（直接）。
- `docs/ux/error-messages.md#4-coreerroricloudplaceholdericloud-占位符`（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-20 import-progress](S1-20-import-progress.md)
- [S1-22 conflict-duplicate](S1-22-conflict-duplicate.md)
- [S1-23 conflict-name](S1-23-conflict-name.md)
- [S1-24 replace-confirm](S1-24-replace-confirm.md)
- [S1-02 choose-path](S1-02-choose-path.md)
- [S1-03 validate-path](S1-03-validate-path.md)
