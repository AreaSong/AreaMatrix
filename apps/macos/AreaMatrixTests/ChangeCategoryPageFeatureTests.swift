@testable import AreaMatrix
import XCTest

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
        let didMove = await model.submitMoveToCategory(fileID: original.id, targetCategory: "finance")
        let requests = await mover.recordedRequests()

        XCTAssertTrue(didMove)
        XCTAssertEqual(requests, [
            .preview(repoPath: "/tmp/repo", fileID: original.id, targetCategory: "finance"),
            .move(repoPath: "/tmp/repo", fileID: original.id, targetCategory: "finance")
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
        let didMove = await model.submitMoveToCategory(fileID: original.id, targetCategory: "finance") { movedFile in
            movedCallback = movedFile
        }
        await model.loadCurrentCategory(moved.category, focusingOn: moved.id)
        let listRequests = await lister.recordedRequests()

        XCTAssertTrue(didMove)
        XCTAssertEqual(movedCallback, moved)
        XCTAssertEqual(listRequests, [
            FileFilterSnapshot.currentCategory("docs"),
            FileFilterSnapshot.currentCategory("finance")
        ])
        XCTAssertEqual(model.files, [moved])
        XCTAssertEqual(model.selection, .single(moved.id))
        XCTAssertEqual(model.selectedFileDetail, moved)
    }

    @MainActor
    func testS135C124ContentRefreshUpdatesTreeAndSwitchesToMovedCategory() {
        let moved = FileEntrySnapshot.changeCategoryFixture(
            id: 244,
            path: "finance/contract.pdf",
            category: "finance",
            name: "contract.pdf",
            updatedAt: 1_700_000_600
        )
        let plan = CategoryMoveRefreshPlan.make(
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

    @MainActor
    func testS135C110PreviewKeepsCoreAutoNumberedNameVisibleWithoutMovingFile() async {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 245, name: "contract.pdf")
        let preview = MoveToCategoryPreviewSnapshot.changeCategoryFixture(
            fileID: original.id,
            targetPath: "finance/contract_1.pdf",
            targetName: "contract_1.pdf",
            nameConflictResolved: true
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
        XCTAssertEqual(
            model.changeCategoryState.preview(for: .init(fileID: original.id, targetCategory: "finance")),
            preview
        )
        XCTAssertTrue(preview.nameConflictResolved)
        XCTAssertEqual(preview.targetName, "contract_1.pdf")
        XCTAssertEqual(preview.targetPath, "finance/contract_1.pdf")
    }

    @MainActor
    func testS216ClassifierCorrectionLoadsRealReasonAndCorePreviewBeforeApply() async {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 246, name: "contract.pdf")
        let reason = ClassifyResultSnapshot(
            category: "docs",
            suggestedName: "contract.pdf",
            reason: .extension,
            confidence: 0.93
        )
        let preview = MoveToCategoryPreviewSnapshot.changeCategoryFixture(
            fileID: original.id,
            targetPath: "finance/contract.pdf",
            targetName: "contract.pdf"
        )
        let predictor = ChangeCategoryRecordingPredictor(result: .success(reason))
        let mover = ChangeCategoryRecordingMover(previewResult: .success(preview))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(original)),
            fileCategoryMover: mover,
            categoryPredictor: predictor,
            errorMapper: DetailMetaErrorMapper(mapping: .changeCategoryClassify())
        )

        await model.selectFiles([original.id])
        model.beginClassifierCorrection()
        await model.loadClassifierCorrectionContext(fileID: original.id, filename: original.currentName)
        await model.loadMoveToCategoryPreview(fileID: original.id, targetCategory: "finance")
        let predictionRequests = await predictor.recordedRequests()
        let moveRequests = await mover.recordedRequests()

        XCTAssertEqual(predictionRequests, [
            ChangeCategoryPredictionRequest(repoPath: "/tmp/repo", filename: "contract.pdf")
        ])
        XCTAssertEqual(moveRequests, [
            .preview(repoPath: "/tmp/repo", fileID: original.id, targetCategory: "finance")
        ])
        XCTAssertEqual(model.classifierCorrectionContextState.result(for: original.id), reason)
        let previewRequest = MainFileCategoryMovePreviewRequest(
            fileID: original.id,
            targetCategory: "finance"
        )
        XCTAssertEqual(model.changeCategoryState.preview(for: previewRequest), preview)
    }

    @MainActor
    func testS216ApplyCorrectionUsesRealCoreBridgeAndReturnedRuleDraft() async {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 247, name: "contract.pdf")
        let corrected = FileEntrySnapshot.changeCategoryFixture(
            id: original.id,
            path: "finance/contract.pdf",
            category: "finance",
            name: "contract.pdf",
            updatedAt: 1_700_000_800
        )
        let preview = MoveToCategoryPreviewSnapshot.changeCategoryFixture(
            fileID: original.id,
            targetPath: corrected.path,
            targetName: corrected.currentName
        )
        let draft = ClassifierRuleDraftSnapshot(
            sourceFileID: original.id,
            targetCategory: "finance",
            keywordCandidates: ["client-a", "contract"],
            extensionCandidates: ["pdf"],
            priority: 42
        )
        let correction = ClassifierCorrectionResultSnapshot(
            updatedFile: corrected,
            ruleDraft: draft,
            moveFileRequested: true,
            rememberRequested: true,
            ruleConfirmationRequired: true
        )
        let mover = ChangeCategoryRecordingMover(
            previewResult: .success(preview),
            correctionResult: .success(correction)
        )
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(original)),
            fileCategoryMover: mover,
            changeLogLister: DetailLogRecordingLister(results: [.success([])]),
            errorMapper: DetailMetaErrorMapper(mapping: .changeCategoryClassify())
        )

        await model.selectFiles([original.id])
        model.beginClassifierCorrection()
        await model.loadMoveToCategoryPreview(fileID: original.id, targetCategory: "finance")
        let didCorrect = await model.submitMoveToCategory(
            fileID: original.id,
            targetCategory: "finance",
            mode: .classifierCorrection,
            options: MainFileCategoryMoveOptions(
                moveFile: true,
                remember: true
            )
        )
        let requests = await mover.recordedRequests()

        XCTAssertTrue(didCorrect)
        XCTAssertEqual(requests, [
            .preview(repoPath: "/tmp/repo", fileID: original.id, targetCategory: "finance"),
            .correction(
                repoPath: "/tmp/repo",
                fileID: original.id,
                targetCategory: "finance",
                moveFile: true,
                remember: true
            )
        ])
        XCTAssertEqual(model.classifierCorrectionResult?.ruleDraft, draft)
        XCTAssertEqual(model.selectedFileDetail, corrected)
        XCTAssertNil(model.pendingActionDestination)
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
        let classifierURL = repoURL.appendingPathComponent(".areamatrix/classifier.yaml")
        let classifierBefore = try String(contentsOf: classifierURL)
        let preview = try await bridge.previewMoveToCategory(
            repoPath: repoURL.path,
            fileID: imported.id,
            newCategory: "finance"
        )
        let moved = try await bridge.moveToCategory(repoPath: repoURL.path, fileID: imported.id, newCategory: "finance")
        let detail = try await bridge.getFile(repoPath: repoURL.path, fileID: imported.id)
        let correction = try await bridge.correctFileCategory(
            repoPath: repoURL.path,
            fileID: imported.id,
            targetCategory: "docs",
            moveFile: true,
            remember: true
        )
        let changes = try await bridge.listChanges(repoPath: repoURL.path, filter: .detailLog(fileID: imported.id))

        XCTAssertEqual(preview.fileID, imported.id)
        XCTAssertEqual(preview.fromCategory, "docs")
        XCTAssertEqual(preview.toCategory, "finance")
        XCTAssertEqual(preview.targetPath, "finance/contract.pdf")
        XCTAssertEqual(moved.id, imported.id)
        XCTAssertEqual(moved.category, "finance")
        XCTAssertEqual(detail.path, "finance/contract.pdf")
        XCTAssertEqual(correction.updatedFile.id, imported.id)
        XCTAssertEqual(correction.updatedFile.category, "docs")
        XCTAssertEqual(correction.updatedFile.path, "docs/contract.pdf")
        XCTAssertTrue(correction.moveFileRequested)
        XCTAssertTrue(correction.rememberRequested)
        XCTAssertTrue(correction.ruleConfirmationRequired)
        XCTAssertEqual(correction.ruleDraft?.targetCategory, "docs")
        XCTAssertTrue(correction.ruleDraft?.extensionCandidates.contains("pdf") == true)
        XCTAssertEqual(try String(contentsOf: classifierURL), classifierBefore)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("docs/contract.pdf").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("finance/contract.pdf").path
        ))
        XCTAssertTrue(changes.contains { $0.action == "moved" })
    }

    func testS135C110DefaultCoreBridgePreviewsAutoNumberedTargetNameWithoutMovingFile() async throws {
        let repoURL = try makeChangeCategoryTemporaryDirectory(prefix: "repo")
        let sourceRoot = try makeChangeCategoryTemporaryDirectory(prefix: "source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let financeSourceURL = sourceRoot.appendingPathComponent("finance-contract.pdf")
        let docsSourceURL = sourceRoot.appendingPathComponent("docs-contract.pdf")
        try Data("existing finance bytes".utf8).write(to: financeSourceURL)
        try Data("moving docs bytes".utf8).write(to: docsSourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        _ = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: financeSourceURL,
            overrideCategory: "finance",
            overrideFilename: "contract.pdf",
            duplicateStrategy: .skip
        )
        let movingFile = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: docsSourceURL,
            overrideCategory: "docs",
            overrideFilename: "contract.pdf",
            duplicateStrategy: .skip
        )

        let preview = try await bridge.previewMoveToCategory(
            repoPath: repoURL.path,
            fileID: movingFile.id,
            newCategory: "finance"
        )

        XCTAssertEqual(preview.fileID, movingFile.id)
        XCTAssertEqual(preview.fromCategory, "docs")
        XCTAssertEqual(preview.toCategory, "finance")
        XCTAssertTrue(preview.nameConflictResolved)
        XCTAssertTrue(preview.targetPath.hasPrefix("finance/"))
        XCTAssertNotEqual(preview.targetPath, "finance/contract.pdf")
        XCTAssertNotEqual(preview.targetName, "contract.pdf")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("docs/contract.pdf").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("finance/contract.pdf").path
        ))
    }

}

