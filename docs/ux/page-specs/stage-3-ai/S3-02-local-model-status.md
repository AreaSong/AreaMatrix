# S3-02 local-model-status - 本地模型状态

> 所属阶段：Stage 3 智能化  
> 页面 ID：S3-02
> 页面类型：本地模型  
> 页面文件：`S3-02-local-model-status.md`  
> 上级索引：[stage-3-ai.md](../stage-3-ai.md)

## 开发位置

- **目标平台**：macOS 本地 AI 状态。
- **建议目录**：`apps/macos/AreaMatrix/Features/AI/LocalModelStatusView.swift`。
- **建议组件**：`LocalModelStatusView`、`ModelRuntimeCard`、`ModelStatusCheckPanel`、`ModelHealthCheckPanel`。
- **实现说明**：本页只展示本地模型状态检测结果和恢复入口，不负责下载、训练或删除模型文件，不启用远程模型，不上传任何文件内容。

## 页面背景

用户希望知道本地 AI 是否可用、模型路径和版本是否正确、运行时是否能启动、失败后如何恢复。本地模型是 AreaMatrix 的隐私优先路径，因此状态要透明且可诊断。

入口：AI 设置页点击 `Local model status`；本地 AI 功能失败时点击 `View local model status`。
退出：模型就绪后返回 AI 设置或原功能页；用户打开安装帮助、模型位置或诊断。

## 整体风格

本页是诊断和恢复页，不做模型能力宣传。状态、模型路径、版本、最后检查时间和恢复动作优先展示。未安装、路径不可读、版本不兼容、运行时不可用等状态使用文本和图标/徽标共同表达，避免只靠颜色区分。

## 页面功能

- 显示本地模型运行状态。
- 显示模型名称、版本、大小、存储位置。
- 显示最后状态检查时间、不可用原因和健康检查结果。
- 提供重试状态检查、打开安装帮助、打开模型位置、健康检查和诊断入口。
- 显示本地 AI 可用功能列表。
- 提供健康检查和错误详情。

## 布局与内容

标题：`Local model status`

状态卡：
- `Status: Ready`、`Not installed`、`Path unreadable`、`Version incompatible`、`Loading`、`Error`
- `Model: AreaMatrix Local Classifier v1`
- `Storage: ~/Library/Application Support/AreaMatrix/Models`
- `Disk usage: 2.4 GB`
- `Last checked: Apr 29, 2026 11:30`

状态检查区：
- 首次打开：`Local model status has not been checked yet.`
- 检查中：`Checking local model status...`
- 加载：`Loading model runtime...`
- 校验：`Verifying model manifest...`
- 状态未知：`Local model status is not available yet.`
- 默认主按钮：`Check status`
- 默认次按钮：`Open install help`

功能支持：
- `Classification suggestions: Available`
- `Auto tags: Available / Not supported`
- `Semantic search: Requires embeddings index`

操作按钮：
- `Retry status check`
- `Open install help`
- `Open model location`
- `Retry`
- `Repair`
- `Run health check`
- `Open diagnostics`

安装帮助入口：
- 标题：`Install local model`
- 说明：`Follow the local model setup instructions, then return here and run Retry status check.`
- 操作：`Open install help`、`Retry status check`
- 本页不直接下载、删除或训练模型；如果后续加入模型下载器，需要新增 task 或扩大当前 task 范围。

Repair 确认 sheet：
- 标题：`Repair local model metadata?`
- 说明：`AreaMatrix will rebuild local model status cache and manifest verification metadata. It will not download, delete, train, or modify model weights, and it will not read your files.`
- 主按钮：`Repair`
- 次按钮：`Cancel`
- Cancel 后返回本页并保持原状态；Back 在确认 sheet 中等同 Cancel。
- Repair 成功后显示 `Local model metadata repaired.`，重新执行一次 status check；若 status 变为 Ready，刷新 AI 设置页 provider 卡片。
- Repair 失败后显示 `Local model metadata could not be repaired.`，保留原错误状态，操作为 `Retry repair`、`Open install help`、`Open diagnostics`。

