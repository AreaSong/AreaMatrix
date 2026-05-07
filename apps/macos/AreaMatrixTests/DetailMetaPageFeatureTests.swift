import XCTest
@testable import AreaMatrix

final class DetailMetaPageFeatureTests: XCTestCase {
    @MainActor
    func testS112ShowsCachedMetadataImmediatelyBeforeC112RefreshCompletes() async {
        let cached = FileEntrySnapshot.detailMetaFixture(id: 12, currentName: "cached.pdf")
        let refreshed = FileEntrySnapshot.detailMetaFixture(id: 12, currentName: "refreshed.pdf")
        let detailer = DetailMetaSuspendedDetailer(result: .success(refreshed))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [cached]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: detailer,
            errorMapper: DetailMetaErrorMapper(mapping: .detailMetaFileNotFound())
        )

        let selectionTask = Task { await model.selectFiles([cached.id]) }
        await detailer.waitForRequest()

        XCTAssertEqual(model.selection, .single(cached.id))
        XCTAssertEqual(model.selectedFileDetail, cached)
        XCTAssertTrue(model.isDetailLoading)

        await detailer.finish()
        await selectionTask.value

        XCTAssertEqual(model.selectedFileDetail, refreshed)
        XCTAssertEqual(model.files, [refreshed])
        XCTAssertFalse(model.isDetailLoading)
        XCTAssertNil(model.detailErrorMapping)
    }

    @MainActor
    func testS112KeepsCachedSummaryWhenC112GetFileFails() async {
        let cached = FileEntrySnapshot.detailMetaFixture(id: 13, currentName: "missing.pdf")
        let mapping = CoreErrorMappingSnapshot.detailMetaFileNotFound()
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [cached]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .failure(CoreError.FileNotFound(path: cached.path))),
            errorMapper: mapper
        )

        await model.selectFiles([cached.id])
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(model.selectedFileDetail, cached)
        XCTAssertEqual(model.detailErrorMapping, mapping)
        XCTAssertEqual(mappedErrors, [CoreError.FileNotFound(path: cached.path)])
        XCTAssertFalse(model.isDetailLoading)
    }

    func testS112MetadataRowsIncludeC112SourceAndStatus() {
        let indexed = FileEntrySnapshot.detailMetaFixture(
            id: 14,
            currentName: "indexed.pdf",
            storageMode: "Indexed",
            sourcePath: "~/Downloads/indexed.pdf"
        )

        let rows = detailMetaMetadataRows(for: indexed)

        XCTAssertEqual(rows.value(for: "Source"), "~/Downloads/indexed.pdf")
        XCTAssertEqual(rows.value(for: "Status"), "Index-only")
    }

    func testS112MetadataRowsUseFallbackForMissingC112Source() {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 15, currentName: "no-source.pdf", sourcePath: nil)

        XCTAssertEqual(detailMetaMetadataRows(for: detail).value(for: "Source"), "Not available")
    }

    @MainActor
    func testS113LoadsSelectedFileChangeLogThroughC113ListChanges() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 16, currentName: "logged.pdf")
        let entry = ChangeLogEntrySnapshot.detailLogFixture(fileID: detail.id, action: "imported")
        let lister = DetailLogRecordingLister(results: [.success([entry])])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            changeLogLister: lister,
            errorMapper: DetailMetaErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([detail.id])
        await model.loadSelectedFileChangeLog()
        let requests = await lister.recordedRequests()

        XCTAssertEqual(requests, [
            DetailLogRequest(repoPath: "/tmp/repo", filter: .detailLog(fileID: detail.id)),
        ])
        XCTAssertEqual(model.detailLogState, .loaded(fileID: detail.id, entries: [entry]))
    }

    @MainActor
    func testS113MapsListChangesFailureInline() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 17, currentName: "locked.pdf")
        let mapping = CoreErrorMappingSnapshot.detailLogDb()
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            changeLogLister: DetailLogRecordingLister(results: [.failure(CoreError.Db(message: "change log locked"))]),
            errorMapper: mapper
        )

        await model.selectFiles([detail.id])
        await model.loadSelectedFileChangeLog()
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(model.detailLogState, .failed(fileID: detail.id, mapping))
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "change log locked")])
    }

    @MainActor
    func testS113StaleChangeLogRequestDoesNotOverwriteNewSelection() async {
        let oldFile = FileEntrySnapshot.detailMetaFixture(id: 18, currentName: "old.pdf")
        let newFile = FileEntrySnapshot.detailMetaFixture(id: 19, currentName: "new.pdf")
        let lister = DetailLogSuspendedLister(entries: [
            ChangeLogEntrySnapshot.detailLogFixture(fileID: oldFile.id, action: "imported"),
        ])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [oldFile, newFile]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaSequenceDetailer(results: [.success(oldFile), .success(newFile)]),
            changeLogLister: lister,
            errorMapper: DetailMetaErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([oldFile.id])
        let loadTask = Task { await model.loadSelectedFileChangeLog() }
        await lister.waitForRequest()
        await model.selectFiles([newFile.id])
        await lister.finish()
        await loadTask.value

        XCTAssertEqual(model.selection, .single(newFile.id))
        XCTAssertEqual(model.detailLogState, .notLoaded)
    }

    @MainActor
    func testS113DetailLogDiagnosticsRequiresPrivacyConfirmationAndCollectsCoreSnapshot() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 20, currentName: "diagnostics.pdf")
        let mapping = CoreErrorMappingSnapshot.detailLogDb()
        let snapshot = DiagnosticsSnapshotSnapshot(
            snapshotPath: "/tmp/repo/.areamatrix/diagnostics/detail-log.zip",
            createdAt: 1_700_000_300,
            warnings: ["paths redacted", "usernames redacted"]
        )
        let diagnosticsCollector = ShellRecordingDiagnosticsCollector(result: .success(snapshot))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            changeLogLister: DetailLogRecordingLister(results: [.failure(CoreError.Db(message: "change log locked"))]),
            errorMapper: DetailMetaErrorMapper(mapping: mapping),
            diagnosticsCollector: diagnosticsCollector
        )

        await model.selectFiles([detail.id])
        await model.loadSelectedFileChangeLog()
        await model.collectDetailLogDiagnostics()
        let preConfirmationPaths = await diagnosticsCollector.requestedRepoPaths()

        XCTAssertEqual(preConfirmationPaths, [])
        XCTAssertEqual(model.detailLogDiagnosticsState, .idle)

        model.requestDetailLogDiagnosticsPrivacyConfirmation()
        await model.collectDetailLogDiagnostics()
        let collectedPaths = await diagnosticsCollector.requestedRepoPaths()

        XCTAssertEqual(collectedPaths, ["/tmp/repo"])
        XCTAssertEqual(model.detailLogDiagnosticsState, .collected(fileID: detail.id, snapshot))
    }

    @MainActor
    func testS113DetailLogDiagnosticsFailureMapsCoreErrorInline() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 21, currentName: "diagnostics-fail.pdf")
        let mapping = CoreErrorMappingSnapshot.detailLogDb()
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let diagnosticsCollector = ShellRecordingDiagnosticsCollector(
            result: .failure(CoreError.PermissionDenied(path: "/tmp/repo"))
        )
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            changeLogLister: DetailLogRecordingLister(results: [.failure(CoreError.Db(message: "change log locked"))]),
            errorMapper: mapper,
            diagnosticsCollector: diagnosticsCollector
        )

        await model.selectFiles([detail.id])
        await model.loadSelectedFileChangeLog()
        model.requestDetailLogDiagnosticsPrivacyConfirmation()
        await model.collectDetailLogDiagnostics()
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(model.detailLogDiagnosticsState, .failed(fileID: detail.id, mapping))
        XCTAssertEqual(mappedErrors, [
            CoreError.Db(message: "change log locked"),
            CoreError.PermissionDenied(path: "/tmp/repo"),
        ])
    }

}

