# 设置面板

> 记录 AreaMatrix macOS 设置窗口的真实信息架构、持久化边界与高风险确认行为。
>
> 阅读时长：约 7 分钟。

---

## 入口与布局

设置窗口通过菜单或 `Command-,` 打开。左侧为固定宽度侧栏，右侧显示当前资料库对应的设置内容。

当前共有 7 个一级 Tab：

| TabId | 名称 | 当前职责 |
|---|---|---|
| `general` | 通用 | 默认存储模式、概览输出、忽略规则、生成内容语言、外观状态 |
| `repository` | 资料库 | 路径、健康状态、资料库配置、Finder、恢复入口 |
| `classifier` | 分类规则 | 可视化规则维护、规则引擎开关、YAML 操作、分类预览 |
| `ai` | AI | AI 总开关、provider、功能开关、隐私规则、调用日志和暂停 |
| `integrations` | 集成 | iCloud 状态与警告、Finder 和外部改动说明 |
| `advanced` | 高级 | 诊断、日志、恢复工具、概览输出和危险导入选项 |
| `about` | 关于 | 版本、平台差异、许可证、外部链接、诊断和日志 |

侧栏 Tab 是稳定路由标识。功能入口可以直接打开指定 Tab，例如 AI 错误恢复可以跳转到 `ai`。

## 通用

### 默认存储模式

可选值为：

- `Copy (recommended)`：复制到资料库，保留来源文件。
- `Move`：导入成功后来源位置不再保留该文件；切换为默认值前必须确认。
- `Index-only`：只登记外部路径；来源文件移动后可能变为缺失；切换为默认值前必须确认。

该设置只是导入默认值，单次导入仍可在导入界面修改。

### 概览输出

- 默认只写 `.areamatrix/generated/`。
- 用户明确确认后，可以同时维护资料库根目录的 `AREAMATRIX.md`。
- AreaMatrix 不把 `README.md` 作为自动输出目标。
- 已存在的 `AREAMATRIX.md` 只有在类型安全且用户确认后才会写入 AreaMatrix 管理块。

### 忽略规则

`Open ignore.yaml` 打开 `.areamatrix/ignore.yaml`。文件缺失时，应用可以在用户确认后创建默认文件；该动作不得修改资料库中的其他文件。

### 语言与外观

通用页提供 `system`、`zh-CN`、`en`。`system` 在打开资料库时解析为当前系统支持的内容语言；
`zh-CN` 在 Swift 持久化层保持用户选择，并在 Core 边界归一化为 `zh-Hans`。该值控制当前资料库的树和
生成内容语言，不代表整个 SwiftUI 界面已完成运行时本地化切换。

外观当前只显示并锁定为 `system`，应用跟随系统外观。

### 重置

`Reset this tab` 只恢复通用页持久化字段，不是全局设置重置。其他 Tab 不提供统一的全局重置命令。

## 资料库

资料库页展示并操作当前资料库：

- 当前路径、数据库状态、最近打开时间和容量摘要。
- 在 Finder 中打开资料库、复制路径、更换资料库。
- 打开恢复工具或平台能力说明。
- 导出 repository diagnostics snapshot；导出前必须确认，且不会自动上传。snapshot 会复制
  `index.db` 及存在的 WAL/SHM，可能包含路径、文件名、标签、笔记和其他 metadata，但不复制用户原文件正文；
  分享前必须审阅 snapshot 及其 companion files。
- 更新资料库配置中的概览输出、locale、iCloud 警告和未匹配文件回落策略。

资料库配置读取兼容 `system`、`zh-Hans`、`zh-CN`、`en`；保存时使用设置页稳定值，调用 Core 前执行上述归一化。它仍是资料库内容配置，不是应用 UI 语言开关。

更换资料库不会在设置页直接移动旧资料库内容，而是进入资料库选择和校验流程。

## 分类规则

分类规则页以可视化规则维护为主：

- 列出规则并选择当前规则。
- 创建、更新和删除非默认分类规则。
- 编辑 slug、显示名、说明、命名模板、扩展名和关键词。
- 保存前执行字段校验和影响预览。
- 删除规则或移除 matcher 前要求确认。

从该页面保存规则只影响后续分类；不会移动、删除、重命名或重新分类已有文件。

规则引擎开关包括 extension rules、keyword rules 和 fallback to inbox。这些开关写入当前资料库配置。

