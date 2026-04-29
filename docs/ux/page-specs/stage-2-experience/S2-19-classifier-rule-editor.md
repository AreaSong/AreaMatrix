# S2-19 classifier-rule-editor - 自定义分类规则编辑器

> 所属阶段：Stage 2 体验完善
> 页面 ID：S2-19
> 页面类型：自定义分类
> 页面文件：`S2-19-classifier-rule-editor.md`
> 上级索引：[stage-2-experience.md](../stage-2-experience.md)

## 开发位置

- **目标平台**：macOS 分类规则 UI
- **建议目录**：`apps/macos/AreaMatrix/Features/Classifier/`
- **建议组件**：`ClassifierRuleEditor`、`CategoryListEditor`、`RuleDetailEditor`
- **实现说明**：替代直接编辑 YAML 的常见路径，但仍保留 Open YAML 高级入口。

## 页面背景

用户想新增、编辑或停用分类匹配规则，不希望直接改 classifier.yaml。

入口：Settings -> Classifier、命令面板 `Open classifier rules`、规则影响预览 Back。
退出：Save 成功后留在设置页并显示保存状态；Revert 回上次有效版本；Open YAML 只打开高级入口，不关闭设置页；Cancel/关闭设置页时提示未保存更改。

## 页面功能

- 管理分类列表。
- 管理每个分类承载的扩展名、关键词、优先级和命名模板。
- 校验并保存到 classifier.yaml。
- 回退到上次有效版本。
- 预览单条规则影响。
- 删除分类或删除扩展名/关键词值前展示影响并二次确认。
- 处理保存失败和校验错误。

## 布局与内容

Settings -> Classifier 中新增可视化编辑区。

左侧分类列表：

- docs
- code
- design
- finance
- media
- inbox

左侧工具：
- 搜索分类。
- `New category`
- 分类行状态：has errors、dirty、default category。

右侧分类详情：

- slug
- display name
- description
- extensions
- keywords
- priority
- naming template

字段默认值：
- slug：从 display name 生成小写短横线形式，用户可编辑。
- display name：新建时为空，必填。
- description：可空。
- extensions：默认空列表。
- keywords：默认空列表。
- priority：默认 `0`，范围 `-1000..1000`。
- naming_template：默认空字符串；支持 `{original}`、`{stem}`、`{ext}`、`{date}`、`{slug}`。

匹配值编辑区：

- `Extensions` chip list：例如 `pdf`、`docx`；输入时 UI 可接受 `.pdf`，保存前规范化为 `pdf`。
- `Keywords` chip list：例如 `合同`、`invoice`。
- 每个 chip 有删除按钮，删除前必须能进入或展示 impact preview。

规则语义说明：
- 当前 `classifier.yaml` 没有独立 rule object；分类本身承载 `extensions`、`keywords`、`priority` 和 `naming_template`。
- Stage 2 不提供 `path` rule、`source_folder` rule 或独立 rule `enabled` 字段。
- 如需停用某个匹配规则，删除对应 extension/keyword chip；如需让分类暂时不再自动命中，清空该分类的 extensions 和 keywords。

按钮：`New category`、`Add extension`、`Add keyword`、`Preview impact`、`Validate`、`Save`、`Revert`、`Open YAML`、`Delete category...`。

## 状态与规则

