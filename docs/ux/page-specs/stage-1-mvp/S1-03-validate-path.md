# S1-03 validate-path - 校验与风险提示

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-03
> 页面类型：首次启动
> 页面文件：`S1-03-validate-path.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 首次启动向导
- **建议目录**：`apps/macos/AreaMatrix/Features/Onboarding/`
- **建议组件**：`ValidatePathStepView`、`PathCheckListView`、`RepositoryPathValidator`
- **实现说明**：负责真实路径校验和风险收口；仍不执行初始化。

## 页面背景

用户已选择资料库路径。AreaMatrix 必须在创建任何内容前说明路径是否可用、是否在 iCloud、是否是外置卷、是否已有 repo、是否为非空目录。

入口：`S1-02 choose-path` 点击 Continue / Use default；Settings > Repository 换库流程选择新路径后进入。
退出：Back / Change Path 返回 `S1-02 choose-path`；新建或接管分支 Continue 进入 `S1-04 confirm-init`；已存在完整 repo 分支 Open Repository 进入 `S1-10 main-loading`；关闭窗口或 Escape 先弹退出确认，确认后退出向导或返回 Settings 来源页。

## 页面功能

- 展示当前路径。
- 执行并展示路径检查结果。
- 对 iCloud、外置卷、非空目录给出风险说明。
- 对不可写、空间不足等错误给恢复动作。

## 布局与内容

顶部路径信息框：`~/AreaMatrix/`。

检查列表：

- 可写权限
- 可用空间，例如 `32.4 GB`
- 是否 iCloud 路径
- 是否外置卷
- 是否已有 AreaMatrix repo
- 是否非空目录

非空目录卡片标题：`将接管已有目录`

卡片内容必须包含：

- 将创建 `.areamatrix/` 内部目录。
- 将扫描现有文件和文件夹。
- 不移动、不重命名、不删除、不覆盖任何已有文件。
- 已有 `README.md` 和项目目录结构保持原样。

iCloud 卡片标题：`iCloud Drive 路径`

卡片必须有复选框：`我理解 iCloud 同步可能带来延迟与冲突风险`。

已存在完整 repo 分支：

- 标题：`已找到 AreaMatrix 资料库`
- 说明：`该文件夹已经包含可打开的 .areamatrix/index.db。AreaMatrix 将打开现有资料库，不会重新初始化或接管。`
- 显示 schema version、最近打开时间（若有）和 repo path。
- 底部按钮改为 `Back`、`Choose another folder`、主按钮 `Open Repository`。

新建或接管分支底部按钮：`Back`、`Continue`。

## 状态与规则

- 默认状态：进入页面后立即开始检查，检查完成前 `Continue` / `Open Repository` 不显示或禁用。
- 所有检查通过：Continue 可用。
- 不可写：显示红色错误卡，按钮 `Change Path` / `Retry`，禁用 Continue。
- 空间不足：显示建议释放空间或换路径。
- iCloud：未勾选风险确认时禁用 Continue。
- 外置卷：显示 warning，但不阻止继续。
- 已存在完整 repo：显示“打开现有资料库”分支，不显示新建/接管说明，不允许进入 `S1-04 confirm-init`。
- 已存在 repo 但 schema 不兼容：进入 `S1-11 main-repo-error`，主动作是 `Choose another folder` 或 `Export diagnostics`；不得静默迁移或重建。
- 已存在 repo 但 DB corrupted：进入 `S1-37 db-repair-confirm`，并说明修复只处理 `.areamatrix/` 元数据。
- 已存在 repo 但 metadata 不完整 / repair-needed：进入 `S1-37 db-repair-confirm`，不得从校验页直接 reindex。
- 权限不足、不可写、空间不足：留在本页错误态，提供 `Change Path` / `Retry`，不创建 `.areamatrix/`。
- 空态不适用：本页必须展示路径和检查列表；检查结果缺失按加载态或错误态处理。

## 交互

- `Retry` 重新运行检查。
- `Change Path` 返回 `S1-02 choose-path`。
- 新建或接管分支点击 `Continue` 进入 `S1-04 confirm-init`。
- 已存在完整 repo 分支点击 `Open Repository`：保存/更新 repo 选择后进入 `S1-10 main-loading`；打开成功进入 `S1-09 main-list` 或 `S1-08 main-empty`，打开失败进入 `S1-11 main-repo-error`。
- `Choose another folder` 返回 `S1-02 choose-path`，不修改当前已存在 repo。
- 检查中显示 spinner 和当前检查项。
- 关闭窗口或 Escape 显示 `Quit setup?`；确认后退出，不创建 `.areamatrix/`，不保存新 repo 配置。
- 从 Settings 发起的换库流程中，Back / Cancel 返回 `S1-27 settings-repository`，新 repo 成功打开前不修改当前 repo。

## 可访问性

- 检查列表每一项需要有文本状态，例如 `Passed`、`Warning`、`Failed`，不能只靠颜色或图标。
- iCloud 风险确认复选框要和说明文本关联，未勾选时 Continue 的禁用原因可被 VoiceOver 读出。
- Back、Change Path、Retry、Continue / Open Repository 都必须支持键盘焦点顺序。

## 数据与依赖

- `FileManager.isWritableFile` 和试建临时文件。
- volume 可用空间。
- iCloud 路径/资源属性检测。
- `.areamatrix/index.db` 和 schema 检测。
- 非隐藏文件/目录统计。
- repo open preflight result，包括完整 repo / 不完整 repo / schema 不兼容。

## 验收清单

- 不可写路径无 crash，且不能继续。
- iCloud 路径必须显式确认。
- 非空目录必须显示不破坏文件承诺。
- 本页不创建最终 repo 结构。
- 已存在完整 repo 只能走 `Open Repository`，不得进入初始化或接管确认。
- 不完整或不兼容 repo 必须进入错误/修复路径，不能自动重建。
- 关闭窗口、Escape、Back 和 Settings Cancel 都有明确返回路径。

## 来源

- `docs/ux/first-launch.md#3-validatepath校验与风险提示`（直接）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-02 choose-path](S1-02-choose-path.md)
- [S1-04 confirm-init](S1-04-confirm-init.md)
- [S1-08 main-empty](S1-08-main-empty.md)
- [S1-09 main-list](S1-09-main-list.md)
- [S1-10 main-loading](S1-10-main-loading.md)
- [S1-11 main-repo-error](S1-11-main-repo-error.md)
- [S1-37 db-repair-confirm](S1-37-db-repair-confirm.md)
