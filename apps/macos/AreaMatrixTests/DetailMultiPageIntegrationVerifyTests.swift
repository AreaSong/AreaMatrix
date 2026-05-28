@testable import AreaMatrix
import XCTest

final class DetailMultiPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS209C207LoadsActionLogExecutesUndoAndBlocksUnsafeAction() async {
        let action = UndoActionRecordSnapshot.s209PendingBatchAddTags()
        var blockedAction = action
        blockedAction.status = .blocked
        blockedAction.canUndo = false
        blockedAction.disabledReason = "External change prevents undo."
        let undoStore = S209RecordingUndoStore(results: [
            .list(.success([action])),
            .undo(.success(.s209ExecutedBatchAddTags())),
            .list(.success([blockedAction]))
        ])
        let mapper = S115ErrorMapper(mapping: .s209UndoFailure())
        let load = await BatchTagUndoAction.loadAction(
            repoPath: "/tmp/repo",
            undoToken: action.actionID,
            undoStore: undoStore,
            errorMapper: mapper
        )
        let applied = await BatchTagUndoAction.undo(
            repoPath: "/tmp/repo",
            action: action,
            undoStore: undoStore,
            errorMapper: mapper
        )
        let blockedLoad = await BatchTagUndoAction.loadAction(
            repoPath: "/tmp/repo",
            undoToken: blockedAction.actionID,
            undoStore: undoStore,
            errorMapper: mapper
        )

