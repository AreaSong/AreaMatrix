# S1-14 detail-note - 伴生笔记

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-14
> 页面类型：详情
> 页面文件：`S1-14-detail-note.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 详情面板
- **建议目录**：`apps/macos/AreaMatrix/Features/Detail/`
- **建议组件**：`NoteTabView`、`MarkdownNoteEditor`、`NoteSaveStatusView`
- **实现说明**：Note 是文件伴生笔记，不是全局笔记系统。Stage 1 固定采用 debounce 自动保存；保存失败不能清空用户输入。

## 页面背景

用户希望为某个文件补充上下文、处理状态或关联信息。笔记以 Markdown 形式保存，与文件条目关联。

入口：`S1-12 detail-meta` 的 `Note` tab。
退出：切回 `Meta` / `Log` tab、切换 List 选中项、清空选择或关闭主窗口。若有未保存失败草稿，退出前必须保留 draft 并提示。

## 页面功能

- 展示或创建文件伴生笔记。
- 编辑 Markdown 内容。
- 显示保存状态。
- Stage 1 必做编辑与保存状态；Markdown Preview 只作为可选增强，不作为验收必需。

## 布局与内容

顶部保留文件摘要和 tabs，当前选中 `Note`。

工具条：

- 标题：`Note`
- 保存状态：`Saved` / `Saving...` / `Unsaved`
- 必做按钮：`Open note file`
- 可选按钮：`Preview` / `Edit`，若未实现 Preview，本页始终显示编辑模式。

无笔记空态：

```text
还没有笔记
为这个文件添加上下文、处理状态或关联信息。
```

按钮：`Create Note`

编辑区示例：

```markdown
# 客户A 2026 Q1 合同

- 来源：邮件附件
- 用途：季度服务合同归档
- 处理状态：已核对金额
```

## 状态与规则

- 无笔记：显示空态和 Create Note。
- 默认状态：首次进入本 tab 时读取 note；无 note 则显示空态。
- 加载态：读取 note 时显示 `Loading note...`，保留文件摘要，不显示空编辑器。
- 编辑中：显示 Unsaved 或 Saving。
- 保存成功：显示 Saved。
- 保存失败：显示 inline error `无法保存笔记`，按钮 `Retry`，保留输入内容。
- 只读 repo：禁用编辑，显示说明。
- 文件缺失：允许查看已有笔记；禁用写入并提示 `文件缺失时暂不能保存笔记`。
- 多选或无选中时不显示本页。

## 交互

- 输入后 debounce 自动保存，停止输入约 800ms 后保存；保存中显示 `Saving...`。
- `Retry` 只重试最近一次保存失败的草稿，不重新读取并覆盖当前编辑内容。
- 切 tab 不丢草稿。
- 切文件前若保存失败，保留 draft 并提示。
- 点击 `Create Note` 创建空草稿并聚焦编辑区；创建前不写入文件，首次自动保存成功后才生成 note。
- 点击 `Open note file` 打开伴生笔记文件；如果 note 尚未保存，先提示用户等待保存或继续编辑。

## 可访问性

- 编辑器需要有 `Companion note` 标签，保存状态需要可被 VoiceOver 宣告。
- 保存失败错误要和编辑器关联，不能只显示红色边框。
- Create Note、Retry、tab 切换均可通过键盘访问；未保存失败草稿提示需要可读。

## 数据与依赖

- Core `read_note(repoPath, fileId)`。
- Core `write_note(repoPath, fileId, contentMd)`。
- note save state。

## 验收清单

- 无笔记时能创建。
- 保存失败不丢内容。
- 切换 Meta/Log/Note 不破坏草稿。
- 自动保存策略在 UI 状态和错误恢复中一致。
- Preview 未实现时不影响 Stage 1 验收。
- 文件缺失或只读 repo 不会清空已有草稿。

## 来源

- `docs/ux/ui-states.md#tab-约定`（组合）。
- `docs/api/core-api.md#note-api`（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-12 detail-meta](S1-12-detail-meta.md)
- [S1-13 detail-log](S1-13-detail-log.md)
