# S1-02 choose-path - 选择资料库位置

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-02
> 页面类型：首次启动
> 页面文件：`S1-02-choose-path.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 首次启动向导
- **建议目录**：`apps/macos/AreaMatrix/Features/Onboarding/`
- **建议组件**：`ChoosePathStepView`、`RepositoryPathField`、`OnboardingStore`
- **实现说明**：只做路径选择和轻校验，不创建 repo，不扫描目录。

## 页面背景

用户需要选择一个普通文件夹作为 AreaMatrix 资料库根目录。这个目录可以是空目录，也可以是已有内容的目录。页面重点是让用户知道资料库不是黑盒。

入口：`S1-01 welcome` 点击 Continue；初始化失败页 `Change Path`；Settings > Repository 的 `Change repository...`。
退出：Back 返回来源页；Continue / Use default 进入 `S1-03 validate-path`；关闭窗口或 Escape 先弹退出确认，确认后退出向导且不写 repo 配置；从 Settings 进入时 Cancel/Back 返回 `S1-27 settings-repository` 且保留当前 repo。

## 页面功能

- 显示默认推荐路径 `~/AreaMatrix/`。
- 允许用户手动编辑路径。
- 允许通过系统目录选择器选择文件夹。
- 说明可以接管已有目录且不会破坏内容。

## 布局与内容

标题：`选择资料库位置`

说明文案：

```text
资料库是一个普通文件夹，你可以随时在 Finder 中访问。
```

推荐位置区：

- 标签：`推荐位置`
- 路径：`~/AreaMatrix/`

路径选择区：

- 标签：`路径`
- 输入框默认：`~/AreaMatrix/`
- 右侧按钮：`Choose...`
- 下方提示：`接管已有目录不会移动、改名、删除或覆盖原有内容。`

底部按钮：`Back`、`Use default`、`Continue`。

## 状态与规则

- 默认状态：路径输入框预填推荐路径，Continue 可用；焦点默认在路径输入框或 Continue，取决于路径是否有效。
- 路径为空：输入框下方显示 `请输入资料库路径`，禁用 Continue。
- 路径指向 `.areamatrix/` 内部：显示 `请选择资料库根目录，而不是 .areamatrix 内部目录`。
- 路径字符串无法解析：显示轻量错误，不进入下一步。
- 不在本页判断 iCloud、空间、权限和非空目录，这些留给 `S1-03 validate-path`。
- 加载态不适用：目录选择由系统 sheet 承接；本页本身不做长任务。
- 空态不适用：路径输入始终存在，空路径按表单错误处理。

## 交互

- `Use default` 将路径重置为 `~/AreaMatrix/` 并进入校验页。
- `Choose...` 打开 `NSOpenPanel`，只允许选择目录。
- `Continue` 通过轻校验后进入 `S1-03 validate-path`。
- `Back` 返回欢迎页。
- 关闭窗口或 Escape 显示 `Quit setup?`；确认后退出，不创建文件、不保存新 repoPath。
- 从 Settings 发起的换库流程中，Back / Cancel 返回 `S1-27 settings-repository`，不得清空当前已打开 repo。

## 可访问性

- 路径输入框需要有可访问标签 `Repository path`，错误文案要和输入框关联。
- `Choose...`、`Use default`、`Back`、`Continue` 均可通过键盘访问。
- 不只用红色表示路径错误；必须同时显示错误文本。

## 数据与依赖

- macOS `NSOpenPanel`。
- 本地默认路径规则。
- 上次未完成初始化时可预填 repoPath。

## 验收清单

- 可以使用默认路径继续。
- 可以选择任意目录路径继续。
- 选择 `.areamatrix/` 子目录会被阻止。
- 关闭窗口、Escape、Back 和 Settings Cancel 都有明确返回路径。
- 本页不会创建或修改任何文件。

## 来源

- `docs/ux/first-launch.md#2-choosepath选择资料库路径`（直接）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-03 validate-path](S1-03-validate-path.md)
