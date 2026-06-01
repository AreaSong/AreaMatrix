// swiftlint:disable file_length
@testable import AreaMatrix
import XCTest

final class MainListIntegrationClosureTests: XCTestCase {
    @MainActor
    func testMultiSelectionRoutesToDetailMultiAndRefreshesSelectedDetails() async {
        let docsFile = FileEntrySnapshot.integrationClosureFixture(id: 1, currentName: "a.pdf")
        let financeFile = FileEntrySnapshot.integrationClosureFixture(id: 2, currentName: "b.pdf")
        let detailer = MainListIntegrationDetailer(results: [.success(docsFile), .success(financeFile)])
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [docsFile, financeFile]),
            fileLister: MainListIntegrationNoopLister(),
            fileDetailer: detailer,
            errorMapper: MainListIntegrationErrorMapper(mapping: .integrationClosureDbFixture())
        )

        await model.selectFiles([docsFile.id, financeFile.id])
        let detailRequests = await detailer.recordedRequests()

        XCTAssertEqual(model.selection, .multiple([docsFile.id, financeFile.id]))
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertNil(model.detailErrorMapping)
        XCTAssertEqual(detailRequests, [docsFile.id, financeFile.id])
    }

    @MainActor
    func testSingleFileContextActionsRouteToSheetsWithoutCallingControlMapOutOfScopeCore() async {
        let docsFile = FileEntrySnapshot.integrationClosureFixture(id: 7, currentName: "a.pdf")
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [docsFile]),
            fileLister: MainListIntegrationNoopLister(),
            fileDetailer: MainListIntegrationDetailer(results: [.success(docsFile)]),
            errorMapper: MainListIntegrationErrorMapper(mapping: .integrationClosureDbFixture())
        )

        await model.selectFiles([docsFile.id])
        model.beginRename()
        XCTAssertEqual(model.pendingActionDestination, .rename(fileID: docsFile.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "S1-33")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "Rename File")

        model.beginChangeCategory()
        XCTAssertEqual(model.pendingActionDestination, .changeCategory(fileID: docsFile.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "S1-35")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "Change Category")

        model.beginClassifierCorrection()
        XCTAssertEqual(
            model.pendingActionDestination,
            .changeCategory(fileID: docsFile.id, mode: .classifierCorrection)
        )
        XCTAssertEqual(model.pendingActionDestination?.pageID, "S2-16")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "Correct Classification")

        model.beginAIClassificationSuggestion()
        XCTAssertEqual(model.pendingActionDestination, .aiClassificationSuggestion(fileID: docsFile.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "S3-04")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "AI Category Suggestion")

        model.beginAIClassificationChange(fileID: docsFile.id, targetCategory: "finance/invoices")
        XCTAssertEqual(
            model.pendingActionDestination,
            .changeCategory(
                fileID: docsFile.id,
                initialTargetCategory: "finance/invoices",
                mode: .classifierCorrection
            )
        )

        model.beginDelete()
        XCTAssertEqual(model.pendingActionDestination, .delete(fileID: docsFile.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "S1-34")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "Move File to Trash?")
    }

    func testChangeCategoryTargetsComeFromCurrentTreeRows() {
        let docsFile = FileEntrySnapshot.integrationClosureFixture(id: 10, currentName: "a.pdf")
        let rows = RepositoryTreeNodeSnapshot.integrationClosureFixtureTree().sidebarRows

        XCTAssertEqual(
            MainFileActionCategoryOptions.availableCategories(file: docsFile, categoryRows: rows),
            ["docs"]
        )
        XCTAssertEqual(
            MainFileActionCategoryOptions.defaultTargetCategory(for: docsFile, categoryRows: rows),
            "docs"
        )
    }

    @MainActor
    func testMultiSelectionHidesSingleFileActionDestinations() async {
        let first = FileEntrySnapshot.integrationClosureFixture(id: 1, currentName: "a.pdf")
        let second = FileEntrySnapshot.integrationClosureFixture(id: 2, currentName: "b.pdf")
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [first, second]),
            fileLister: MainListIntegrationNoopLister(),
            fileDetailer: MainListIntegrationNoopDetailer(),
            errorMapper: MainListIntegrationErrorMapper(mapping: .integrationClosureDbFixture())
        )

        await model.selectFiles([first.id, second.id])
        model.beginRename()
        model.beginChangeCategory()
        model.beginDelete()

        XCTAssertNil(model.pendingActionDestination)
    }

    @MainActor
    func testWriteActionsAreDisabledForReadOnlyRepository() async {
        let file = FileEntrySnapshot.integrationClosureFixture(id: 3, currentName: "readonly.pdf")
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [file], isReadOnly: true),
            fileLister: MainListIntegrationNoopLister(),
            fileDetailer: MainListIntegrationDetailer(results: [.success(file)]),
            errorMapper: MainListIntegrationErrorMapper(mapping: .integrationClosureDbFixture())
        )

        await model.selectFiles([file.id])
        model.beginRename()
        model.beginChangeCategory()
        model.beginAIClassificationSuggestion()
        model.beginAIClassificationChange(fileID: file.id, targetCategory: "docs")
        model.beginDelete()

        XCTAssertEqual(model.writeActionDisabledReason(fileID: file.id), .repoReadOnly)
        XCTAssertNil(model.pendingActionDestination)
    }

    @MainActor
    func testWriteActionsAreDisabledWhileListIsLoading() async {
        let file = FileEntrySnapshot.integrationClosureFixture(id: 4, currentName: "loading.pdf")
        let lister = MainListIntegrationSuspendedLister()
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: lister,
            fileDetailer: MainListIntegrationNoopDetailer(),
            errorMapper: MainListIntegrationErrorMapper(mapping: .integrationClosureDbFixture())
        )

        let loadingTask = Task {
            await model.loadCurrentCategory("docs")
        }
        await lister.waitForRequest()
        model.beginRename(fileID: file.id)
        await lister.finish()
        await loadingTask.value

        XCTAssertNil(model.pendingActionDestination)
    }

    @MainActor
    func testWriteActionsAreDisabledForImportLockedFile() async {
        let file = FileEntrySnapshot.integrationClosureFixture(id: 8, currentName: "locked.pdf")
        let model = MainFileListModel(
            opening: .integrationClosureFixture(
                repoPath: "/tmp/repo",
                files: [file],
                writeLockedFileIDs: [file.id]
            ),
            fileLister: MainListIntegrationNoopLister(),
            fileDetailer: MainListIntegrationDetailer(results: [.success(file)]),
            errorMapper: MainListIntegrationErrorMapper(mapping: .integrationClosureDbFixture())
        )

        await model.selectFiles([file.id])
        model.beginAIClassificationSuggestion()
        model.beginDelete()

        XCTAssertEqual(model.writeActionDisabledReason(fileID: file.id), .importLocked)
        XCTAssertNil(model.pendingActionDestination)
    }

    @MainActor
    func testListDbErrorDiagnosticsCollectsCoreSnapshot() async {
        let snapshot = DiagnosticsSnapshotSnapshot(
            snapshotPath: ".areamatrix/diagnostics/main-list.zip",
            createdAt: 1_700_000_200,
            warnings: []
        )
        let collector = MainListIntegrationDiagnosticsCollector(result: .success(snapshot))
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: []),
            fileLister: MainListIntegrationNoopLister(),
            fileDetailer: MainListIntegrationNoopDetailer(),
            errorMapper: MainListIntegrationErrorMapper(mapping: .integrationClosureDbFixture()),
            diagnosticsCollector: collector
        )

        await model.collectCurrentListDiagnostics()
        let repoPaths = await collector.recordedRepoPaths()

        XCTAssertEqual(model.diagnosticsState, .collected(snapshot))
        XCTAssertEqual(repoPaths, ["/tmp/repo"])
    }

    @MainActor
    func testExternalRenameKeepsSelectionByFileIDAndRefreshesDetail() async {
        let original = FileEntrySnapshot.integrationClosureFixture(id: 5, currentName: "old.pdf")
        let renamed = FileEntrySnapshot.integrationClosureFixture(id: 5, currentName: "new.pdf")
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: MainListIntegrationNoopLister(),
            fileDetailer: MainListIntegrationDetailer(results: [.success(original)]),
            errorMapper: MainListIntegrationErrorMapper(mapping: .integrationClosureDbFixture())
        )

        await model.selectFiles([original.id])
        model.handleExternalRename(renamed)

        XCTAssertEqual(model.selection, .single(original.id))
        XCTAssertEqual(model.files, [renamed])
        XCTAssertEqual(model.selectedFileDetail, renamed)
        XCTAssertEqual(model.statusBanner, .renamedPreservedSelection(fileID: original.id))
    }

    @MainActor
    func testExternalRemovalShowsMissingDetailRecoveryInsteadOfFullRepoError() async {
        let selected = FileEntrySnapshot.integrationClosureFixture(id: 9, currentName: "gone.pdf")
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [selected]),
            fileLister: MainListIntegrationNoopLister(),
            fileDetailer: MainListIntegrationDetailer(results: [.success(selected)]),
            errorMapper: MainListIntegrationErrorMapper(mapping: .integrationClosureDbFixture())
        )

        await model.selectFiles([selected.id])
        model.handleExternalRemoval(fileID: selected.id)

        XCTAssertEqual(model.selection, .single(selected.id))
        XCTAssertEqual(model.files, [])
        var missingSelected = selected
        missingSelected.availability = .missing
        XCTAssertEqual(model.selectedFileDetail, missingSelected)
        XCTAssertEqual(model.detailErrorMapping?.kind, .fileNotFound)
        XCTAssertEqual(model.statusBanner, .removedSelectedFile(fileID: selected.id))
    }

    func testStatusDisplayCoversPageSpecStates() {
        XCTAssertEqual(
            FileEntrySnapshot.integrationClosureFixture(
                id: 1,
                currentName: "copied.pdf",
                storageMode: "Copied"
            ).statusDisplay,
            "OK"
        )
        XCTAssertEqual(
            FileEntrySnapshot.integrationClosureFixture(
                id: 2,
                currentName: "indexed.pdf",
                storageMode: "Indexed"
            ).statusDisplay,
            "Index-only"
        )
        XCTAssertEqual(
            FileEntrySnapshot.integrationClosureFixture(
                id: 3,
                currentName: "missing.pdf",
                availability: .missing
            ).statusDisplay,
            "Missing"
        )
        XCTAssertEqual(
            FileEntrySnapshot.integrationClosureFixture(
                id: 4,
                currentName: "placeholder.pdf",
                availability: .iCloudPlaceholder
            ).statusDisplay,
            "iCloud"
        )
    }

    @MainActor
    func testListLoadingExposesCurrentCategoryStageText() async {
        let file = FileEntrySnapshot.integrationClosureFixture(id: 12, currentName: "loading.pdf")
        let lister = MainListIntegrationSuspendedLister()
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: lister,
            fileDetailer: MainListIntegrationNoopDetailer(),
            errorMapper: MainListIntegrationErrorMapper(mapping: .integrationClosureDbFixture())
        )

        let loadingTask = Task { await model.loadCurrentCategory("docs") }
        await lister.waitForRequest()
        XCTAssertEqual(model.loadingStatusText, "正在加载 docs...")
        XCTAssertEqual(model.loadingAccessibilityText, "Loading files. 正在加载 docs...")
        await lister.finish()
        await loadingTask.value
    }
}