错误详情：
- `Model is not installed`
- `Model path is not readable`
- `Model version is incompatible`
- `Model files are corrupted`
- `Runtime failed to start`
- 每个错误必须有恢复动作。

诊断入口：
- 标题：`Local model diagnostics`
- 内容范围：模型 manifest 状态、runtime 启动状态、模型目录权限、磁盘空间、最后错误码。
- 不包含：用户文件正文、完整文件路径列表、API key、远程 provider 配置。
- 操作：`Copy diagnostics summary`、`Back to local model status`。
- 返回后焦点回到 `Open diagnostics`。

## 状态与规则

- 首次打开默认态：如果没有 cached status，显示 `Local model status has not been checked yet.`，主按钮 `Check status`，次按钮 `Open install help`；不得自动下载、安装、删除或训练模型。
- 自动检查触发：从 AI 设置页首次进入时可自动执行一次轻量 status check；从失败提示进入时只读取已有失败 snapshot，除非用户点击 `Retry status check`。
- 手动检查触发：`Check status` 和 `Retry status check` 都只读取 manifest、路径权限、磁盘占用和 runtime 可启动性，不读取用户文件内容。
- 未安装：显示 `Local model is not installed.`，主按钮 `Open install help`，次按钮 `Retry status check`，功能支持区全部标记 `Unavailable`。
- 路径不可读：显示 `Local model path cannot be read.`，主按钮 `Open model location`，次按钮 `Retry status check`。
- 版本不兼容：显示 `Local model version is not compatible.`，主按钮 `Open install help`，次按钮 `Run health check`。
- 校验中：显示 `Verifying model files...`，危险操作禁用。
- 模型损坏：显示 `Model files are corrupted.`，提供 `Repair`、`Open install help` 和 `Open diagnostics`，不静默回退远程。
- `Repair` 只适用于模型目录可读、版本兼容、manifest 或 AreaMatrix 本地模型状态缓存不一致、checksum cache 缺失或 metadata index stale 的轻量恢复。
- `Repair` 不适用于 `Not installed`、`Path unreadable`、`Version incompatible` 或 `Runtime failed to start`；这些状态下按钮禁用，并显示对应主恢复入口。
- `Repair` 只允许重建 AreaMatrix 本地模型状态缓存、manifest 校验缓存和模型 metadata index，不得下载模型、删除模型缓存、训练模型、改写模型权重或读取用户文件内容。
- `Repair` 执行中显示 `Repairing local model metadata...`，禁用 `Retry status check`、`Repair`、`Run health check` 和 `Open model location`；保留 `Open diagnostics` 只读入口。
- Repair 确认 sheet 中点击 Cancel 或 Back 不做任何变更，并返回原错误状态。
- Repair 成功后立即重新执行 status check；若仍不可用，显示新的状态原因和 `Open install help` / `Open diagnostics`，不得自动启用远程 AI。
- Repair 失败时保留原错误状态和 cached status snapshot，显示 `Retry repair`、`Open install help`、`Open diagnostics`。
- Runtime 失败：显示 `Runtime failed to start.`，提供 `Run health check`、`Open diagnostics` 和非 AI 回退说明。
- 未安装时，AI 功能页不能假装可用，应引导到本页或安装帮助。
- 本页不得提供直接下载、删除模型缓存或训练模型的必做 UI；这些能力若后续加入，必须有独立规格和验证。
- 模型损坏且无法轻量 Repair 时，主路径为 `Open install help` 和 `Open diagnostics`，不静默回退远程。
- 本地模型状态不可用不应自动启用远程 AI。
- 健康检查只测试 runtime 和模型 manifest，不读取用户文件内容。
- 本地模型失败只提供修复、本地规则分类、inbox 或普通搜索等非 AI 回退，不显示启用远程 AI 的主路径。