        XCTAssertEqual(load.action, action)
        XCTAssertEqual(applied.result, .s209ExecutedBatchAddTags())
        XCTAssertEqual(blockedLoad.unavailableReason, "External change prevents undo.")
        let listRequests = await undoStore.listRequests()
        let undoRequests = await undoStore.undoRequests()
        XCTAssertEqual(listRequests, ["/tmp/repo", "/tmp/repo"])
        XCTAssertEqual(undoRequests, ["/tmp/repo|\(action.actionID)"])
    }

    @MainActor
    func testS209C207MapsUndoFailureWithoutMockingSuccess() async {
        let action = UndoActionRecordSnapshot.s209PendingBatchAddTags()
        let undoStore =
            S209RecordingUndoStore(results: [.undo(.failure(CoreError.Conflict(path: "docs/contract.pdf")))])
        let applied = await BatchTagUndoAction.undo(
            repoPath: "/tmp/repo",
            action: action,
            undoStore: undoStore,
            errorMapper: S115ErrorMapper(mapping: .s209UndoFailure())
        )

        XCTAssertNil(applied.result)
        XCTAssertEqual(applied.failure, .s209UndoFailure())
        let undoRequests = await undoStore.undoRequests()
        XCTAssertEqual(undoRequests, ["/tmp/repo|\(action.actionID)"])
    }

    @MainActor
    func testS209C207ApplyCompletionHandsUndoActionToMainWindowToast() async {
        let action = UndoActionRecordSnapshot.s209PendingBatchAddTags()
        let undoStore = S209RecordingUndoStore(results: [.list(.success([action]))])
        let completion = await BatchTagUndoAction.completionAfterBatchApply(
            repoPath: "/tmp/repo",
            report: .s209BatchAddTagsReport(),
            failure: nil,
            undoStore: undoStore,
            errorMapper: S115ErrorMapper(mapping: .s209UndoFailure())
        )

        XCTAssertEqual(completion.undoState, .ready(action))
        XCTAssertTrue(completion.closesSheet)
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(listRequests, ["/tmp/repo"])
    }

    @MainActor
    func testS209C207UndoRefreshTargetsDriveVisibleRefreshes() async {
        let action = UndoActionRecordSnapshot.s209PendingBatchAddTags()
        let undoStore = S209RecordingUndoStore(results: [
            .undo(.success(.s209ExecutedBatchAddTags())),
            .list(.success([.s209ExecutedActionLogRow()]))
        ])
        let applied = await BatchTagUndoAction.undo(
            repoPath: "/tmp/repo",
            action: action,
            undoStore: undoStore,
            errorMapper: S115ErrorMapper(mapping: .s209UndoFailure())
        )
        guard let result = applied.result else {
            return XCTFail("expected undo_action to return refresh_targets")
        }
        let plan = BatchTagUndoRefreshPlan(refreshTargets: result.refreshTargets)
        let refreshed = await BatchTagUndoAction.refreshActionLog(
            repoPath: "/tmp/repo",
            actionID: result.actionID,
            undoStore: undoStore,
            errorMapper: S115ErrorMapper(mapping: .s209UndoFailure())
        )

        XCTAssertTrue(plan.refreshesSelectionDetails)
        XCTAssertTrue(plan.refreshesChangeLog)
        XCTAssertTrue(plan.refreshesUndoActions)
        XCTAssertEqual(refreshed.action, .s209ExecutedActionLogRow())
        let undoRequests = await undoStore.undoRequests()
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(undoRequests, ["/tmp/repo|\(action.actionID)"])
        XCTAssertEqual(listRequests, ["/tmp/repo"])
    }

    @MainActor
    func testS115PageIntegrationUsesRealC111AndC112CoreBridgeForMultiSelection() async throws {
        let repoURL = try makeS115TemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let docsURL = repoURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        try "contract".write(to: docsURL.appendingPathComponent("contract.pdf"), atomically: true, encoding: .utf8)
        try "notes".write(to: docsURL.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        let bridge = CoreBridge()
        try await bridge.adoptExistingRepository(repoPath: repoURL.path)
        let config = try await bridge.loadConfig(repoPath: repoURL.path)
        let tree = try await bridge.listTree(repoPath: repoURL.path, locale: "zh-Hans")
        let model = MainFileListModel(
            opening: RepositoryOpeningResult(config: config, tree: tree, currentCategoryFiles: []),
            fileLister: bridge,
            fileDetailer: bridge,
            errorMapper: bridge
        )

        await model.loadCurrentCategory("docs")
        let selectedIDs = Set(model.files.map(\.id))
        await model.selectFiles(selectedIDs)
        let summary = MultiSelectionDetailSummary(selection: model.selection, files: model.files)

        XCTAssertEqual(selectedIDs.count, 2)
        XCTAssertEqual(model.selection, .multiple(selectedIDs))
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertNil(model.selectedFileNoteWriteBlock)
        XCTAssertNil(model.detailErrorMapping)
        XCTAssertEqual(model.detailLogState, .notLoaded)
        XCTAssertFalse(model.isDetailLoading)
        XCTAssertEqual(summary.selectedCount, 2)
        XCTAssertEqual(summary.unresolvedMetadataCount, 0)
        XCTAssertFalse(summary.warningMessages.contains("部分选中项无法读取元数据"))
        XCTAssertEqual(summary.fileTypeRows.map(\.label).sorted(), ["Markdown", "PDF"])
    }

    @MainActor
    func testS115PageIntegrationExitsToSingleAndEmptyWithoutBatchWriteActions() async {
        let first = FileEntrySnapshot.s115Fixture(id: 1, currentName: "a.pdf")
        let second = FileEntrySnapshot.s115Fixture(id: 2, currentName: "b.pdf")
        let detailer = S115SequenceDetailer(results: [
            .success(first),
            .success(second),
            .success(second)
        ])
        let model = MainFileListModel(
            opening: .s115Fixture(repoPath: "/tmp/repo", files: [first, second]),
            fileLister: S115NoopLister(),
            fileDetailer: detailer,
            errorMapper: S115ErrorMapper(mapping: .s115DbMapping())
        )

        await model.selectFiles([first.id, second.id])
        model.beginRename()
        model.beginChangeCategory()
        model.beginDelete()

        XCTAssertEqual(model.selection, .multiple([first.id, second.id]))
        XCTAssertNil(model.pendingActionDestination)
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertNil(model.selectedFileNoteWriteBlock)
        XCTAssertEqual(model.detailLogState, .notLoaded)

        await model.selectFiles([second.id])
        XCTAssertEqual(model.selection, .single(second.id))
        XCTAssertEqual(model.selectedFileDetail, second)

        await model.selectFiles([])
        XCTAssertEqual(model.selection, .none)
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertNil(model.detailErrorMapping)
        XCTAssertEqual(model.detailLogState, .notLoaded)
    }

    @MainActor
    func testS115PageIntegrationKeepsCopyPathsAvailableOnPartialC112Failure() async {
        let available = FileEntrySnapshot.s115Fixture(id: 10, currentName: "available.pdf")
        let stale = FileEntrySnapshot.s115Fixture(id: 11, currentName: "stale.pdf")
        let mapping = CoreErrorMappingSnapshot.s115FileNotFoundMapping()
        let model = MainFileListModel(
            opening: .s115Fixture(repoPath: "/tmp/repo", files: [available, stale]),
            fileLister: S115NoopLister(),
            fileDetailer: S115SequenceDetailer(results: [
                .success(available),
                .failure(CoreError.FileNotFound(path: stale.path))
            ]),
            errorMapper: S115ErrorMapper(mapping: mapping)
        )

        await model.selectFiles([available.id, stale.id])
        let summary = MultiSelectionDetailSummary(selection: model.selection, files: model.files)
        let copier = ShellRecordingPathCopier()
        let announcer = S117RecordingAccessibilityAnnouncer()
        let shell = OnboardingModel(
            pathCopier: copier,
            accessibilityAnnouncer: announcer
        )
        shell.copyMainListPaths(
            opening: .s115Fixture(repoPath: "/tmp/repo", files: model.files),
            relativePaths: summary.paths
        )

        XCTAssertEqual(model.selection, .multiple([available.id, stale.id]))
        XCTAssertEqual(model.detailErrorMapping, mapping)
        XCTAssertEqual(summary.paths, [available.path, stale.path])
        XCTAssertEqual(copier.multiPathRequests.map(\.relativePaths), [[available.path, stale.path]])
        XCTAssertEqual(shell.toastMessage, "2 paths copied.")
        XCTAssertEqual(announcer.announcements, ["2 paths copied."])
    }
}

private actor S115NoopLister: CoreFileListing {
    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        []
    }
}

