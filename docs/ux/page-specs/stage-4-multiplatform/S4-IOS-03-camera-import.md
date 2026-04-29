# S4-IOS-03 camera-import - 拍照导入

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-IOS-03
> 页面类型：iOS import review sheet
> 页面文件：`S4-IOS-03-camera-import.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：iOS 移动端。
- **建议目录**：`apps/ios/AreaMatrix/Features/Import/CameraImportView.swift`。
- **建议组件**：`CameraImportReviewSheet`、`CapturedPhotoPreview`、`MobileConflictSummary`、`ImportProgressView`。
- **实现边界**：这是 AreaMatrix 拥有的拍照导入确认 sheet。iOS 系统相机权限弹窗、系统相机拍摄界面和系统拍摄预览属于前置系统 surface，不作为独立 AreaMatrix 页面规格，也不新增单页文件。

## 页面背景

移动端最自然的导入方式之一是拍照保存票据、合同、白板或纸质资料。AreaMatrix 需要让用户在拍照后确认文件名、目标分类和保存方式，并保持“不覆盖、不丢失”的导入承诺。

入口：移动端资料库 `+` 菜单点击 `Take Photo`，完成系统权限检查和系统相机拍摄后进入本 sheet。
退出：导入成功返回移动端资料库并显示结果；用户在本 sheet 取消则回到资料库；相机权限拒绝或系统拍摄取消在进入本 sheet 前返回资料库并显示轻量提示。

## 页面功能

- 接收系统相机返回的单张照片临时文件。
- 显示 AreaMatrix 导入确认预览，支持返回系统相机重拍。
- 为照片生成默认文件名，例如 `Photo 2026-04-29 1130.jpg`。
- 允许用户编辑文件名和选择目标分类。
- 显示导入模式：复制到资料库，移动端不提供“原地索引”作为默认选项。
- 处理同名冲突，默认保留两份并自动编号。
- 显示导入进度和导入结果。
- 对系统权限拒绝、系统拍摄取消、临时文件不可读给出明确返回路径。

## 布局与内容

导入确认 Sheet：
- 标题：`Import Photo`
- 左上角：`Cancel`
- 右上角：`Import`
- 照片预览：显示系统相机返回的照片缩略图，保持原始比例，不裁切重要内容。
- 预览操作：`Retake`，关闭本 sheet 并回到系统相机；`View full size` 可用时打开系统预览。
- 文件名输入：默认 `Photo YYYY-MM-DD HHmm.jpg`
- 分类选择：默认根据 Stage 1 分类规则或最近使用分类。
- 来源行：`Source: Camera`
- 文件大小行：拍摄后估算大小。
- 保存方式：`Copy into repository`，只读说明。
- 安全说明：`The original captured photo will not be deleted until import is complete or you cancel.`
- 冲突提示：同名不同内容时显示黄色冲突区，沿用 Stage 1 ImportSheet 的保留两份默认策略。

冲突区：
- 重复内容：显示 `Duplicate content`，默认 `Skip duplicate`。
- 同名不同内容：显示 `Name conflict`，默认 `Keep both`，展示自动编号后的文件名。
- Replace 选项如展示，必须标为危险，并在应用前进入 `S4-X-09 replace-confirm`。

进度与结果：
- 导入中：`Copying photo...`、`Writing metadata...`
- 成功：`Photo imported`
- 失败：失败原因、`Retry`、`Retake`、`Cancel`

## 状态与规则

- 默认状态：照片可读、文件名有效、目标分类可写时，`Import` 可用。
- 空态：系统相机没有返回可用照片时不打开本 sheet；若已进入 sheet 后临时文件丢失，显示错误态而不是空预览。
- 加载态：读取照片、生成缩略图、检测重复或计算建议分类时显示 `Preparing photo...`，`Import` 临时禁用。
- 错误态：临时照片不可读、冲突检测失败、目标分类不可写或导入失败时显示原因，并保留 `Retake`、`Retry` 或 `Cancel`。
- 相机权限未决定：进入系统权限请求前可显示轻量 preflight 说明；该说明不是独立页面，不进入本页验收。
- 权限拒绝：不进入本 sheet；返回移动端资料库并显示 `Camera access is required to take a photo.`，动作 `Open Settings`。
- 拍摄取消：不进入本 sheet；回到移动端资料库，不显示错误。
- 临时照片不可读：显示错误页状态 `Could not read captured photo.`，提供 `Retake` 和 `Cancel`。
- 文件名为空：禁用 `Import`，输入框下方显示 `File name is required.`
- 文件名包含非法字符：自动替换并提示 `Some characters were adjusted for file system compatibility.`
- 目标分类不可写：禁用 `Import`，提供 `Choose another category`。
- 重复内容：默认 `Skip duplicate`，允许改为 `Keep both`。
- 同名冲突：默认 `Keep both`，生成 `Photo ... (2).jpg`。
- Replace：必须进入 `S4-X-09 replace-confirm`，且平台不可逆时不显示或禁用。
- 导入失败：保留拍摄结果预览，允许重试，不要求用户重新拍照。
- 用户取消本 sheet：删除 AreaMatrix 临时导入项，不写入 repo，不删除已经保存到用户相册或系统临时区之外的源照片。

## 交互

1. 点击 `Take Photo` 后先检查相机权限；权限拒绝或系统拍摄取消都返回 `S4-IOS-02 mobile-library`。
2. 系统相机返回照片后进入本 sheet，并立即生成只读预览和默认文件名。
3. 导入确认中修改文件名只影响新照片，不影响已有文件。
4. 点击 `Import` 后显示进度：`Copying photo...`、`Writing metadata...`、`Done`。
5. 导入成功显示结果 toast：`Photo imported`，动作 `View`。
6. 如果 Core 返回冲突，保持在确认 Sheet 内展示冲突区，而不是另开独立全屏。
7. 点击 `Retake` 放弃当前临时导入项并回到系统相机；重新拍摄后回到同一个 sheet 语义。
8. 点击 `Cancel` 不写入 repo，不创建 change log。

## 数据与依赖

- iOS camera permission。
- Photos/camera capture output。
- 临时照片文件生命周期管理。
- Core transactional import API。
- 分类规则、最近分类、冲突检测。
- iCloud repo 写入时需要 coordinated write 或平台等价封装。

## 验收清单

- 权限拒绝、拍摄取消、拍摄成功、临时照片不可读、导入失败、重复内容、同名冲突都能手工验证。
- 系统权限弹窗、系统相机 UI 和系统预览不被当作 AreaMatrix 独立页面实现。
- 默认保存方式是复制进 repo，不删除相机临时结果直到导入完成或用户取消。
- 同名冲突默认保留两份，不覆盖已有文件。
- Replace 如可见，必须进入 `S4-X-09`，平台不可逆时不可执行。
- 导入成功后移动端资料库能立刻看到新照片。
- VoiceOver 能读出照片预览说明、文件名输入、分类选择、冲突状态和导入按钮禁用原因。

## 来源

- 来源类型：组合来源。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-04-camera-import.md`。
- 组合来源：`docs/ux/drag-import-flow.md`、`docs/ux/dedup-conflict.md`。
- 推导说明：系统权限、系统相机与系统预览作为前置 surface；AreaMatrix 单页规格只覆盖拍摄完成后的导入确认 sheet，导入冲突遵守默认保留两份。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [移动端资料库浏览](S4-IOS-02-mobile-library.md)
- [Replace 二次确认](S4-X-09-replace-confirm.md)
- [逐页 UI 开发规格索引](../README.md)
