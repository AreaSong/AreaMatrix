# S4-X-07 rescan-confirm - 手动重扫确认

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-X-07
> 页面类型：Windows / Linux dialog  
> 页面文件：`S4-X-07-rescan-confirm.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：Windows、Linux；iOS 不提供常驻 watcher 重扫入口。
- **建议目录**：`apps/*/AreaMatrix/Features/System/RescanConfirmDialog.*`。
- **建议组件**：`RescanConfirmDialog`、`RescanImpactSummary`、`RescanProgressView`。
- **实现边界**：这是手动 `Run rescan now` 前的高风险确认和进度页，不实现底层 watcher 或索引算法。

## 页面背景

Watcher 异常、网络挂载事件不可靠、DB 与文件系统不一致时，用户可能需要手动重扫。重扫会读取 repo 文件树并更新 DB 记录，属于高风险回流动作，必须说明影响、风险、验证结果和失败恢复。重扫不得移动、删除、重命名或覆盖用户文件；它只更新 AreaMatrix 索引，并把无法自动判断的结果留给用户 Review。

入口：`S4-WIN-04 watcher-status`、`S4-LNX-04 watcher-status`、缺失文件恢复页的高级入口。  
退出：成功返回 watcher 状态或主窗口；取消返回来源页；失败停留结果页并保留诊断入口。

## 页面功能

- 显示将要重扫的 repo 路径、预计范围和原因。
- 在真正写入前先运行 dry-run 预览，展示新增、更新、缺失、疑似改名、冲突、不可读和未知数量。
- 说明不会移动、删除、覆盖用户文件。
- 说明 DB 记录可能会更新为当前文件系统状态。
- 说明潜在风险：缺失、权限不足或网络挂载延迟可能让部分记录进入 `Needs Review`，但不会静默删除文件。
- 说明恢复思路：失败或中断时保留上一次可用索引和诊断信息；用户可重试、查看缺失项或导出诊断。
- 要求用户确认后启动。
- 显示重扫进度、成功摘要、失败摘要。
- 防止并发启动多个 rescan。

## 布局与内容

标题：`Run repository rescan?`

影响摘要：
- `Repository: ...`
- `Reason: watcher paused / network mount / manual repair`
- `Scope: entire repository`
- `Estimated items: ...`，不可得时显示 `Unknown`

Dry-run 预览区：
- 阶段：`Preparing preview`、`Scanning preview`、`Review impact`。
- 文案：`Preview only. No database records or files will be changed until you confirm.`
- 摘要字段：
  - `Added`
  - `Updated`
  - `Missing / Deleted from file system`
  - `Renamed candidates`
  - `Conflicts`
  - `Unreadable`
  - `Unknown`
- 列表预览：显示每类最多前 5 项，包含相对路径、检测原因和建议后续动作。
- `Unknown` 大于 0 时显示：`Some changes could not be classified. They will stay in Needs Review if you run rescan.`

安全说明：
- `Rescan reads files and updates AreaMatrix records.`
- `It will not move, delete, rename, or overwrite user files.`
- `Conflicts found during rescan will appear in Needs Review.`
- `Missing or unreadable files will be listed for review, not silently deleted.`

风险与恢复说明：
- `If rescan fails, AreaMatrix keeps unresolved items in Needs Review and preserves diagnostics.`
- `If results look wrong, review missing/conflict items before running another rescan.`

确认项：
- `I understand AreaMatrix will update its index from the current file system state.`

底部按钮：
- `Cancel`
- 主按钮：`Run Rescan`

进度页：
- 阶段：`Scanning files`、`Comparing records`、`Updating index`、`Done`
- 按钮：`Close`；若 Core 支持取消，显示 `Cancel remaining`

结果页：
- 摘要字段：`Added`、`Updated`、`Missing`、`Conflicts`、`Unreadable`、`Skipped`
- 主按钮：`Open Needs Review`，当 `Missing`、`Conflicts` 或 `Unreadable` 大于 0 时显示
- 次按钮：`Review missing`，只筛选缺失和不可读项目
- 辅助按钮：`Export diagnostics`
- 关闭按钮：`Close`

## 状态与规则

- 默认状态：先显示 dry-run 预览入口或自动开始预览；预览未完成时确认项可见但 `Run Rescan` 禁用。
- 加载态：估算范围时显示 `Preparing preview...`；扫描预览时显示 `Scanning preview...`。
- 空态：repo 不可用时显示 `Repository is not available.` 并禁用主按钮。
- 错误态：DB locked、权限不足、路径丢失分别显示恢复动作。
- Dry-run 不写 DB、不修改 change log、不移动、删除、重命名或覆盖任何文件。
- Dry-run 失败：显示 `Could not preview repository changes.`，提供 `Retry preview`、`Export diagnostics`、`Cancel`；不得启用 `Run Rescan`。
- Dry-run 取消：返回来源页或停留本页，未产生任何 DB / change log / 文件变化。
- Dry-run 结果过期：如果预览完成后 watcher 发现 repo 发生新变化，显示 `Preview may be out of date.`，要求重新预览后才能运行。
- `Unknown` 数量不阻断 rescan，但必须在确认项上方说明这些项目会进入 `Needs Review`，不能被当作删除或自动合并。
- 禁用条件：已有 rescan 运行、DB locked、repo path missing、dry-run 未完成、dry-run 失败、预览结果过期、确认项未勾选。
- 失败时不得删除中间文件，不得静默提交半成品索引；已发现但未解决的冲突、缺失和不可读项留在 `Needs Review`。
- 中断态：如果用户关闭应用或平台中断任务，下次打开必须显示上次 rescan 未完成，并提供 `Retry`、`Open Needs Review`、`Export diagnostics`。
- 结果验证：成功页必须显示数量摘要；数量为 `Unknown` 时显示 `Unknown` 而不是猜测。
- 恢复路径：用户认为结果不正确时，先进入 `Open Needs Review` 或 `Review missing`；不得提供“一键删除所有缺失记录”。
- 回滚边界：本页不承诺撤回 Core 已提交的索引更新；只提供基于 change log / Needs Review 的逐项恢复和重新 rescan 路径。

## 交互

1. 来源页点击 `Run rescan now` 后打开本 dialog。
2. 页面先启动 dry-run preview；预览期间只读扫描文件系统和 DB snapshot。
3. dry-run 完成后显示 `Review impact`，用户必须看到 `Added`、`Updated`、`Missing / Deleted from file system`、`Renamed candidates`、`Conflicts`、`Unreadable`、`Unknown`。
4. 用户阅读影响并勾选确认项。
5. 点击 `Run Rescan` 调用 Core rescan API；如果预览已过期，先要求重新运行 dry-run。
6. 进度期间 watcher 状态页显示 `Rescan running`，不能再次启动。
7. 成功后显示新增、更新、缺失、冲突、不可读、跳过数量，并写入可审计的 rescan summary。
8. 如果存在缺失、冲突、不可读或 Unknown 项，结果页主操作为 `Open Needs Review`。
9. 失败后显示 `Retry`、`Open Needs Review`、`Export diagnostics`、`Close`。
10. 用户关闭失败页后返回来源页，watcher 状态保留错误或 needs attention，不把失败标为成功。

## 数据与依赖

- Core rescan API。
- Core rescan dry-run / preview API。
- Repository summary / estimated item count。
- Watcher state snapshot。
- Change log / conflict list / missing list 更新。
- Dry-run preview summary：added、updated、missing_or_deleted_from_fs、renamed_candidates、conflicts、unreadable、unknown、snapshot_id、created_at、is_stale。
- Rescan summary：added、updated、missing、conflicts、unreadable、skipped、started_at、finished_at、status。
- Diagnostic export。
- 错误映射：`DatabaseLocked`、`PermissionDenied`、`PathMissing`、`WatcherUnavailable`。

## 验收清单

- Windows/Linux watcher 页的 rescan 必须先进入本确认页。
- 确认前必须看到 dry-run 影响预览。
- dry-run 期间不写 DB、不写 change log、不修改任何文件。
- dry-run 失败、取消或结果过期时不能启动 rescan。
- 未勾选确认项不能启动重扫。
- 并发 rescan 被禁止。
- 页面明确说明不移动、不删除、不覆盖用户文件。
- 成功结果显示新增、更新、缺失、冲突、不可读、跳过数量。
- 缺失或冲突不会被静默当作删除，必须进入 `Needs Review`。
- 失败或中断不会静默提交半成品索引，且有重试、查看 Review 项和诊断导出。
- rescan summary 可审计，至少能追踪本次扫描状态和结果数量。
- 页面明确说明不承诺一键回滚已提交索引更新，只提供逐项恢复和重新 rescan 路径。
- 屏幕阅读器能读出影响范围、确认项和进度阶段。

## 来源

- 来源类型：组合来源。
- 直接来源：`docs/adr/0005-fsevents-listener.md`、`docs/architecture/source-of-truth.md` 的 watcher/reindex 兜底语义。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-45-s4-x-07-rescan-confirm.md`。
- 组合来源：`AGENTS.md` 高风险边界、Windows/Linux watcher 页面。
- 推导说明：手动重扫从 watcher 页面拆出为独立高风险确认，防止直接触发回流。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [Windows 文件监听状态](S4-WIN-04-watcher-status.md)
- [Linux 文件监听状态](S4-LNX-04-watcher-status.md)
- [缺失文件恢复](S4-X-06-missing-file-recovery.md)
- [逐页 UI 开发规格索引](../README.md)
