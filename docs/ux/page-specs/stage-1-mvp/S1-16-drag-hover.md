# S1-16 drag-hover - 拖拽 Hover 投放状态

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-16
> 页面类型：导入
> 页面文件：`S1-16-drag-hover.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 导入流程
- **建议目录**：`apps/macos/AreaMatrix/Features/Import/`
- **建议组件**：`DropZoneOverlay`、`SidebarDropTargetModifier`、`ImportCoordinator`
- **实现说明**：这是主窗口拖拽 hover 状态，不是 sheet。drop 后才进入 ImportSheet。

## 页面背景

用户从 Finder 或其他 app 拖文件进入 AreaMatrix，但尚未松手。界面必须说明可投放、目标分类是什么、可以拖到侧栏改变目标。

## 页面功能

- 高亮可投放区域。
- 显示将导入到哪个分类。
- 支持 Sidebar 节点作为 drop target。
- 识别单文件、多文件、文件夹。

## 布局与内容

主窗口保持三栏，List 区域覆盖半透明 overlay。

Overlay 文案：

```text
Drop files to import
导入到：docs
拖到左侧分类可改变目标
```

多文件：`Drop 12 files to import`

文件夹：`Drop folder to import recursively`

拖到 Sidebar `finance` 节点时：

- `finance` 节点高亮。
- Overlay 目标改为 `导入到：finance`。
- Tooltip：`Import into "finance"`。

## 状态与规则

- 默认状态：拖入 List 区域时目标为当前 Tree selection；拖入空白区域时目标为 auto classify。
- 拖出窗口后 overlay 消失。
- 不支持的 item 显示轻量 warning，但不阻断其他有效文件。
- Drop 到 Sidebar 节点优先级高于当前选中分类。
- 没有有效 file URL 或 file promise 时禁用 drop 接收，显示 `Cannot import this item`。
- 全部拖入项都没有有效 file URL 或 file promise 时，drop 不进入 ImportSheet，不创建 import session。
- 空态不适用：hover overlay 只在拖拽进入窗口时出现；无拖拽时回到来源主窗口。
- 加载态不适用：解析拖拽 item 的短暂等待仍显示 hover overlay，不展示独立 loading 页面。
- 错误态：全部 item 无效时显示 non-blocking warning 或 toast，overlay 消失，不写文件、不写 DB。

## 交互

- Drop 到 List：目标为当前 Tree selection。
- Drop 到 Sidebar：目标为该节点。
- Drop 到 Root 节点：目标为 repo root，`destination=selectedDirectory`，不自动分类。
- Drop 到窗口空白区域：目标为自动分类，`destination=autoClassify`。
- File -> Import...：目标为自动分类，`destination=autoClassify`。
- 松手后进入单文件、多文件或文件夹 ImportSheet。
- 单个普通文件 drop 后进入 `S1-17 import-single-sheet`；多个文件进入 `S1-18 import-batch-sheet`；一个或多个文件夹进入 `S1-19 import-folder-sheet`。
- 全部拖入项无效时，松手后显示非阻断 warning 或 toast：`Cannot import these items`，随后 overlay 消失并回到原主窗口。

## 可访问性

- overlay 文案必须读出目标分类和 drop 结果，不只依赖高亮边框。
- Sidebar drop target 的目标变化要有文本 tooltip 或可访问说明。
- 无效拖拽 warning 需要可被 VoiceOver 宣告。

## 数据与依赖

- NSItemProvider。
- URL / file promise 解析。
- 当前 Tree selection。

## 验收清单

- Hover 时用户能看出目标分类。
- Sidebar 节点 hover 会改变目标。
- 空白区域 drop 与 File -> Import 都明确进入自动分类，不沿用当前 selection。
- 拖出窗口恢复正常 UI。
- 全部无效拖拽不会创建 import session，不写文件、不写 DB。

## 来源

- `docs/ux/drag-import-flow.md#drop-zone-与视觉态`（直接）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-17 import-single-sheet](S1-17-import-single-sheet.md)
- [S1-18 import-batch-sheet](S1-18-import-batch-sheet.md)
- [S1-19 import-folder-sheet](S1-19-import-folder-sheet.md)
