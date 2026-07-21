# 撤销、标签、批量操作、快捷键、命令面板与智能列表

> 记录 AreaMatrix 已实现的高频组织能力及其可逆性、上下文和文件安全边界。
>
> 阅读时长：约 7 分钟。

---

## 能力关系

- 分类决定文件在资料库中的位置。
- 标签提供跨分类组织维度。
- Saved Search 保存查询规则，Smart List 在侧栏提供固定入口。
- 命令面板聚合当前上下文可执行的命令和目标。
- Undo/Redo 使用 Core 返回的 token 和 action log，不通过猜测文件状态生成反向操作。

## Undo 与 Redo

可逆操作在成功后记录 action log 和 token。UI 可以从 toast 或 Undo History 发起 Undo/Redo；Core 校验 token、当前状态和冲突后执行。

主要规则：

- 只有明确返回可逆 token 的动作才能显示 Undo。
- Undo 失败必须保留原始状态，并给出结构化恢复建议。
- Redo 通过对应 action log 恢复，不直接重放 UI 点击。
- Finder、终端、同步工具产生的外部变化会进入 change log，但不自动生成可执行 Undo。
- 批量操作的 Undo 以批次 token 为边界，不能只恢复其中一部分后仍宣称整批成功。

`Option-Command-Z` 打开 Undo History。主资料库内容获得按键处理时，`Command-Z` 打开 Undo 流程，
`Shift-Command-Z` 加载并执行最新可用 Redo；无可用项或执行失败时打开 Undo History 显示原因。

## 标签

标签支持单文件编辑和批量添加：

- Detail Meta 展示当前标签。
- Add Tag 支持已有标签建议和新标签输入。
- Remove Tag 只移除文件与标签的关联。
- 批量 Add 使用预览和明确选择范围，并返回可逆 action token。
- 当前没有批量 Remove Tag API；移除标签仍在单文件 Detail 中完成。

标签不会改变文件分类或物理路径。标签写入失败时，列表、详情和 action log 必须保持一致或明确进入可重试错误状态。

## 批量操作

主列表多选后可以进入批量动作。当前高风险动作均先展示影响范围：

| 动作 | 前置界面 | 文件影响 |
|---|---|---|
| Change category | 目标分类和路径预览 | repo-owned 文件可能移动；indexed 文件只更新 metadata |
| Rename | 新名称预览和冲突检查 | 只处理所选文件，冲突时不静默覆盖 |
| Add tags | 标签和选择范围 | 不改变文件路径；当前不提供批量 Remove Tag |
| Delete | 删除影响确认 | repo-owned 文件进入 Trash；indexed 文件按合同移除索引 |

批量执行返回逐项结果。部分失败不能被压缩为整批成功；结果页必须区分 succeeded、failed、skipped 和 pending。

## 已实现快捷键

快捷键只在应用处于前台且对应窗口或视图接收事件时生效。AreaMatrix 没有注册系统级全局 hotkey。

### 应用菜单

| 快捷键 | 动作 |
|---|---|
| `Command-I` | 打开 Import |
| `Command-,` | 打开 Settings |
| `Command-K` | 打开 Command Palette |
| `Option-Command-Z` | 打开 Undo History |

### Welcome

| 快捷键 | 动作 |
|---|---|
| `Command-O` | 进入 Choose Path；Browse 才打开目录选择器 |

### 主资料库上下文

| 快捷键 | 动作 |
|---|---|
| `Command-F` | 进入搜索输入 |
| `Command-K` | 切换 Command Palette |
| `Command-Z` | 打开 Undo 流程 |
| `Shift-Command-Z` | 执行最新可用 Redo；失败时进入 Undo History |

各 sheet 的 Return、Escape 等按键使用 SwiftUI default/cancel action，只在该 sheet 内生效。

当前没有 `Command-L`、`Command-1/2/3`、`Command-R` 或“用 `Command-O` 打开当前文件”的应用级合同。

## Command Palette

`Command-K` 打开命令面板。命令来源包括 Core command index 和应用侧安全 fallback；可用项由当前路由、选择状态、只读状态和能力检查决定。

命令面板可以提供：

- Import 和资料库操作。
- 搜索、Saved Search 和 Smart List 入口。
- 当前选择可用的文件动作。
- Settings 和 Help 入口；日志与诊断继续从 Settings 的对应页面进入。

不可执行项应禁用或不展示，并给出原因。命令面板不能绕过批量预览、Replace 确认、Trash 确认、恢复确认或 AI 隐私同意。

## Saved Search 与 Smart List

Saved Search 保存查询、过滤器和显示名称。Smart List 是侧栏中的 Saved Search 投影：

- 点击后进入搜索结果上下文。
- 结果仍使用主列表和详情视图。
- 管理界面支持创建、更新和删除 Saved Search。
- 删除 Smart List 不删除匹配文件。
- 查询错误必须保留规则并提供修正入口，不能静默返回空列表。

## 错误与恢复

- 文件动作失败时保留逐项状态和结构化错误。
- Undo/Redo token 过期或状态冲突时不执行猜测性恢复。
- 批量失败后允许刷新列表、详情和 change log。
- About 文本诊断不包含用户文件正文；repository snapshot 可能包含路径、文件名、标签、笔记和其他
  metadata。两者写出前都进行隐私确认，且不会自动上传。
- 只读资料库禁用写动作，但保留搜索、查看和安全诊断入口。

## 验证重点

- 菜单快捷键与 `AreaMatrixApp` 注册一致。
- 上下文快捷键只在对应视图生效。
- 批量结果准确区分每个状态。
- Undo/Redo 使用真实 token 和 action log。
- Command Palette 不绕过确认边界。
- Smart List 删除不影响用户文件。

## Related

- [ui-states.md](ui-states.md)
- [search.md](search.md)
- [settings-panel.md](settings-panel.md)
- [../modules/change-log.md](../modules/change-log.md)
- [../api/core-api.md](../api/core-api.md)
