# S1-12 detail-meta - 文件元数据详情

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-12
> 页面类型：详情
> 页面文件：`S1-12-detail-meta.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 详情面板
- **建议目录**：`apps/macos/AreaMatrix/Features/Detail/`
- **建议组件**：`DetailPanelView`、`MetaTabView`、`FileActionButtons`
- **实现说明**：List 单选时默认显示 Meta tab。Log 和 Note 懒加载。iCloud 冲突、缺失文件和只读状态的入口由本页集中呈现。

## 页面背景

用户选中一个文件，需要快速知道它在哪、是什么、如何进入资料库、当前状态是否正常。

入口：`S1-09 main-list` 单选文件、导入完成后自动选中新文件、或 `S1-36 icloud-conflict-list` 定位到某个冲突文件。
退出：切换到 `Log` / `Note` tab、切换 List 选中项、清空选择、打开文件操作 sheet、进入 iCloud 冲突解决 sheet。

## 页面功能

- 展示文件摘要和核心元数据。
- 展示分类、路径、大小、hash、导入时间等。
- 提供 Show in Finder、Copy Path、Open。
- 文件缺失时提供恢复动作。
- iCloud 冲突副本可见，并提供单项或全库冲突入口。

## 布局与内容

顶部摘要：

- 文件图标
- 文件名：`2026Q1_合同_客户A.pdf`
- 相对路径：`docs/contracts/2026Q1_合同_客户A.pdf`

Tabs：`Meta`、`Log`、`Note`。

Meta 字段：

- Category：`docs / contracts`
- Storage mode：`Copy`
- Size：`1.2 MB`
- Imported：`Apr 28, 2026 10:32`
- Modified：`Apr 28, 2026 10:31`
- SHA256：`a84f91c2...`
- Source：`~/Downloads/合同.pdf`
- Status：`OK`
- Conflict：`None` / `iCloud conflicted copy`

iCloud 冲突 banner，仅存在冲突时显示：

```text
这是 iCloud 生成的冲突副本。AreaMatrix 不会自动删除任何一个版本。
```

按钮：`Resolve conflict...`、`Review all conflicts...`。

底部操作：`Show in Finder`、`Copy Path`、`Open`、更多菜单 `Rename...` / `Change Category...` / `Delete...`。

## 状态与规则

- 默认状态：单选文件后立即展示已缓存 metadata；缺失的 hash、conflict 或 classifier explanation 可显示 loading 占位，不阻塞基础字段。
- 空态：无选中时显示 `detailEmpty`，不显示 Meta 字段。
- 加载失败：保留文件名和相对路径，显示 inline error `无法加载文件详情`，按钮 `Retry` / `Collect Diagnostics...`；诊断不包含用户文件内容。
- 文件缺失：显示 banner `该文件已缺失`，按钮 `Locate...` / `Remove from index`。
- 外部移动：显示 `该文件已移动到 <path> [Go to]`。
- iCloud conflicted copy：显示冲突 banner 和 `Resolve conflict...`；默认不删除、不移动、不合并任何版本。
- 当前文件可唯一配对到一组冲突时，`Resolve conflict...` 打开 `S1-25 icloud-conflict-min`。
- 当前 repo 有多组冲突或配对不确定时，显示 `Review all conflicts...`，进入 `S1-36 icloud-conflict-list`；不确定时禁用单项 Resolve。
- 只读：禁用写操作，保留查看。
- 打开文件、Reveal、Copy Path 失败时显示非阻断错误，保留本页状态。
- `Remove from index` 必须打开 `S1-34 file-delete-confirm` 的 Remove from index 模式，不得在本页直接执行。

## 交互

- 点击 `为什么？` 可打开分类解释 popover。
- `Show in Finder` 定位文件或目标目录。
- `Copy Path` 复制相对路径或绝对路径，按菜单文案区分。
- `Rename...` 打开 `S1-33 file-rename-sheet`。
- `Change Category...` 打开 `S1-35 change-category-sheet`。
- `Delete...` 或 `Remove from index` 打开 `S1-34 file-delete-confirm`。
- `Resolve conflict...` 打开 `S1-25 icloud-conflict-min`，成功后刷新本页 conflict 字段和 banner。
- `Review all conflicts...` 打开 `S1-36 icloud-conflict-list`，关闭后回到当前文件详情并刷新状态。
- `Go to` 外部移动目标时切换 Tree/List 到新位置并保持 fileId 选中；目标不存在时显示可恢复错误。

## 可访问性

- 所有字段必须有标签和值，缺失值读作 `Unknown` 或 `Not available`。
- banner、冲突提示、missing 状态不能只靠颜色表达。
- 文件操作菜单和 Resolve conflict 入口必须可通过键盘访问。

## 数据与依赖

- FileEntry metadata。
- classifier explanation。
- missing/index-only/readonly 状态。
- iCloud conflicted copy 识别和 conflict pair provider。
- Detail metadata loading/error state。
- Finder reveal API。

## 验收清单

- 单选文件后 Meta 能立即显示，不等待 Log/Note。
- 缺失文件有 Locate 和 Remove from index，且移除索引需要确认。
- 所有字段有标签和值。
- iCloud 冲突文件有明确 badge/banner，不会被静默处理。
- 单项冲突进入 `S1-25`；全库或不确定冲突进入 `S1-36`。
- 详情加载失败不清空当前文件摘要，并有 Retry/Diagnostics。

## 来源

- `docs/ux/ui-states.md#detail详情面板状态机`（直接）。
- `docs/ux/classifier-calibration.md#为什么分到这里解释面板`（组合）。
- `docs/ux/dedup-conflict.md#icloud-conflicted-copy冲突解决-ux`（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-33 file-rename-sheet](S1-33-file-rename-sheet.md)
- [S1-34 file-delete-confirm](S1-34-file-delete-confirm.md)
- [S1-35 change-category-sheet](S1-35-change-category-sheet.md)
- [S1-25 icloud-conflict-min](S1-25-icloud-conflict-min.md)
- [S1-36 icloud-conflict-list](S1-36-icloud-conflict-list.md)
