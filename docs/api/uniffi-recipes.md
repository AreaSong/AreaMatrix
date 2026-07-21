# UniFFI Swift 封装套路集

> 把同步 Rust FFI 调用包装成符合 Swift 语言习惯的 async / throws API 的实战模式：actor 串行化与线程切换、错误映射快照、record / enum 类型映射、preview token 两段式、外部事件批量同步与 cursor、绑定再生成。所有示例中的函数签名、类型名和枚举 case 都能在 `core/area_matrix.udl` 与生成绑定 `apps/macos/AreaMatrix/Bridge/UniFFI/area_matrix.swift` 中找到逐字对应。
>
> 阅读时长：约 12 分钟。

---

## 设计前提

UniFFI 从 `core/area_matrix.udl` 生成 Swift 绑定；`core/build.rs` 从同一份 UDL 生成 Rust scaffolding（本项目走 UDL 路线，不用 proc-macro 导出）。所有套路都建立在以下事实上：

- **全部函数是同步阻塞的。** 本项目 UDL 全部为同步函数（无 `[Async]`），线程切换由 Swift 层负责。
- **生成 API 是模块级全局函数，不是某个类型的成员。** 例如 `listFiles(repoPath:filter:)`、`importFile(repoPath:sourcePath:options:)`、`deleteFile(repoPath:fileId:)`。
- **没有会话句柄。** 每个业务函数的第一个参数都是 `repoPath: String`；不存在 open / close 式状态。资料库初始化是一次性的 `initRepo(repoPath:options:)`，之后所有调用直接带路径。
- **`[Throws=CoreError]` 映射为 Swift `throws`。** UDL 里只有 `get_version` 和 `map_core_error` 两个函数不抛错，其余全部可能抛 `CoreError`。
- **UDL 中唯一的 interface 是 `[Error] interface CoreError`。** 没有 callback interface，没有对象句柄，Rust 不会反向推事件给 Swift。外部文件变化由 Swift 平台层监听后再喂给 Core（见 Recipe 6）。
- **数据以值类型 DTO 跨边界。** `dictionary` 生成 Swift struct，`enum` 生成 Swift enum，全部按值复制；大结果通过分页参数控制体量。

Swift 端分层约定（详见 [../architecture/ffi-design.md](../architecture/ffi-design.md)）：业务代码不直接调用生成函数，统一经过手写的 `CoreBridge` actor（`apps/macos/AreaMatrix/Bridge/CoreBridge.swift`）与 Bridge 层协议；UI 层消费 Bridge 转换后的 `XxxSnapshot` DTO。

---

## Recipe 1: 同步 FFI 包成 async——CoreBridge actor 与 Task.detached

### 基本形态

`CoreBridge` 是 actor；涉及文件 IO、DB、hash 的调用在 actor 方法内通过 `Task.detached` 切到后台线程，避免阻塞 MainActor：

```swift
actor CoreBridge {
    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        try await Task.detached(priority: .userInitiated) {
            let coreFiles = try listCoreFiles(repoPath: repoPath, filter: FileFilter(filter))
            return coreFiles.map { FileEntrySnapshot(coreEntry: $0) { _, _ in .available } }
        }.value
    }
}
```

detached closure 只捕获 Sendable 值或不可变快照，不在 closure 内更新 SwiftUI 状态；错误原样抛回，再由页面模型映射（见 Recipe 3）。

### 同名遮蔽：全局函数 vs actor 方法

actor 方法与生成的全局函数经常同名（`listFiles`、`importFile`、`syncExternalChanges`）。Swift 的非限定名字查找优先解析类型成员：在 actor 方法内直接写 `listFiles(...)` 会命中方法自身——签名不同时是参数类型不匹配的编译错误，签名相同时则变成自调用。仓库里有两种消歧姿势，选其一即可：

私有中转函数（`CoreBridge.swift` 的做法）：

