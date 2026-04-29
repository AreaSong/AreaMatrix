# S4-X-01 sync-conflict - 多端同步冲突 Review

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-X-01
> 页面类型：多端共用 Review 页面  
> 页面文件：`S4-X-01-sync-conflict.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：iOS、Windows、Linux 共用 UX 规则，各平台原生实现。
- **建议目录**：`apps/*/AreaMatrix/Features/Conflicts/SyncConflictReviewView.*`。
- **建议组件**：`SyncConflictReviewView`、`ConflictVersionCard`、`ConflictResolutionActions`、`ResolutionAuditSummary`。
- **实现边界**：这是具体冲突的 Review 与解决页面。冲突入口 banner / list panel 见 `S4-X-03 sync-conflict-entry`；本页不实现完整内容 diff，也不自动删除任何版本。

## 页面背景

Stage 4 引入多端使用后，同一个 repo 可能被 iOS、Windows、Linux、macOS 或云盘后台同时影响。冲突来源包括云盘冲突副本、同名不同内容、DB 与文件系统不一致、某端尚未同步完成。AreaMatrix 的原则是不静默吞掉冲突、不自动删除用户文件，并把解决动作写入 change log。

入口：`S4-X-03 sync-conflict-entry`、文件详情 `Review`、导入流程中的冲突项。  
退出：用户选择保留两份、指定保留版本、稍后处理、导出诊断；解决后返回原页面并刷新 `Needs Review`。

## 页面功能

- 展示单个冲突或一个冲突组的类型、涉及文件、版本数量、来源平台和检测时间。
- 展示两个或多个版本的基础信息：路径、大小、修改时间、来源设备或同步提供方。
- 默认提供 `Keep both`：两个版本都保留为普通可见文件，incoming 自动编号进入目标目录。
- 提供 `Use existing version`：canonical path 保留 existing；incoming 继续以冲突副本或自动编号文件保留在用户可见目录，不移动到隐藏归档，不删除。
- 提供 `Use incoming version`：危险；只有 Trash/Recycle Bin 或 Core 安全备份能力可用时才允许进入二次确认，否则禁用。
- 对 Replace、Use incoming、删除类动作要求进入 [S4-X-09 replace-confirm](S4-X-09-replace-confirm.md) 或同等二次确认。
- 将解决结果写入 change log，至少包含 conflict id、strategy、kept paths、moved/replaced path、platform、timestamp。
- 支持 `Decide later`，冲突仍留在 `Needs Review`。

## 布局与内容

各平台用原生容器实现，但信息层级一致。

标题：
- `Review sync conflict`
- 返回：平台原生 Back / Close。

冲突摘要：
- `Conflict type: Same name, different content`
- `File: docs/reports/报告.pdf`
- `Detected: Apr 29, 2026 11:30`
- `Source: OneDrive`、`iCloud`、`Local file system`、`Unknown`

版本卡片：
- 版本 A：`Existing file`
  - 路径、大小、修改时间、hash 前 8 位、来源平台。
- 版本 B：`Incoming file` 或 `Conflict copy`
  - 路径、大小、修改时间、hash 前 8 位、来源平台。
- 多版本冲突：按版本列表展示，每个版本都有 `Open`、`Reveal`、`Copy Path` 可用性状态。

解决选项：
- `Keep both`，默认推荐，说明自动编号或保留 conflict copy。
- `Use existing version`，说明 existing 继续占用 canonical path，incoming 会以冲突副本或自动编号名称保留在同一用户可见目录。
- `Use incoming version`，危险，说明 incoming 将成为 canonical path；existing 只会移动到 Trash/Recycle Bin 或 Core 明确提供的安全备份位置。没有可靠恢复能力时禁用。
- `Decide later`，保持冲突状态。

Impact summary：
- 该区块随解决选项实时更新，必须同时展示文件影响和 DB 影响。
- `Keep both`
  - 文件影响：existing 保持原路径；incoming 以自动编号或现有 conflict copy 路径保留在用户可见目录。
  - DB 影响：保留或新增两个可见 file record，关闭当前 conflict id。
  - Change log：写入 `conflict_resolved_keep_both`，包含 conflict id、两个 record id、kept paths、platform、timestamp。
- `Use existing version`
  - 文件影响：existing 保持 canonical path；incoming 不删除，继续以 conflict copy 或自动编号名称保留在用户可见目录。
  - DB 影响：canonical record 指向 existing；incoming record 标记为普通可见文件或已保留副本；关闭当前 conflict id。
  - Change log：写入 `conflict_resolved_use_existing`，包含 conflict id、canonical record id、incoming retained record id、retained path。
- `Use incoming version`
  - 文件影响：incoming 将成为 canonical path；existing 只会移动到 Trash/Recycle Bin 或 Core safety backup 位置。
  - DB 影响：canonical record 将指向 incoming；existing record 保留为可恢复记录或写入安全备份引用；关闭当前 conflict id。
  - Change log：写入 `conflict_resolved_use_incoming`，并先进入 [S4-X-09 replace-confirm](S4-X-09-replace-confirm.md) 展示完整 Replace plan。
- `Decide later`
  - 文件影响：无变化。
  - DB 影响：无变化，conflict id 保持 `Needs Review`。
  - Change log：不写解决日志。

底部按钮：
- `Cancel`
- 主按钮：`Apply resolution`
- 危险路径触发后先打开 [S4-X-09 replace-confirm](S4-X-09-replace-confirm.md)。

## 状态与规则

- 默认状态：选中 `Keep both`，`Apply resolution` 可用。
- 加载态：读取版本元数据时显示 `Loading conflict details...`。
- 空态：冲突 ID 不存在时显示 `Conflict no longer exists.`，提供 `Back to Needs Review`。
- 错误态：版本不可访问时仍显示记录和路径，禁用 `Open` / `Reveal`，提供恢复说明。
- 禁用条件：未选择解决策略、缺少必要版本信息、DB locked。
- 不允许无确认覆盖任一版本。
- 如果平台没有可靠 Trash/Recycle Bin，`Use incoming version` 不能描述为可逆。
- 如果平台没有可靠 Trash/Recycle Bin 且 Core 没有安全备份能力，`Use incoming version` 必须禁用。
- Stage 4 不使用隐藏冲突归档作为默认策略；任何保留版本都必须留在用户可见目录或进入已说明的系统恢复位置。
- 来源平台未知：显示 `Unknown`，不伪造设备名。
- Impact summary 读取失败或缺少必要 record id 时，`Apply resolution` 禁用，并显示 `Could not build resolution impact.`
- 解决失败：冲突保持未解决状态，不删除中间文件。

## 交互

1. 从 `S4-X-03` 或文件详情进入本页时携带 conflict id。
2. 页面加载冲突摘要和版本卡片。
3. 用户可以打开或定位每个版本来确认内容。
4. 用户选择解决策略后，页面刷新 Impact summary，展示将影响的文件路径、record id、conflict id 和 change log 类型。
5. 点击 `Apply resolution` 前，如果 Impact summary 不完整，按钮保持禁用。
6. 若策略涉及替换、删除或移动旧版本，进入 [S4-X-09 replace-confirm](S4-X-09-replace-confirm.md)，明确写出将发生的文件操作和 DB 记录影响。
7. Core 执行解决后更新文件系统、DB、change log，并从冲突列表移除；change log 至少记录 conflict id、strategy、kept paths、moved/replaced path、record ids、platform、timestamp。
8. 用户选择 `Decide later` 或 `Cancel` 时不改变文件、不写解决日志，只保留冲突待处理。

## 数据与依赖

- Conflict detail API：hash、relative path、cloud conflict naming、source-of-truth reconciliation。
- Core conflict resolution API。
- Change log API。
- Change log 字段：conflict id、strategy、kept paths、moved/replaced path、platform、timestamp。
- Impact summary 字段：conflict id、strategy、affected record ids、canonical path、retained paths、backup/recovery target、planned change log type。
- 平台 reveal/open 能力。
- Trash/Recycle Bin 可用性检测。
- 云盘元数据如果不可得，来源显示 Unknown。

## 验收清单

- Review 页面能清楚比较两个或多个版本的路径、大小、修改时间和来源。
- 默认策略是保留两份。
- `Keep both` 和 `Use existing version` 都让两个版本继续保持用户可见。
- `Decide later` 不改变文件系统。
- 每个解决策略都能看到文件影响、DB record 影响和 change log 类型。
- Impact summary 不完整时不能执行解决。
- Replace/Use incoming 等破坏性结果必须进入 [S4-X-09 replace-confirm](S4-X-09-replace-confirm.md) 或同等二次确认。
- 平台不可逆时不能把操作描述为可撤销。
- 无可靠 Trash/Recycle Bin 且无 Core 安全备份能力时，`Use incoming version` 禁用。
- Stage 4 不默认使用隐藏冲突归档，也不把任何版本移入不可见位置。
- 解决成功后 change log 有记录。
- 解决失败时冲突仍留在 `Needs Review`。

## 来源

- 来源类型：组合来源。
- 直接来源：`docs/ux/dedup-conflict.md`。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-15-sync-conflict-detect.md`。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-16-sync-conflict-resolve.md`。
- 组合来源：`docs/architecture/source-of-truth.md`、`docs/adr/0006-icloud-support.md`。
- 推导说明：Stage 4 roadmap 引入多端同步目标，本页将原冲突提示文档收敛为具体 Review 页面；入口提示拆到 `S4-X-03`。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [冲突入口](S4-X-03-sync-conflict-entry.md)
- [Replace 二次确认](S4-X-09-replace-confirm.md)
- [平台能力差异说明](S4-X-02-platform-differences.md)
- [逐页 UI 开发规格索引](../README.md)
