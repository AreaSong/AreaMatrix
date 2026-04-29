# S1-07 init-done - 初始化完成

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-07
> 页面类型：首次启动
> 页面文件：`S1-07-init-done.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 首次启动向导
- **建议目录**：`apps/macos/AreaMatrix/Features/Onboarding/`
- **建议组件**：`InitDoneStepView`
- **实现说明**：这是向导最后一步，点击主按钮后进入 `S1-10 main-loading` 打开 repo，再落到空库或正常列表。

## 页面背景

资料库已成功创建或接管，用户可以进入主窗口浏览和导入文件。

退出：点击 `Open Repository` 进入 `S1-10 main-loading`；加载成功后进入 `S1-08 main-empty` 或 `S1-09 main-list`。

## 页面功能

- 告知资料库已准备好。
- 展示 repoPath。
- 展示新建或接管摘要。
- 引导打开资料库或 Finder。

## 布局与内容

标题：`资料库已准备好`

主说明：

```text
AreaMatrix 已完成初始化。你现在可以浏览资料库，或把文件拖进窗口开始归档。
```

完成摘要：

新建空资料库：

- 已创建默认分类。
- 已创建本地索引。
- 已启用自动概览。

接管已有目录：

- 已建立本地索引。
- 已扫描现有文件。
- 已保留原有目录结构。
- 已生成内部概览。

下一步提示：拖入文件、浏览分类、查看详情。

按钮：`Open Repository`、`Open in Finder`。

## 状态与规则

- 默认状态：`Open Repository` 为主按钮，焦点默认在该按钮。
- 如果打开 Finder 失败，显示非阻断错误。
- 打开 Finder 执行中禁用重复点击；失败不禁用 `Open Repository`。

## 交互

- `Open Repository` 关闭向导并进入 `S1-10 main-loading`；repo 打开成功后根据文件数量进入 `S1-08 main-empty` 或 `S1-09 main-list`。
- `Open in Finder` 打开 repo 根目录。

## 数据与依赖

- 初始化结果摘要。
- repoPath。
- Finder open API。

## 验收清单

- 完成页展示 repoPath。
- 接管场景展示“已保留原有目录结构”。
- 进入主窗口后可以拖入文件。
- Open Repository 后先显示加载态，不展示半成品主窗口。

## 来源

- `docs/ux/first-launch.md#7-done完成`（直接）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-10 main-loading](S1-10-main-loading.md)
- [S1-08 main-empty](S1-08-main-empty.md)
- [S1-09 main-list](S1-09-main-list.md)