```swift
private func listCoreFiles(repoPath: String, filter: FileFilter) throws -> [FileEntry] {
    try listFiles(repoPath: repoPath, filter: filter)
}
```

模块限定（`CoreImporting.swift`、`CoreBatchChangeCategory.swift` 的做法）：

```swift
let entry = try await Task.detached(priority: .userInitiated) {
    try AreaMatrix.importFile(repoPath: repoPath, sourcePath: sourceURL.path, options: options)
}.value
```

`AreaMatrix` 是 app 模块名，生成的全局函数与手写代码同属该模块，用模块名限定即可绕开方法遮蔽。

### actor 隔离的真实边界

`CoreBridge` 的 actor 隔离只作用于同一个实例，不要把它当成进程级写队列：

- 应用可以创建多个 `CoreBridge` 实例；跨实例的数据库协调依赖 SQLite WAL、事务和 5 秒 `busy_timeout`，不依赖 Swift 排队。
- actor 方法在等待 `Task.detached(...).value` 时允许重入；跨调用一致性必须由 Core 事务、回滚 guard、幂等 token 或 preview token（见 Recipe 5）保证。
- DB 短暂竞争表现为 `CoreError.Db`，其 locked / busy 子语义由 Core 侧映射识别并标记为可重试（见 Recipe 2）。

完整并发模型见 [../architecture/concurrency.md](../architecture/concurrency.md)。

---

## Recipe 2: CoreError——按 variant 分支，不解析字符串

### 封闭变体清单

`CoreError` 是 UDL 声明的封闭错误合同，15 个 variant，每个携带一个结构化字段（Swift label 见下）：

| Variant | Swift case | 稳定语义 |
|---|---|---|
| `Io` | `.Io(message:)` | 文件或底层 IO 失败 |
| `Db` | `.Db(message:)` | SQLite 或 metadata 失败 |
| `Config` | `.Config(reason:)` | 配置无效或保存失败 |
| `Validation` | `.Validation(reason:)` | API 输入或编辑草稿无效 |
| `Classify` | `.Classify(reason:)` | 分类规则执行失败 |
| `Conflict` | `.Conflict(path:)` | 路径、命名或状态冲突 |
| `DuplicateFile` | `.DuplicateFile(existingPath:)` | active 文件已拥有相同内容 |
| `FileNotFound` | `.FileNotFound(path:)` | 操作目标对应文件不存在 |
| `ExpiredAction` | `.ExpiredAction(actionId:)` | Undo / Redo token 已过期 |
| `RepoNotInitialized` | `.RepoNotInitialized(path:)` | 目录不是已初始化资料库 |
| `InvalidPath` | `.InvalidPath(path:)` | 路径越界或格式无效 |
| `ICloudPlaceholder` | `.ICloudPlaceholder(path:)` | 本地内容尚未下载 |
| `StagingRecoveryRequired` | `.StagingRecoveryRequired(path:)` | staging 状态必须先恢复 |
| `PermissionDenied` | `.PermissionDenied(path:)` | 文件或资料库权限不足 |
| `Internal` | `.Internal(message:)` | 未预期内部失败 |

Rust 定义在 `core/src/error/core_error.rs`，语义与恢复姿态的权威表在 [error-codes.md](error-codes.md)。

### catch 姿势

按 variant 和结构化 payload 分支，绝不解析 `Display`、`localizedDescription` 或用户文案：

```swift
do {
    _ = try AreaMatrix.importFile(repoPath: repoPath, sourcePath: sourceURL.path, options: options)
} catch let error as CoreError {
    switch error {
    case let .DuplicateFile(existingPath):
        presentDuplicateChoices(existingPath: existingPath) // Skip / Keep both / 经确认 Replace
    case let .ICloudPlaceholder(path):
        presentDownloadAndRetry(path: path) // 下载由用户显式触发，不自动重试
    case let .StagingRecoveryRequired(path):
        enterImportRecovery(path: path)
    default:
        presentMappedError(error) // 其余走 Recipe 3 的映射快照
    }
}
```