private enum ChangeCategoryRequest: Equatable {
    case preview(repoPath: String, fileID: Int64, targetCategory: String)
    case move(repoPath: String, fileID: Int64, targetCategory: String)
    case correction(repoPath: String, fileID: Int64, targetCategory: String, moveFile: Bool, remember: Bool)
}

private actor ChangeCategoryRecordingMover: CoreFileCategoryMoving {
    private let previewResult: Result<MoveToCategoryPreviewSnapshot, Error>
    private let moveResult: Result<FileEntrySnapshot, Error>
    private let correctionResult: Result<ClassifierCorrectionResultSnapshot, Error>
    private var requests: [ChangeCategoryRequest] = []

    init(
        previewResult: Result<MoveToCategoryPreviewSnapshot, Error>,
        moveResult: Result<FileEntrySnapshot, Error> = .failure(CoreError.Internal(message: "unexpected move")),
        correctionResult: Result<ClassifierCorrectionResultSnapshot, Error> = .failure(
            CoreError.Internal(message: "unexpected classifier correction")
        )
    ) {
        self.previewResult = previewResult
        self.moveResult = moveResult
        self.correctionResult = correctionResult
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

    func correctFileCategory(
        repoPath: String,
        fileID: Int64,
        targetCategory: String,
        moveFile: Bool,
        remember: Bool
    ) async throws -> ClassifierCorrectionResultSnapshot {
        requests.append(.correction(
            repoPath: repoPath,
            fileID: fileID,
            targetCategory: targetCategory,
            moveFile: moveFile,
            remember: remember
        ))
        return try correctionResult.get()
    }

    func recordedRequests() -> [ChangeCategoryRequest] {
        requests
    }
}

private struct ChangeCategoryPredictionRequest: Equatable {
    var repoPath: String
    var filename: String
}

private actor ChangeCategoryRecordingPredictor: CoreCategoryPredicting {
    private let result: Result<ClassifyResultSnapshot, Error>
    private var requests: [ChangeCategoryPredictionRequest] = []

    init(result: Result<ClassifyResultSnapshot, Error>) {
        self.result = result
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requests.append(ChangeCategoryPredictionRequest(repoPath: repoPath, filename: filename))
        return try result.get()
    }

    func recordedRequests() -> [ChangeCategoryPredictionRequest] {
        requests
    }
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

    func listFiles(repoPath _: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        requests.append(filter)
        guard !results.isEmpty else { return [] }

        switch results.removeFirst() {
        case let .success(files):
            return files
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [FileFilterSnapshot] {
        requests
    }
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
                RepositoryTreeNodeSnapshot(
                    slug: "finance",
                    displayName: "finance",
                    fileCount: financeCount,
                    children: []
                )
            ]
        )
    }
}

private extension MoveToCategoryPreviewSnapshot {
    static func changeCategoryFixture(
        fileID: Int64,
        targetPath: String,
        targetName: String,
        indexOnly: Bool = false,
        nameConflictResolved: Bool = false
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
            nameConflictResolved: nameConflictResolved,
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
    let name = "AreaMatrixChangeCategory-\(prefix)-\(UUID().uuidString)"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
