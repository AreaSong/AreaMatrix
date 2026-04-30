# S1-10 main-loading - 加载 / 扫描状态

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-10
> 页面类型：主窗口
> 页面文件：`S1-10-main-loading.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 主窗口三栏
- **建议目录**：`apps/macos/AreaMatrix/Features/MainWindow/`
- **建议组件**：`MainLoadingView`、`TreeSkeletonView`、`ListLoadingOverlay`
- **实现说明**：用于 repo opening、Tree loading、List loading、rescan，不要让 UI 闪白。

## 页面背景

用户打开资料库、切换大分类或触发扫描时，数据需要时间加载。页面要显示正在做什么，同时尽量保留已有内容。

入口：`S1-03 validate-path` 打开已有 repo、`S1-07 init-done` 进入主窗口、`S1-37 db-repair-confirm` 修复成功、主窗口切换 Tree 节点或触发 rescan。
退出：repo 打开成功进入 `S1-08 main-empty` 或 `S1-09 main-list`；局部列表加载成功回到当前主窗口；critical 失败进入 `S1-11 main-repo-error`；局部查询失败进入 `S1-32 error-recovery` 的 inline error 组件。

## 页面功能

- 显示全屏 repo opening 状态。
- 显示 Tree/List 局部 skeleton。
- 显示扫描进度。
- 在可行时允许继续浏览已加载节点。

## 布局与内容

Repo opening 全屏文案：

```text
正在打开资料库...
```

全屏 opening 只显示 repo path、spinner 和可选 `Cancel opening`。Cancel opening 返回上一入口：首次打开返回 `S1-03 validate-path`；普通启动则退出打开流程并保留旧 repo 配置。

Tree loading：保留旧 Tree，未加载部分显示 skeleton。

List loading：List 顶部显示：

```text
正在加载 docs...
```

Rescan 顶部进度：

```text
正在扫描资料库 324 / 1200
```

## 状态与规则

- repo opening 不显示半成品主界面。
- Tree loading 可保留上次树。
- List loading 可保留旧列表但显示遮罩或顶部进度。
- 迁移/恢复时 Tree locked，只允许查看。
- 默认状态：打开 repo 时 Detail 为空；切换 Tree 节点时 Detail 清空为 `选择一个文件查看详情`。
- list loading 期间禁用当前列表写操作（Rename/Delete/Change Category），但允许切换已加载 Tree 节点。
- DB locked 属于局部查询失败时，优先显示 List inline error，Tree 不进入 locked。
- repo path missing、permission denied、DB corrupted、schema incompatible 才进入 `S1-11 main-repo-error`。
- 空态不适用：本页表示打开、扫描或刷新中的过渡状态；无数据结果完成后进入 `S1-08 main-empty`。

## 交互

- 用户可以切换已加载节点。
- 新 selection 应取消旧 List 查询。
- 长任务失败进入 inline error 或 repo error。
- 点击 `Cancel opening` 只取消 UI 打开流程，不删除 repo 配置、不修改用户文件。
- 局部 Retry 只重试当前 Tree/List 请求；repo opening Retry 重新执行 open repo。

## 可访问性

- loading 文本必须说明当前阶段，例如 `Opening repository`、`Loading files`、`Scanning changes`。
- 进度条必须有可访问值；未知进度使用 indeterminate 描述。
- `Cancel opening` 的后果需要可读说明，不能只显示图标。

## 数据与依赖

- repoState。
- tree loading state。
- list pagination state。
- scan progress。
- 上一入口 route，用于 Cancel opening 后返回。

## 验收清单

- 打开 repo 时不会看到空白窗口。
- 切换分类不会导致 Detail 显示错文件。
- rescan 有进度和失败提示。
- DB locked 不阻断 Tree；critical repo 错误才进入 S1-11。
- 列表加载期间写操作禁用且不会误作用到旧 selection。

## 来源

- `docs/ux/ui-states.md#tree侧边栏状态机`（直接）。
- `docs/ux/ui-states.md#list文件列表状态机`（直接）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-03 validate-path](S1-03-validate-path.md)
- [S1-07 init-done](S1-07-init-done.md)
- [S1-08 main-empty](S1-08-main-empty.md)
- [S1-09 main-list](S1-09-main-list.md)
- [S1-11 main-repo-error](S1-11-main-repo-error.md)
- [S1-32 error-recovery](S1-32-error-recovery.md)
- [S1-37 db-repair-confirm](S1-37-db-repair-confirm.md)