private actor S115SequenceDetailer: CoreFileDetailing {
    enum Result {
        case success(FileEntrySnapshot)
        case failure(Error)
    }

    private var results: [Result]

    init(results: [Result]) {
        self.results = results
    }

    func getFile(repoPath _: String, fileID: Int64) async throws -> FileEntrySnapshot {
        guard !results.isEmpty else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }

        switch results.removeFirst() {
        case let .success(file):
            return file
        case let .failure(error):
            throw error
        }
    }
}

private actor S115ErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        mapping
    }
}

private extension RepositoryOpeningResult {
    static func s115Fixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .s115Fixture(repoPath: repoPath),
            tree: .s115TreeFixture(fileCount: Int64(files.count)),
            currentCategoryFiles: files
        )
    }
}

private extension RepoConfigSnapshot {
    static func s115Fixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
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
        )
    }
}

private extension RepositoryTreeNodeSnapshot {
    static func s115TreeFixture(fileCount: Int64) -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            fileCount: fileCount,
            children: [
                RepositoryTreeNodeSnapshot(slug: "docs", displayName: "docs", fileCount: fileCount, children: [])
            ]
        )
    }
}

private extension FileEntrySnapshot {
    static func s115Fixture(id: Int64, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 128,
            hashSha256: "s115-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func s209UndoFailure() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: "无法撤销批量标签操作",
            severity: .medium,
            suggestedAction: "打开 Undo 历史查看阻塞原因。",
            recoverability: .refreshRequired,
            rawContext: "S2-09 C2-07 undo_action"
        )
    }

    static func s115DbMapping() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "当前列表不可用",
            severity: .high,
            suggestedAction: "请重试当前列表。",
            recoverability: .retryable,
            rawContext: "S1-15 C1-11 list_files"
        )
    }

    static func s115FileNotFoundMapping() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .fileNotFound,
            userMessage: "部分选中项无法读取元数据",
            severity: .medium,
            suggestedAction: "刷新当前选择，确认文件是否仍在资料库中。",
            recoverability: .refreshRequired,
            rawContext: "S1-15 C1-12 get_file"
        )
    }
}

private extension UndoActionRecordSnapshot {
    static func s209PendingBatchAddTags() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-c2-07",
            kind: "batch_add_tags",
            summary: "Added urgent to 2 files.",
            affectedCount: 3,
            affectedFileNames: ["contract.pdf", "notes.md"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_400,
            updatedAt: 1_700_000_400
        )
    }

    static func s209ExecutedActionLogRow() -> UndoActionRecordSnapshot {
        var action = s209PendingBatchAddTags()
        action.status = .executed
        action.canUndo = false
        action.updatedAt = 1_700_000_420
        return action
    }
}

private extension UndoActionResultSnapshot {
    static func s209ExecutedBatchAddTags() -> UndoActionResultSnapshot {
        UndoActionResultSnapshot(
            actionID: "undo-c2-07",
            status: .executed,
            summary: "Undone: added urgent to 2 files.",
            affectedCount: 3,
            refreshTargets: ["tags", "change_log", "undo_actions"],
            completedAt: 1_700_000_420
        )
    }
}

private extension BatchMutationReportSnapshot {
    static func s209BatchAddTagsReport() -> BatchMutationReportSnapshot {
        BatchMutationReportSnapshot(
            requestedFileCount: 2,
            requestedTagCount: 1,
            addedCount: 2,
            skippedCount: 0,
            failedCount: 0,
            itemResults: [
                BatchMutationItemResultSnapshot(fileID: 1, tag: "urgent", status: .added, error: nil),
                BatchMutationItemResultSnapshot(fileID: 2, tag: "urgent", status: .added, error: nil)
            ],
            undoToken: "undo-c2-07"
        )
    }
}

private actor S209RecordingUndoStore: CoreUndoActionLogging {
    enum Result { case list(Swift.Result<[UndoActionRecordSnapshot], Error>), undo(Swift.Result<
        UndoActionResultSnapshot,
        Error
    >) }

    private var results: [Result]
    private var recordedListRequests: [String] = []
    private var recordedUndoRequests: [String] = []

    init(results: [Result]) {
        self.results = results
    }

    func listUndoActions(repoPath: String) async throws -> [UndoActionRecordSnapshot] {
        recordedListRequests.append(repoPath)
        guard case let .list(result) = try consumeResult() else {
            throw CoreError.Internal(message: "expected list_undo_actions before undo_action")
        }
        return try result.get()
    }

    func undoAction(repoPath: String, actionID: String) async throws -> UndoActionResultSnapshot {
        recordedUndoRequests.append("\(repoPath)|\(actionID)")
        guard case let .undo(result) = try consumeResult() else {
            throw CoreError.Internal(message: "expected undo_action result")
        }
        return try result.get()
    }

    func listRequests() -> [String] {
        recordedListRequests
    }

    func undoRequests() -> [String] {
        recordedUndoRequests
    }

    private func consumeResult() throws -> Result {
        guard !results.isEmpty else { throw CoreError.Db(message: "missing undo action result") }
        return results.removeFirst()
    }
}

private func makeS115TemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixS115Integration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