## 交互

1. 页面打开时先显示 cached status；若无 cached status 且入口是 AI 设置页，则自动执行一次轻量 status check。
2. 点击 `Check status` 或 `Retry status check` 重新读取模型 manifest、路径权限、磁盘占用和 runtime 状态。
3. 点击 `Open install help` 打开本地模型安装说明；返回本页后用户手动运行 `Retry status check`。
4. 点击 `Open model location` 只定位模型目录；路径不存在或不可读时显示对应错误，不创建或删除文件。
5. 点击 `Run health check` 执行轻量测试，不读取用户文件。
6. 点击 `Repair` 先打开 Repair 确认 sheet；点击 Cancel 或 Back 返回本页并保持原状态。
7. 点击确认 sheet 的 `Repair` 后只重建本地模型状态缓存、manifest 校验缓存和 metadata index；成功后重新执行 status check，并刷新 AI 设置页 provider 卡片。
8. Repair 失败时保留原状态，允许 `Retry repair`，也可打开安装帮助或诊断；不得切换远程 provider。
9. 点击 `Open diagnostics` 打开本地诊断入口，诊断内容不得包含用户文件正文、完整文件路径列表、API key 或远程 provider 配置；返回后焦点回到触发按钮。

## 可访问性

- 状态检查、校验状态和错误状态必须通过 VoiceOver 可读，不只显示图标。
- 所有恢复按钮支持键盘操作；打开帮助、模型位置或诊断后返回时，焦点回到触发按钮。
- 状态刷新应使用适度的辅助技术公告，不在每个轮询变化时打断用户。
- 禁用按钮必须有可读禁用原因，例如状态检查中、路径不可读或 runtime 状态未返回。

## 数据与依赖

- Local model manager。
- Model manifest and version info。
- Runtime health check。
- AI feature capability matrix。
- Cached local model status snapshot。
- Diagnostics summary provider。

## 验收清单

- 首次打开无 cached status 时有明确默认态、`Check status` 和安装帮助入口。
- 自动/手动 status check 触发规则清楚，且不会下载、安装、删除、训练模型或读取用户文件内容。
- Ready、Not installed、Path unreadable、Version incompatible、Loading、Error 都有不同 UI。
- Checking、Verifying、Corrupted、Runtime failed 都有不同 UI 和恢复动作。
- 本页不提供直接下载、删除模型缓存或训练模型的必做 UI。
- 打开模型位置只定位目录，不创建、删除、移动或覆盖任何文件。
- 健康检查不读取用户文件内容。
- `Repair` 的适用条件、禁用条件、确认 sheet、Cancel/Back、执行中、成功和失败状态明确可测。
- `Repair` 只重建本地模型状态缓存、manifest 校验缓存和 metadata index，不下载、删除、训练、改写模型权重或读取用户文件内容。
- 模型损坏且轻量 Repair 失败时，主路径是安装帮助和诊断，不会自动启用远程 AI。
- 本地模型失败不会自动切换远程 AI。
- 本地模型失败时仍能回到本地规则分类、inbox 或普通搜索。
- Open diagnostics 的内容范围、隐私排除项和返回路径明确可测。
- VoiceOver 能读出状态、错误和操作按钮状态。

## 来源

- 组合来源：[本地模型状态任务](../../../../tasks/prompts/phase-4/4-2-stage3-ai/task-02-local-model-status.md)、[Stage 3 AI 分类](../../../roadmap/milestones.md#ai-分类l3)。
- 依据现有文档推导：本地模型状态检查、校验、健康检查和非 AI 回退状态，遵守本地优先与“不读取用户文件内容”的隐私边界。

---

## Related

- [Stage 3 页面索引](../stage-3-ai.md)
- [S3-01 AI 设置总页](S3-01-ai-settings.md)
- [S3-10 AI 失败回退提示](S3-10-ai-fallback.md)
- [逐页 UI 开发规格索引](../README.md)
