# S4-LNX-01 choose-repo - Linux 资料库选择

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-LNX-01
> 页面类型：Linux onboarding page  
> 页面文件：`S4-LNX-01-choose-repo.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：Linux 桌面端。
- **建议目录**：`apps/linux/AreaMatrix/Features/Onboarding/ChooseRepositoryView.*`。
- **建议组件**：`LinuxChooseRepositoryView`、`GtkFolderPickerAdapter`、`LinuxPathValidator`。
- **实现边界**：这是 Linux 资料库选择页，默认本地目录，不承诺云盘同步集成。

## 页面背景

Linux 端目标是完成最小闭环：选择本地 repo、浏览、导入、文件监听。Linux 发行版和桌面环境差异较大，本页需要用保守、可解释的本地文件夹模型，不把 iCloud 或 OneDrive 作为默认路径。

入口：Linux app 首次启动、切换资料库、最近资料库不可访问。  
退出：已有 repo 进入 `S4-LNX-02 main-window`；空目录进入 `S4-X-04 repository-init-confirm`；非空目录进入 `S4-X-05 repository-adopt-confirm`；高风险路径进入 `S4-LNX-03 local-folder-notice`；取消关闭或停留未连接。

## 页面功能

- 选择已有 AreaMatrix repo。
- 选择空目录准备初始化。
- 识别空目录和非空目录，分别进入 `S4-X-04` 初始化确认或 `S4-X-05` 接管确认。
- 检测可读、可写、是否位于本地文件系统、是否疑似网络挂载。
- 显示最近资料库列表。
- 对 Linux 大小写敏感和权限差异给出必要提示。

## 布局与内容

使用 GTK、Qt 或其他 Linux 原生工具包时，保持简洁表单布局。

标题：`Choose AreaMatrix Repository`

说明：
`Select a local folder for your AreaMatrix repository. Network drives and third-party sync folders may behave differently across Linux distributions.`

路径选择：
- 输入框：`Repository folder`
- 按钮：`Browse...`
- 辅助：`Use default: ~/AreaMatrix`

检测结果：
- `Existing AreaMatrix repository`
- `Empty folder`
- `Non-empty folder`
- `Permission denied`
- `Network or removable path detected`

最近资料库：
- 名称、路径、最后打开时间、状态。

底部按钮：
- `Cancel`
- `Continue`

## 状态与规则

- 默认建议 `~/AreaMatrix`，但不自动创建。
- 默认状态：未选择路径时仅显示默认建议和最近资料库；`Continue` 禁用，直到用户选择或输入目录并完成校验。
- 加载态：路径校验中显示 `Checking folder...`，`Continue` 禁用。
- 空态：没有最近资料库时隐藏最近列表，不显示空白区域。
- 错误态：路径不存在、不是目录、权限不足、repo 版本不兼容或检测失败时，在输入框下方显示具体原因。
- 禁用条件：未选择路径、校验中、路径不是目录、路径不可读、路径不可写且需要初始化/接管、高风险路径确认未完成、repo 版本不兼容且无升级路径时，`Continue` 禁用。
- 非本地路径或网络挂载：显示黄色提示，允许继续但需确认。
- 权限不足：禁止继续，显示建议命令不应直接复制危险 chmod；只提示“选择有写权限的位置”。
- 目录不存在：提供 `Create folder after confirmation`，不在本页创建。
- 空目录：进入 `S4-X-04 repository-init-confirm`，不在本页创建目录。
- 非空目录：进入 `S4-X-05 repository-adopt-confirm`，不写入。
- 大小写敏感：不阻止，但在冲突策略中应按 Core 规则处理。

## 交互

1. 点击 `Browse...` 打开系统 folder picker。
2. 选择路径后执行只读校验。
3. 点击默认路径仅填入输入框并校验，不立即创建目录。
4. 点击最近资料库行填入路径并校验。
5. 点击 `Continue` 按校验结果进入主窗口、`S4-X-04`、`S4-X-05` 或 `S4-LNX-03`。
6. 校验失败时错误文本与输入框关联，便于屏幕阅读器读取。

## 数据与依赖

- GTK/Qt folder picker 或 xdg-desktop-portal。
- Rust core repo detection。
- POSIX permissions 检测。
- 本地/网络/可移动路径尽力识别。
- 最近 repo 存储。

## 验收清单

- `~/AreaMatrix` 默认建议不会被自动创建。
- 本地 repo、空目录、非空目录、权限不足、网络挂载都有不同提示。
- 非空目录不会在本页写入 `.areamatrix/`。
- 最近资料库不可访问时有状态说明。
- 键盘和屏幕阅读器可完成路径选择和继续操作。

## 来源

- 来源类型：组合来源。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-10-linux-repo-connect.md`。
- 直接来源：`docs/roadmap/milestones.md` Stage 4 Linux 端。
- 组合来源：`docs/ux/first-launch.md` 的资料库选择安全规则。
- 推导说明：Linux 本地目录选择后的初始化/接管确认复用 Stage 4 多端共用确认页。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [本地目录提示](S4-LNX-03-local-folder-notice.md)
- [空目录初始化确认](S4-X-04-repository-init-confirm.md)
- [非空目录接管确认](S4-X-05-repository-adopt-confirm.md)
- [逐页 UI 开发规格索引](../README.md)
