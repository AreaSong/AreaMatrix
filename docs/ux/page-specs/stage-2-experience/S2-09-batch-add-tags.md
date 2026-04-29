# S2-09 batch-add-tags - 批量加标签

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-09
> 页面类型：标签 / 批量
> 页面文件：`S2-09-batch-add-tags.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 标签与批量操作
- **建议目录**：`apps/macos/AreaMatrix/Features/BatchActions/`
- **建议组件**：`BatchAddTagsSheet`、`BatchTagPreviewView`
- **实现说明**：从 Detail multi 进入。批量结果应可撤销或至少可追踪。

## 页面背景

用户多选文件后，希望一次给多个文件添加标签。

入口：Detail multi 的 `Add tag...`、列表右键菜单、命令面板上下文命令。
退出：Apply 成功后返回主窗口并显示 Undo toast；Cancel 不改变任何标签；部分失败时停留结果摘要。

## 页面功能

- 显示已选择文件数量。
- 输入或选择标签。
- 展示会影响多少文件。
- 执行批量添加。
- 完成后显示 Undo toast。
- 显示重复标签跳过数量和部分失败详情。

## 布局与内容

Sheet 标题：`批量添加标签`

摘要：

```text
已选择 50 个文件
```

标签输入：

- 输入框：`Search or create tag...`
- 候选标签列表
- 将添加的标签 chips
- 标签校验复用 `S2-07 tags-add` 的 `Tag slug/displayName normalization`；批量页不另造命名规则。
- Pending tag chip 状态：`Ready`、`Already selected`、`Invalid`、`Blocked`。
- 非法标签错误显示在输入框下方，例如 `Tag name is invalid.`、`Tag already selected.`、`Tag store is read-only.`

预览：

```text
将为 50 个文件添加标签：urgent, clientA
已包含这些标签的文件会跳过重复写入。
```

结果摘要：
- `Added to 47 files`
- `3 files already had these tags`
- `0 failed`

按钮：`Cancel`、`Apply`。

按钮语义：
- `Apply` 是主动作，只提交全部校验通过的 pending tags。
- 任一 pending tag 为 `Invalid`、`Already selected` 或 `Blocked` 时禁用 `Apply`，不得静默跳过无效标签。
- `Cancel` 不创建标签、不写标签关系、不写 change_log。

## 状态与规则

- 默认态：显示选中数量、标签输入和预览。
- 禁用态：未选择任何标签、当前多选为空、tag store 不可写、存在非法标签、存在重复 pending tag 或 tag normalization 失败时禁用 Apply。
- 加载态：候选标签加载中显示 `Loading tags...`；已输入 chips 保留。
- 空态：多选为空时显示 `No files selected` 并只提供 `Close`。
- 错误态：创建新标签失败、批量写入部分失败或 tag normalization 失败时显示结果摘要和 `View details`，成功项保留。
- 恢复态：Undo 失败时显示错误 toast，并允许打开 `S2-11 undo-history` 查看阻塞原因。
- 未选择任何标签时禁用 Apply。
- 空输入不能创建 tag。
- 输入为空、非法字符、超过 tag validator 限制、命中保留名或 normalization 后为空时，输入框下方显示错误并禁用添加到 pending。
- 输入与已有 tag 归一化后相同：复用已有 tag，不创建新 tag。
- 输入与已在 pending chips 中的 tag 归一化后相同：显示 `Tag already selected.`，不新增第二个 chip。
- tag store 只读或不可写时，允许查看候选和已选文件数量，但禁用新建标签和 Apply。
- Apply 前再次运行 tag normalization 和 duplicate validator；失败时不提交任何写入。
- 某些文件已含标签时不重复写入。
- 部分失败时显示结果摘要，成功项保留。
- Apply 后 toast：`已添加标签 [Undo]`。
- Cancel 不改变任何标签或 Tag store。
- 成功新增、重复跳过和失败项都必须出现在可追踪结果摘要中。
- 成功新增的标签关系写入 change_log 并进入 Undo stack；原本已有的标签关系不进入 Undo 反向操作。

## 交互

- 回车添加标签到 pending chips；若输入非法、重复或 tag store 不可写，则显示字段错误，不新增 chip。
- Apply 执行批量写入。
- Undo 移除本次新增标签，不影响原本已有标签。
- 执行中按钮显示 `Applying...`，禁止重复提交。
- 结果摘要中的 `View details` 展开失败文件、原因和是否可重试。
- 结果摘要必须区分 `Added`、`Already had tag`、`Failed`；关闭摘要不丢 change_log。
- 创建新标签失败时保留 pending chips 和输入，用户可修正或重试。

## 数据与依赖

- List multi selection。
- Tag store。
- Tag slug/displayName normalization。
- Tag duplicate validator。
- Invalid tag error mapping。
- Batch tag API。
- Undo stack。
- change_log writer。
- Partial failure recovery state。

## 验收清单

- 多选 50 项可批量加标签。
- 重复标签不会重复写入。
- pending chips 中不能出现归一化后重复的标签。
- 非法、空值、超过限制、保留名或 normalization 失败的标签会阻止 Apply。
- tag store 不可写时不能创建新标签或提交批量关系。
- Undo 只撤销本次新增标签。
- Cancel 不产生任何写入。
- Apply 不会静默跳过无效 pending tag；修复前不可提交。
- 部分失败后能看见成功、跳过、失败数量和失败原因。
- 成功、跳过、失败结果可追踪；新增关系写入 change_log。
- 原本已有标签不会被 Undo 移除。
- Undo 失败可进入 Undo 历史查看阻塞原因。
- 创建新标签失败、批量写入失败和 Undo 失败都有可恢复路径。

## 来源

- `docs/ux/deep-features.md#list-多选批量加标签`（直接来源）。
- 批量失败恢复规则依据 Stage 2 批量体验推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-07 tags-add](S2-07-tags-add.md)
- [S2-10 undo-toast](S2-10-undo-toast.md)
- [S2-11 undo-history](S2-11-undo-history.md)
