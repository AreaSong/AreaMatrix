# S3-09 ai-privacy-rules - AI 隐私规则

> 所属阶段：Stage 3 智能化  
> 页面 ID：S3-09
> 页面类型：隐私规则  
> 页面文件：`S3-09-ai-privacy-rules.md`  
> 上级索引：[stage-3-ai.md](../stage-3-ai.md)

## 开发位置

- **目标平台**：macOS AI 隐私规则。
- **建议目录**：`apps/macos/AreaMatrix/Features/AIPrivacy/AIPrivacyRulesView.swift`。
- **建议组件**：`AIPrivacyRulesView`、`AIPrivacyRuleEditor`、`AIPrivacyRuleTestView`、`RuleMatchPreview`。
- **实现说明**：隐私规则主要用于阻止内容发送到远程 AI，也可选择限制本地 AI。默认保护远程调用。

## 页面背景

用户需要明确控制哪些目录、分类、关键词或文件类型不能用于 AI，尤其不能发送到远程 provider。规则必须可见、可测试、可解释，不能只作为后台配置存在。

入口：AI 设置页 `Manage privacy rules`；远程 AI 配置隐私说明；AI 跳过提示 `View privacy rule`。
退出：保存规则返回 AI 设置；删除规则；测试规则；取消编辑。

## 整体风格

本页是安全控制面板，优先让用户看懂规则会阻止什么、影响哪些 AI 功能、最近命中过什么。规则编辑采用表单和预览，不自动创建或自动放宽规则。删除、模板添加和未保存离开都必须有明确确认或提示。

## 页面功能

- 列出现有隐私规则。
- 新增、编辑、禁用、删除规则。
- 定义规则类型：Folder、Category、Keyword、Extension、Tag。
- 定义适用范围：Remote AI 或 Local and remote AI。
- 测试某个文件是否命中规则。
- 显示规则命中后的功能影响。
- 提供默认保护规则建议。
- 提供全局远程 AI gate 和敏感字段过滤控制。

## 布局与内容

标题：`AI Privacy Rules`

顶部说明：
`Privacy rules are checked before AI uses file metadata or extracted text. Remote AI is blocked by default for matching rules.`

全局远程控制区：
- 标题：`Remote AI privacy gate`
- 状态：`Remote AI allowed` / `Remote AI blocked`
- 控件：`Allow remote AI after provider consent`，控制 `privacy_gate_enabled`，默认关闭；开启时若 S3-03 未完成 provider/key/scope/connection/consent，必须跳转 S3-03，不能在本页直接启用远程 provider。
- 按钮：`Block remote AI with privacy gate`，只关闭 `privacy_gate_enabled`；不删除 Keychain key，不关闭 `remote_provider_enabled`，不删除 provider 配置，不删除本地 AI 设置、摘要、标签、日志或既有 AI 结果。
- 链接：`Configure remote AI`，打开 S3-03；从 S3-03 Cancel 返回本页并保持原 gate 状态。
- 说明：本区是隐私 gate，不是 provider 禁用页；provider 凭据、测试连接、scope、真正禁用 remote provider 和删除 Keychain key 仍由 S3-03 管理。

远程调用状态字段：
- `provider_configured`、`provider_verified`、`remote_provider_enabled` 和 `feature_scope` 来自 S3-03，只读展示。
- `privacy_gate_enabled` 由本页控制，也可在 S3-03 首次成功启用远程时默认打开。
- 远程调用允许条件固定为：provider 已配置、测试成功、远程 provider enabled、对应 feature scope 允许、privacy gate enabled、字段规则通过、调用日志可写。
- 任一条件不满足时，所有远程 AI 页面显示 skipped 或 unavailable，并在 S3-05 记录 provider gate / matched field type / sent fields none。
- 本页关闭 `privacy_gate_enabled` 只阻止远程调用；用户若要禁用 provider 或删除 Keychain key，必须进入 S3-03。
- 本页的 `Block remote AI with privacy gate` 不得被实现为 S3-03 的 `Disable remote AI`；它不会修改 `remote_provider_enabled`，也不会删除 provider 配置或 Keychain key。