两条硬边界：

- 生成绑定给 `CoreError` 的 `localizedDescription` 是 `String(reflecting: self)`，属于调试文本且可能携带绝对路径，不能作为用户文案，也不能据此选择业务动作。
- 不要在 Swift 侧对 `message` / `reason` / `path` 做 `contains(...)` 之类的字符串嗅探。DB 的 locked / busy 与 corrupted 子语义由 Core 侧 `is_db_locked_message` / `is_db_corrupted_message` 识别，并已经反映在映射结果的 severity 与 recoverability 里；Swift 只消费映射元数据。

### 需要透传原始上下文时

Bridge 层如需读取 payload（例如把缺失路径带进恢复页面），用集中式的快照工具而不是在页面里散落 switch：`CoreErrorMappingSnapshots.swift` 提供 `CoreErrorRawContextSnapshot`，可按 kind 提取 `rawContext`（如 `CoreErrorRawContextSnapshot.fileNotFoundPath(from:)`）。

---

## Recipe 3: 错误映射快照——mapCoreError(input:) 与 AppSemanticError

### Core 提供的纯函数

UDL 暴露了一个不抛错的纯函数，把结构化错误输入换算成稳定 UI 元数据：

```swift
public func mapCoreError(input: ErrorMappingInput) -> ErrorMapping
```

`ErrorMappingInput` 的字段是 `kind: ErrorKind` 加 `path` / `reason` / `message` 三个可选字符串；`ErrorMapping` 返回 `kind`、`userMessage`、`severity`、`suggestedAction`、`recoverability`、`rawContext`。映射是无副作用纯函数：不读文件系统、不开 DB、不写日志。

### Swift 快照类型

`apps/macos/AreaMatrix/Bridge/CoreErrorMappingSnapshots.swift` 把上述 DTO 包装成 UI 友好的快照，是错误呈现的唯一 App 侧合同——不存在另一套字符串型 `AppError`：

- `CoreErrorMappingSnapshot`：kind / userMessage / severity / suggestedAction / recoverability / rawContext 的 Equatable 快照。
- `CoreErrorKindSnapshot`、`CoreErrorSeveritySnapshot`、`CoreErrorRecoverabilitySnapshot`：稳定枚举。
- `AppSemanticError`：App 自身语义错误的载体，直接携带同一个 mapping snapshot（如 `AppSemanticError.invalidPath(rawContext:)`），与 CoreError 走同一条呈现管线。
- `CoreErrorMapping` 协议：`func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot`，`CoreBridge` 已实现；扩展提供 `mapError(_:)`，可同时接住 `CoreError`、`AppSemanticError` 和未知 `Error`。

从 `CoreError` 到映射输入的转换按 variant 逐字段进行（`mapCoreErrorFromCore(_:)` 内部构造 `ErrorMappingInput(coreError:)`），Swift 不掺入任何字符串判断。

### 页面模型消费示例

页面模型注入按能力拆分的 Bridge 协议，按 `recoverability` 决定呈现姿态：

```swift
@MainActor
final class FileListModel: ObservableObject {
    @Published private(set) var files: [FileEntrySnapshot] = []
    @Published var failure: CoreErrorMappingSnapshot?

    private let fileLister: any CoreFileListing
    private let errorMapper: any CoreErrorMapping

    init(fileLister: any CoreFileListing, errorMapper: any CoreErrorMapping) {
        self.fileLister = fileLister
        self.errorMapper = errorMapper
    }

    func load(repoPath: String, category: String?) async {
        do {
            files = try await fileLister.listFiles(
                repoPath: repoPath,
                filter: .currentCategory(category)
            )
        } catch {
            failure = await errorMapper.mapError(error)
        }
    }
}
```

