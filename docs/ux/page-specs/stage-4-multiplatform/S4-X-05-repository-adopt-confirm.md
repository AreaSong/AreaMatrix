# S4-X-05 repository-adopt-confirm - 非空目录接管确认

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-X-05
> 页面类型：多端共用 dialog / sheet  
> 页面文件：`S4-X-05-repository-adopt-confirm.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：iOS、Windows、Linux 共用 UX 规则，各平台原生实现。
- **建议目录**：`apps/*/AreaMatrix/Features/Onboarding/RepositoryAdoptConfirm.*`。
- **建议组件**：`RepositoryAdoptConfirmView`、`ExistingFolderSummary`、`AdoptSafetyChecklist`。
- **实现边界**：这是非空普通目录接管前确认页，不移动、不重命名、不删除、不覆盖任何已有用户文件。

## 页面背景

用户选择了已有文件的普通目录。接管会创建 `.areamatrix/` 并扫描现有文件，但不得修改用户原文件。该页是高风险边界，必须把影响和回滚思路说清楚。

入口：`S4-IOS-01`、`S4-WIN-01`、`S4-LNX-01` 检测到非空普通目录。  
退出：确认后进入对应平台主页面；取消返回选择页；扫描或写入 metadata 失败停留本页并提示恢复。

## 页面功能

- 显示目录路径、文件数量估算、是否已有 `.areamatrix/`。
- 明确承诺不移动、不删除、不重命名、不覆盖已有用户文件。
- 说明只会创建 `.areamatrix/` 并建立索引。
- 显示云盘、网络挂载、权限风险。
- 要求用户勾选确认项后才能继续。
- 失败时提供重试、选择其他目录、导出诊断。

## 布局与内容

标题：`Use Existing Folder`

路径摘要：
- `Folder: ...`
- `Estimated items: ...`
- `Writable: Yes/No`
- `Location type: iCloud Drive / OneDrive / Local folder / Network mount / Unknown`

安全说明：
- `AreaMatrix will not move, delete, rename, or overwrite existing files.`
- `It will create a .areamatrix folder for metadata and scan this folder.`

确认项：
- `I understand AreaMatrix will add metadata to this folder.`
- 高风险路径追加：`I understand this location may sync or report changes differently.`

底部按钮：
- `Cancel`
- `Choose Another Folder`
- 主按钮：`Use This Folder`

## 状态与规则

- 默认状态：确认项未勾选，`Use This Folder` 禁用。
- 加载态：估算文件和权限时显示 `Checking folder...`。
- 空态：如果复检发现目录为空，提示改走 `S4-X-04 repository-init-confirm`。
- 错误态：不可写、路径丢失、权限不足时不允许继续。
- 禁用条件：确认项未勾选、路径不可写、检测到已有损坏 metadata 且无法恢复。
- 删除 `.areamatrix/` 不得导致用户文件丢失；说明作为回滚提示展示。

## 交互

1. 页面打开时重新检查目录状态和 `.areamatrix/` 是否存在。
2. 用户展开 `What will be added?` 可查看 `.areamatrix/` 说明。
3. 勾选确认项后主按钮启用。
4. 点击 `Use This Folder` 后创建 metadata 并扫描；过程显示 `Preparing repository...`。
5. 成功后进入对应平台主页面并显示首次扫描状态。
6. 失败后不清理用户文件；若 metadata 半成品需要恢复，提示下次启动 recovery。

## 数据与依赖

- Core adopt existing folder API。
- Core scan/build tree API。
- 平台权限和路径类型检测。
- 诊断导出能力。
- 错误映射：`PermissionDenied`、`InvalidRepository`、`DatabaseLocked`、`DiskUnavailable`。

## 验收清单

- 非空目录接管前必须显示高风险确认。
- 页面明确承诺不移动、不删除、不重命名、不覆盖用户文件。
- 未勾选确认项不能继续。
- 不可写目录不能接管。
- 失败后不会留下最终目录半成品，也不会修改用户原文件。
- 屏幕阅读器能读出确认项、路径和风险说明。

## 来源

- 来源类型：组合来源。
- 直接来源：`docs/ux/first-launch.md`、`docs/architecture/adopt-existing-folders.md`。
- 组合来源：`AGENTS.md` 的高风险边界与关键不变量、Stage 4 平台选择页。
- 推导说明：非空目录接管是多端共用高风险动作，必须从选择页拆出为独立确认规格。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [iOS 首次连接资料库](S4-IOS-01-connect-repo.md)
- [Windows 资料库选择](S4-WIN-01-choose-repo.md)
- [Linux 资料库选择](S4-LNX-01-choose-repo.md)
- [逐页 UI 开发规格索引](../README.md)
