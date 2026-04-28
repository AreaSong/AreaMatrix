# UniFFI Swift 封装套路集

> 把同步 / 阻塞的 Rust FFI 调用包装成符合 Swift 语言习惯的 async / throws / Sendable / actor-safe API。本文是落地实现的 cookbook。
>
> 阅读时长：约 12 分钟。

---

## 设计前提

UniFFI 暴露的 Rust 函数：

- 都是**同步阻塞**（UniFFI 0.28 不原生支持 `async fn`）
- 通过 `Result<T, CoreError>` 抛错 → Swift 端 `throws`
- callback interface 是**同步**的，从 Rust 任意线程调用

Swift 端要做的：

1. 把阻塞调用切到后台线程，避免卡 MainActor
2. 把同步 callback 翻译成 `AsyncStream` / `Combine`
3. 序列化对 Core 的写操作（避免 SQLite 锁竞争）
4. 把 `CoreError` 翻译成 UI 友好的 `AppError`
5. 管理 callback 生命周期，避免内存泄露

---

## Recipe 1: 把同步函数包成 async throws

### 模式 A：纯计算

```swift
import Foundation

extension AreaMatrix {
    public static func listFilesAsync(category: String) async throws -> [FileEntry] {
        try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.listFiles(category: category)
        }.value
    }
}

let files = try await AreaMatrix.listFilesAsync(category: "docs")
```

### 模式 B：写操作（必须串行化）

通过 actor 把所有写串到一个队列：

```swift
public actor CoreBridge {
    public static let shared = CoreBridge()

    public func importFile(src: URL, options: ImportOptions) async throws -> FileEntry {
        try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.importFile(srcPath: src.path, options: options)
        }.value
    }

    public func deleteFile(_ id: Int64) async throws {
        try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.deleteFile(fileId: id, mode: .toTrash)
        }.value
    }
}
```

调用：

```swift
let entry = try await CoreBridge.shared.importFile(src: url, options: opts)
```

actor 保证按到达顺序执行，避免两个 import 同时持有 SQLite 写锁。

---

## Recipe 2: 错误转换 — CoreError → AppError

```swift
public enum AppError: LocalizedError {
    case notFound(String)
    case duplicate(existingId: Int64)
    case dbBusy
    case iCloudPlaceholder(String)
    case storageFull(needGB: Int)
    case permissionDenied(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let n): return String(format: NSLocalizedString("error.not_found", comment: ""), n)
        case .duplicate: return NSLocalizedString("error.duplicate", comment: "")
        case .dbBusy: return NSLocalizedString("error.db_busy", comment: "")
        case .iCloudPlaceholder: return NSLocalizedString("error.icloud_placeholder", comment: "")
        case .storageFull(let gb): return String(format: NSLocalizedString("error.storage_full", comment: ""), gb)
        case .permissionDenied(let p): return String(format: NSLocalizedString("error.permission_denied", comment: ""), p)
        case .unknown(let m): return m
        }
    }
}

extension Error {
    public var appError: AppError {
        guard let core = self as? CoreError else { return .unknown(localizedDescription) }
        switch core {
        case .NotFound(let entity): return .notFound(entity)
        case .Duplicate(let id): return .duplicate(existingId: id)
        case .Db(let m) where m.contains("busy"): return .dbBusy
        case .ICloudPlaceholder(let path): return .iCloudPlaceholder(path)
        case .Io(let m) where m.contains("ENOSPC"): return .storageFull(needGB: 1)
        case .Permission(let p): return .permissionDenied(p)
        default: return .unknown(core.localizedDescription)
        }
    }
}
```

调用方：

```swift
do {
    try await CoreBridge.shared.importFile(src: url, options: opts)
} catch {
    let err = error.appError
    showAlert(message: err.errorDescription ?? "")
}
```

---

## Recipe 3: 反向 callback → AsyncStream

Rust 通过 callback interface 推事件给 Swift；UI 端用 `AsyncStream` 消费。

### Rust 端定义