```swift
let mapping = await errorMapper.mapError(error)
switch mapping.recoverability {
case .retryable:
    showRetry(mapping)
case .userActionRequired:
    showUserAction(mapping)
case .refreshRequired:
    refreshAndPresent(mapping)
case .fatal:
    showBlockingRecovery(mapping)
}
```

展示层可以显示经过控制的 `mapping.rawContext`，但不得把含用户名或绝对路径的原始描述直接抛给用户。

---

## Recipe 4: record / enum 类型映射注意点

### 命名与类型规则

| UDL | Swift | 真实例子 |
|---|---|---|
| `dictionary` | struct + public memberwise init | `FileEntry`、`ImportOptions`、`SyncResult` |
| `enum { "Moved", ... }` | enum，case 转 lowerCamelCase | `StorageMode` 的 `.moved` / `.copied` / `.indexed` |
| snake_case 字段 | camelCase 属性 | `existing_path` → `existingPath`、`fs_event_id` → `fsEventId` |
| snake_case 函数 | camelCase 函数 | `list_tree_json` → `listTreeJson(repoPath:locale:)` |
| `i64` / `f32` / `boolean` | `Int64` / `Float` / `Bool` | `FileEntry.sizeBytes: Int64` |
| `T?` / `sequence<T>` | `T?` / `[T]` | `getFsEventCursor` 返回 `Int64?` |

容易踩空的三个点：

- **缩写词大小写按机械规则转换。** `content_md` → `contentMd`（不是 `contentMD`），所以是 `writeNote(repoPath:fileId:contentMd:)`；同理 cursor 函数是 `getFsEventCursor` / `setFsEventCursor`（`Fs` 不是 `FS`）。
- **分页字段不是可选的。** `FileFilter.limit` / `offset` 是 `Int64`，调用方必须显式给值；仓库用 `FileFilterSnapshot.currentCategory(_:)` 这类工厂集中默认值（limit 50, offset 0）。
- **enum 关联值只在 error variant 上出现。** 普通 UDL enum（如 `DuplicateStrategy` 的 `.skip` / `.overwrite` / `.keepBoth` / `.ask`）都是无 payload 的简单 case。

### 生成 conformance 的真实范围

生成的 record / enum 只带 `Equatable` 和 `Hashable`（字段可哈希时），`CoreError` 额外有 `Foundation.LocalizedError`。**没有任何 `Sendable`、`Codable` 或 `Identifiable` conformance**。跨 actor 边界传递时它们是纯值类型，语义安全，但编译器没有 `Sendable` 证明；在严格并发模式下直接跨界会产生诊断。

仓库姿势不是给生成类型补扩展，而是在 Bridge 层立刻转成手写 Snapshot DTO：

```swift
struct FileEntrySnapshot: Equatable, Identifiable {
    var id: Int64
    var path: String
    var currentName: String
    var category: String
    var sizeBytes: Int64
    var storageMode: String
    // ……由 FileEntry 换算，UI 只消费这一层
}
```

这样 UI 拿到的是稳定、可扩展（比如附加 `availability` 展示态）的类型，生成类型的形状变化被隔离在 Bridge 内。生成文件本身不可手工修改——任何补丁都会在下一次再生成时丢失（见 Recipe 8）。

---

## Recipe 5: 导入与批量入口——preview token 两段式

### 单文件导入

```swift
let options = ImportOptions(
    mode: .copied,                 // StorageMode: .moved / .copied / .indexed
    destination: .autoClassify,    // ImportDestination: .autoClassify / .selectedDirectory / .category
    targetDirectory: nil,
    overrideCategory: nil,
    overrideFilename: nil,
    duplicateStrategy: .ask        // DuplicateStrategy: .skip / .overwrite / .keepBoth / .ask
)
let entry: FileEntry = try AreaMatrix.importFile(
    repoPath: repoPath,
    sourcePath: sourceURL.path,
    options: options
)
```

