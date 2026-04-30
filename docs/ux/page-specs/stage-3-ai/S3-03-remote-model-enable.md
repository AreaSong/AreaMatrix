# S3-03 remote-model-enable - 远程模型配置与显式启用

> 所属阶段：Stage 3 智能化  
> 页面 ID：S3-03
> 页面类型：远程模型  
> 页面文件：`S3-03-remote-model-enable.md`  
> 上级索引：[stage-3-ai.md](../stage-3-ai.md)

## 开发位置

- **目标平台**：macOS 远程 AI 配置。
- **建议目录**：`apps/macos/AreaMatrix/Features/AI/RemoteModelConfigSheet.swift`。
- **建议组件**：`RemoteModelConfigSheet`、`RemoteProviderPicker`、`RemoteAIConsentView`、`APIKeySecureField`。
- **实现说明**：远程模型必须由用户自带 key、显式启用并确认数据会离开本机。任何远程调用不得默认开启。

## 页面背景

用户希望使用远程模型作为可选增强，例如更好的摘要、标签或语义搜索。远程调用是隐私高风险边界，本页必须把 provider、key、使用范围、发送内容类型和隐私规则说明清楚。

入口：AI 设置页点击 `Configure remote AI`；某个 AI 功能需要远程能力时点击 `Enable remote AI`。
退出：配置成功返回 AI 设置或来源 AI 功能页；从 S3-09 跳入时配置成功返回 S3-09；取消不保存输入；测试失败留在 sheet。

## 整体风格

这是隐私高风险确认 sheet，采用克制、表单化布局。优先说明 provider、key 存储、使用范围和数据流向，不使用鼓励上传或性能承诺类文案。远程状态必须始终用文字、徽标和禁用原因表达，不能只用颜色。

## 页面功能

- 选择远程 provider。
- 输入 API key，并保存到 Keychain。
- 选择模型名称或手动填写模型 ID。
- 选择使用范围：分类、摘要、标签、语义搜索。
- 显示会发送的数据类型。
- 测试连接，且测试不发送用户文件内容。
- 要求用户勾选远程数据流向确认。
- 提供禁用远程 AI 的动作。
- 维护远程 provider 状态字段，不编辑目录/关键词/字段隐私规则。

## 布局与内容

Sheet 标题：`Configure remote AI`

Provider 区：
- `Provider`: OpenAI / Anthropic / Other。
- `Model`: 下拉或文本框。
- `Endpoint URL`: 仅 Other 显示。
- 加载状态：`Loading available models...`
- 空状态：`No models available for this provider. Enter a model ID manually.`

Credential 区：
- `API key`: secure field。
- 辅助文案：`Stored in Keychain. Never written to logs or diagnostics.`
- 按钮：`Test connection`

Usage scope：
- checkbox `Classification suggestions`
- checkbox `Auto summaries`
- checkbox `Auto tags`
- checkbox `Semantic search`
- 每项下面显示可能发送字段：文件名、repo-relative path、扩展名、提取文本片段、AI 摘要、note summary（用户 Note 的派生摘要）、标签/分类上下文。
- 所有可能发送字段在远程调用前都必须经过 S3-09 隐私规则 gate；任何命中规则的文件或字段不得发送，必须写入 skipped 日志。
- `note summary` 属于 Note 派生字段；本页不得承诺或实现发送完整用户 Note 原文。

隐私说明卡：
`Remote AI may send selected file metadata or extracted text to the provider you choose. Privacy rules are checked before every remote call.`

状态字段摘要：
- `provider_configured`：provider、model 或 endpoint 已保存。
- `provider_verified`：当前 provider/model/endpoint/key 组合的 Test connection 成功；任一字段变化后重置为 false。
- `remote_provider_enabled`：用户在本页显式点击 `Enable remote AI` 后为 true；点击 `Disable remote AI` 后为 false。
- `feature_scope`：本页保存的远程可用功能范围，包含 Classification / Summary / Tags / Semantic search。
- `privacy_gate_enabled`：由 S3-09 管理的远程隐私 gate；本页启用远程成功时默认设为 true，之后用户可在 S3-09 关闭。
- 远程调用允许条件固定为：`provider_configured == true`、`provider_verified == true`、`remote_provider_enabled == true`、对应 `feature_scope` 允许、`privacy_gate_enabled == true`、S3-09 字段/规则通过、S3-05 调用日志可写。
- 本页只负责 provider/key/model/scope/connection/consent；目录、关键词、扩展名、Tag、Category 和字段过滤规则由 S3-09 负责。

