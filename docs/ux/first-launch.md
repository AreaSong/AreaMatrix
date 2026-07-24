# 首次启动与资料库打开

> 记录 AreaMatrix macOS 从 Welcome、路径校验、初始化或接管到主界面的真实路由与恢复边界。
>
> 阅读时长：约 8 分钟。

---

## 启动分流

应用启动时先读取已配置资料库路径：

- 没有配置路径：进入 Welcome。
- 有配置路径：进入 `mainLoading`，执行 startup recovery、扫描 session/树加载，并尝试打开已配置资料库。
- 打开失败：根据结构化错误进入资料库错误、恢复或重新选择路径，而不是无条件回到首次设置。

启动恢复只处理 AreaMatrix-owned metadata 和已定义的恢复状态，不删除用户原文件。

## Welcome

Welcome 提供两个主要动作：

- `选择本地文件夹`：快捷键 `Command-O`，进入 Choose Path；该页的浏览按钮才打开只允许选择目录的
  `NSOpenPanel`。
- `了解 AreaMatrix 如何工作`：打开
  `https://github.com/AreaSong/AreaMatrix/blob/main/docs/user-guide/getting-started.md`。

右上角界面语言控件单击后按“跟随系统 → 简体中文 → English → 跟随系统”循环，不打开 menu。每次点击
立即保存设备级 `AppLanguage` 并广播到所有窗口；它不修改资料库内容语言。图标、tooltip、VoiceOver label
和 value 必须明确表达当前模式：跟随系统显示带自动标识的地球，简体中文显示“中”，English 显示“EN”。
tooltip 与 VoiceOver 使用完整模式名称；跟随系统时还要说明当前解析为简体中文或 English。Welcome 与
General 使用同一个 app-level store，任一入口的变化会立即在
另一入口反映，且不重建 onboarding route 或丢失已输入的路径。

帮助链接必须通过 HTTPS URL policy；URL 无效、非 HTTPS 或系统拒绝打开时，显示 help unavailable 错误，不回退到任意本地路径或 shell 命令。

Welcome 的动效和扫描文案只用于过渡到 Choose Path。用户在 Browse 中选择目录前不会写入用户资料。

## 路由

主要路由如下：

```text
welcome
  -> choosePath
  -> validatePath
  -> confirmRepositoryInitialization
  -> initializing
  -> initializationDone
  -> mainLoading
  -> mainEmpty | mainList
```

已初始化资料库可以从校验页直接进入 `mainLoading`。数据库或 metadata 不可用时进入明确的 repair/error 路由。

## 选择路径

Choose Path 是 Welcome 与 Core 路径校验之间的独立步骤：

- 路径框可编辑，默认推荐 `~/AreaMatrix/`。
- 用户可以拖入 folder URL，也可以使用浏览按钮打开目录选择器。
- 路径偏离推荐默认值时可以执行“恢复推荐默认路径”。
- 本地预检只拒绝空字符串、无法解析的路径和 `.areamatrix` 内部路径；继续后再由 Core 返回完整环境校验。

选择或输入路径不会初始化资料库，也不会写入用户文件。

## 路径校验

路径校验由 Core 返回结构化状态，UI 不通过目录名称猜测：

- checklist 显示路径存在且为目录、可读、可写、可用空间、iCloud、外置卷、是否已初始化和是否非空。
- 空目录：可以创建空资料库；非空但未初始化目录：可以接管已有目录；已初始化资料库：可以直接打开。
- 路径缺失、不是目录、不可读、不可写、空间不足或环境检查字段缺失时不能继续。
- 存在未完成扫描时进入明确的修复流程，不能按普通初始化继续。
- iCloud 和外置卷以 warning 展示；iCloud 路径还要求用户勾选风险确认后才能继续。

路径状态在用户确认前会重新校验。若状态已经变化，返回校验页，不能继续使用旧预览。

## 创建空资料库

创建空资料库只在用户选择的目录内建立 AreaMatrix-owned 结构和默认配置。默认概览写入 `.areamatrix/generated/`。

第一次生成概览前必须确认资料库内容语言。默认选择是“跟随界面”并持久化为 policy，而不是把当时的
concrete 界面语言写死；用户显式选择简体中文或 English 后，之后切换 Welcome 界面不改变该选择。