```rust
#[uniffi::export(callback_interface)]
pub trait ProgressCallback: Send + Sync {
    fn on_progress(&self, percent: i32, bytes: i64);
    fn on_complete(&self, file_id: i64);
    fn on_error(&self, message: String);
}

#[uniffi::export]
pub fn import_with_progress(src: String, callback: Box<dyn ProgressCallback>) -> CoreResult<()> {
    do_import(&PathBuf::from(src), |p, b| callback.on_progress(p, b))
        .map(|id| callback.on_complete(id))
        .map_err(|e| { callback.on_error(e.to_string()); e })
}
```

### Swift 端：AsyncStream 包装

```swift
public enum ImportEvent: Sendable {
    case progress(percent: Int, bytes: Int64)
    case complete(fileId: Int64)
    case error(String)
}

public final class ImportProgressBridge: ProgressCallback, @unchecked Sendable {
    private let continuation: AsyncStream<ImportEvent>.Continuation

    init(continuation: AsyncStream<ImportEvent>.Continuation) {
        self.continuation = continuation
    }

    public func onProgress(percent: Int32, bytes: Int64) {
        continuation.yield(.progress(percent: Int(percent), bytes: bytes))
    }

    public func onComplete(fileId: Int64) {
        continuation.yield(.complete(fileId: fileId))
        continuation.finish()
    }

    public func onError(message: String) {
        continuation.yield(.error(message))
        continuation.finish()
    }
}

extension AreaMatrix {
    public static func importWithProgress(src: URL) -> AsyncStream<ImportEvent> {
        AsyncStream { continuation in
            let bridge = ImportProgressBridge(continuation: continuation)
            Task.detached(priority: .userInitiated) {
                do {
                    try AreaMatrix.importWithProgress(src: src.path, callback: bridge)
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                _ = bridge
            }
        }
    }
}
```

### 调用

```swift
@MainActor
final class ImportViewModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var error: String?

    func startImport(_ url: URL) async {
        for await event in AreaMatrix.importWithProgress(src: url) {
            switch event {
            case .progress(let p, _):
                progress = Double(p) / 100
            case .complete:
                progress = 1.0
            case .error(let msg):
                error = msg
            }
        }
    }
}
```

注意：

- callback 在 Rust 任意线程调用 → AsyncStream 内部的 yield 是线程安全的
- UI 端 `for await` 在 MainActor 上下文 → 直接 update `@Published` 没问题
- continuation.onTermination 用闭包捕获 bridge，确保 Stream 被取消前 bridge 不被释放

---

## Recipe 4: FSEvent 推送 → AsyncStream

```rust
#[uniffi::export(callback_interface)]
pub trait FsEventListener: Send + Sync {
    fn on_event(&self, event: FsChangeEvent);
}

#[uniffi::export]
pub fn subscribe_fs_events(listener: Box<dyn FsEventListener>) -> CoreResult<EventSubscription>;

pub struct EventSubscription { token: i64 }

impl Drop for EventSubscription {
    fn drop(&mut self) { unsubscribe(self.token); }
}

#[uniffi::export]
impl EventSubscription {
    pub fn cancel(&self) { unsubscribe(self.token); }
}
```

Swift：

```swift
public actor FsEventBus {
    public static let shared = FsEventBus()

    private var subscription: EventSubscription?
    private var continuations: [UUID: AsyncStream<FsChangeEvent>.Continuation] = [:]

    public func events() -> AsyncStream<FsChangeEvent> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.add(id, continuation) }
            continuation.onTermination = { _ in
                Task { await self.remove(id) }
            }
        }
    }

    private func add(_ id: UUID, _ c: AsyncStream<FsChangeEvent>.Continuation) {
        continuations[id] = c
        ensureSubscribed()
    }

    private func remove(_ id: UUID) {
        continuations.removeValue(forKey: id)
        if continuations.isEmpty {
            subscription = nil
        }
    }

    private func ensureSubscribed() {
        guard subscription == nil else { return }
        let listener = Listener { [weak self] event in
            Task { await self?.broadcast(event) }
        }
        subscription = try? AreaMatrix.subscribeFsEvents(listener: listener)
    }

    private func broadcast(_ event: FsChangeEvent) {
        for c in continuations.values { c.yield(event) }
    }

    private final class Listener: FsEventListener, @unchecked Sendable {
        let handler: (FsChangeEvent) -> Void
        init(handler: @escaping (FsChangeEvent) -> Void) { self.handler = handler }
        func onEvent(event: FsChangeEvent) { handler(event) }
    }
}
```

