# S4-X-06 missing-file-recovery - 缺失文件恢复

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-X-06
> 页面类型：多端共用 dialog / sheet  
> 页面文件：`S4-X-06-missing-file-recovery.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：iOS、Windows、Linux 共用 UX 规则，各平台原生实现。
- **建议目录**：`apps/*/AreaMatrix/Features/Recovery/MissingFileRecovery.*`。
- **建议组件**：`MissingFileRecoveryView`、`MissingFileSummary`、`RemoveRecordConfirm`。
- **实现边界**：这是 DB 记录存在但文件系统中找不到文件时的恢复页，不自动删除记录，也不修改用户文件。

## 页面背景

多端同步、外部移动、磁盘断开或云盘占位符失败都可能导致文件缺失。用户需要定位、重新连接、稍后处理或删除记录。删除记录是危险动作，只删除 AreaMatrix 记录，不删除磁盘文件。

入口：`S4-IOS-05 mobile-file-detail`、Windows/Linux 主窗口缺失文件行、`S4-X-03 sync-conflict-entry`。  
退出：定位成功返回原详情；稍后处理返回原页面；删除记录成功返回列表；错误停留本页。

## 页面功能

- 显示缺失文件的相对路径、最近已知位置、最后见到时间。
- 区分路径丢失、权限不足、云盘占位符、外接盘断开。
- 提供 `Locate File`、`Try Again`、`Decide Later`。
- 明确 `Locate File` 结果：hash 匹配才可重新关联；hash 不匹配不得覆盖或直接关联；权限不足保留缺失状态；用户取消不改变 DB 或文件系统。
- 在 Windows / Linux 上，当缺失可能来自 watcher 停止、网络挂载延迟或多项索引不同步时，提供高级入口 `Run Rescan...`，进入 `S4-X-07 rescan-confirm`。
- 提供危险动作 `Remove Record...`，进入同页二次确认区或平台 alert。
- 删除记录成功后写入 change log。

## 布局与内容

标题：`File is missing`

摘要区：
- `File: docs/reports/report.pdf`
- `Last known location: ...`
- `Last seen: Apr 29, 2026 11:30`
- `Reason: Path missing / Permission denied / Cloud placeholder / Unknown`

恢复动作：
- 主按钮：`Locate File`
- 次按钮：`Try Again`
- 次按钮：`Decide Later`
- 高级按钮：`Run Rescan...`，仅 Windows / Linux 且需要全库索引回流时显示。
- 危险按钮：`Remove Record...`

危险确认区：
- 标题：`Remove this record?`
- 文案：`This removes the AreaMatrix record only. It will not delete any user file from disk.`
- 输入确认或 checkbox：`I understand this only removes the record.`
- 按钮：`Cancel`、`Remove Record`

## 状态与规则

- 默认状态：显示最近已知信息，`Locate File` 可用。
- 加载态：重新检查路径时显示 `Checking file...`。
- 空态：缺少历史路径时显示 `No last known path is available.`，隐藏 reveal 类操作。
- 错误态：定位失败时保留页面并显示原因。
- Locate hash 匹配：允许 `Relink File`，成功后写入 change log 并返回来源页。
- Locate hash 不匹配：显示 `Selected file does not match the missing record.`，不得覆盖、不得关联；可进入 [S4-X-01 sync-conflict](S4-X-01-sync-conflict.md) 建立冲突 Review，或要求用户重新选择。
- Locate 权限不足：显示 `Permission denied` 和平台恢复动作，保留缺失状态。
- Locate 用户取消：关闭 picker 后停留本页或返回来源页，不改变 DB 或文件系统。
- `Run Rescan...` 显示条件：仅 Windows / Linux；当前 repo 已连接；缺失原因可能是 watcher stopped、network mount、external move、批量缺失或连续 `Try Again` 仍无法恢复。
- `Run Rescan...` 隐藏条件：iOS、未连接 repo、只需重新授权 iCloud/Files 权限、当前平台无 rescan 能力。
- `Run Rescan...` 禁用条件：DB locked、已有 rescan 运行、repo path missing、dry-run capability 不可用或 watcher 状态未知且无法判断范围；禁用时必须显示原因。
- `Run Rescan...` 不直接重扫，必须进入 [S4-X-07 rescan-confirm](S4-X-07-rescan-confirm.md) 的 dry-run 影响预览；取消后返回本页，缺失状态保持不变。
- 禁用条件：未完成危险确认时 `Remove Record` 禁用。
- 删除记录不删除磁盘文件；如果文件稍后重新出现，按外部新增/重扫规则处理。

## 交互

1. 页面打开时重新检查文件是否恢复。
2. 点击 `Try Again` 触发只读路径检查，不做全库 rescan。
3. 点击 `Run Rescan...` 打开 [S4-X-07 rescan-confirm](S4-X-07-rescan-confirm.md)；该页先做 dry-run，用户取消或 dry-run 失败时返回本页并保留缺失状态。
4. 点击 `Locate File` 打开平台 picker；选中文件后先做只读权限与 hash 校验。
5. hash 匹配时显示 `Relink File` 确认，确认后调用 Core relink API 并写入 change log。
6. hash 不匹配时不得直接关联；用户可重新选择，或进入 [S4-X-01 sync-conflict](S4-X-01-sync-conflict.md) 作为不同版本处理。
7. 权限不足时显示恢复动作；用户取消 picker 时不改变任何记录。
8. 点击 `Decide Later` 返回原页面，缺失状态保留在 `Needs Review`。
9. 点击 `Remove Record...` 展开危险确认。
10. 确认后调用 Core 删除记录 API，写入 change log。

## 数据与依赖

- Core file detail / missing status API。
- Core locate/relink 或 remove record API。
- Core hash validation 和 conflict creation/review handoff。
- Change log API。
- 平台 file picker / reveal 能力。
- 云盘、权限、路径可达性检测。
- Windows / Linux watcher 状态、rescan capability、dry-run capability 和已有 rescan 运行状态。

## 验收清单

- 缺失文件不会被当作普通文件打开。
- `Try Again` 是只读检查，不触发全库重扫。
- Windows / Linux 的 `Run Rescan...` 只有在需要全库索引回流时显示，且不能绕过 `S4-X-07` 的 dry-run 和确认。
- iOS 不显示 `Run Rescan...`，iCloud/Files 权限问题应进入权限恢复路径。
- `Locate File` 只有 hash 匹配才可重新关联，并且成功后写入 change log。
- hash 不匹配时不得覆盖或直接关联，可进入冲突 Review 或要求重新选择。
- 权限不足和用户取消都不会修改 DB 或文件系统。
- `Remove Record` 必须二次确认，并明确不删除磁盘文件。
- 删除记录成功后 change log 有记录。
- `Decide Later` 不改变文件系统或 DB。
- 屏幕阅读器能读出缺失原因和危险按钮含义。

## 来源

- 来源类型：组合来源。
- 直接来源：`docs/ux/ui-states.md`、`docs/ux/error-messages.md` 的缺失与恢复语义。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-44-s4-x-06-missing-file-recovery.md`。
- 组合来源：`docs/architecture/source-of-truth.md`、`docs/modules/change-log.md`。
- 推导说明：移动端详情中的 `Remove record` 后续入口被拆成多端共用恢复规格。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [移动端文件详情](S4-IOS-05-mobile-file-detail.md)
- [冲突入口](S4-X-03-sync-conflict-entry.md)
- [手动 rescan 确认](S4-X-07-rescan-confirm.md)
- [逐页 UI 开发规格索引](../README.md)