需要知道「Move 之后源文件是否已删掉」时用 `importFileWithResult(repoPath:sourcePath:options:)`，返回的 `ImportResult` 带 `entry`、`sourceRemovalStatus`（`.notRequested` / `.removed` / `.retained`）和 `sourceRemovalFailure`，避免调用方解析错误文本猜测源文件状态。

### 批量写入口：先 preview 拿 token，再 commit

批量写操作没有 callback，也没有流式进度；合同是「preview 报告 + preview token + 一次性 commit + 逐项结果报告」。四组入口都在 UDL 中成对出现：

| Preview | Commit |
|---|---|
| `previewBatchMoveToCategory(repoPath:fileIds:targetCategory:moveRepoOwnedFiles:)` | `batchMoveToCategory(...previewToken:)` |
| `previewBatchDelete(repoPath:fileIds:deleteMode:)` | `batchDeleteToTrash(...previewToken:)` |
| `previewBatchRename(repoPath:fileIds:rule:)` | `batchRename(...previewToken:)` |
| —（无 preview） | `batchAddTags(repoPath:fileIds:tags:)` |

```swift
let preview = try AreaMatrix.previewBatchMoveToCategory(
    repoPath: repoPath,
    fileIds: selectedFileIds,
    targetCategory: "documents",
    moveRepoOwnedFiles: true
)
guard preview.canApply else {
    presentBlocked(reason: preview.applyBlockedReason)
    return
}

let report = try AreaMatrix.batchMoveToCategory(
    repoPath: repoPath,
    fileIds: selectedFileIds,
    targetCategory: preview.targetCategory,
    moveRepoOwnedFiles: preview.moveRepoOwnedFiles,
    previewToken: preview.previewToken
)
// report.movedCount / metadataOnlyCount / failedCount / itemResults / updatedFiles / undoToken
```

要点：

- token 绑定「选择集 + 目标 + 选项 + 被检查状态」。中途外部变化让 Apply 不安全时，commit 抛 `CoreError.Conflict`，UI 回到 Preview 重来，而不是带着旧 token 硬提交。
- 部分失败不抛错，在 `itemResults` 里逐项可追踪；成功项保留并返回 `undoToken` 进入 undo 链路。
- 删除入口按语义区分：单文件 `deleteFile(repoPath:fileId:)` 是「移入系统 Trash + metadata 软删除」合同，没有永久删除参数；Indexed / 外部条目的索引移除走 `removeIndexEntry(repoPath:fileId:)`；批量删除用 `BatchDeleteMode` 的 `.moveToTrash` / `.removeFromIndex` 区分两种模式。
- 一次 batch 调用把整批决策交给 Core 在事务内处理，比 N 次单独 FFI 少跨边界、也能产出单一 undo token；但不要据此发明不存在的批量导入 FFI——**多文件导入是 Swift 侧串行循环单文件 `importFile`**，进度、会话与 stop-after-current-file 都由 Swift 编排（见 [../architecture/concurrency.md](../architecture/concurrency.md)）。

---

## Recipe 6: 外部事件批量同步与 cursor

Rust 不订阅文件系统。外部变化链路是「Swift 平台层监听 → 归一化事件 → 同步 FFI 喂给 Core → cursor 持久化」：

```text
FSEventStream（MainActor 回调, 200ms 去抖, 按路径合并）
  → MainExternalCreatedFileWatcher 过滤 .areamatrix/、目录事件、InFlight 自产回流
  → MainExternalSyncWindow（严格按序、一次一个窗口）
  → syncExternalChanges(repoPath:events:)   ← 同步 FFI
  → getFsEventCursor / setFsEventCursor     ← cursor 恢复与补写
```

平台侧实现在 `apps/macos/AreaMatrix/PlatformServices/MainExternalCreatedFileWatcher.swift`，Bridge 侧协议在 `apps/macos/AreaMatrix/Bridge/CoreExternalChangesSyncing.swift`。

