# S4-IOS-02 mobile-library - 移动端资料库浏览

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-IOS-02
> 页面类型：iOS main page  
> 页面文件：`S4-IOS-02-mobile-library.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：iOS 移动端。
- **建议目录**：`apps/ios/AreaMatrix/Features/Library/MobileLibraryView.swift`。
- **建议组件**：`MobileLibraryView`、`LibraryListViewModel`、`RepositoryStatusBar`、`MobileImportMenu`。
- **实现边界**：这是 iOS 主浏览页，只覆盖移动端最小浏览、搜索入口、导入入口和详情跳转，不实现桌面三栏。

## 页面背景

用户已经连接一个 AreaMatrix 资料库，需要在 iPhone 或 iPad 上浏览资料、打开文件详情、处理同步状态，并从移动端发起导入。移动端空间有限，必须围绕“浏览和快速处理”设计，而不是把 macOS sidebar、table、detail 直接压缩。

入口：连接资料库成功、从分享扩展完成导入后选择 `Open AreaMatrix`、App 冷启动恢复最近资料库。  
退出：点开文件进入 `S4-IOS-05 mobile-file-detail`；点导入进入拍照或文件导入；资料库不可访问时回到连接页。

## 页面功能

- 显示当前资料库名称和同步/访问状态。
- 浏览分类、最近文件、冲突文件三个核心集合。
- 提供移动端搜索入口，但 Stage 4 只要求复用已有搜索能力，不新增语义搜索范围。
- 支持文件列表的基础排序：最近更新、名称、大小。
- 支持下拉刷新，只读取最新 Core 状态和导入队列；不触发高风险全库 re-scan。
- 提供拍照导入、Files 导入和分享导入说明入口，其中 Files 导入进入 `S4-IOS-07 files-import`。
- `Paste from Clipboard` 是可隐藏入口，不属于 Stage 4 必验收；若展示，必须复用 [S4-IOS-07 files-import](S4-IOS-07-files-import.md) 的确认、安全默认和错误恢复规则。
- 显示 iCloud 占位符、冲突、缺失文件等状态，不静默吞掉。

## 布局与内容

使用 iOS `NavigationStack` 加底部 tab 或顶部 segmented control。推荐 iPhone 使用底部 tab，iPad 可以使用 split view，但仍以移动端交互为主。

导航栏：
- 标题：当前 repo 名称，例如 `AreaMatrix`
- 左侧：资料库状态入口，状态异常时显示文字徽标 `Needs attention`
- 右侧：`+` 导入菜单和搜索按钮

首页摘要区：
- 当前路径简写：`iCloud Drive / AreaMatrix`
- 状态行：`Synced just now`、`Checking changes...`、`3 items need review`
- 黄色提示只用于需要用户处理的同步或权限问题。

内容分区：
- `Recent`：最近修改文件，显示文件名、分类路径、修改时间、大小。
- `Categories`：按一级分类展示数量，例如 `Documents 24`。
- `Needs Review`：冲突、缺失、占位符下载失败等项目，只有存在问题时显示。
- `Imports`：导入队列状态，只有有进行中任务时显示。

列表行：
- 左侧文件类型图标。
- 主文本：文件名。
- 副文本：分类路径或来源。
- 右侧：状态徽标，例如 `iCloud`、`Conflict`、`Missing`。

导入菜单：
- `Take Photo`
- `Import from Files`
- `Paste from Clipboard`，可隐藏；只有能生成可预览导入项并进入确认流程时才展示。

## 状态与规则

- 空态：资料库为空时显示导入引导，不显示桌面式空表格。
- 加载态：显示骨架列表和 `Loading repository...`，不要让用户误以为资料库为空。
- 错误态：repo 不可访问、权限失效、DB locked 或状态读取失败时，保留最后一次缓存数据并显示可恢复 banner。
- iCloud 正在下载：对应行显示 `Downloading from iCloud...`，文件操作按钮禁用。
- 缺失文件：行保留，显示 `Missing`，进入详情时给恢复动作。
- DB locked：顶部显示非阻塞 banner，列表可保留最后一次缓存数据。
- 冲突文件：必须出现在 `Needs Review`，不能只隐藏在原分类中。
- 网络不可用：只影响云同步和占位符下载，不影响已下载文件浏览。
- `Paste from Clipboard` 隐藏时不显示占位或禁用按钮；展示时点击后必须进入与 [S4-IOS-07 files-import](S4-IOS-07-files-import.md) 等价的导入确认，不得直接写入 repo。

## 交互

1. 进入页面先读取 repo summary，再并行加载 recent、categories、needs review。
2. 下拉刷新触发只读状态刷新；刷新期间顶部状态显示 `Checking changes...`，不启动 `Run rescan now`。
3. 点击文件行进入移动端详情页。
4. 长按文件行打开 context menu：`Open`、`Share`、`Reveal in Files`、`Add Note`，具体可用性按平台能力决定。
5. 点击 `+` 展开导入菜单；拍照进入 `S4-IOS-03`，Files 导入进入 `S4-IOS-07`。
6. 如果展示 `Paste from Clipboard`，点击后先读取剪贴板生成临时导入项，再进入 [S4-IOS-07 files-import](S4-IOS-07-files-import.md) 的确认语义；读取失败只显示错误，不写入 repo。
7. 点击冲突 banner 进入 `S4-X-03 sync-conflict-entry`；缺失文件进入 `S4-X-06 missing-file-recovery`；iCloud 权限问题进入 `S4-IOS-06 icloud-permission`。

## 数据与依赖

- Core list/tree/recent API。
- iOS security scoped bookmark 恢复。
- iCloud placeholder 与下载状态检测。
- 导入队列状态。
- 文件打开与分享依赖系统 `QuickLook`、`ShareLink` 或平台封装。
- 可选 clipboard import adapter；不可用时隐藏 `Paste from Clipboard`。

## 验收清单

- iPhone 宽度下不出现拥挤的三栏布局。
- 空资料库、正常资料库、加载中、错误、iCloud 下载、冲突六类状态都能预览。
- 文件行能跳转到详情，导入菜单能进入拍照导入。
- 同步问题能从首页直接发现。
- VoiceOver 能读出文件名、分类路径和状态徽标。
- 页面不新增 Stage 4 以外的团队协作或账号系统。
- `Paste from Clipboard` 隐藏时不影响 Stage 4 验收；展示时必须进入确认流程且不得直接导入。

## 来源

- 来源类型：组合来源。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-03-mobile-library-query.md`。
- 直接来源：`docs/roadmap/milestones.md` Stage 4 iOS 端。
- 组合来源：Stage 1 主窗口、Detail、错误恢复页面规格。
- 推导说明：移动端资料库首页依据现有桌面信息架构推导，但明确不照搬 macOS 三栏；下拉刷新限定为只读状态刷新。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [拍照导入](S4-IOS-03-camera-import.md)
- [iOS Files 导入确认](S4-IOS-07-files-import.md)
- [冲突入口](S4-X-03-sync-conflict-entry.md)
- [缺失文件恢复](S4-X-06-missing-file-recovery.md)
- [逐页 UI 开发规格索引](../README.md)