确认复选框：
`I understand remote AI sends allowed content to a third-party provider.`

底部按钮：
- `Cancel`
- `Disable remote AI`，仅已启用时显示。
- 主按钮 `Enable remote AI`

Disable remote AI 确认 sheet：
- 标题：`Disable remote AI?`
- 说明：`Remote AI calls will stop immediately. Local AI features and existing saved summaries, tags, and call logs will not be deleted.`
- 选项：`Also remove stored API key`，默认不勾选；勾选后从 Keychain 删除 key。
- 主按钮：`Disable remote AI`
- 次按钮：`Cancel`
- 禁用成功后返回 AI 设置页，远程 provider 状态显示 `Off`，`remote_provider_enabled` 和 `privacy_gate_enabled` 都为 false；如果同时删除 key，Credential 区下次打开为空。

## 状态与规则

- API key 为空时禁用 `Test connection` 和 `Enable remote AI`。
- 未选择任何 usage scope 时禁用 Enable。
- 未勾选确认时禁用 Enable。
- Test connection 未成功时禁用 Enable，并显示 `Verify the connection before enabling remote AI.`。
- Test connection 失败时不保存启用状态。
- Test connection 只发送 provider/model/key 可用性的最小探测请求，不发送用户文件名、路径、摘要、提取文本、标签或 Note。
- key 不写入日志、诊断包、崩溃报告、导出日志、错误文本或 UI 明文。
- Provider/model 列表加载失败时，仍允许手动输入 model id，但 Enable 仍必须先通过 Test connection。
- API key 无效：显示 `The API key was rejected by the provider.`，不得回显 key 片段。
- 网络失败：显示 `Connection failed. Check your network or endpoint URL.`，不得自动切换 provider。
- 点击 `Enable remote AI` 成功后必须一次性保存 `provider_configured`、`provider_verified`、`remote_provider_enabled`、`feature_scope`，并默认打开 `privacy_gate_enabled`；任何字段/规则仍可能在 S3-09 阻断后续调用。
- 如果保存 provider/key 成功但 settings 保存失败，页面显示 `Remote AI settings could not be saved.`，`remote_provider_enabled` 保持进入 sheet 前状态；已写入 Keychain 的新 key 标记为 unused credential，并提供 `Retry save`、`Remove unused key`、`Cancel`。
- 如果启用成功但打开 `privacy_gate_enabled` 失败，显示 `Remote provider was configured, but privacy gate could not be enabled.`；远程调用仍不得开始，操作为 `Retry enable privacy gate`、`Open privacy rules`、`Disable remote AI`。
- 禁用远程后，`remote_provider_enabled` 和 `privacy_gate_enabled` 都立即关闭，所有远程调用 gate 立即阻断；已有本地 AI 功能不受影响。
- `Disable remote AI` 需要确认；`Also remove stored API key` 默认不勾选，勾选后从 Keychain 删除 key。
- 任何远程功能保存 scope 后也不能绕过 S3-09；隐私规则命中时调用结果为 skipped，sent fields 为 none。
- 从 S3-09 进入本页时，Cancel 返回 S3-09 并保持原 `privacy_gate_enabled`、provider 和 scope 状态；测试失败同样返回前不改变状态。

## 交互