### 启动：用 cursor 决定监听起点

```swift
guard let cursor = try await bridge.getFSEventCursor(repoPath: repoPath) else {
    // 没有 cursor 说明无法安全重放历史，必须走整库 rescan 恢复路径
    requestRescan()
    return
}
// FSEventStreamCreate(..., sinceWhen: FSEventStreamEventId(max(cursor, 0)), ...)
```

注意大小写：Bridge 协议方法按 Swift 惯例命名为 `getFSEventCursor` / `setFSEventCursor`，内部转发到生成的全局函数 `getFsEventCursor(repoPath:)` / `setFsEventCursor(repoPath:lastEventId:)`（机械转换规则见 Recipe 4）。

### 批量同步与结果

事件用生成 record `ExternalEvent`（相对路径 + kind + FSEvents event id）表达，kind 是 `.created` / `.removed` / `.modified` / `.renamed`：

```swift
let coreEvents = [
    ExternalEvent(path: "docs/report.pdf", kind: .created, fsEventId: 8_812),
    ExternalEvent(path: "notes/draft.md", kind: .renamed, fsEventId: 8_815),
]
let result: SyncResult = try await Task.detached(priority: .userInitiated) {
    try syncExternalChanges(repoPath: repoPath, events: coreEvents)
}.value
// result.detectedCreates / detectedRenames / detectedDeletes / detectedModifies / result.errors
```

### cursor 规则

Core 处理一批事件的顺序是：一个 SQLite 事务写 files + change_log → 重新生成受影响 overview → 持久化批次最大 cursor。据此得出 Swift 侧三条纪律：

- **失败不推进 cursor。** overview 或 cursor 写入失败时 Core 不确认该批次，下一次同一窗口重放；created / renamed / removed / modified 分支在 Core 侧幂等，重放安全。绝不能为了「消掉错误」在失败后手动 `setFsEventCursor`。
- **watermark 补写。** 一个回调窗口内的业务事件可能被路径规则或 InFlight 过滤掉一部分。窗口携带整窗最大 event id（`cursorWatermark`）；Core 成功后若 watermark 高于实际业务事件最大 id，Swift 再补一次 `setFsEventCursor(repoPath:lastEventId:)`。纯过滤窗口到达队首后直接确认 watermark。
- **严格按序。** 一次只处理队首一个窗口，失败保留队首并阻塞后续窗口；空窗口也要排队，不能越过更早窗口确认 cursor。

事件语义与窗口状态机详见 [../architecture/fs-watcher.md](../architecture/fs-watcher.md)。

---

## Recipe 7: 长任务——没有 cancel handle 时的做法

FFI 层没有取消句柄、进度 callback 或超时参数，Swift 的 `Task.cancel()` 也不会中断一个正在执行的同步 Rust 调用。可用的模式是「可恢复的小调用 + report DTO + 持久化 session / cursor」：

- **调用间检查控制状态。** 批量导入每次只跑一个单文件导入，stop-after-current-file 在当前调用返回后阻止下一项启动；停止语义永远落在两次 FFI 调用之间，而不是调用内部。
- **长流程做成可恢复会话。** 整库扫描的进度与中断状态由 Core 持久化为 scan session，UI 只读状态、按需恢复：

```swift
// 在 Task.detached 中执行
if let session = try getLatestScanSession(repoPath: repoPath),
   session.status == .interrupted {
    let report = try resumeScanSession(repoPath: repoPath, scanSessionId: session.id)
    // report: ReindexReport（inserted / updated / missing / conflicts / errors ...）
}
```

- **等待上限交给 Core 配置。** SQLite 最长等待由 5 秒 `busy_timeout` 控制；Swift 不再叠加自己的轮询或 kill 逻辑。

---

## Recipe 8: 绑定再生成与漂移检查

生成绑定是版本控制内的产物，修改顺序固定为：Core API 文档 → UDL → Rust 实现 → 绑定 → Swift bridge。UDL 变化后：

