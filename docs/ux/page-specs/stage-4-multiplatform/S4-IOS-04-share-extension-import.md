# S4-IOS-04 share-extension-import - 分享面板导入

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-IOS-04
> 页面类型：iOS Share Extension sheet  
> 页面文件：`S4-IOS-04-share-extension-import.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：iOS Share Extension。
- **建议目录**：`apps/ios/AreaMatrixShareExtension/ShareImportView.swift`。
- **建议组件**：`ShareImportView`、`SharedContainerImportQueue`、`ExtensionRepositoryAccess`。
- **实现边界**：这是 iOS 系统分享面板里的轻量导入界面，不承载完整资料库浏览，也不要求用户在扩展里解决复杂冲突。

## 页面背景

用户在 Safari、Files、Mail 或其他 App 中通过系统 Share Sheet 选择 AreaMatrix。扩展需要快速确认导入对象、目标资料库和目标分类，然后把文件交给主 App 或共享容器处理。

入口：iOS Share Sheet 选择 `AreaMatrix`。  
退出：保存导入任务后进入 `Save queued` 并关闭扩展，主 App 下次启动接管队列；用户点 `Open AreaMatrix` 进入 [S4-IOS-02 mobile-library](S4-IOS-02-mobile-library.md)；权限过期或没有 repo 时进入 [S4-IOS-06 icloud-permission](S4-IOS-06-icloud-permission.md) 或连接流程；用户 Cancel 返回来源 App / Share Sheet，不写入 repo。

## 页面功能

- 展示分享进来的文件或 URL 的基本信息。
- 选择目标资料库，默认使用最近连接的资料库。
- 选择目标分类或使用自动分类建议。
- 编辑导入文件名。
- 对多个分享项显示数量和总大小。
- 在扩展时间限制内尽快保存任务，不做长时间 hash 或深度扫描。
- 权限不足时说明需要打开主 App 重新连接资料库。
- 明确 `Save queued`、`Open AreaMatrix`、Cancel 和权限过期四类退出路径。

## 布局与内容

整体是系统扩展 sheet，内容必须短、可快速完成。

顶部：
- 标题：`Save to AreaMatrix`
- 右上角：`Cancel`

导入对象区：
- 单文件：显示文件图标、文件名、来源 App、大小。
- 多文件：显示 `3 items from Files`、总大小、前 3 个文件名预览。
- URL：显示网页标题或 URL，文件名默认从标题生成。

目标区：
- 资料库选择：`Repository`，默认最近 repo。
- 分类选择：`Category`，默认自动建议或 `Inbox`。
- 文件名输入：单文件可编辑，多文件显示批量命名规则，不逐项编辑。

提示区：
- 文案：`AreaMatrix will copy these items into the repository after you confirm.`
- 如果主 App 需要继续处理，显示 `Import may continue in AreaMatrix.`

底部按钮：
- `Cancel`
- `Save`
- 保存成功后可显示 `Open AreaMatrix`。

## 状态与规则

- 默认状态：分享项可读且最近 repo 权限有效时，`Save` 可用。
- 空态：没有可导入分享项时显示 `No supported items to import.`，`Save` 禁用，只保留 `Cancel`。
- 加载态：解析 `NSExtensionItem` 和复制到 app group 临时区时显示 `Reading shared item...` 或 `Saving queue item...`。
- 错误态：分享项不可读、队列写入失败、repo 权限过期或扩展即将超时时显示可读错误和 `Open AreaMatrix` / `Cancel`。
- 没有已连接资料库：显示 `Open AreaMatrix to connect a repository`，`Save` 禁用。
- 资料库权限过期：显示黄色提示，提供 `Open AreaMatrix`。
- 分享项读取中：显示 `Reading shared item...`。
- 分享项不可读取：显示该项错误，允许用户取消。
- 多文件中部分不可读取：显示 `2 of 3 items can be imported`，用户可继续导入可读取项。
- 同名冲突：扩展内不展开复杂冲突 UI，默认写入任务时标记为 `needsConflictReview`，主 App 里解决；如果 Core 能快速给出自动编号结果，可显示 `Will save as ... (2)`。
- 扩展超时风险：超过合理时间的操作转交主 App，扩展只显示排队结果。
- Save queued：显示 `Saved to AreaMatrix` 或 `Queued for AreaMatrix`，随后关闭扩展或展示 `Open AreaMatrix`。
- 权限过期：`Save` 禁用，显示 `Open AreaMatrix to reconnect this repository`，不得假装排队成功。
- Cancel：立即关闭扩展并返回来源 App，不创建导入任务，不复制源项目。

## 交互

1. 扩展启动后解析 `NSExtensionItem`，生成导入预览。
2. 如果最近 repo 权限有效，默认选中；否则显示修复入口。
3. 用户可修改分类和文件名；输入校验即时显示。
4. 点击 `Save` 后把源项目复制到 app group 临时区或创建安全书签任务。
5. 保存任务成功后显示 `Saved to AreaMatrix`，并关闭扩展或提供 `Open AreaMatrix`。
6. 点击 `Open AreaMatrix` 打开主 App；如果队列项无需更多确认，主 App 接管并完成事务式导入后进入 [S4-IOS-02 mobile-library](S4-IOS-02-mobile-library.md)。
7. 如果队列项需要用户确认、分类选择或冲突处理，主 App 打开 [S4-IOS-07 files-import](S4-IOS-07-files-import.md) 的确认流程。
8. 主 App 接管失败或 repo 权限过期时，跳转 [S4-IOS-06 icloud-permission](S4-IOS-06-icloud-permission.md)，队列项保留为待处理。

## 数据与依赖

- iOS Share Extension lifecycle。
- App Group shared container。
- 最近 repo 与 security scoped bookmark。
- Core import queue 或主 App 接管协议。
- 文件名清理、分类建议、冲突预检测。
- Main App takeover 协议：queued、needs review、permission expired、completed。

## 验收清单

- Safari URL、Files 单文件、Files 多文件三类分享都能展示预览。
- 没有 repo 或权限过期时不会假装导入成功。
- 扩展内操作足够短，不进行长时间阻塞 hash。
- 保存后主 App 能继续完成导入。
- Save queued、Open AreaMatrix、permission expired、Cancel 四类路径都能手工验证。
- Cancel 不创建队列任务；权限过期不会显示导入成功。
- 多文件部分失败时能说明哪些项会被导入。
- 页面符合系统扩展尺寸，不出现完整主 App 导航。

## 来源

- 来源类型：组合来源。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-05-share-extension-import.md`。
- 组合来源：`docs/ux/drag-import-flow.md` 的导入安全规则。
- 推导说明：Share Extension 生命周期、时间限制和主 App 接管行为依据 iOS 平台能力推导。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [移动端资料库浏览](S4-IOS-02-mobile-library.md)
- [iOS Files 导入确认](S4-IOS-07-files-import.md)
- [逐页 UI 开发规格索引](../README.md)
