# 隐私与数据处理

> AreaMatrix 默认在本机处理资料库、日志和诊断；任何远程数据流必须由用户明确配置和允许。
>
> 阅读时长：约 6 分钟。

## 本地数据

AreaMatrix 可能在本机处理：

- 用户选择的资料库路径、文件名、路径、大小、时间和文件内容。
- `.areamatrix/` 内的数据库、配置、扫描状态、索引、生成概览和恢复信息。
- 标签、笔记、改动历史、Saved Search、Smart List 和 AI 隐私规则。
- 本地日志、诊断摘要和 AI 调用记录。

应用不以遥测或后台上传为前提。诊断导出由用户显式触发，并在导出前展示内容、脱敏等级、大小，以及是否包含
repository metadata snapshot。当前诊断包不接受任意用户文件附件。

## 日志与诊断

标准、诊断和开发者模式在所有安装版本中都可由用户开启。用户可以查看当前模式、保留期限、磁盘预算、实际占用、
丢弃事件数，并随时关闭持久化或删除本地日志。开发者模式提供更多技术细节，但不会解除 prohibited 数据边界。

运行事件字段分为：

- `public`：稳定 action/component/error code、结果和耗时。
- `pseudonymous`：使用 keyed alias 的文件引用、扩展名和大小区间。
- `sensitive`：真实文件名、路径、repository 名称和 metadata snapshot。
- `prohibited`：文件或 Note 正文、secret、token、Authorization header、完整 AI prompt/output 或原始响应体。

`prohibited` 数据不进入任何日志模式。`sensitive` 数据只在对应本地设置或诊断包步骤明确选择后使用；选择文件名不等于
选择完整路径，选择运行日志不等于选择 repository metadata snapshot。

脱敏在事件产生端和诊断导出端分别执行。错误字符串、第三方响应、恶意文件名、URL 和非 home 路径同样处理。
文件别名使用随机密钥生成的不可反查 pseudonym，不直接 hash 原文件名。

## 问题捕获与诊断包

用户可以标记刚才的问题。应用只冻结有界的事件窗口、稳定状态和受控资源引用，不记录屏幕视频、鼠标轨迹、hover、
滚动或逐键输入。

`.amdiagnostic` 在本地生成，用户保存前可以预览事件范围、环境摘要、隐私报告和附件清单。包默认不包含用户文件正文、
真实路径或 repository DB。当前唯一允许的附件类别是用户单独确认的 repository metadata snapshot，以及存在时与其配套的
WAL/SHM；它们可能含路径、文件名、tags 和 notes，必须保持明确标记。离线 viewer 将包视为不可信输入，不执行其中的
URL、脚本、恢复动作或命令。

AreaMatrix 不因创建或保存诊断包而自动上传。网络发送必须在 endpoint、身份、传输加密、服务端保留、删除、撤回和
安全责任都形成独立合同后才能提供；远程服务也不能静默开启本机开发者模式。

## 文件访问

AreaMatrix 只应访问用户明确选择的资料库和导入来源。文件系统访问遵守：

- 接管不修改已有文件。
- 导入副作用由用户选择的存储模式决定。
- 自动生成内容默认位于 `.areamatrix/generated/`。
- 用户已有 `README.md` 不被覆盖。
- 删除 `.areamatrix/` 不删除用户文件。

## 本地 AI

本地模型在本机运行时，AreaMatrix 仍应：

- 明确显示模型状态和不可用原因。
- 只读取完成当前任务所需的最小数据。
- 允许用户拒绝、修改或清除生成结果。
- 不把本地模型可用等同于所有 AI 功能自动启用。

## 远程 AI

远程 Provider 默认关闭。启用需要：

1. 用户明确选择 Provider 和 endpoint。
2. 凭据安全保存在 macOS Keychain 或等价平台存储。
3. 隐私规则允许当前任务和数据范围。
4. 界面说明可能发送的数据类别。
5. 用户显式触发调用。

Rust Core 负责生成不含密钥的调用计划和处理净化后的 observation。macOS 平台层负责 Keychain、URLSession 和网络限制。Core 不读取 Keychain，也不直接发起网络请求。

## 数据最小化

远程调用只发送任务所需信息。产品界面必须区分文件名、路径、提取文本、笔记、标签、摘要和完整文件内容，不能把它们作为一个不可分辨的数据包处理。

未被明确允许的内容不得发送。错误信息、日志和调用记录不得保存密钥、Authorization header、完整响应 header 或不必要的底层错误原文。

## 用户控制

用户可以：

- 关闭远程 Provider。
- 删除或更换凭据。
- 修改允许和拒绝规则。
- 放弃 AI 建议，不写入分类、摘要或标签。
- 查看净化后的调用记录。
- 清除可编辑的生成内容。
- 开启或关闭标准、诊断和开发者日志模式。
- 设置日志保留期限与磁盘预算并删除本地日志。
- 标记问题、预览脱敏结果并决定是否保存诊断包。
- 分别决定是否包含文件名、完整路径或 repository metadata snapshot；不支持添加任意用户文件附件。

## Related

- [产品概览](overview.md)
- [产品能力](capabilities.md)
- [AI 用户指南](../user-guide/ai-features-and-privacy.md)
- [AI 与文件安全规则](../../.ai-governance/project/areamatrix-rules.md)
- [安全政策](../../SECURITY.md)
- [可观测性与诊断](../development/observability.md)
