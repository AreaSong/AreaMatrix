# AI 功能与隐私

> AI 能力是可选增强。用户需要明确配置模型、数据范围和远程调用权限。
>
> 阅读时长：约 7 分钟。

## 可用能力

- 分类建议。
- 文件摘要编辑。
- 标签建议和批量标签建议。
- 语义搜索与索引。
- 本地/远程失败回退。
- 调用日志查看。

## 本地模型

在 AI 设置中查看 Core 当前配置的本地模型状态、安装帮助、模型目录和健康检查结果。当前界面不提供模型选择器；模型不可用时，按状态页提示检查服务、模型标识和诊断信息。AreaMatrix 不应把“检测到模型配置”误报为“模型已经成功完成调用”。

## 文件摘要

选择文件后，在详情区域打开 `Summary` 标签页。摘要编辑器可以生成、编辑、保存或清除摘要，并在需要时显示隐私阻断、失败恢复和调用日志入口。离开存在未保存内容的摘要时，应用会要求保存或放弃，不能静默丢弃编辑结果。

## 远程 Provider

1. 选择 Provider 和 endpoint。
2. 将凭据保存到 macOS Keychain。
3. 执行受限连通性探测。
4. 配置允许和拒绝规则。
5. 在具体功能中显式触发远程调用。

探测成功只证明当前配置可连接，不代表所有数据都允许发送。

## 审阅建议

分类、摘要和标签建议都需要用户审阅。应用建议前查看目标文件、建议内容和影响；放弃建议不得改变文件、标签或摘要。

每次新的 AI attempt 在进入 privacy/provider 等待前冻结当前资料库的 concrete content locale。local 到
remote 的 automatic provider fallback 属于同一 attempt，继续使用原 locale；用户明确发起的新 attempt
才重新读取设置。恢复中的 AI session 必须保存稳定 operation code、结构化 payload 和 concrete locale，
不能保存翻译后的 UI 文案，也不能在恢复时用当前设置补猜缺失 locale。

AI 生成的摘要以及建议中的自然语言 display/reason 使用该 content locale。文件名、路径、category slug、
已有 candidate tag、用户自定义 tag 和用户输入保持原文。AreaMatrix 不把这些值隐式翻译后回写，也不因
跨语言近义关系自动合并 tag/category；接受建议仍需用户审阅，并使用现有精确冲突与重复处理规则。

未编辑的生成结果属于 generated-owned。用户编辑摘要或接受建议 tag 后，对应值立即转为 user-owned
verbatim content；之后替换它必须再次明确确认。修改界面语言或资料库内容语言不会重新调用 AI，也不会
重写任何已有结果。“重新生成全部概览”不包含 AI 摘要。搜索查询与返回的用户内容保持原文，不执行隐式
翻译；持久化 AI 自然语言才使用 operation 冻结的 content locale。

对 user-owned 摘要再次生成时，当前已保存值保持不变；新 draft 与当前摘要并列展示，用户明确选择替换、
保留原摘要或继续编辑。清除 user-owned 摘要也需要确认。最终保存遇到 content revision 冲突时保留 draft，
不得自动重试或合并；终态失败后的 Retry 创建新的 `operation_id` 并通过 `retry_of_operation_id` 关联旧操作。

content locale 只记录请求语言。只有 provider 返回结构化 language metadata，或本地 advisory detector 达到
明确高置信度时，界面才提示“结果语言可能不同”；没有可靠信号时不猜测。警告不会改变 provenance、内容
或所有权，也不会触发自动翻译、自动重试或静默 provider 切换。

## 隐私规则

隐私规则决定某类任务和数据是否可以离开本机。规则至少应区分文件名、路径、笔记、提取文本、标签、摘要和完整内容。未明确允许的数据不得发送。

## 调用日志

调用日志用于解释任务、Provider、结果和失败回退。`Privacy checked` 表示本次请求确实经过隐私规则评估，
不等于命中了某条规则；命中的规则会单独显示。旧日志若缺少可证明的检查记录，会保守显示为未记录。
日志不得包含凭据、Authorization header、完整敏感响应 header 或不必要的底层错误原文。
调用日志记录稳定 operation/provider/result code 与本次 content locale；面向用户的说明在查看时按当前
界面语言解析。日志不得把 catalog key、`AppDisplayText` 或已翻译消息当作恢复源事实。

## Related

- [隐私与数据处理](../product/privacy.md)
- [产品能力](../product/capabilities.md)
- [搜索、标签与智能列表](search-tags-and-smart-lists.md)
- [安全政策](../../SECURITY.md)