private actor MainListIntegrationNoopLister: CoreFileListing {
    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        []
    }
}

private actor MainListIntegrationSuspendedLister: CoreFileListing {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didReceiveRequest = false

    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        didReceiveRequest = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return []
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

private actor MainListIntegrationNoopDetailer: CoreFileDetailing {
    private var requests: [Int64] = []

    func getFile(repoPath _: String, fileID: Int64) async throws -> FileEntrySnapshot {
        requests.append(fileID)
        throw CoreError.FileNotFound(path: "\(fileID)")
    }

    func recordedRequests() -> [Int64] {
        requests
    }
}

private actor MainListIntegrationDetailer: CoreFileDetailing {
    enum Result {
        case success(FileEntrySnapshot)
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [Int64] = []

    init(results: [Result]) {
        self.results = results
    }

    func getFile(repoPath _: String, fileID: Int64) async throws -> FileEntrySnapshot {
        requests.append(fileID)
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

    func recordedRequests() -> [Int64] {
        requests
    }
}

private actor MainListIntegrationErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        mapping
    }
}

private actor MainListIntegrationDiagnosticsCollector: CoreDiagnosticsCollecting {
    enum Result {
        case success(DiagnosticsSnapshotSnapshot)
        case failure(Error)
    }

    private let result: Result
    private var repoPaths: [String] = []

    init(result: Result) {
        self.result = result
    }

    func createDiagnosticsSnapshot(repoPath: String) async throws -> DiagnosticsSnapshotSnapshot {
        repoPaths.append(repoPath)
        switch result {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }

    func recordedRepoPaths() -> [String] {
        repoPaths
    }
}

private extension RepositoryOpeningResult {
    static func integrationClosureFixture(
        repoPath: String,
        files: [FileEntrySnapshot],
        isReadOnly: Bool = false,
        writeLockedFileIDs: Set<Int64> = []
    ) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .integrationClosureFixture(repoPath: repoPath),
            tree: .integrationClosureFixtureTree(),
            currentCategoryFiles: files,
            isReadOnly: isReadOnly,
            writeLockedFileIDs: writeLockedFileIDs
        )
    }
}

private extension RepoConfigSnapshot {
    static func integrationClosureFixture(repoPath: String) -> RepoConfigSnapshot {
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
    static func integrationClosureFixtureTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [
                RepositoryTreeNodeSnapshot(
                    slug: "docs",
                    displayName: "docs",
                    fileCount: 2,
                    children: []
                )
            ]
        )
    }
}

private extension FileEntrySnapshot {
    static func integrationClosureFixture(
        id: Int64,
        path: String = "docs/contracts/a.pdf",
        category: String = "docs",
        currentName: String,
        storageMode: String = "Copied",
        availability: FileAvailabilitySnapshot = .available
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: path,
            originalName: currentName,
            currentName: currentName,
            category: category,
            sizeBytes: 128,
            hashSha256: "integration-closure-\(id)",
            storageMode: storageMode,
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100,
            availability: availability
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func integrationClosureDbFixture() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "当前列表不可用",
            severity: .high,
            suggestedAction: "请重试当前列表。",
            recoverability: .retryable,
            rawContext: "db locked"
        )
    }
}
