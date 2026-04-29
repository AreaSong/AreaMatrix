# S4-X-08 repository-settings - 多端资料库设置

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-X-08
> 页面类型：多端共用 settings page  
> 页面文件：`S4-X-08-repository-settings.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：iOS、Windows、Linux 共用 UX 规则，各平台原生实现。
- **建议目录**：`apps/*/AreaMatrix/Features/Settings/RepositorySettingsView.*`。
- **建议组件**：`RepositorySettingsView`、`RepositoryLocationSection`、`PlatformCapabilitySection`。
- **实现边界**：这是当前资料库设置入口，不实现账号、团队协作、插件市场或云盘 SDK 配置。

## 页面背景

用户需要查看当前 repo 位置、平台能力、连接状态、诊断导出和重新连接入口。`S4-X-02 platform-differences` 中的 `Open repository settings` 明确进入本页。

入口：平台能力差异说明页、主窗口设置、权限错误页、资料库状态栏。  
退出：返回上一设置页；重新连接进入平台选择资料库页；打开能力说明进入 `S4-X-02`。

## 页面功能

- 展示当前 repo 名称、路径、平台位置类型和 Core version。
- 展示访问状态、watcher 状态、云盘/本地目录状态。
- 提供 `Reconnect Repository`、`Choose Another Folder`、`Export diagnostics`。
- 提供 `Platform capabilities` 入口。
- 明确危险操作不在本页直接执行。

## 布局与内容

标题：`Repository Settings`

资料库区：
- `Name`
- `Location`
- `Type: iCloud Drive / OneDrive / Local folder / Network mount / Unknown`
- `Last opened`
- `Core version`

状态区：
- `Access: Available / Expired / Permission denied / Unknown`
- `Watcher: Running / Paused / Not available`
- `Cloud: iCloud / OneDrive / Third-party sync / None / Unknown`

操作区：
- 主按钮：`Reconnect Repository`
- 次按钮：`Choose Another Folder`
- 次按钮：`Platform capabilities`
- 辅助按钮：`Export diagnostics`

危险操作区：
- 不显示删除 repo 或删除用户文件操作。
- 若未来加入 `Forget Repository`，必须另开危险确认规格。

## 状态与规则

- 默认状态：显示当前 repo snapshot，所有安全操作可用。
- 加载态：读取状态时显示 `Loading repository settings...`。
- 空态：未连接 repo 时显示 `No repository connected.`，主按钮为 `Connect Repository`。
- 错误态：状态读取失败显示 `Could not load repository status` 和 `Try again`。
- 禁用条件：没有 repo 时禁用 diagnostics；权限失效时禁用 open/reveal 类操作。
- `Choose Another Folder` 不删除当前 repo 记录，直到新 repo 成功连接。

## 交互

1. 打开页面读取 repo snapshot 和 platform capability snapshot。
2. 点击 `Reconnect Repository` 进入当前平台资料库选择页。
3. 点击 `Choose Another Folder` 进入当前平台资料库选择页并保留返回路径。
4. 点击 `Platform capabilities` 进入 `S4-X-02 platform-differences`。
5. 点击 `Export diagnostics` 生成不包含用户文件内容的诊断包。
6. 状态刷新失败不清空已有设置，只显示错误 banner。

## 数据与依赖

- Repository settings store。
- Platform capability provider。
- Core version/build info。
- Watcher status。
- Diagnostic export。
- 最近 repo / security scoped bookmark / ACL / POSIX 权限状态。

## 验收清单

- `S4-X-02` 的 `Open repository settings` 有明确落点。
- 未连接、正常、权限失效、状态未知都有不同 UI。
- 本页不提供删除用户文件、云盘 SDK 配置、账号登录或插件入口。
- 诊断导出说明不包含用户文件内容。
- 重新连接失败不会丢失当前 repo 记录。
- 屏幕阅读器能读出设置字段和值。

## 来源

- 来源类型：组合来源。
- 直接来源：`docs/ux/settings-panel.md` 的资料库设置语义。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-20-repository-settings-cross-platform.md`。
- 组合来源：`S4-X-02 platform-differences`、Stage 4 多端状态页、`AGENTS.md` 安全边界。
- 推导说明：为承接多端能力页和错误恢复页的设置入口新增最小资料库设置规格。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [平台能力差异说明](S4-X-02-platform-differences.md)
- [iOS 首次连接资料库](S4-IOS-01-connect-repo.md)
- [Windows 资料库选择](S4-WIN-01-choose-repo.md)
- [Linux 资料库选择](S4-LNX-01-choose-repo.md)
- [逐页 UI 开发规格索引](../README.md)
