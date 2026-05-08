import XCTest
@testable import AreaMatrix

final class ChangeCategoryPageFeatureTests: XCTestCase {
    @MainActor
    func testS135C124PreviewUsesCoreBridgeWithoutMovingFile() async {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 240, name: "contract.pdf")
        let preview = MoveToCategoryPreviewSnapshot.changeCategoryFixture(
            fileID: original.id,
            targetPath: "finance/contract.pdf",
            targetName: "contract.pdf"
        )
        let mover = ChangeCategoryRecordingMover(previewResult: .success(preview))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(original)),
            fileCategoryMover: mover,
            errorMapper: DetailMetaErrorMapper(mapping: .changeCategoryClassify())
        )

        await model.selectFiles([original.id])
        model.beginChangeCategory()
        await model.loadMoveToCategoryPreview(fileID: original.id, targetCategory: "finance")
        let requests = await mover.recordedRequests()

        XCTAssertEqual(requests, [.preview(repoPath: "/tmp/repo", fileID: original.id, targetCategory: "finance")])
        XCTAssertEqual(model.files, [original])
        XCTAssertEqual(model.selectedFileDetail, original)
        XCTAssertEqual(model.pendingActionDestination, .changeCategory(fileID: original.id))
        XCTAssertEqual(
            model.changeCategoryState,
            .ready(.init(fileID: original.id, targetCategory: "finance"), preview)
        )
    }

    @MainActor
    func testS135C124SubmitMoveRefreshesListDetailAndChangeLog() async {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 241, name: "contract.pdf")
        let moved = FileEntrySnapshot.changeCategoryFixture(
            id: 241,
            path: "finance/contract.pdf",
            category: "finance",
            name: "contract.pdf",
            updatedAt: 1_700_000_400
        )
        let preview = MoveToCategoryPreviewSnapshot.changeCategoryFixture(
            fileID: original.id,
            targetPath: moved.path,
            targetName: moved.currentName
        )
        let mover = ChangeCategoryRecordingMover(previewResult: .success(preview), moveResult: .success(moved))
        let logEntry = ChangeLogEntrySnapshot.detailLogFixture(fileID: moved.id, action: "moved")
        let logLister = DetailLogRecordingLister(results: [.success([logEntry])])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(original)),
            fileCategoryMover: mover,
            changeLogLister: logLister,
            errorMapper: DetailMetaErrorMapper(mapping: .changeCategoryClassify())
        )

        await model.selectFiles([original.id])
        model.beginChangeCategory()
        await model.loadMoveToCategoryPreview(fileID: original.id, targetCategory: "finance")
        await model.submitMoveToCategory(fileID: original.id, targetCategory: "finance")
        let requests = await mover.recordedRequests()

        XCTAssertEqual(requests, [
            .preview(repoPath: "/tmp/repo", fileID: original.id, targetCategory: "finance"),
            .move(repoPath: "/tmp/repo", fileID: original.id, targetCategory: "finance"),
        ])
        XCTAssertEqual(model.files, [moved])
        XCTAssertEqual(model.selection, .single(moved.id))
        XCTAssertEqual(model.selectedFileDetail, moved)
        XCTAssertEqual(model.detailLogState, .loaded(fileID: moved.id, entries: [logEntry]))
        XCTAssertEqual(model.detailTabRequest, .automatic(.log))
        XCTAssertNil(model.pendingActionDestination)
        XCTAssertEqual(model.changeCategoryState, .idle)
        XCTAssertEqual(model.statusBanner, .changedCategory(fileID: moved.id, category: "finance"))
    }

    @MainActor
    func testS135C124SuccessfulMoveReloadsTargetCategoryAndKeepsFileHighlighted() async {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 243, name: "contract.pdf")
        let moved = FileEntrySnapshot.changeCategoryFixture(
            id: 243,
            path: "finance/contract.pdf",
            category: "finance",
            name: "contract.pdf",
            updatedAt: 1_700_000_500
        )
        let preview = MoveToCategoryPreviewSnapshot.changeCategoryFixture(
            fileID: original.id,
            targetPath: moved.path,
            targetName: moved.currentName
        )
        let mover = ChangeCategoryRecordingMover(previewResult: .success(preview), moveResult: .success(moved))
        let lister = ChangeCategoryRecordingLister(results: [.success([original]), .success([moved])])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: lister,
            fileDetailer: DetailMetaImmediateDetailer(result: .success(original)),
            fileCategoryMover: mover,
            errorMapper: DetailMetaErrorMapper(mapping: .changeCategoryClassify())
        )
        var movedCallback: FileEntrySnapshot?

        await model.loadCurrentCategory("docs")
        await model.selectFiles([original.id])
        model.beginChangeCategory()
        await model.loadMoveToCategoryPreview(fileID: original.id, targetCategory: "finance")
        await model.submitMoveToCategory(fileID: original.id, targetCategory: "finance") { movedFile in
            movedCallback = movedFile
        }
        await model.loadCurrentCategory(moved.category, focusingOn: moved.id)
        let listRequests = await lister.recordedRequests()

        XCTAssertEqual(movedCallback, moved)
        XCTAssertEqual(listRequests, [
            FileFilterSnapshot.currentCategory("docs"),
            FileFilterSnapshot.currentCategory("finance"),
        ])
        XCTAssertEqual(model.files, [moved])
        XCTAssertEqual(model.selection, .single(moved.id))
        XCTAssertEqual(model.selectedFileDetail, moved)
    }

    @MainActor
    func testS135C124ContentRefreshUpdatesTreeAndSwitchesToMovedCategory() async {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 244, name: "contract.pdf")
        let moved = FileEntrySnapshot.changeCategoryFixture(
            id: 244,
            path: "finance/contract.pdf",
            category: "finance",
            name: "contract.pdf",
            updatedAt: 1_700_000_600
        )
        let plan = MainRepositoryContentCategoryMoveRefreshPlan.make(
            movedFile: moved,
            currentSidebarID: "docs",
            currentTree: .changeCategoryTree(docsCount: 1, financeCount: 0),
            refreshedTree: .changeCategoryTree(docsCount: 0, financeCount: 1)
        )

        XCTAssertEqual(plan.tree.sidebarRow(id: "docs")?.totalFileCount, 0)
        XCTAssertEqual(plan.tree.sidebarRow(id: "finance")?.totalFileCount, 1)
        XCTAssertEqual(plan.selectedSidebarID, "finance")
        XCTAssertEqual(plan.focusedFileID, moved.id)
        XCTAssertEqual(plan.categoryForFileList, "finance")
    }

    @MainActor
    func testS135C124FailureKeepsSheetOpenAndMapsCoreError() async {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 242, name: "blocked.pdf")
        let mapping = CoreErrorMappingSnapshot.changeCategoryClassify()
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let mover = ChangeCategoryRecordingMover(
            previewResult: .failure(CoreError.Classify(reason: "unknown category"))
        )
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(original)),
            fileCategoryMover: mover,
            errorMapper: mapper
        )

        await model.selectFiles([original.id])
        model.beginChangeCategory()
        await model.loadMoveToCategoryPreview(fileID: original.id, targetCategory: "finance")
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(model.files, [original])
        XCTAssertEqual(model.selectedFileDetail, original)
        XCTAssertEqual(model.pendingActionDestination, .changeCategory(fileID: original.id))
        XCTAssertEqual(
            model.changeCategoryState,
            .failed(.init(fileID: original.id, targetCategory: "finance"), operation: .preview, mapping)
        )
        XCTAssertEqual(mappedErrors, [CoreError.Classify(reason: "unknown category")])
    }

    func testS135C124DefaultCoreBridgePreviewsThenMovesCopiedFileAndWritesChangeLog() async throws {
        let repoURL = try makeChangeCategoryTemporaryDirectory(prefix: "repo")
        let sourceRoot = try makeChangeCategoryTemporaryDirectory(prefix: "source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let sourceURL = sourceRoot.appendingPathComponent("contract.pdf")
        try Data("category bytes".utf8).write(to: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let imported = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: "contract.pdf",
            duplicateStrategy: .skip
        )
        let preview = try await bridge.previewMoveToCategory(
            repoPath: repoURL.path,
            fileID: imported.id,
            newCategory: "finance"
        )
        let moved = try await bridge.moveToCategory(repoPath: repoURL.path, fileID: imported.id, newCategory: "finance")
        let detail = try await bridge.getFile(repoPath: repoURL.path, fileID: imported.id)
        let changes = try await bridge.listChanges(repoPath: repoURL.path, filter: .detailLog(fileID: imported.id))

        XCTAssertEqual(preview.fileID, imported.id)
        XCTAssertEqual(preview.fromCategory, "docs")
        XCTAssertEqual(preview.toCategory, "finance")
        XCTAssertEqual(preview.targetPath, "finance/contract.pdf")
        XCTAssertEqual(moved.id, imported.id)
        XCTAssertEqual(moved.category, "finance")
        XCTAssertEqual(detail.path, "finance/contract.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("finance/contract.pdf").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("docs/contract.pdf").path))
        XCTAssertTrue(changes.contains { $0.action == "moved" })
    }
}

private enum ChangeCategoryRequest: Equatable, Sendable {
    case preview(repoPath: String, fileID: Int64, targetCategory: String)
    case move(repoPath: String, fileID: Int64, targetCategory: String)
}

private struct ChangeCategoryTreeRequest: Equatable, Sendable {
    var repoPath: String
    var locale: String
}

private actor ChangeCategoryRecordingMover: CoreFileCategoryMoving {
    private let previewResult: Result<MoveToCategoryPreviewSnapshot, Error>
    private let moveResult: Result<FileEntrySnapshot, Error>
    private var requests: [ChangeCategoryRequest] = []

    init(
        previewResult: Result<MoveToCategoryPreviewSnapshot, Error>,
        moveResult: Result<FileEntrySnapshot, Error> = .failure(CoreError.Internal(message: "unexpected move"))
    ) {
        self.previewResult = previewResult
        self.moveResult = moveResult
    }

    func previewMoveToCategory(
        repoPath: String,
        fileID: Int64,
        newCategory: String
    ) async throws -> MoveToCategoryPreviewSnapshot {
        requests.append(.preview(repoPath: repoPath, fileID: fileID, targetCategory: newCategory))
        return try previewResult.get()
    }

    func moveToCategory(repoPath: String, fileID: Int64, newCategory: String) async throws -> FileEntrySnapshot {
        requests.append(.move(repoPath: repoPath, fileID: fileID, targetCategory: newCategory))
        return try moveResult.get()
    }

    func recordedRequests() -> [ChangeCategoryRequest] { requests }
}

private actor ChangeCategoryRecordingLister: CoreFileListing {
    enum Result {
        case success([FileEntrySnapshot])
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [FileFilterSnapshot] = []

    init(results: [Result]) {
        self.results = results
    }

    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        requests.append(filter)
        guard !results.isEmpty else { return [] }

        switch results.removeFirst() {
        case .success(let files):
            return files
        case .failure(let error):
            throw error
        }
    }

    func recordedRequests() -> [FileFilterSnapshot] { requests }
}

private actor ChangeCategoryTreeLister: CoreRepositoryTreeListing {
    private let result: Result<RepositoryTreeNodeSnapshot, Error>
    private var requests: [ChangeCategoryTreeRequest] = []

    init(result: Result<RepositoryTreeNodeSnapshot, Error>) {
        self.result = result
    }

    func listTree(repoPath: String, locale: String) async throws -> RepositoryTreeNodeSnapshot {
        requests.append(ChangeCategoryTreeRequest(repoPath: repoPath, locale: locale))
        return try result.get()
    }

    func recordedRequests() -> [ChangeCategoryTreeRequest] { requests }
}

private extension FileEntrySnapshot {
    static func changeCategoryFixture(
        id: Int64,
        path: String = "docs/contracts/contract.pdf",
        category: String = "docs",
        name: String,
        updatedAt: Int64 = 1_700_000_100
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: path,
            originalName: name,
            currentName: name,
            category: category,
            sizeBytes: 512,
            hashSha256: "change-category-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: updatedAt
        )
    }
}

