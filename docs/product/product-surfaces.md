# AreaMatrix 产品界面地图

> 本文记录 macOS 应用的稳定产品界面、入口、职责、数据来源和风险边界，不使用历史页面编号。
>
> 阅读时长：约 10 分钟。

## 界面模型

AreaMatrix 只有一个顶层 `WindowGroup`。产品任务通过窗口内路由和临时界面完成：

- **Window route**：占据主窗口的完整产品状态。
- **Primary region**：主工作区中的稳定区域。
- **Sheet / Panel / Popover**：聚焦任务或辅助信息。
- **Confirmation dialog**：高影响操作确认。
- **Status view**：加载、空态、错误、阻断和恢复状态。

## 顶层窗口路由

| 界面 | 用途 | 主要功能 | 数据来源 | 风险边界 |
|---|---|---|---|---|
| 欢迎与资料库选择 | 建立第一个可用资料库入口 | 欢迎、选择路径、校验路径、区分创建与接管 | 平台目录选择、Core 路径校验 | 不得在确认前修改所选目录 |
| 资料库初始化 | 创建元数据或接管已有目录 | 初始化步骤、扫描进度、失败重试、完成打开 | Core repository API、扫描会话 | 只创建 AreaMatrix 状态，不改变已有文件 |
| 资料库加载 | 打开资料库并构建主视图状态 | 加载配置、树、文件列表和恢复状态 | CoreBridge repository opening | 错误必须转入可恢复状态 |
| 资料库工作区 | 浏览和整理资料 | 目录树、文件列表、详情、搜索、导入和批量操作 | Core 查询、平台服务和 UI state | 文件写入进入对应专项确认 |
| 资料库错误与修复 | 恢复不可用资料库 | 重试、诊断、元数据修复和重新选择 | Core recovery/repair、repository snapshot 或 About 脱敏文本诊断 | 只修复 `.areamatrix`，不得删除用户文件 |

## 主工作区区域

| 区域 | 主要功能 |
|---|---|
| Toolbar | 导入、搜索、命令和资料库级操作入口 |
| Sidebar | 目录树、智能列表、标签和导航上下文 |
| File list | 表格、排序、选择、多选和状态提示 |
| Detail | 元数据、AI 摘要、改动日志、笔记、标签和文件操作 |
| Drop overlay | Finder 拖放目标和导入入口提示 |
| Feedback regions | Undo/Redo、同步、错误和操作结果反馈 |

## 导入界面

- 单文件导入预览。
- 批量文件导入预览。
- 文件夹扫描与预览。
- 移动、复制、仅索引模式选择。
- 分类、命名和目标路径确认。
- 重复文件和同名冲突审阅。
- iCloud 占位符状态。
- 进度、取消、恢复和结果摘要。
- 进度停止、诊断收集和结果导出的隐私确认。
- Replace 与高影响冲突决策二次确认。

导入界面会产生真实文件和数据库副作用。预览、确认、执行、结果和恢复必须保持分离。

## 搜索与组织界面

- 常规搜索结果。
- 搜索筛选 Popover。
- 保存搜索 Sheet；已有 Smart List 的重命名、复制、改查询和删除由管理 Sheet 承担。
- Smart List 管理 Sheet。
- 搜索索引状态与重试 Sheet。
- 查询语法帮助与语义索引构建、取消确认。
- 语义搜索结果、索引构建和回退状态。
- 标签编辑 Popover 和标签筛选。
- 批量加标签、改分类、重命名和删除 Sheet。
- 分类纠正、规则保存和影响预览 Sheet。
- `Cmd-K` 命令面板 Sheet。
- Undo 历史 Sheet 和 Redo 反馈。

## AI 与隐私界面

- AI 设置面。
- 本地模型状态。
- 远程 Provider 配置。
- 凭据生命周期提示和连通性探测结果。
- AI 分类建议确认。
- 摘要编辑与清除。
- 单文件和批量标签建议。
- AI 调用日志浏览器（筛选、删除选中、清空）和单条调用详情。
- 隐私规则列表、编辑、测试、推荐模板和只读引用。
- 本地或远程能力不可用时的回退状态。

界面必须区分“已配置”“允许发送”“探测成功”和“实际调用成功”，不得用单一启用状态替代完整授权链。

## 设置界面

- 通用设置。
- 资料库路径、配置、健康和平台能力。
- 分类器规则与预览。
- 集成和 iCloud 状态。
- AI 配置与隐私。
- 独立的诊断与日志页。
- 高级恢复、repository diagnostics 与危险选项。
- 平台差异与关于信息。

设置由主窗口路由承载，不是独立 SwiftUI `Settings` Scene。

## 日志与诊断界面

- `diagnostics` 是设置窗口的独立一级 Tab，提供标准、诊断和开发者模式，限时租约、保留期限、磁盘预算、健康状态、
  incident 标记、本地日志删除和 Trace Console 入口。
- Advanced 与 About 页只提供跳转入口；Advanced 继续负责 repository metadata snapshot 和恢复工具，About 继续负责
  App/Core/schema 摘要与脱敏文本诊断。
- 用户投影以本地化活动和问题状态解释事件；开发者投影提供 timeline、tree、graph、terminal、raw data、
  expected-vs-actual 和 trace comparison，并使用同一组稳定事件身份。
- 异常退出后若能恢复中断 session，主窗口显示只读恢复提示并关联恢复 incident；提示不会自动执行文件恢复。
- `.amdiagnostic` 保存前展示事件范围、隐私选择、预计大小，以及可选 repository metadata snapshot 附件；已保存包作为不可信输入离线打开，
  先校验 schema、类型、大小、checksum、符号链接和硬链接边界。
- About 脱敏文本诊断和 repository metadata snapshot 仍是独立产物，不与运行事件或诊断包混为一体。

日志与诊断默认保存在 Application Support，不写入资料库根目录、不自动上传，也不把 observation 当成
用户文件恢复或业务审计的真相源。删除入口只删除 manifest 明确拥有的日志或 incident；`read_only` 历史 incident 和
未知文件不可删除，也不触碰用户资料库内容。

## 同步、冲突与恢复界面

- 主列表 Needs Review 入口面板和详情冲突横幅。
- iCloud 冲突最小处理 Sheet。
- iCloud 冲突列表。
- 同步冲突审阅和决策。
- Keep both、替换和其他 resolution 的确认。
- 启动恢复提示与重试。
- 资料库错误视图。
- DB 元数据修复确认与结果。
- 诊断包隐私预览与保存确认。

冲突应用、修复、重新索引和占位符下载属于高风险行为，必须显示影响范围并保留取消路径。

## 通用状态

每个主要界面按需要覆盖：

- Loading：保持布局稳定并说明正在读取的资源。
- Empty：说明为何为空，并提供与场景匹配的入口。
- Error：显示用户可理解的原因、恢复动作和诊断入口。
- Blocked：说明缺少的配置、权限、模型或确认条件。
- Stale：说明数据可能过期并提供刷新。
- Unavailable：能力不存在或环境不支持时，不显示可执行假入口。

## Related

- [产品能力](capabilities.md)
- [用户工作流](workflows.md)
- [UX 文档](../ux/README.md)
- [错误恢复矩阵](../development/error-recovery-matrix.md)
- [macOS 前端架构](../architecture/macos-frontend-architecture.md)