UI 端订阅：

```swift
.task {
    for await event in await FsEventBus.shared.events() {
        await viewModel.handle(event)
    }
}
```

---

## Recipe 5: 批量调用

逐个调 FFI 在大批量场景下浪费过多线程切换。Rust 端提供批量入口：

```rust
#[uniffi::export]
pub fn import_batch(srcs: Vec<String>, callback: Box<dyn BatchProgressCallback>) -> CoreResult<Vec<i64>> {
    let mut ids = Vec::with_capacity(srcs.len());
    for (i, src) in srcs.iter().enumerate() {
        callback.on_item_start(i as i32, src.clone());
        match import_file_internal(src) {
            Ok(id) => {
                ids.push(id);
                callback.on_item_done(i as i32, id);
            }
            Err(e) => callback.on_item_error(i as i32, e.to_string()),
        }
    }
    Ok(ids)
}
```

Swift 端：

```swift
public func importBatch(_ urls: [URL]) -> AsyncStream<BatchEvent> {
    AsyncStream { continuation in
        let bridge = BatchBridge(continuation: continuation)
        Task.detached {
            do {
                _ = try AreaMatrix.importBatch(srcs: urls.map(\.path), callback: bridge)
            } catch {
                continuation.yield(.failed(error.localizedDescription))
            }
            continuation.finish()
        }
    }
}
```

性能差异（导入 100 个文件）：

| 方式 | 总耗时 | 说明 |
|---|---|---|
| 100 次单独 FFI | 8.5s | 每次都过 FFI 边界 |
| 1 次 batch FFI | 6.2s | 一次进入，循环 |

---

## Recipe 6: 取消（cooperative）

```rust
#[uniffi::export(callback_interface)]
pub trait CancellationToken: Send + Sync {
    fn is_cancelled(&self) -> bool;
}

#[uniffi::export]
pub fn long_running_op(input: Vec<String>, cancel: Box<dyn CancellationToken>) -> CoreResult<()> {
    for item in input {
        if cancel.is_cancelled() { return Err(CoreError::Cancelled); }
        process(&item)?;
    }
    Ok(())
}
```

Swift：

```swift
public final class SwiftCancellationToken: CancellationToken, @unchecked Sendable {
    private let cancelled = OSAllocatedUnfairLock(initialState: false)

    public func cancel() {
        cancelled.withLock { $0 = true }
    }

    public func isCancelled() -> Bool {
        cancelled.withLock { $0 }
    }
}

func runWithTaskCancellation(items: [String]) async throws {
    let token = SwiftCancellationToken()
    try await withTaskCancellationHandler {
        try await Task.detached {
            try AreaMatrix.longRunningOp(input: items, cancel: token)
        }.value
    } onCancel: {
        token.cancel()
    }
}
```

---

## Recipe 7: 生命周期管理

UniFFI 把 callback interface 传 Box 进 Rust 后，Rust 持有该对象的 strong reference。Swift 必须保留实例直到 Rust 释放它。

### 错误用法

```swift
func startWatching() {
    let listener = MyListener()
    try? AreaMatrix.subscribeFsEvents(listener: listener)
}
```

`listener` 出 scope 后，Swift 引用计数归零。Rust 端持有的 `Box` 仍尝试 callback Swift 对象 → crash。

### 正确用法

```swift
final class WatcherHolder {
    static let shared = WatcherHolder()
    private var listeners: [UUID: FsEventListener] = [:]

    func register(_ id: UUID, _ listener: FsEventListener) {
        listeners[id] = listener
    }
    func unregister(_ id: UUID) {
        listeners.removeValue(forKey: id)
    }
}
```

或用 `EventSubscription`（见 Recipe 4），让 Drop 触发 unsubscribe。

---

## Recipe 8: Sendable 与跨 Actor 边界

UniFFI 生成的 record（如 `FileEntry`）是 plain struct，所有字段都是 `Sendable`。在自动模式下编译器会推断为 Sendable。

如果 record 含 callback interface 字段（不会在我们项目里发生），需手动 `@unchecked Sendable`。

```swift
extension FileEntry: Sendable {}
extension Category: Sendable {}
extension ChangeRecord: Sendable {}
```

如果 UniFFI 生成的代码已加 Sendable conformance，则不需要重复声明。