创建流程不得删除选择目录中的既有内容。如果目录在确认后变为非空，必须重新校验而不是继续按空目录处理。

## 接管已有目录

接管已有目录的核心不变量：

- 不移动、不重命名、不删除、不覆盖已有用户文件。
- 不覆盖已有 `README.md`。
- 扫描只建立 metadata、分类和可恢复 scan session。
- 自动概览默认写入 `.areamatrix/generated/`。
- iCloud placeholder 不被隐式下载。

接管确认页应明确显示目录非空、将创建的 AreaMatrix metadata，以及已有文件保持原位。

## 初始化与进度

进入 `initializing` 后，应用：

1. 再次校验路径与所选模式一致。
2. 执行 startup residue recovery。
3. 记录 watcher 起始 event ID。
4. 调用 Core 创建或接管资料库。
5. 成功后写入 watcher cursor 和已配置路径。
6. 进入完成页，再打开资料库。

接管时 UI 可以读取 scan session 显示已扫描、已插入、已更新、冲突、不可读和跳过数量。进度 polling
失败只显示 warning；初始化是否成功仍由 Core 初始化调用的最终结果决定，warning 不能替代成功证据。

## 取消与安全点

初始化中的退出请求需要确认。确认后应用设置 cancellation request，并等待 Core 调用返回到安全点。

到达安全点后：

- 返回 Welcome。
- 清理内存中的进度和诊断展示状态。
- 提示下次选择同一资料库时继续或进入恢复。

取消不承诺立即删除 `.areamatrix/`，也不承诺把目录恢复成从未初始化过。可恢复 metadata、scan session 或 staging 状态由 startup recovery 和对应 Core 合同处理。任何清理都只能作用于已确认属于 AreaMatrix 的内部状态。

## 中断恢复

应用重新启动或重新选择同一路径时：

- 先运行 `recover_on_startup`。
- 读取最近 scan session。
- 可继续的接管扫描通过 `resume_scan_session` 恢复。
- metadata 需要修复时进入 DB repair 确认页。
- 打开动作取消时，只取消当前打开流程，不修改资料库配置和用户文件。

历史 session 不完整、DB 不可读或路径不可用时不能自动宣称恢复成功。

## 完成与打开

`initializationDone` 显示 repoPath、初始化模式、scan session 和 recovery 摘要。用户继续后进入 `mainLoading`，完成 startup recovery 和树加载，再进入空资料库或文件列表。

若完成后打开失败，保留初始化结果和错误映射，允许重试或在 Finder 中检查资料库。

## 错误与诊断

- 错误来自结构化 `CoreError` 映射。
- 权限、路径缺失、DB、配置和 IO 错误分别给出恢复建议。
- 诊断导出前确认隐私边界。
- 诊断不包含用户文件正文，不自动上传。
- Finder 和外部帮助打开失败必须在当前界面反馈。

## 文件安全不变量

- 选择目录前不写文件。
- 接管不改变已有文件布局。
- 初始化取消只在 Core 安全点结束。
- 恢复和 DB repair 只处理 AreaMatrix-owned metadata，除非另有明确确认。
- 删除 `.areamatrix/` 不得删除用户文件本身。
- 任何页面都不得承诺未经测试证明的自动清理结果。

## 验证重点

- 无配置路径进入 Welcome；有配置路径先尝试 recovery/open。
- `Command-O` 进入 Choose Path；浏览按钮打开目录选择器。
- 可编辑路径、folder URL 拖入、推荐默认路径与恢复默认动作可用。
- 缺失环境检查字段会阻止继续；iCloud 路径必须明确确认风险。
- Learn More 使用固定 HTTPS 用户指南 URL。
- 空目录、非空目录、已初始化目录和错误路径路由正确。
- 初始化取消在安全点返回，且不修改用户文件。
- 接管后已有 `README.md` 和其他文件保持原样。
- 中断 session 能继续或进入明确恢复路径。

## Related

- [settings-panel.md](settings-panel.md)
- [ui-states.md](ui-states.md)
- [../user-guide/getting-started.md](../user-guide/getting-started.md)
- [../architecture/adopt-existing-folders.md](../architecture/adopt-existing-folders.md)
- [../development/recovery.md](../development/recovery.md)
