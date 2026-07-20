# 拖拽与导入流程

> 记录 AreaMatrix macOS 导入入口、预览、冲突处理、逐项执行、停止与恢复的真实 UX 合同。
>
> 阅读时长：约 8 分钟。

---

## 入口

用户可以通过以下入口发起导入：

- 应用菜单 `Import...`，快捷键为 `Command-I`。
- 主资料库工具栏的 Import。
- Dock/Open Files 请求；资料库尚未可用时排队，打开资料库后再消费。
- 主窗口或侧栏支持的文件拖放区域：根节点和 Smart List 映射到 repository root，分类及子目录映射到
  顶层分类，列表区沿用当前侧栏目标，空资料库映射到 auto classify。
- 文件选择器选择一个或多个文件、文件夹。

所有入口先形成统一的 `ImportEntryRequest`，再进入预览。拖放本身不直接写文件或 DB。

## 预览

预览负责把输入转换为可检查的行：

- 来源名称和类型。
- 预测分类与目标相对路径。
- 存储模式：Copy、Move、Index-only。
- duplicate hash、同名冲突、不可读路径和 iCloud placeholder 状态。
- 用户选择的分类覆盖、命名策略和冲突策略。

预览是只读操作。Apply 之前不得创建最终资料库文件、移动来源文件或写入活动 DB 行。

### 文件夹预扫描

文件夹导入先递归预扫描，再允许执行：

- 默认不包含隐藏文件，也不跟随 symlink。
- `.DS_Store`、`.git/`、`.areamatrix/`、`node_modules/` 等排除项显示汇总。
- 扫描错误会阻止导入，用户只能 Retry scan 或 Cancel。
- 切换“包含隐藏文件”或“跟随符号链接”后重新扫描，不复用旧结果。

## 存储模式

| 模式 | 来源文件 | 资料库文件 | DB |
|---|---|---|---|
| Copy | 保留 | 成功后创建 repo-owned 文件 | 记录 Copied |
| Move | 成功后从来源位置移除 | 成功后创建 repo-owned 文件 | 记录 Moved |
| Index-only | 保留在原位置 | 不创建副本 | 记录 Indexed 和来源路径 |

Move 和 Replace 都必须在执行前显示影响。选择 Move 后，用户通过执行 Import 确认风险，当前没有独立的二次
modal；Replace 始终需要单独二次确认。Index-only 必须提示来源移动会导致条目缺失。

## Duplicate 与同名冲突

duplicate 以内容 hash 为基础，策略包括 Skip、Ask、Keep Both 和经过确认的 Replace。

同名但内容不同的文件默认使用安全的新名称，不覆盖已有文件。Replace 只有在高级设置启用且本次操作再次确认后可用；可恢复的旧 repo-owned 文件进入系统 Trash。

批量冲突可以使用统一策略或逐项处理。未解决的冲突保持 pending，不得被计入成功。

## iCloud placeholder

预览或 Core 发现 placeholder 时返回明确状态：

- 不读取未下载正文。
- 不由 watcher 或 Core 隐式下载。
- UI 可以提供 `Download & retry`，下载动作属于 macOS 平台层并由用户明确触发。
- 下载或重试失败时保留来源和现有资料库状态。

## 执行模型

批量导入由 Swift `ImportBatchCopyImportModel` 逐项串行编排。每个条目调用单文件 Core 导入合同；当前不存在 Core 端的批量 progress callback、worker pool 或并行导入合同。

执行顺序：

1. 保存可恢复的导入 session 摘要。
2. 标记当前行并显示目标路径。
3. 调用单文件 Core 导入。
4. 更新该行的 imported、duplicate、error 或 pending 状态。
5. 保存完成数、失败数和当前路径。
6. 进入下一行，或因停止请求、duplicate 决策或 fatal 错误结束循环。

已完成条目保持完成；单个失败不会被改写为成功。fatal 错误会暂停剩余队列并保留重试上下文。

## 进度界面

进度页显示：

- completed、failed、remaining、pending 和 stopped 数量。
- 当前目标路径。
- 每一行的 importing、imported、failed、skipped 或 pending 状态。
- 查看详情、停止、重试当前项、停止并查看结果、诊断等上下文动作。

AreaMatrix 当前不提供 `Run in background`。关闭进度上下文不能把仍在执行的导入伪装为后台任务。

## Stop after current file

用户选择停止时先确认：

- 已完成的文件保留。
- 未开始的文件取消。
- 当前文件处理到 Core 安全边界后停止。

停止请求不会中断正在进行的文件系统/DB 提交。当前条目返回后，Swift 循环标记 stopped，并不再启动下一项。

停止后结果摘要区分 imported、failed、stopped 和 pending。结果表当前把未开始的 stopped 行显示为
`Skipped`，没有独立的 stopped 行状态。若 session 已到可安全结束条件，应用清除 app-owned session 摘要；
底层 staging 与 DB 恢复仍由 Core 恢复合同负责。

## 失败与重试

失败分为：

- 可重试：权限恢复、placeholder 下载完成、暂时性 DB/IO 错误。
- 需要决策：duplicate、同名冲突、Replace 确认。
- fatal：当前上下文无法安全继续。

重试当前项前，应用先确认保存的 session 和 Core 恢复状态。重试不得重复创建活动行、覆盖已有文件或让 cursor/session 提前表示完成。

## 结果

结果页展示：

- 成功、失败、停止和待处理四个汇总数量。
- 每行状态为 Imported、Skipped、Failed 或 Pending；停止前未开始的行使用 Skipped，并保留原因。
- 最后导入路径。
- 未解决 duplicate 和 iCloud 数量。
- 脱敏详情导出。
- 返回资料库、在 Finder 中查看或继续处理冲突。

详情导出不包含用户文件正文，路径按诊断合同处理。

## 文件安全不变量

- 预览不产生最终写入。
- Copy 失败不删除来源文件。
- Move 只有在文件与 DB 提交成功后才移除来源位置。
- Index-only 不复制或移动来源文件。
- 失败导入不得留下可见的最终目录半成品。
- Replace 不静默覆盖；旧 repo-owned 文件必须可恢复。
- 自动生成内容只写允许的 AreaMatrix 目标，不覆盖 `README.md`。

## 验证重点

- 多路径请求保留顺序和逐项状态。
- Stop 在当前项完成后阻止下一项启动。
- duplicate、同名、placeholder 和 fatal 错误不会被计入成功。
- session 重试幂等，DB 与文件系统保持一致。
- Copy、Move、Index-only 和 Replace 分别满足文件安全合同。

## Related

- [dedup-conflict.md](dedup-conflict.md)
- [ui-states.md](ui-states.md)
- [../user-guide/importing-files.md](../user-guide/importing-files.md)
- [../architecture/transactional-import.md](../architecture/transactional-import.md)
- [../architecture/fs-watcher.md](../architecture/fs-watcher.md)
