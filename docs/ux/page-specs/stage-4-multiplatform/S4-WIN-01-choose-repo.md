# S4-WIN-01 choose-repo - Windows 资料库选择

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-WIN-01
> 页面类型：Windows onboarding page  
> 页面文件：`S4-WIN-01-choose-repo.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：Windows 桌面端。
- **建议目录**：`apps/windows/AreaMatrix/Features/Onboarding/ChooseRepositoryView.*`。
- **建议组件**：`ChooseRepositoryView`、`WindowsRepositoryPicker`、`WindowsPathValidator`。
- **实现边界**：这是 Windows 首次启动和重新连接资料库页面，不实现主窗口浏览，不在选择前写入目录。

## 页面背景

Windows 用户需要选择一个 AreaMatrix 资料库目录，可能位于本地磁盘、外接盘或 OneDrive。Stage 4 目标是复用 Rust core，并用 Windows 原生文件选择与监听能力完成最小闭环。本页必须继承 Stage 1 “接管目录前不移动、不删除、不覆盖”的不变量。

入口：Windows app 首次启动、用户切换资料库、最近资料库不可访问。  
退出：已有 repo 进入 `S4-WIN-02 main-window`；检测到 OneDrive 进入 `S4-WIN-03 onedrive-notice`；空目录进入 `S4-X-04 repository-init-confirm`；非空目录进入 `S4-X-05 repository-adopt-confirm`；取消则关闭或停留在未连接状态。

## 页面功能

- 选择已有 AreaMatrix repo。
- 选择空目录准备初始化。
- 识别非空普通目录并要求后续确认。
- 检测路径是否可读、可写、是否在 OneDrive、是否网络盘或外接盘。
- 显示最近资料库列表和不可访问原因。
- 提供手动输入路径的可选入口，方便高级用户粘贴路径。
- 在继续前显示将要使用的完整路径。

## 布局与内容

窗口使用 Windows 原生桌面风格。推荐尺寸约 720x520，内容左对齐，按钮在底部右侧。

标题区：
- 标题：`Choose AreaMatrix Repository`
- 说明：`Select a folder that contains your AreaMatrix repository, or choose an empty folder to create one.`

路径选择区：
- 输入框：`Repository folder`
- 占位：`C:\Users\you\Documents\AreaMatrix`
- 按钮：`Browse...`
- 可选链接：`Paste path from clipboard`

检测结果区：
- 正常：`AreaMatrix repository found`
- 空目录：`Empty folder. AreaMatrix can initialize it after confirmation.`
- 非空目录：`This folder already contains files. AreaMatrix will ask before creating its metadata folder.`
- OneDrive：`This folder is inside OneDrive.`，点击继续前进入 OneDrive 提示。
- 不可写：显示错误和 `Choose another folder`。

最近资料库区：
- 列表项显示名称、路径、最后打开时间、状态。
- 不可访问状态显示 `Missing`、`Permission denied`、`Drive disconnected`。

底部按钮：
- `Cancel`
- `Browse...`
- 主按钮 `Continue`

## 状态与规则

- 默认状态：未选择路径时显示路径输入、Browse 和最近资料库；`Continue` 禁用。
- 空态：没有最近资料库时隐藏最近列表，不显示空白表格。
- 加载态：选择或输入路径后显示 `Checking folder...`，`Continue` 临时禁用。
- 错误态：路径不存在、不是目录、不可写、版本不兼容或检测失败时，在路径输入框下方显示具体原因。
- 未选择路径：`Continue` 禁用。
- 路径不存在：显示 `Folder not found`。
- 文件路径而非目录：显示 `Select a folder, not a file.`。
- 不可写：禁止继续初始化或接管，但可打开已有 repo 的只读提示不在 Stage 4 MVP 默认支持。
- OneDrive 路径：必须进入 `onedrive-notice` 确认，不直接进入主窗口。
- 非空目录：不得直接创建 `.areamatrix/`。
- 最近目录缺失：保留列表行，提供 `Remove from recent`，不删除磁盘文件。

## 交互

1. 点击 `Browse...` 打开 Windows folder picker。
2. 选择后立即进行只读校验，检测期间显示 `Checking folder...`。
3. 校验结果显示在路径下方，按钮状态随结果更新。
4. 点击最近资料库行会填入路径并重新校验，不直接跳转。
5. 点击 `Continue`：已有 repo 进入主窗口；OneDrive 路径先进入提示；空目录进入 `S4-X-04`；非空目录进入 `S4-X-05`。
6. 发生错误时焦点回到路径输入框，并读出错误。

## 数据与依赖

- Windows folder picker。
- Rust core repo detection。
- OneDrive 路径检测，包含用户目录下 `OneDrive` 和组织 OneDrive 命名。
- Windows ACL 可读可写检测。
- 最近 repo 持久化。
- 错误映射：`PermissionDenied`、`InvalidRepository`、`DiskUnavailable`、`OneDrivePathDetected`。

## 验收清单

- 本地已有 repo、空目录、非空目录、OneDrive 目录、不可写目录都能显示不同状态。
- 选择 OneDrive 后必须经过 OneDrive 提示页。
- 非空目录在本页不会被写入。
- 最近资料库不可访问时不会自动移除。
- 键盘 Tab 顺序为路径、Browse、最近列表、Cancel、Continue。
- Narrator 能读出路径校验结果。

## 来源

- 来源类型：组合来源。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-34-s4-win-01-choose-repo.md`。
- 直接来源：`docs/roadmap/milestones.md` Stage 4 Windows 端。
- 组合来源：`docs/ux/first-launch.md` 的选择资料库和接管目录安全规则。
- 推导说明：Windows 选择路径后的初始化/接管确认复用 Stage 4 多端共用确认页。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [OneDrive 提示](S4-WIN-03-onedrive-notice.md)
- [空目录初始化确认](S4-X-04-repository-init-confirm.md)
- [非空目录接管确认](S4-X-05-repository-adopt-confirm.md)
- [逐页 UI 开发规格索引](../README.md)