private extension RepositoryOpeningResult {
    static func changeCategoryOpening(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        var opening = RepositoryOpeningResult.detailMetaFixture(repoPath: repoPath, files: files)
        opening.tree = .changeCategoryTree(docsCount: Int64(files.count), financeCount: 0)
        return opening
    }
}

private extension RepositoryTreeNodeSnapshot {
    static func changeCategoryTree(docsCount: Int64, financeCount: Int64) -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [
                RepositoryTreeNodeSnapshot(slug: "docs", displayName: "docs", fileCount: docsCount, children: []),
                RepositoryTreeNodeSnapshot(slug: "finance", displayName: "finance", fileCount: financeCount, children: []),
            ]
        )
    }
}

private extension MoveToCategoryPreviewSnapshot {
    static func changeCategoryFixture(
        fileID: Int64,
        targetPath: String,
        targetName: String,
        indexOnly: Bool = false
    ) -> MoveToCategoryPreviewSnapshot {
        MoveToCategoryPreviewSnapshot(
            fileID: fileID,
            fromCategory: "docs",
            toCategory: "finance",
            currentPath: "docs/contracts/\(targetName)",
            targetPath: targetPath,
            targetName: targetName,
            storageMode: indexOnly ? "Indexed" : "Copied",
            indexOnly: indexOnly,
            nameConflictResolved: false,
            willMoveFile: !indexOnly
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func changeCategoryClassify() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .classify,
            userMessage: "Target category is unavailable.",
            severity: .medium,
            suggestedAction: "Choose another category, then retry.",
            recoverability: .userActionRequired,
            rawContext: "S1-35 C1-24 preview_move_to_category"
        )
    }
}

private func makeChangeCategoryTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixChangeCategory-\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