```bash
./dev build core
./dev bindings update --udl core/area_matrix.udl --out-dir apps/macos/AreaMatrix/Bridge/UniFFI
./dev bindings verify
```

- `./dev bindings update` 更新 Xcode 实际消费的 tracked 绑定（`Bridge/UniFFI/`）；更新后审查生成 diff。
- `./dev bindings verify` 是只读检查：在临时目录重新生成 `area_matrix.swift`、`area_matrixFFI.h` 与 `module.modulemap` 并与 tracked 版本比较，CI 用它阻止 UDL、生成器输出与 Xcode 消费文件三者脱节。
- 生成器版本固定为 `core/Cargo.lock` 中的 UniFFI 版本，避免本地与 CI 生成结果不一致。
- 不要手工修补生成 Swift 或 C header；需要的行为写在 Bridge 层手写文件里。

---

## 常见陷阱

| 陷阱 | 后果 | 规避 |
|---|---|---|
| MainActor 上直接调用阻塞 FFI | UI 冻结 | 经 `CoreBridge` actor 用 `Task.detached` 切后台 |
| 解析错误字符串来分支业务 | 违反错误合同，文案一变即碎 | 按 `CoreError` variant 分支；子语义交给 `mapCoreError` |
| 把 `localizedDescription` 当用户文案 | 展示调试文本，可能泄露绝对路径 | 用 `ErrorMapping.userMessage` 与受控 `rawContext` |
| 把 actor 隔离当进程级写队列 | 多实例下互斥不成立 | 依赖 SQLite WAL、`busy_timeout`、Core 事务与 preview token |
| 期待 `Task.cancel()` 中断 Core 调用 | 同步调用不可中断 | 调用间检查控制状态；长流程用 session 恢复 |
| actor 方法内调用同名生成函数 | 解析成方法自身：编译错误或自调用 | 模块限定 `AreaMatrix.xxx(...)` 或私有中转函数 |
| 失败后仍推进 FSEvent cursor | 外部变化被永久跳过 | 失败保留 cursor，依赖幂等重放 |
| 带过期或伪造的 `previewToken` 提交 batch | Core 返回 `Conflict`，Apply 被拒 | 外部状态变化后回到 preview 重新生成 token |
| 手工修改生成绑定 | 下次再生成即丢失 | 改 UDL 后 `./dev bindings update`，扩展写在 Bridge 层 |
| 一次性拉取超大列表 | 大结果整体跨 FFI 复制 | 用 `FileFilter.limit` / `offset` 分页，详情按需走 `getFile(repoPath:fileId:)` |

---

## 命名与分层惯例

| 场景 | 惯例 | 真实例子 |
|---|---|---|
| Swift 调 Core 的唯一手写入口 | `CoreBridge` actor（实例注入，无全局单例） | `Bridge/CoreBridge.swift` |
| 按能力拆分的注入协议 | `Core<Capability>ing` | `CoreFileListing`、`CoreExternalChangesSyncing`、`CoreErrorMapping` |
| UI 消费的桥接 DTO | `XxxSnapshot` | `FileEntrySnapshot`、`CoreErrorMappingSnapshot`、`SyncResultSnapshot` |
| 与 actor 方法同名的生成函数 | 模块限定或私有中转 | `AreaMatrix.importFile(...)`、`listCoreFiles(...)` |
| App 语义错误 | `AppSemanticError` 携带 mapping snapshot | `Bridge/CoreErrorMappingSnapshots.swift` |

---

## Related

- [core-api.md](core-api.md)
- [error-codes.md](error-codes.md)
- [../architecture/ffi-design.md](../architecture/ffi-design.md)
- [../architecture/concurrency.md](../architecture/concurrency.md)
- [../architecture/fs-watcher.md](../architecture/fs-watcher.md)
- [../development/build.md](../development/build.md)