1. 打开 sheet 时读取已配置 provider，但 API key 默认以掩码显示。
2. 修改 provider 后清空模型选择或加载对应模型列表。
3. 点击 `Test connection` 显示 `Testing...`，成功或失败都按 S3-05 的 `Provider Test` 记录类型写入脱敏连接测试日志；成功后显示绿色状态 `Connection verified`。
4. 用户勾选确认并选择 scope 后才能点击 Enable。
5. 点击 Enable 保存 key 到 Keychain，保存 provider settings、feature scope 和 `remote_provider_enabled`，并默认打开 S3-09 的 `privacy_gate_enabled`；成功后按入口返回 AI 设置、S3-09 或来源功能页。
6. 点击 Disable remote AI 弹确认，确认后清除远程启用状态并关闭 `privacy_gate_enabled`；是否删除 key 由复选框 `Also remove stored API key` 控制。
7. 点击 Cancel 丢弃本次未保存输入；已有远程配置保持进入 sheet 前状态。
8. Test connection 成功后如果用户修改 provider、model、endpoint 或 key，连接状态重置为未验证。
9. 禁用远程成功后刷新 AI 设置页、调用 gate 和当前功能页的 provider 状态；取消确认则留在配置 sheet，不改变启用状态。
10. 从 S3-09 进入并成功启用时，返回 S3-09 后顶部 gate 显示 `Remote AI allowed`，字段过滤和规则列表继续按 S3-09 当前配置生效。

## 可访问性

- Provider、model、endpoint、API key、scope 和确认复选框都必须有明确 label 和错误关联。
- `Enable remote AI` 的禁用原因必须可被 VoiceOver 读出，例如 key 为空、未测试连接、未选择 scope 或未确认数据流向。
- API key 字段必须使用 secure field；辅助技术不得朗读 key 内容。
- Disable 确认 sheet 默认焦点在 `Cancel`，危险/主按钮需读出是否会删除 Keychain key。

## 数据与依赖

- Keychain credential store。
- Remote provider client。
- Remote AI settings store。
- Privacy rules gate。
- AI call log，按 S3-05 `Provider Test` schema 记录测试连接，但不得记录 key、key 片段、用户文件内容或 provider 原始响应体。
- Network error mapper。
- Remote disable confirmation state。
- Remote state fields：`provider_configured`、`provider_verified`、`remote_provider_enabled`、`feature_scope`、`privacy_gate_enabled`。
- Unused credential cleanup state。

## 验收清单

- 远程 AI 不能默认启用。
- 用户必须输入 key、选择范围、测试连接成功、勾选数据流向后才能启用。
- 启用远程后 5 个状态字段被明确更新；远程调用必须同时满足 provider、scope、privacy gate、字段规则和日志 gate。
- 测试连接不发送用户文件内容。
- 测试连接日志使用 S3-05 `Provider Test` 类型，sent fields 固定为 none，且不包含 API key、key 片段或 provider 原始响应体。
- API key 不出现在日志、诊断包、UI 明文和错误文本中。
- 禁用远程后后续远程调用被阻止。
- Disable remote AI 有确认 sheet，且删除 Keychain key 只能由用户勾选后执行。
- Enable 保存失败、privacy gate 开启失败、Cancel、测试失败和从 S3-09 往返都有明确回滚行为。
- 远程可发送字段清单完整显示；所有字段类型都受隐私规则 gate 约束。
- 命中 note summary 或其他字段的隐私规则时，远程调用必须 skipped，日志 sent fields 为 none。
- Provider/model 加载中、加载失败、空列表、key 无效、网络失败都有明确状态。
- VoiceOver 能读出隐私说明、确认项和主按钮禁用原因。

## 来源

- 组合来源：[远程 provider 配置任务](../../../../tasks/prompts/phase-4/4-2-stage3-ai/task-13-s3-03-remote-model-enable.md)、[Stage 3 隐私与可控](../../../roadmap/milestones.md#隐私与可控)。
- 依据现有文档推导：远程 AI 显式启用、Keychain 存储、测试连接成功后才能启用和禁用远程确认规则，遵守项目隐私不变量。

---

## Related

- [Stage 3 页面索引](../stage-3-ai.md)
- [S3-01 AI 设置总页](S3-01-ai-settings.md)
- [S3-05 AI 调用日志](S3-05-ai-call-log.md)
- [S3-09 AI 隐私规则](S3-09-ai-privacy-rules.md)
- [S3-10 AI 失败回退提示](S3-10-ai-fallback.md)
- [逐页 UI 开发规格索引](../README.md)
