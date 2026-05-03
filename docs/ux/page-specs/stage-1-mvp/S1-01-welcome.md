# S1-01 welcome - 欢迎页

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-01
> 页面类型：首次启动
> 页面文件：`S1-01-welcome.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 首次启动向导。
- **建议目录**：`apps/macos/AreaMatrix/Features/Onboarding/WelcomeStepView.swift`。
- **建议组件**：`WelcomeStepView`、`OnboardingFlowView`、`SafetyPromiseList`。
- **实现说明**：这是首次启动向导第一个 step。页面本体不执行文件 IO；外层 onboarding shell 可在显示本页前通过 C1-04 `load_config` 读取已配置 repo，用于决定继续显示欢迎页、进入已就绪状态或显示配置错误。

## 页面背景

用户第一次打开 AreaMatrix，尚未选择资料库。页面目标不是营销，而是建立对文件安全的信任：AreaMatrix 使用普通文件夹、本地优先、可追踪，并且接管已有目录时不会覆盖用户已有内容。

入口：无 repo 配置时启动 App；用户重置 onboarding 后重新进入。
退出：点击 Continue 进入 `S1-02 choose-path`；退出 App 或关闭向导时下次仍从本页继续。

## 页面功能

- 展示产品名和一句话定位。
- 展示 4 条安全承诺。
- 说明 AreaMatrix 会使用普通文件夹作为资料库。
- 提供继续向导入口。
- 提供 Learn more 入口。
- 不要求登录，不请求权限，不选择路径。

## 布局与内容

窗口建议宽 760、高 520，内容居中偏左，最大文本宽度约 620。背景使用 macOS 原生 window 背景，不放营销大图。

标题区：
- 产品名：`AreaMatrix`
- 副标题：`把资料放进普通文件夹，让 AreaMatrix 负责索引、分类和记录变化。`
- 辅助说明：`你可以随时用 Finder 打开资料库。`

安全承诺列表：
- `普通文件夹`：你的资料库就是一个文件夹，不是封闭数据库。
- `本地优先`：Stage 1 默认不上传任何资料。
- `可追踪`：导入、改名、移动和外部修改会写入时间线。
- `不覆盖已有文档`：接管目录时不会覆盖已有 `README.md` 或用户文件。

底部：
- 左侧文本按钮：`Learn more...`
- 右侧主按钮：`Continue`

## 状态与规则

- 默认状态：显示欢迎文案和 Continue，焦点默认在 Continue。
- 本页没有加载态和错误态；如果配置读取失败，应由外层 onboarding 显示错误恢复。
- 空态不适用：欢迎页始终有固定内容，不依赖用户资料库数据。
- `Continue` 始终可用。
- `Learn more...` 打不开时显示非阻断 toast，不影响继续。
- 本页无禁用条件；只有退出确认弹窗打开时，底层按钮暂时不可操作。
- 执行中状态不适用：本页不发起长任务。
- 不在本页请求文件系统权限或创建目录。
- 不显示未来阶段能力，避免用户误解 Stage 1 范围。

## 交互

1. 首次启动后显示本页，焦点默认在 `Continue`。
2. 点击 `Continue` 进入路径选择。
3. 按 Enter 触发 `Continue`。
4. 按 Escape 或关闭窗口时显示 `Quit setup?` 确认；确认后退出，未写入任何 repo 配置。
5. 点击 `Learn more...` 打开应用内帮助或本地文档。

## 可访问性

- Continue 必须可通过 Tab 聚焦并可用 Enter 触发。
- VoiceOver 先读标题，再读三条能力说明，再读按钮。
- 本页没有颜色语义要求；若使用图标，图标必须有可访问标签。

## 数据与依赖

- App settings：判断是否已有 repo。
- C1-04 `load_config`：仅当 App settings 已有 repo path 时由外层 onboarding shell 触发，用于读取真实 `RepoConfig` 或映射配置错误。
- Onboarding route state。
- Help link opener。
- 欢迎页内容本身不创建 `.areamatrix/`，不访问用户文件，也不执行配置更新。

## 验收清单

- 无 repo 配置时启动必须显示本页。
- 有 repo 配置时，外层 onboarding shell 必须通过 C1-04 `load_config` 读取真实配置；配置缺失返回默认值且不得创建 metadata。
- 页面包含 4 条安全承诺，且明确“不覆盖 README/用户文件”。
- Continue 可通过鼠标、Enter 和 VoiceOver 操作。
- Learn more 失败不阻断继续。
- 本页不触发任何文件系统写入。
- 关闭向导后再次启动仍能回到 onboarding。

## 来源

- `docs/ux/first-launch.md#1-welcome欢迎页`（直接）。
- `docs/product/prd.md#3-核心价值主张`（组合，本地优先与普通文件夹定位）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-02 choose-path](S1-02-choose-path.md)
