# S2-20 icloud-conflict-visual - iCloud 冲突可视化增强

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-20
> 页面类型：冲突增强
> 页面文件：`S2-20-icloud-conflict-visual.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 冲突增强
- **建议目录**：`apps/macos/AreaMatrix/Features/Conflicts/`
- **建议组件**：`ICloudConflictReviewView`、`ConflictVersionPreview`
- **实现说明**：Stage 2 比 Stage 1 更强，允许 metadata + QuickLook/文本预览对比，但默认仍保留两份。

## 页面背景

iCloud 生成冲突副本后，用户需要比较两个版本并选择保留策略。AreaMatrix 不应自动删除任何版本。

入口：List 行 conflict badge、Detail banner 的 `Resolve conflict...`、Needs Review 集合。
退出：Keep both 成功后将冲突记录标记为 resolved/acknowledged 并从 Needs Review 移除；Keep left/right 成功后另一版本进入 Trash；Cancel 不改变文件；失败时保持 unresolved。

## 页面功能

- 展示两个版本 metadata。
- 尽量提供 QuickLook 或文本预览。
- 提供保留两份、保留左侧、保留右侧。
- 删除的一侧必须进 Trash。
- 支持多版本冲突列表。
- 失败时保留冲突状态并提供重试。

## 布局与内容

标题：`解决 iCloud 冲突`

版本对比：

左侧：

- `报告.pdf`
- modified：`2026-04-01 10:20`
- size：`860 KB`
- hash：`a84f...`

右侧：

- `报告 (Conflicted Copy...).pdf`
- modified：`2026-04-01 10:21`
- size：`912 KB`
- hash：`b91c...`

预览区：QuickLook 或文本摘要；不可预览时显示 metadata-only。

按钮：`Keep both`、`Keep left`、`Keep right`、`Cancel`。

按钮语义：
- `Keep both` 是默认主按钮，保留所有版本并只更新冲突状态。
- `Keep left` / `Keep right` 是 destructive confirmation flow；点击后必须弹二次确认，明确另一版本会移动到 Trash。
- `Cancel` 和 `Decide later` 不改变任何文件或 DB 记录。
- Trash 不可用、只读 repo、metadata 不完整时禁用 `Keep left` / `Keep right`，不提供永久删除替代。

多版本冲突：
- 顶部显示 `3 versions found`。
- 左侧版本列表按 modified desc 排序。
- 右侧显示当前选中两个版本的对比。
- `Keep both` 保留全部版本；Keep left/right 只对当前成对选择生效前必须确认。

## 状态与规则

- 默认态：默认选择 `Keep both`。
- 禁用态：未选中可比较版本、metadata 不完整、Trash 不可用或 repo 只读时禁用 Keep left/right，并显示具体原因；写入或移动进行中禁用 Keep both、Keep left、Keep right 和版本切换，`Cancel` 在真正提交前可用；提交进入不可中断阶段后显示 `Finishing...`，避免重复文件操作。
- 加载态：metadata/hash/preview 加载中显示 `Loading conflict details...`。
- 空态：入口打开但冲突已被外部解决时显示 `Conflict no longer exists`，提供 `Refresh` 和 `Close`。
- 错误态：metadata 或 QuickLook 失败时显示原因；metadata 失败禁用 Keep left/right，QuickLook 失败不阻止 metadata 决策。
- 恢复态：Trash 或 change_log 写入失败时保持 conflict unresolved，显示 `Retry` 和 `Decide later`。
- 默认选择 Keep both。
- Trash 不可用时禁用 Keep left/right。
- 只读 repo 只允许查看和 Keep both。
- 无法预览不阻止 metadata 决策。
- Keep left/right 必须明确说明另一版本会移到 Trash；Stage 2 不提供永久删除。
- Keep left/right 点击后必须二次确认：`Move the other version to Trash?`，确认按钮为 destructive `Move other version to Trash`。
- Keep both 必须保留所有版本，将 conflict 状态写为 resolved/acknowledged，并从 Needs Review 中移除；不得删除、移动或覆盖任何版本。
- Keep left/right 成功后只把未保留版本移到 Trash，失败时保持 unresolved，不清除 Needs Review。
- 操作成功后写 change_log 并显示 Undo toast；Undo 失败进入 Undo 历史阻塞态。
- Cancel 和 Decide later 不改变任何文件或 DB 记录。

## 交互

- Keep both 保留所有版本，写入 resolved/acknowledged 状态并从 Needs Review 移除。
- Keep left/right 先打开二次确认；确认后将另一份移到 Trash，并写 change_log。
- Cancel 不改文件。
- 点击 Keep left/right 后按钮显示 `Moving to Trash...`，禁止重复提交。
- 操作失败时显示失败原因，冲突仍显示在 Needs Review。
- 点击版本行只切换预览，不执行任何文件操作。
- 点击 Undo 从 Trash 恢复被移走版本，并重新刷新冲突状态。

## 可访问性

- 键盘：版本列表、左右预览、Keep both、Keep left/right 二次确认和 Cancel 均可键盘访问。
- 焦点：打开后焦点落在冲突标题或默认 `Keep both`；二次确认取消后焦点回到触发的 Keep left/right。
- VoiceOver：读出版本文件名、modified、size、hash、预览可用性、默认策略和 destructive 后果。
- 错误关联：metadata 失败、QuickLook 失败、Trash 不可用、只读 repo 和 change_log 失败必须关联到对应版本或按钮。
- 状态表达：冲突、选中版本、metadata-only、destructive 和 unresolved 状态不能只靠颜色或图标。

## 数据与依赖

- iCloud conflicted copy detection。
- QuickLook preview。
- hash/metadata。
- Trash API。
- change_log。
- Undo stack。
- Needs Review navigation state。
- Conflict resolved/acknowledged state writer。

## 验收清单

- 冲突可视化对比可用。
- 默认不删除。
- Keep both 成功后保留全部版本并从 Needs Review 移除。
- 删除版本走 Trash。
- 操作写入 change_log。
- metadata loading、QuickLook 失败、Trash 不可用、只读 repo、多版本冲突都有 UI。
- Cancel 不改变文件；失败保持 unresolved。
- 成功后有 Undo toast，Undo 失败可在 Undo 历史查看。
- Keep left/right 有 destructive 二次确认；Trash 不可用时禁用且无永久删除替代。

## 来源

- `docs/ux/dedup-conflict.md#icloud-conflicted-copy冲突解决-ux`（直接来源）。
- `tasks/prompts/phase-4/4-1-stage2-experience/task-39-s2-20-icloud-conflict-visual.md`（组合来源）。
- 多版本、Undo 和失败恢复规则依据 Stage 2 冲突增强目标推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-10 undo-toast](S2-10-undo-toast.md)
- [S2-11 undo-history](S2-11-undo-history.md)
- [S2-15 command-palette](S2-15-command-palette.md)