敏感字段过滤区：
- 标题：`Remote allowed fields`
- 字段列表：`filename`、`repo-relative path`、`extension`、`extracted text excerpt`、`AI summary`、`note summary`、`tag/category context`
- 每行控件：`Allow for remote AI` checkbox、当前状态 `Allowed` / `Blocked`、最近命中数。
- `note summary` 说明：`Derived from your note. Full note text is never sent.`
- 远程 gate 关闭时字段控件禁用，并显示 `Remote AI is blocked.`
- 字段被 block 时，任何需要该字段的远程调用必须 skipped，S3-05 日志 sent fields 为 none，并记录 matched field type。
- 本地 AI 是否受字段过滤影响由规则 `Applies to` 决定；默认字段过滤只约束 Remote AI。

无规则空态：
- 标题：`No AI privacy rules yet`
- 说明：`Remote AI is still off by default. Add rules to block specific folders, keywords, extensions, categories, or tags whenever AI is enabled.`
- 主按钮：`Add rule`
- 次按钮：`Use recommended templates...`

推荐模板 sheet：
- `Private finance folders`
- `Secrets and key files`
- `Confidential keywords`
- 模板不会自动创建；用户必须选择模板并点击 `Add selected rules`。

规则列表列：
- `Enabled`
- `Type`
- `Pattern`
- `Applies to`
- `Matches`
- `Last matched`

规则行示例：
- enabled, `Folder`, `finance/private/`, `Remote AI`, `42 files`
- enabled, `Keyword`, `confidential`, `Local and remote AI`, `8 files`
- disabled, `Extension`, `.key`, `Remote AI`, `2 files`
- enabled, `Tag`, `client-private`, `Remote AI`, `12 files`

编辑表单：
- `Type` picker。
- `Pattern` input。
- `Applies to` segmented control。
- `Description` optional。
- `Enabled` checkbox。
- 表单按钮：`Save rule`、`Cancel`
- 脏状态提示：`You have unsaved changes.`

测试区：
- `Test file` picker 或当前文件。
- 结果：`Matched by Folder: finance/private/` 或 `No rules matched`。
- 显示影响：`Remote summary: skipped`、`Local tags: allowed`。

按钮：
- `Add rule`
- `Edit`
- `Disable`
- `Delete...`
- `Test rules`

Delete privacy rule 确认 sheet：
- 标题：`Delete privacy rule?`
- 说明：`Future AI calls may no longer skip content that matched this rule. This will not delete files, existing AI results, tags, summaries, notes, or call logs.`
- 危险按钮：`Delete rule`
- 次按钮：`Cancel`
- 删除成功后刷新规则列表、AI 设置隐私摘要和当前页面匹配计数。

## 状态与规则