---

## Recipe 9: SwiftUI 集成模板

```swift
@MainActor
public final class FileListViewModel: ObservableObject {
    @Published public private(set) var files: [FileEntry] = []
    @Published public private(set) var isLoading = false
    @Published public var error: AppError?

    public func load(category: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            files = try await CoreBridge.shared.listFiles(category: category)
        } catch {
            self.error = error.appError
        }
    }

    public func delete(_ id: Int64) async {
        do {
            try await CoreBridge.shared.deleteFile(id)
            files.removeAll { $0.id == id }
        } catch {
            self.error = error.appError
        }
    }
}

struct FileListView: View {
    @StateObject var vm = FileListViewModel()
    let category: String

    var body: some View {
        List {
            ForEach(vm.files, id: \.id) { f in
                Text(f.name)
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task { await vm.delete(f.id) }
                        }
                    }
            }
        }
        .overlay { if vm.isLoading { ProgressView() } }
        .task { await vm.load(category: category) }
        .alert("Error", isPresented: .constant(vm.error != nil), presenting: vm.error) { _ in
            Button("OK") { vm.error = nil }
        } message: { err in
            Text(err.errorDescription ?? "")
        }
    }
}
```

---

## Recipe 10: 测试 FFI 包装

XCTest：

```swift
final class CoreBridgeTests: XCTestCase {
    var tempRepo: URL!

    override func setUp() async throws {
        tempRepo = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-\(UUID())")
        try AreaMatrix.openRepo(path: tempRepo.path)
    }

    override func tearDown() async throws {
        try? AreaMatrix.closeRepo()
        try? FileManager.default.removeItem(at: tempRepo)
    }

    func testImport() async throws {
        let src = createTestFile()
        let entry = try await CoreBridge.shared.importFile(
            src: src,
            options: ImportOptions(mode: .copy, preferredCategory: nil)
        )
        XCTAssertEqual(entry.category, "inbox")
        XCTAssertGreaterThan(entry.sizeBytes, 0)
    }

    func testImportProgress() async throws {
        let src = createLargeTestFile()
        var lastPercent = 0
        for await event in AreaMatrix.importWithProgress(src: src) {
            if case let .progress(p, _) = event { lastPercent = p }
        }
        XCTAssertEqual(lastPercent, 100)
    }
}
```

Mock callback 用于单元测试：

```swift
final class MockProgress: ProgressCallback {
    var events: [ImportEvent] = []
    func onProgress(percent: Int32, bytes: Int64) {
        events.append(.progress(percent: Int(percent), bytes: bytes))
    }
    func onComplete(fileId: Int64) { events.append(.complete(fileId: fileId)) }
    func onError(message: String) { events.append(.error(message)) }
}
```

---

## 性能与陷阱

| 陷阱 | 后果 | 规避 |
|---|---|---|
| MainActor 直接调阻塞 FFI | UI 冻结 | 永远 Task.detached |
| 多个并发写不串行化 | SQLite busy | CoreBridge actor 串行 |
| callback 闭包捕获 self 强引用 | retain cycle | `[weak self]` |
| AsyncStream 不调 finish | 调用方永远等 | 错误路径也要 finish |
| callback 实例不 retain | use-after-free crash | 用 holder 或 EventSubscription |
| 在 Rust 同步 callback 内调 await | 编译错误 | callback 内只能 yield |
| 大对象在 FFI 反复传递 | 内存拷贝多次 | 用 ID + 按需拉详情 |
| 用 OSAllocatedUnfairLock 的旧版本 | API 不存在 | macOS 14+ 才有 |

---

## 命名约定

| 场景 | 命名 |
|---|---|
| 同步包装 async | `XxxAsync` 或 直接 async 化 |
| AsyncStream 工厂 | `xxxStream()` 或返回 `AsyncStream` |
| Bridge 类 | `XxxBridge` |
| Sink 实现 | `XxxSink` |
| 取消 token | `XxxCancellationToken` |
| 订阅句柄 | `XxxSubscription` |

---

## Related

- [core-api.md](core-api.md)
- [error-codes.md](error-codes.md)
- [../architecture/concurrency.md](../architecture/concurrency.md)
- [../development/testing.md](../development/testing.md)
- [../development/observability.md](../development/observability.md)
