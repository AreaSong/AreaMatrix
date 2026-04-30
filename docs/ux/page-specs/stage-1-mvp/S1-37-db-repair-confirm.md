# S1-37 db-repair-confirm - 数据库修复确认

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-37
> 页面类型：错误恢复
> 页面文件：`S1-37-db-repair-confirm.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 错误恢复确认页或 sheet。
- **建议目录**：`apps/macos/AreaMatrix/Features/ErrorRecovery/DatabaseRepairConfirmView.swift`。
- **建议组件**：`DatabaseRepairConfirmView`、`RepairProgressView`。
- **实现说明**：只处理 DB corrupted / metadata repair 的确认和进度；不删除用户文件，不接管新目录。

## 页面背景

当 Core 报告数据库损坏或元数据需要重建时，用户必须先理解修复会做什么，再明确确认。修复对象是 `.areamatrix/` 元数据，不是用户文件。

入口：`S1-11 main-repo-error` 的 `Open repair`；`S1-27 settings-repository` 错误状态的 `Open recovery tools...`；`S1-32 error-recovery` 的 DB corrupted 分支。
退出：Cancel 返回错误页；修复成功进入 `S1-10 main-loading` 后回到 `S1-09 main-list`；失败回到本页并可导出诊断。

## 页面功能

- 说明 DB corrupted 的影响。
- 说明 Full rescan 会重建索引元数据，不删除用户文件。
- 要求确认后才能执行。
- 展示修复进度和失败恢复动作。

## 布局与内容

标题：`Repair Repository Metadata?`

说明：
```text
AreaMatrix cannot read the repository metadata database. Your files remain in the repository folder.
```

将执行：
- 备份或保留当前损坏的 `.areamatrix/` 元数据状态，供诊断使用。
- 重扫资料库文件夹。
- 重建可用的本地索引。
- 重新加载 Tree / List / Detail。

不会执行：
- 不移动用户文件。
- 不重命名用户文件。
- 不删除用户文件。
- 不覆盖已有 `README.md`。
- 不自动上传诊断。

确认复选框：
`我理解修复只处理 AreaMatrix 元数据，不会删除我的资料库文件`

底部按钮：`Cancel`、`Export diagnostics...`、主按钮 `Run Full Rescan`。

## 状态与规则

- 默认状态：显示确认复选框未勾选，`Run Full Rescan` 禁用，`Export diagnostics...` 可用。
- 未勾选确认复选框时，`Run Full Rescan` 禁用。
- 如果 Core 无法创建元数据恢复点或诊断快照，禁用 `Run Full Rescan`，只允许导出诊断。
- 修复执行中锁定写操作，但允许显示只读进度。
- 修复失败不得删除现有用户文件，也不得清空原诊断信息。
- `Export diagnostics...` 必须说明不包含用户文件内容、不自动上传、路径和用户名会脱敏。
- 空态不适用：本页只在已有 DB corrupted / repair-needed 错误上下文时打开；上下文缺失时返回来源错误页并提示重新检测。

## 交互

1. 打开页面时读取 repo path、DB error code、最近一次成功打开时间。
2. 用户可先点击 `Export diagnostics...` 保存本地诊断包。
3. 用户勾选确认后，`Run Full Rescan` 可用。
4. 点击 `Run Full Rescan` 后进入进度态：`Scanning files`、`Rebuilding index`、`Reloading repository`。
5. 成功后进入主窗口加载态，再回到正常列表。
6. 失败时留在本页，显示错误、`Retry Full Rescan`、`Export diagnostics...`、`Open repository in Finder`。
7. `Cancel` 返回来源错误页，不执行修复。

## 可访问性

- 修复会做什么、不会做什么和确认复选框必须逐项可读。
- 进度态需要读出当前步骤，不只依赖 spinner。
- Cancel、Export diagnostics、Run Full Rescan、Retry Full Rescan 均可通过键盘访问。

## 数据与依赖

- Core DB corrupted / repair-needed error。
- repo path 和 last successful open metadata。
- full rescan / repair API。
- metadata recovery point 或 diagnostics snapshot。
- Diagnostics exporter。
- Finder reveal。

## 验收清单

- DB corrupted 不会直接自动修复。
- 页面明确说明用户文件仍在资料库文件夹中。
- 未确认前不能运行 Full rescan。
- 修复成功和失败路径都有可见反馈。
- 诊断导出不包含用户文件内容、不自动上传。
- Cancel 不修改 DB 或文件系统。

## 来源

- `docs/ux/error-messages.md#22-db-corruptedcritical`（直接）。
- `docs/ux/ui-states.md#关键错误态设计不阻断`（组合）。
- `AGENTS.md` 中 DB schema / 数据修复高风险边界（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-09 main-list](S1-09-main-list.md)
- [S1-10 main-loading](S1-10-main-loading.md)
- [S1-11 main-repo-error](S1-11-main-repo-error.md)
- [S1-27 settings-repository](S1-27-settings-repository.md)
- [S1-32 error-recovery](S1-32-error-recovery.md)