- 加载中：显示 `Loading privacy rules...`，列表和编辑表单禁用，保留返回 AI 设置入口。
- 读取失败：显示 `AI privacy rules could not be loaded.`，主操作 `Retry`，次操作 `Back to AI settings`。
- Pattern 为空时禁用保存。
- Folder pattern 必须相对 repo root，不允许误写绝对路径时静默通过。
- Folder pattern 输入绝对路径时显示 `Use a path relative to the AreaMatrix repository root.`，保存禁用。
- Keyword 规则固定匹配文件名、repo-relative path、AI 摘要、提取文本片段、note summary（用户 Note 的派生摘要）；不展示或发送完整用户 Note 原文，除非后续规格显式打开。
- Extension pattern 必须以 `.` 开头；Tag 和 Category 必须从现有 registry 选择或显示不存在提示。
- Tag 规则是 Stage 3 必做规则类型；Pattern 必须来自现有 tag registry，不允许保存自由输入的不存在 tag。
- Category 规则必须来自现有 category registry，不允许保存自由输入的不存在 category。
- `Save rule` 禁用条件：规则仍在加载、Pattern 为空、Pattern 校验失败、Tag/Category 不存在、Applies to 未选择或当前表单无变化。
- 删除规则需要确认，并说明未来 AI 调用可能不再跳过该规则匹配内容。
- 禁用规则不删除规则，可恢复。
- 远程 AI 调用前必须检查规则；命中后调用日志记录 `Skipped by privacy rule`。
- 如果命中字段是 note summary、提取文本或其他远程可发送字段，远程调用必须 skipped，S3-05 日志 sent fields 为 none。
- 全局远程 gate 关闭时，所有远程 AI 调用必须 skipped；AI 页面显示 `Remote AI blocked by privacy gate`，S3-05 日志 provider gate 为 `privacy_gate_disabled`，sent fields 为 none。
- 字段过滤命中时，AI 页面显示 `Skipped by privacy field rule`，并提供 `View privacy rule` 和 `View AI call`；S3-05 日志记录 feature、file/batch、matched field type、provider gate 和 rule id/name。
- `Allow remote AI after provider consent` 禁用条件：规则仍在加载、S3-03 provider 未配置、测试连接未成功、未选择 remote usage scope 或当前保存失败。
- 如果 `remote_provider_enabled` 为 false，本页显示 `Remote provider is disabled in AI settings.`，`Allow remote AI after provider consent` 禁用，主恢复入口为 `Configure remote AI`。
- 如果 `provider_configured` 为 true 但 `provider_verified` 为 false，本页显示 `Remote provider needs connection test.`，开启 gate 禁用，主恢复入口为 `Configure remote AI`。
- 如果 `feature_scope` 不包含某 AI 功能，Test rules 对该功能显示 `Remote scope: not allowed`，不得通过 privacy gate 绕过 scope。
- S3-03 启用远程成功并默认打开 `privacy_gate_enabled` 后，本页必须继续保留字段过滤和规则阻断能力；规则命中仍 skipped。
- 点击 `Block remote AI with privacy gate` 后只保存 `privacy_gate_enabled = false`；`provider_configured`、`provider_verified`、`remote_provider_enabled` 和 `feature_scope` 都保持不变。
- 关闭 `privacy_gate_enabled` 保存失败时保留上一次成功状态，显示 `Remote AI privacy gate could not be updated.`，操作为 `Retry save` 和 `Revert changes`。
- 字段 checkbox 保存失败时保留用户刚修改的 pending 状态，显示 `Privacy field settings could not be saved.`，操作为 `Retry save` 和 `Revert changes`。
- 规则变更后不自动重新生成已有 AI 结果；如需清理，另走确认动作。
- 无规则时不自动创建默认规则；推荐模板必须用户确认添加。
- 编辑未保存时离开页面或切换规则，必须提示 `Save changes`、`Discard changes`、`Cancel`。
- 保存失败时保留表单内容，显示错误并允许重试。

## 交互

1. 打开页面时读取规则列表和匹配计数。
2. 打开页面时读取远程 gate、字段过滤设置和 S3-03 provider consent 状态。
3. 点击 `Allow remote AI after provider consent` 时，若 provider 未完成配置、未测试成功、未启用或缺少 scope，则进入 S3-03；配置取消后返回本页且不启用远程 gate。
4. 点击 `Block remote AI with privacy gate` 只关闭 `privacy_gate_enabled`，并刷新 AI 设置页远程状态摘要；provider 配置、Keychain key、`remote_provider_enabled`、`provider_verified` 和 `feature_scope` 保持不变。
5. 修改字段过滤 checkbox 后保存字段设置；保存失败时保留 pending 状态并允许重试。
6. 点击 `Add rule` 打开右侧编辑表单或 sheet。
7. 用户选择类型后，Pattern 输入 placeholder 随类型变化。
8. 点击 `Test rules` 选择文件，显示所有命中规则、字段过滤结果和每个 AI 功能的 allow/skip。
9. 点击 Delete 弹确认，确认后删除规则，不影响文件或已有 AI 结果，并刷新隐私摘要。
10. 保存规则后刷新 AI 设置页隐私摘要。
11. 点击 `Use recommended templates...` 打开模板 sheet；用户选择模板并确认后才新增规则。
12. 点击 `Cancel` 关闭编辑表单；若有未保存改动，先弹保存/放弃/取消提示。
13. 从 AI 跳过提示进入时，定位到对应规则或字段过滤项并高亮一次。
14. 从 S3-03 启用远程后返回时，重新读取 5 个状态字段；如果 `privacy_gate_enabled` 已打开，顶部状态显示 `Remote AI allowed`，但命中的字段或规则仍显示 skip。

