# S4-X-09 replace-confirm - 跨平台 Replace 二次确认

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-X-09
> 页面类型：多端共用 dangerous dialog  
> 页面文件：`S4-X-09-replace-confirm.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：iOS、Windows、Linux 共用 UX 规则，各平台原生实现。
- **建议目录**：`apps/*/AreaMatrix/Features/Conflicts/ReplaceConfirmDialog.*`。
- **建议组件**：`ReplaceConfirmDialog`、`ReplaceImpactSummary`、`TrashCapabilityNotice`。
- **实现边界**：这是 Replace / Use incoming 等破坏性结果前的二次确认，不做版本 diff，不自动删除任一版本。

## 页面背景

导入、冲突解决或同步恢复中，用户可能选择用一个版本替换另一个版本。Replace 会改变用户对文件的可见结果，必须确认可逆性、平台回收站能力和 change log 记录。

入口：`S4-WIN-05 import-flow`、`S4-LNX-05 import-flow`、`S4-IOS-07 files-import`、`S4-X-01 sync-conflict`。  
退出：确认后回到来源流程继续执行；取消返回来源流程并保留原策略；失败停留来源流程。

## 页面功能

- 展示将被替换的 existing 文件和 incoming 文件。
- 展示 Replace plan：文件、hash、路径、受影响 DB record、change log 计划和旧文件保留位置。
- 显示平台回收站/Trash 可用性。
- 明确说明旧版本会如何保留：Recycle Bin、Trash，或 Core 明确提供的安全备份位置。
- 要求用户完成二次确认。
- 成功后必须写入 change log。

## 布局与内容

标题：`Confirm Replace`

文件对比：
- `Existing file`：路径、大小、修改时间、hash 前 8 位。
- `Incoming file`：路径、大小、修改时间、hash 前 8 位。

Replace plan：
- `Old file path`
- `New file path`
- `Old hash`
- `New hash`
- `Affected record: <record id> / <relative path>`
- `Conflict or import item: <id>`
- `Old version will be kept at: Recycle Bin / Trash / Core safety backup path`
- `Database update: canonical record will point to incoming file`
- `Change log: replace_file`，包含 old path、new path、old hash、new hash、record id、backup target、platform、timestamp。
- `Recovery note`：说明失败时 existing 文件必须保持可用；如已进入 staging，临时内容会被恢复或清理，不留下最终目录半成品。

可逆性说明：
- Windows Recycle Bin 可用：`The existing file will be moved to Recycle Bin before replacement.`
- Windows Recycle Bin 不可用、检测失败、网络盘不支持或组织策略禁止：默认不显示或禁用 Replace；不得降级为不可逆替换。
- Linux Trash 可用：`The existing file will be moved to Trash before replacement.`
- Linux Trash 不可用：默认不显示或禁用 Replace；Stage 4 不提供不可逆 Replace。
- iOS：不保证系统回收站，优先保留两份；Replace 默认隐藏，除非 Core 提供安全备份。

确认项：
- `I understand this will replace the existing file.`
- 若 Core 提供安全备份能力，追加说明备份位置和恢复限制；否则不显示 Replace。

底部按钮：
- `Cancel`
- 危险按钮：`Replace`

## 状态与规则

- 默认状态：`Replace` 禁用，直到用户完成确认项。
- 加载态：检测 Trash/Recycle Bin 能力时显示 `Checking recovery options...`。
- 空态：缺少任一文件版本时显示 `Replace is not available.`。
- 错误态：回收站能力检测失败时禁用 Replace，不得降级为不可逆替换。
- Core safety backup unavailable：如果 Trash/Recycle Bin 不可用且 Core 没有安全备份，隐藏或禁用 Replace，并提示改用 `Keep both`。
- Trash/Recycle Bin Unknown：按不可用处理，禁用 Replace，不允许把未知恢复能力描述为可撤销。
- DB locked：禁用 Replace，显示 `Database is busy. Try again.`
- 文件不可访问：禁用 Replace，显示具体文件路径和权限/缺失原因。
- Replace plan 缺失或 record id 不完整：禁用 Replace，显示 `Could not build replace plan.`
- 禁用条件：Trash/Recycle Bin 不可用、能力 Unknown、检测失败或 move-to-bin preflight 失败且 Core 未提供安全备份、Core safety backup unavailable、DB locked、文件不可访问、Replace plan 不完整、确认项未完成。
- Windows 与 Linux 规则一致：Recycle Bin / Trash 能力未知或失败时禁用 Replace，不允许把不可逆替换包装成可撤销操作。
- Stage 4 默认禁用不可逆 Replace；未来如需支持，必须另开独立规格重新定义风险、确认和恢复策略。
- 任何 Replace 结果必须写入 change log。
- 执行顺序固定为：preflight -> move old to Recycle Bin/Trash 或 Core safety backup -> write incoming -> update DB -> write change log。
- 任一步失败时 existing 必须保持可用；若 incoming 已进入 staging，则清理或标记为可恢复 staging，不得留下最终目录半成品。

## 交互

1. 来源流程选择 Replace 后打开本 dialog。
2. 页面读取平台回收站能力、move-to-bin preflight、两个版本的元数据和 Replace plan。
3. Replace plan 完整且恢复能力可靠时，用户完成确认项后危险按钮启用。
4. 点击 `Replace` 后来源流程按固定执行顺序执行事务式替换。
5. move old to Recycle Bin/Trash 或 Core safety backup 失败时立即停止，不写 incoming、不更新 DB。
6. write incoming 或 update DB 失败时必须保持 existing 可用，并显示 staging recovery 状态。
7. change log 写入失败时不得把操作标为完成；来源流程显示可恢复错误或重试。
8. 点击 `Cancel` 不改变冲突策略，返回来源流程。

## 数据与依赖

- Core conflict/import replacement API。
- Change log API。
- Replace plan API：old file、new file、hash、paths、affected record id、conflict/import item id、backup target、planned change log entry。
- Trash/Recycle Bin availability。
- Move-to-bin preflight result。
- Core safety backup availability，如无该能力则不得显示不可逆 Replace。
- DB lock state。
- Staging recovery state。
- 文件元数据和 hash。
- 平台错误映射：`PermissionDenied`、`TrashUnavailable`、`DiskUnavailable`、`DatabaseLocked`。

## 验收清单

- Replace 前必定出现二次确认。
- Replace 前必须展示 Replace plan，包含文件、hash、路径、受影响 record、change log 计划和旧文件保留位置。
- 平台不可逆时不能把操作描述为可撤销。
- Linux Trash 不可用时默认禁用 Replace。
- Windows Recycle Bin 失败时不覆盖文件。
- Windows Recycle Bin 检测失败、不可用或 move-to-bin preflight 失败时禁用 Replace。
- Trash/Recycle Bin Unknown、Core safety backup unavailable、DB locked、文件不可访问或 Replace plan 不完整时禁用 Replace。
- 执行顺序必须为 preflight -> 安全保留旧文件 -> 写入 incoming -> 更新 DB -> 写入 change log。
- 任一步失败时 existing 文件保持可用，staging 可恢复或可清理。
- iOS 不默认显示 Replace，除非有安全备份能力。
- 不可逆 Replace 在 Stage 4 不可被执行。
- 成功 Replace 后 change log 有记录。
- 屏幕阅读器能读出危险说明和确认项。

## 来源

- 来源类型：直接来源 + 组合来源。
- 直接来源：`docs/ux/dedup-conflict.md` 的 Replace 二次确认规范。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-21-replace-confirm-cross-platform.md`。
- 组合来源：`AGENTS.md` 高风险边界、Stage 4 Windows/Linux/iOS 导入与冲突页面。
- 推导说明：跨平台回收站能力不同，因此将 Replace 确认抽为多端共用规格。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [冲突 Review](S4-X-01-sync-conflict.md)
- [iOS Files 导入确认](S4-IOS-07-files-import.md)
- [Windows 导入流程](S4-WIN-05-import-flow.md)
- [Linux 导入流程](S4-LNX-05-import-flow.md)
- [逐页 UI 开发规格索引](../README.md)
