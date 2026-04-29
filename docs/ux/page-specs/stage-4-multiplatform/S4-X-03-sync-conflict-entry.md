# S4-X-03 sync-conflict-entry - 多端冲突入口

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-X-03
> 页面类型：多端共用 panel / banner  
> 页面文件：`S4-X-03-sync-conflict-entry.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：iOS、Windows、Linux 共用 UX 规则，各平台原生实现。
- **建议目录**：`apps/*/AreaMatrix/Features/Conflicts/SyncConflictEntry.*`。
- **建议组件**：`SyncConflictBanner`、`NeedsReviewList`、`ConflictBadge`、`ConflictEntryActions`。
- **实现边界**：这是冲突发现入口，不负责具体版本比较和解决；Review 页面见 `S4-X-01 sync-conflict`。

## 页面背景

多端使用后，冲突必须在主浏览、文件详情和导入结果中可见。入口层需要把用户带到 Review 页面，同时保证 `Later` 不改变文件系统。

入口：任一平台主窗口检测到冲突、文件详情状态为冲突、导入结果中存在冲突项。  
退出：点击 `Review` 进入 `S4-X-01 sync-conflict`；点击 `Later` 关闭当前提示但保留 `Needs Review`；错误进入平台错误恢复页。

## 页面功能

- 在主窗口、移动端首页或详情页显示冲突存在。
- 列出冲突数量、最近检测时间、主要冲突类型。
- 提供 `Review` 主操作和 `Later` 次操作。
- 在列表中保留冲突项，不因用户稍后处理而隐藏。
- 对无法读取的冲突记录显示恢复入口。

## 布局与内容

冲突 banner：
- 标题：`Sync conflict needs review`
- 说明：`AreaMatrix found files that may represent different versions. No version has been deleted.`
- 主按钮：`Review`
- 次按钮：`Later`

Needs Review 列表：
- 列/行内容：文件名、相对路径、冲突类型、来源平台、检测时间。
- 状态徽标：`Conflict`、`Missing version`、`Unknown source`。
- 行点击：进入 `S4-X-01 sync-conflict`。

详情页入口：
- 黄色 banner：`This file has a sync conflict`
- 按钮：`Review`

## 状态与规则

- 默认状态：冲突入口可见，`Review` 可用。
- 空态：无冲突时不显示 banner；`Needs Review` 可显示 `No items need review.`。
- 加载态：读取冲突摘要时显示 `Checking conflicts...`。
- 错误态：冲突摘要读取失败时显示 `Could not load review items` 和 `Try again`。
- 禁用条件：冲突记录缺少必要 ID 时，`Review` 禁用并显示 `Repair index first`。
- `Later` 不修改文件、不写入解决日志、不从 `Needs Review` 移除。

## 交互

1. 主页面加载 repo summary 后读取冲突摘要。
2. 有冲突时显示 banner，并在 `Needs Review` 保留列表入口。
3. 点击 `Review` 带着 conflict id 进入 `S4-X-01 sync-conflict`。
4. 点击 `Later` 只关闭当前 banner，会话内可不再重复弹出。
5. 冲突解决成功后入口刷新并从列表移除对应项。

## 数据与依赖

- Core conflict summary / list API。
- 当前平台 open/reveal 能力只在 Review 页面使用。
- 来源平台、检测时间、冲突类型。
- 错误映射：`DatabaseLocked`、`PathMissing`、`PermissionDenied`。

## 验收清单

- 主窗口、移动端首页、详情页至少各有一种冲突入口。
- `Later` 不改变文件系统，也不清除冲突状态。
- 冲突列表行能稳定跳转到 `S4-X-01`。
- 冲突摘要加载失败时用户有重试或恢复路径。
- 屏幕阅读器能读出冲突数量、文件名和 `Review` 操作。

## 来源

- 来源类型：组合来源。
- 直接来源：`docs/ux/dedup-conflict.md` 的冲突可见原则。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-15-sync-conflict-detect.md`。
- 组合来源：`docs/architecture/source-of-truth.md`、`docs/adr/0006-icloud-support.md`、Stage 4 多端页面规格。
- 推导说明：入口层由原 `S4-X-01` 中的 banner/list 语义拆出，避免一个单页同时承载入口和 Review。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [冲突 Review](S4-X-01-sync-conflict.md)
- [平台能力差异说明](S4-X-02-platform-differences.md)
- [逐页 UI 开发规格索引](../README.md)
