# S4-X-04 repository-init-confirm - 空目录初始化确认

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-X-04
> 页面类型：多端共用 dialog / sheet  
> 页面文件：`S4-X-04-repository-init-confirm.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：iOS、Windows、Linux 共用 UX 规则，各平台原生实现。
- **建议目录**：`apps/*/AreaMatrix/Features/Onboarding/RepositoryInitConfirm.*`。
- **建议组件**：`RepositoryInitConfirmView`、`RepositoryPathSummary`、`InitSafetyChecklist`。
- **实现边界**：这是空目录初始化前的确认页，只确认创建 AreaMatrix metadata，不执行接管非空目录。

## 页面背景

用户选择了空目录或不存在但可创建的目录。初始化会写入 `.areamatrix/` 元数据，因此必须在写入前展示路径、影响和取消路径。

入口：`S4-IOS-01 connect-repo`、`S4-WIN-01 choose-repo`、`S4-LNX-01 choose-repo` 检测到空目录或可创建目录。  
退出：确认后进入平台主页面；取消返回原选择页；初始化失败进入平台错误恢复或停留本页。

## 页面功能

- 显示将初始化的完整路径和路径类型。
- 说明会创建 `.areamatrix/`，不会移动、删除或覆盖用户文件。
- 显示可写性、剩余空间、平台能力提示。
- 提供确认初始化、返回选择、取消三类动作。
- 初始化失败时给出重试和选择其他目录。

## 布局与内容

标题：`Create AreaMatrix Repository`

路径卡：
- `Folder: ...`
- `Type: iCloud Drive / OneDrive / Local folder / Network mount / Unknown`
- `Writable: Yes/No`

说明区：
- `AreaMatrix will create a .areamatrix folder here.`
- `No existing files will be moved, deleted, renamed, or overwritten.`

检查项：
- `Folder is empty`
- `Write permission available`
- `Enough disk space`
- 云盘/网络路径时显示平台风险说明。

底部按钮：
- `Cancel`
- `Choose Another Folder`
- 主按钮：`Create Repository`

## 状态与规则

- 默认状态：所有检查通过时 `Create Repository` 启用。
- 加载态：检查路径时显示 `Checking folder...`，主按钮禁用。
- 空态：路径为空时显示 `Choose a folder first.`。
- 错误态：不可写、路径丢失、磁盘不可用时显示具体原因。
- 禁用条件：路径不可写、不是目录、检测结果未知且风险不可判断时禁用主按钮。
- 成功后必须同时可被平台 UI 和 Core repo detection 识别。

## 交互

1. 页面打开时重新做只读路径校验，不依赖上一页缓存。
2. 点击 `Create Repository` 执行初始化。
3. 初始化中显示 `Creating metadata...`，禁止重复点击。
4. 成功后进入对应平台主页面：iOS `S4-IOS-02`、Windows `S4-WIN-02`、Linux `S4-LNX-02`。
5. 失败时保留本页，显示 `Try Again` 和 `Choose Another Folder`。
6. 取消时不写入任何文件。

## 数据与依赖

- Core init empty repo API。
- 平台路径可读/可写检测。
- 云盘或挂载类型检测。
- 错误映射：`PermissionDenied`、`DiskUnavailable`、`InvalidRepository`、`ICloudUnavailable`。

## 验收清单

- 写入前能看到完整路径和 `.areamatrix/` 影响说明。
- 不可写路径不能确认。
- 云盘或网络路径有风险提示但不夸大能力。
- 初始化失败不会留下半成品；若存在 recovery 需求，提示下次启动恢复。
- Cancel / Choose Another Folder 均不写入。
- VoiceOver/Narrator 能读出路径、检查项和主按钮禁用原因。

## 来源

- 来源类型：组合来源。
- 直接来源：`docs/ux/first-launch.md` 的初始化确认语义。
- 组合来源：`docs/architecture/adopt-existing-folders.md`、`docs/architecture/transactional-import.md`、Stage 4 选择资料库页面。
- 推导说明：多端初始化确认从 Stage 1 macOS 流程迁移为平台共用 dialog。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [iOS 首次连接资料库](S4-IOS-01-connect-repo.md)
- [Windows 资料库选择](S4-WIN-01-choose-repo.md)
- [Linux 资料库选择](S4-LNX-01-choose-repo.md)
- [逐页 UI 开发规格索引](../README.md)