YAML 辅助操作包括：

- 打开 `classifier.yaml`。
- 在 Finder 中显示该文件。
- 校验当前规则。
- 恢复到上次有效版本。
- 文件缺失或不可读时创建默认配置。

设置页不提供 classifier YAML 的通用 Import/Export，也不提供模板库。YAML 是高级恢复和直接编辑入口，不替代可视化规则维护。

## AI

AI 页管理仓库级 AI 行为：

- AI 总开关。
- local / remote provider preference。
- 本地模型状态和远程 provider 配置入口。
- 分类、标签、摘要等功能开关。
- 隐私规则管理。
- AI 调用日志。
- `Pause all AI` 安全动作。

远程 provider、credential 和隐私规则属于敏感边界。应用必须保持明示配置、最小数据使用、可暂停和可回退；设置页不得把远程调用伪装成本地处理。

调用日志中的 `Privacy rules checked = yes` 表示请求确实进入并完成 privacy gate（隐私门禁）评估，
即使没有命中任何规则。规则 ID、规则名和 matched field 只在实际命中时出现。旧日志缺少显式字段且
`privacy_rule_id = NULL` 时保守显示为 `not recorded`，不能据此推断当时已经完成隐私检查。

## 集成

集成页展示 iCloud Drive 与外部工具状态：

- 当前资料库是否位于 iCloud 管理路径。
- iCloud 状态、风险说明和 Apple 帮助入口。
- `Show iCloud warnings` 持久化开关。
- 在 Finder 中显示资料库。
- 外部应用修改文件时由 watcher 在可用条件下回流。

该页面不会自动下载 iCloud placeholder，也不会修改 Spotlight 或系统 iCloud 设置。

## 高级

高级页提供：

- App/Core/schema 版本和诊断边界说明。
- 日志目录和诊断摘要。
- 恢复工具入口。
- 概览输出设置。
- 默认关闭的 Replace 导入选项。

启用 Replace 前必须确认。即使启用，每次替换仍需单独确认；可恢复的旧资料库文件进入系统 Trash，不能静默覆盖。

高级页不存在 `enableTreeCache`、`listPageSize` 等用户可编辑字段，也不提供任意 key/value 配置编辑器。

## 关于

关于页展示：

- App、Core 和 metadata schema 版本。
- 当前平台能力差异。
- 许可证。
- 项目、Issues、Discussions 等 HTTPS 链接。
- About 脱敏文本诊断和日志路径。

About 文本诊断不包含用户原文件正文，路径和用户名按其合同脱敏。repository diagnostics snapshot 是
完整 metadata 快照，不应标记为脱敏；两种产物都不自动上传。

## 保存、失败与恢复

- 持久化写入通过 Core 配置 API 或明确的平台服务完成。
- 保存期间禁用冲突操作。
- 保存失败时 UI 恢复为上次持久化值，并提供重试或恢复动作。
- 文件或 DB 错误通过结构化 `CoreError` 映射，不用字符串匹配决定主流程。
- 设置窗口不提供全量 settings Import/Export，也不提供 `Reset all settings`。

## 文件安全不变量

- 默认生成内容只写 `.areamatrix/generated/`。
- 不覆盖已有 `README.md`。
- 分类规则保存不移动已有文件。
- iCloud 状态读取不触发隐式下载。
- 诊断不复制或上传用户原文件正文；repository snapshot 仍可能包含 DB 中的用户 metadata 和笔记。
- 更换资料库、恢复、Replace 和远程 AI 都必须进入各自确认边界。

## 验证重点

- 7 个 Tab 路由与侧栏标识一致。
- 持久化失败后 UI 回到已保存值。
- Move、Index-only、根 `AREAMATRIX.md` 和 Replace 都有确认。
- 可视化 classifier CRUD 与 YAML 辅助动作均可恢复。
- AI 隐私、provider 和暂停入口保持可发现。
- 诊断、外部链接、Finder 和 iCloud 错误有明确反馈。

## Related

- [classifier-calibration.md](classifier-calibration.md)
- [first-launch.md](first-launch.md)
- [../user-guide/settings.md](../user-guide/settings.md)
- [../product/privacy.md](../product/privacy.md)
- [../architecture/macos-frontend-architecture.md](../architecture/macos-frontend-architecture.md)