- 默认态：读取当前 classifier 配置，左侧选中第一个分类或上次选中分类。
- 禁用态：未 Validate 或存在错误时禁用 Save；没有未保存更改时禁用 Revert。
- 加载态：读取 classifier 配置时显示 `Loading classifier rules...`。
- 空态：没有自定义分类或匹配值时显示 `No custom classifier rules yet`，仍显示 `New category`、`Add extension` 和 `Add keyword`。
- 错误态：读取、校验、写入失败时显示错误 banner，并保留编辑内容。
- 恢复态：`Revert` 恢复上次有效版本；写入失败后可继续编辑、Validate 或 Revert。
- slug 重复显示字段错误。
- 非法字符阻止保存。
- YAML 写入失败显示错误并保留编辑内容。
- Save 前必须 Validate。
- 删除 extension/keyword chip 前必须展示影响摘要；影响未知时必须进入 `S2-18 classifier-impact-preview`。
- Delete category 禁用条件：当前分类是 `default`、仅剩最后一个分类、或校验无法计算影响。
- Delete category 必须二次确认，文案说明 `This removes the category from classifier.yaml. Existing files are not moved or deleted.`。
- 删除分类或匹配值不会自动移动、删除或重命名任何历史文件；是否更新现有文件分类只能通过 `S2-18 classifier-impact-preview` 的 apply 流程执行。
- Save 失败时保留旧 classifier 配置为活动版本，并在 UI 中保留用户草稿。
- Open YAML 是高级入口，不绕过本页保存校验；从 YAML 返回后必须重新读取并校验。
- Preview impact 打开 `S2-18 classifier-impact-preview`，Back 后保留当前草稿。
- 从 YAML 返回时，如果当前 UI 有 dirty state，显示选择：`Reload from YAML`、`Keep current draft`、`Cancel`；默认不覆盖用户未保存草稿。

## 交互

- 新增 category 后可添加 extensions/keywords 并立即 Preview impact。
- 添加 extension 时输入 `.pdf` 或 `pdf` 都规范化为 `pdf`；非法扩展名显示字段错误。
- 添加 keyword 时去重，空字符串或超过 schema 长度显示字段错误。
- 删除 extension/keyword chip 时先显示影响摘要；用户确认后只修改草稿，不立即写入文件。
- 点击 `Delete category...` 先进入影响预览或展示影响摘要，再弹确认；确认后只从草稿移除 category。
- Open YAML 打开高级编辑，不关闭设置页。
- 修改任一字段后状态变为 dirty。
- 点击 Validate 校验 slug、display_name、extensions、keywords、priority、naming_template、default category 和重复项。
- Validate 成功后 Save 可用；Save 成功后更新 last valid snapshot。
- 点击 Revert 弹确认：`Discard unsaved classifier changes?`，确认后回上次有效版本。
- 关闭设置页时如有 dirty，提示 Save / Discard / Cancel。
- YAML 外部修改返回后选择 `Reload from YAML` 会丢弃当前草稿并重新读取；选择 `Keep current draft` 保留 UI 草稿，下一次 Save 仍必须 Validate。

## 数据与依赖

- classifier.yaml parser/writer。
- validator。
- last valid backup。
- category model matching current classifier.yaml schema。
- Rule impact dry-run entry。
- Dirty state and validation result。
- YAML reload conflict state。
- Delete category / delete value impact summary。

## 验收清单

- 用户不用直接编辑 YAML 即可新增/编辑分类、extensions、keywords、priority 和 naming_template。
- 保存失败不丢编辑内容。
- 校验错误能定位到字段或行号。
- Save 前必须 Validate。
- Revert 能恢复 last valid 版本。
- Open YAML 不关闭设置页，返回后重新读取并校验。
- Preview impact 能进入 S2-18 并带入当前草稿。
- 不出现 `path`、`source_folder` 或独立 rule `enabled` 字段。
- Priority 默认 0，范围 -1000..1000。
- 删除 extension/keyword/category 前有影响预览或摘要和二次确认。
- 删除 category 或匹配值不会移动、删除或重命名历史文件。

## 来源

- `tasks/prompts/phase-4/4-1-stage2-experience/task-15-classifier-rule-editor.md`（组合来源）。
- `docs/ux/settings-panel.md#tab分类规则classifier`（直接来源）。
- 可视化编辑器字段、dirty state 和 last valid 恢复依据现有文档推导，不与 PRD、roadmap、AGENTS 高风险不变量冲突。

---

## Related

- [Stage 2 页面索引](../stage-2-experience.md)
- [逐页 UI 开发规格索引](../README.md)
- [S2-17 classifier-save-rule](S2-17-classifier-save-rule.md)
- [S2-18 classifier-impact-preview](S2-18-classifier-impact-preview.md)
- [S2-15 command-palette](S2-15-command-palette.md)