actor DetailMetaNoopLister: CoreFileListing {
    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        []
    }
}

private actor DetailMetaNoopDetailer: CoreFileDetailing {
    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        throw CoreError.FileNotFound(path: "\(fileID)")
    }
}

actor DetailMetaImmediateDetailer: CoreFileDetailing {
    enum Result {
        case success(FileEntrySnapshot)
        case failure(Error)
    }

    private let result: Result

    init(result: Result) {
        self.result = result
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        switch result {
        case .success(let file):
            return file
        case .failure(let error):
            throw error
        }
    }
}

private actor DetailMetaSuspendedDetailer: CoreFileDetailing {
    typealias Result = DetailMetaImmediateDetailer.Result

    private let result: Result
    private var continuation: CheckedContinuation<Void, Never>?
    private var didReceiveRequest = false

    init(result: Result) {
        self.result = result
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        didReceiveRequest = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        switch result {
        case .success(let file):
            return file
        case .failure(let error):
            throw error
        }
    }

    func waitForRequest() async {
        while !didReceiveRequest {
            await Task.yield()
        }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

private actor DetailMetaSequenceDetailer: CoreFileDetailing {
    typealias Result = DetailMetaImmediateDetailer.Result

    private var results: [Result]

    init(results: [Result]) {
        self.results = results
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        guard !results.isEmpty else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }

        switch results.removeFirst() {
        case .success(let file):
            return file
        case .failure(let error):
            throw error
        }
    }
}

actor DetailMetaErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private var errors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping
    }

    func recordedErrors() -> [CoreError] { errors }
}