## 可访问性

- 规则列表必须读出 enabled 状态、类型、pattern、applies to、matches 和 last matched。
- 编辑表单错误要和对应输入关联；保存禁用原因必须可读。
- `Test rules` 结果必须列出每个命中规则和各 AI 功能 allow/skip，不只用颜色。
- 删除确认默认焦点在 `Cancel`；危险按钮需读出删除后未来 AI 调用可能不再跳过匹配内容。

## 数据与依赖

- Privacy rules store。
- Rule matcher。
- Remote AI privacy gate setting。
- Remote allowed fields settings。
- Remote state fields from S3-03：`provider_configured`、`provider_verified`、`remote_provider_enabled`、`feature_scope`。
- Repo-relative path normalizer。
- Match count estimator。
- AI call gate。
- AI call log for skipped entries。
- Current file/category/path context。
- Recommended rule templates。
- Dirty edit state。
- Existing tag/category registry。
- Delete privacy rule confirmation state。
- Field settings save state。
- Privacy gate save state。

## 验收清单

- 用户能阻止指定目录发送到远程 AI。
- 用户能全局关闭 `privacy_gate_enabled`，且不删除 Keychain key、不关闭 provider 配置、不删除本地 AI 设置。
- `Block remote AI with privacy gate` 只关闭 `privacy_gate_enabled`，不会关闭 `remote_provider_enabled`，不会删除 provider 配置、Keychain key 或既有 AI 结果；真正禁用 remote provider 只能走 S3-03。
- 远程调用允许条件同时检查 provider 配置、连接测试、provider enabled、feature scope、privacy gate、字段规则和日志能力。
- 从 S3-09 跳转 S3-03 后，Cancel、测试失败、启用成功和返回状态都有明确语义。
- 用户能按字段阻止 filename、repo-relative path、extension、extracted text excerpt、AI summary、note summary、tag/category context 发送到远程 AI。
- 加载中、读取失败、无规则空态、保存失败都有明确 UI。
- Folder、Category、Keyword、Extension、Tag 五类规则均可编辑。
- Tag 和 Category 规则只能选择现有 registry 项；不存在时保存禁用并显示错误。
- 无规则空态清楚说明远程 AI 仍默认关闭，模板不会自动创建。
- Pattern 校验清楚，错误和输入框关联。
- Save rule 禁用条件可见，并和对应输入关联。
- Folder 使用 repo-relative path；Keyword 匹配范围固定且可见，包含 note summary 但不展示完整用户 Note。
- Test rules 能显示命中规则和功能影响。
- Test rules 能显示字段过滤命中和远程 gate 影响。
- Test rules 能显示 provider/scope/gate 三类阻断来源，且不会把 privacy gate 当成 provider 启用。
- 删除规则需要确认，并提示未来 AI 调用可能不再跳过该规则匹配内容；禁用规则可恢复。
- 编辑未保存离开前有保存/放弃/取消提示。
- 规则命中时 AI 页面显示跳过，并在调用日志可追溯；命中 note summary 时远程调用 skipped 且 sent fields 为 none。
- 远程 gate 或字段过滤命中时 AI 页面显示跳过，并在调用日志记录 matched field type、provider gate 和 sent fields none。
- VoiceOver 能读出规则启用状态、类型、范围和匹配结果。

## 来源

- 组合来源：[AI 隐私规则任务](../../../../tasks/prompts/phase-4/4-2-stage3-ai/task-19-s3-09-ai-privacy-rules.md)、[Stage 3 隐私与可控](../../../roadmap/milestones.md#隐私与可控)。
- 依据现有文档推导：规则类型、推荐模板、repo-relative folder 校验、keyword 匹配范围、测试区、privacy gate 阻断文案和未保存离开确认规则。

---

## Related

- [Stage 3 页面索引](../stage-3-ai.md)
- [S3-01 AI 设置总页](S3-01-ai-settings.md)
- [S3-03 远程模型配置与显式启用](S3-03-remote-model-enable.md)
- [S3-05 AI 调用日志](S3-05-ai-call-log.md)
- [S3-10 AI 失败回退提示](S3-10-ai-fallback.md)
- [逐页 UI 开发规格索引](../README.md)
