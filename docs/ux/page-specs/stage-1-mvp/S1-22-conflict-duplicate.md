# S1-22 conflict-duplicate - 内容重复冲突

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-22
> 页面类型：冲突
> 页面文件：`S1-22-conflict-duplicate.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 导入冲突处理
- **建议目录**：`apps/macos/AreaMatrix/Features/Import/Conflicts/`
- **建议组件**：`DuplicateConflictView`、`ConflictResolutionView`
- **实现说明**：这是 ImportSheet 内的冲突区域，不是独立窗口。默认安全策略是跳过。

## 页面背景

用户导入文件时，AreaMatrix 发现资料库中已有 hash 相同的文件。这代表内容重复，而不是同名冲突。

入口：`S1-17 import-single-sheet` 或批量 ImportSheet 的冲突区检测到 hash 重复。
退出：选择 Skip / Keep both 后回到 ImportSheet 并更新底部主按钮；选择 Replace 时进入 `S1-24 replace-confirm`；Cancel 继承 ImportSheet 的 Cancel，关闭整个导入且不写文件。

## 页面功能

- 显示已有相同内容文件。
- 显示当前导入文件。
- 提供跳过、保留两份策略。
- `allowReplaceDuringImport=true` 时额外提供替换策略，Replace 进入二次确认。

## 布局与内容

标题：`冲突：内容重复`

说明：`资料库中已存在相同内容的文件。`

已有文件：

- 文件名：`合同_2026Q1_客户A.pdf`
- 位置：`docs/contracts/合同_2026Q1_客户A.pdf`
- 导入时间：`Apr 1, 2026`
- 大小：`1.2 MB`

当前文件：

- 文件名：`合同.pdf`
- 来源：`~/Downloads/合同.pdf`
- 大小：`1.2 MB`

选项：

1. `跳过导入（推荐）`
2. `保留两份（自动编号）`
3. `替换已有文件（危险）`，仅 `allowReplaceDuringImport=true` 时显示

辅助按钮：`Show existing file`。

Replace 不可用说明：

- 默认 `allowReplaceDuringImport=false`：不显示 Replace，底部主按钮仍为 `Import`
- 设置开启但 Trash 不可用：显示 disabled Replace 和 `Replace requires system Trash`

底部按钮沿用 ImportSheet：

- `Cancel`
- `Import`，当选择 Replace 时改为 `Continue`

## 状态与规则

- 默认选择 Skip。
- Keep both 显示新文件名，如 `合同_2026Q1_客户A (2).pdf`。
- `replaceOptionVisibility=hidden` 时不渲染 Replace 选项。
- `replaceOptionVisibility=enabled` 时显示 Replace warning，并进入 `S1-24 replace-confirm`。
- 加载态：hash 仍在计算时显示 `Checking duplicate...`，radio group 暂不出现，ImportSheet 底部 `Import` 禁用。
- Keep both 自动编号失败时显示 `无法生成可用文件名`，禁用 `Import`，建议用户改名或 Skip。
- 已有文件无法定位时禁用 `Show existing file`，但仍允许 Skip；Keep both 需重新预检后才能继续；Replace 若可见，也需重新预检后才能继续。
- Trash 不可用时禁用 Replace 选项，并显示 `Replace requires system Trash`。
- 空态不适用：本区域只在已确认 hash 重复时渲染；重复状态消失时返回普通 ImportSheet 冲突区。

## 交互

- Skip 不创建新文件。
- Keep both 只在最终点击 Import 后创建自动编号副本，确认前不写文件。
- Show existing file 在主窗口定位已有条目。
- Replace 不得直接执行。
- Cancel 关闭整个 ImportSheet，不写文件、不写 DB。
- Replace 选中后底部主按钮文案改为 `Continue`，点击只打开 `S1-24 replace-confirm`。

## 可访问性

- 重复原因、已有文件路径和每个 radio 选项说明都需要可读。
- 默认 Skip 不能只靠选中圆点表达；需要文本说明“recommended”。
- `Show existing file`、Cancel、Continue 必须支持键盘访问。

## 数据与依赖

- SHA256 hash 预检。
- 已有 fileId。
- target name auto-number。
- `allowReplaceDuringImport` settings value。
- Trash availability for Replace。

## 验收清单

- 重复文件默认跳过。
- 保留两份会预览新文件名。
- Replace 默认隐藏；开启设置且 Trash 可用时必须二次确认。
- hash 计算中、自动编号失败、Trash 不可用都有禁用或恢复文案。

## 来源

- `docs/ux/dedup-conflict.md#单文件重复hash-dup`（直接）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-17 import-single-sheet](S1-17-import-single-sheet.md)
- [S1-24 replace-confirm](S1-24-replace-confirm.md)