struct DetailLogRequest: Equatable {
    var repoPath: String
    var filter: ChangeFilterSnapshot
}

actor DetailLogRecordingLister: CoreChangeLogListing {
    enum Result {
        case success([ChangeLogEntrySnapshot])
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [DetailLogRequest] = []

    init(results: [Result]) {
        self.results = results
    }

    func listChanges(repoPath: String, filter: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        requests.append(DetailLogRequest(repoPath: repoPath, filter: filter))
        guard !results.isEmpty else { return [] }

        switch results.removeFirst() {
        case .success(let entries):
            return entries
        case .failure(let error):
            throw error
        }
    }

    func recordedRequests() -> [DetailLogRequest] { requests }
}

private actor DetailLogSuspendedLister: CoreChangeLogListing {
    private let entries: [ChangeLogEntrySnapshot]
    private var continuation: CheckedContinuation<Void, Never>?
    private var didReceiveRequest = false

    init(entries: [ChangeLogEntrySnapshot]) {
        self.entries = entries
    }

    func listChanges(repoPath: String, filter: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        didReceiveRequest = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return entries
    }

    func waitForRequest() async {
        while !didReceiveRequest {
            await Task.yield()
        }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

extension RepositoryOpeningResult {
    static func detailMetaFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: RepoConfigSnapshot(
                repoPath: repoPath,
                defaultMode: "Copied",
                overviewOutput: "GeneratedOnly",
                aiEnabled: false,
                locale: "zh-Hans",
                iCloudWarn: true,
                enableExtensionRules: true,
                enableKeywordRules: true,
                fallbackToInbox: true,
                allowReplaceDuringImport: false
            ),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "Repository",
                fileCount: Int64(files.count),
                children: []
            ),
            currentCategoryFiles: files
        )
    }
}

extension FileEntrySnapshot {
    static func detailMetaFixture(
        id: Int64,
        currentName: String,
        storageMode: String = "Copied",
        sourcePath: String? = "~/Downloads/source.pdf"
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/contracts/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 256,
            hashSha256: "detail-meta-\(id)",
            storageMode: storageMode,
            origin: "Imported",
            sourcePath: sourcePath,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

extension ChangeLogEntrySnapshot {
    static func detailLogFixture(fileID: Int64, action: String) -> ChangeLogEntrySnapshot {
        ChangeLogEntrySnapshot(
            id: fileID + 100,
            fileID: fileID,
            filename: "logged.pdf",
            category: "docs",
            action: action,
            detailJSON: #"{"changed":"modified_at"}"#,
            occurredAt: 1_700_000_200
        )
    }
}

private extension [DetailMetaMetadataRow] {
    func value(for label: String) -> String? {
        first { $0.label == label }?.value
    }
}

extension CoreErrorMappingSnapshot {
    static func detailMetaFileNotFound() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .fileNotFound,
            userMessage: "文件不存在",
            severity: .medium,
            suggestedAction: "刷新当前列表，确认文件是否已被移动或删除。",
            recoverability: .refreshRequired,
            rawContext: "S1-12 C1-12 get_file"
        )
    }

    static func detailLogDb() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "无法加载改动记录",
            severity: .medium,
            suggestedAction: "请重试改动时间线。",
            recoverability: .retryable,
            rawContext: "S1-13 C1-13 list_changes"
        )
    }

}
