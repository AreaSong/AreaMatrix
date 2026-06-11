@testable import AreaMatrix
import XCTest

final class ChangeCategoryPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS135PageIntegrationUsesRealCorePreviewMoveConflictAndRefreshesExit() async throws {
        let context = try await makeS135IntegrationContext()
        defer { context.cleanUp() }
        await context.model.loadCurrentCategory("docs")
        let moving = try XCTUnwrap(context.model.files.first { $0.id == context.movingFile.id })
        await context.model.selectFiles([moving.id])
        context.model.beginChangeCategory()
        XCTAssertEqual(context.model.pendingActionDestination?.pageID, "S1-35")

        await context.model.loadMoveToCategoryPreview(fileID: moving.id, targetCategory: "finance")
        let request = MainFileCategoryMovePreviewRequest(fileID: moving.id, targetCategory: "finance")
        let preview = try XCTUnwrap(context.model.changeCategoryState.preview(for: request))
        try assertS135Preview(preview, context: context)

        var movedCallback: FileEntrySnapshot?
        let didMove = await context.model
            .submitMoveToCategory(fileID: moving.id, targetCategory: "finance") { movedFile in
                movedCallback = movedFile
            }
        XCTAssertTrue(didMove)
        let moved = try XCTUnwrap(movedCallback)
        let refreshedTree = try await context.bridge.listTree(repoPath: context.repoURL.path, locale: "zh-Hans")
        let plan = CategoryMoveRefreshPlan.make(
            movedFile: moved,
            currentSidebarID: "docs",
            currentTree: context.opening.tree,
            refreshedTree: refreshedTree
        )
        await context.model.loadCurrentCategory(plan.categoryForFileList, focusingOn: moved.id)
        let changes = try await context.bridge.listChanges(
            repoPath: context.repoURL.path,
            filter: .detailLog(fileID: moved.id)
        )
        try assertS135CompletedMove(moved, changes: changes, plan: plan, context: context)
    }

    @MainActor
    func testS135PageIntegrationPreviewErrorKeepsSheetOpenWithoutMovingFile() async throws {
        let context = try await makeS135IntegrationContext()
        defer { context.cleanUp() }
        await context.model.loadCurrentCategory("docs")
        let moving = try XCTUnwrap(context.model.files.first { $0.id == context.movingFile.id })
        await context.model.selectFiles([moving.id])
        context.model.beginChangeCategory()
        await context.model.loadMoveToCategoryPreview(fileID: moving.id, targetCategory: "missing-category")

        let request = MainFileCategoryMovePreviewRequest(fileID: moving.id, targetCategory: "missing-category")
        guard case let .failed(failedRequest, .preview, mapping) = context.model.changeCategoryState,
              failedRequest == request
        else {
            return XCTFail("Expected S1-35 preview failure to keep the sheet in recoverable error state")
        }

        XCTAssertEqual(mapping.kind, .classify)
        XCTAssertEqual(context.model.pendingActionDestination, .changeCategory(fileID: moving.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.movingDocsURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: context.repoURL.appendingPathComponent("missing-category/contract.pdf").path
        ))
        XCTAssertEqual(context.model.files, [moving])
        XCTAssertEqual(context.model.selectedFileDetail, moving)
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    func testS135PageIntegrationDetailMetaMenuRoutesToChangeCategorySheet() async {
        let file = FileEntrySnapshot.s135Fixture(id: 249, name: "detail.pdf")
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            errorMapper: DetailMetaErrorMapper(mapping: .s135Conflict())
        )

        await model.selectFiles([file.id])
        let pane = MainRepositoryDetailPane(
            selection: model.selection,
            multiSelectionSummary: MultiSelectionDetailSummary(selection: model.selection, files: model.files),
            detailErrorMapping: model.detailErrorMapping,
            isDetailLoading: model.isDetailLoading,
            selectedFileDetail: model.selectedFileDetail,
            noteWriteBlock: model.selectedFileNoteWriteBlock,
            detailLogState: model.detailLogState,
            detailLogDiagnosticsState: model.detailLogDiagnosticsState,
            detailExternalCreateSyncState: model.detailExternalCreateSyncState,
            detailTagEditorState: model.detailTagEditorState,
            detailTagSuggestionState: model.detailTagSuggestionState,
            tagSuggestionPresentationRequest: model.tagSuggestionPresentationRequest,
            detailTagUndoToast: model.detailTagUndoToast, detailTabRequest: model.detailTabRequest,
            selectedImportProgressRow: nil,
            semanticDetail: nil,
            repoPath: "/tmp/repo",
            batchTagStore: model.tagStore, batchTagUndoStore: model.undoActionStore,
            batchTagErrorMapper: model.errorMapper,
            batchDeleter: CoreBridge(),
            batchCategoryChanger: model.batchCategoryChanger,
            batchRenamer: CoreBridge(),
            categoryRows: .s135Rows,
            onBatchCategoryApplied: { _ in },
            onBatchDeleteApplied: { _ in },
            onBatchRenameApplied: { _ in },
            onBatchCategoryCreateNewCategory: { _ in },
            onRetrySelectedFileDetail: {},
            tagActions: .noop,
            onCopyPaths: { _ in }, onOpenNoteFile: { _ in },
            onRefreshChangeLog: {}, onRequestDetailLogDiagnostics: {}, onConfirmDetailLogDiagnostics: {},
            onCancelDetailLogDiagnostics: {}, onDetailTabRequestConsumed: { _ in },
            onBeginRenameFile: model.beginRename,
            onBeginChangeCategoryFile: model.beginChangeCategory,
            onBeginClassifierCorrectionFile: model.beginClassifierCorrection,
            onBeginAIClassificationSuggestionFile: model.beginAIClassificationSuggestion,
            onBeginDeleteFile: model.beginDelete, onBeginICloudConflictResolution: model.beginICloudConflictResolution,
            onBeginSyncConflictReview: { _ in },
            onOpenAISettings: {},
            writeActionDisabledReason: model.writeActionDisabledReason,
            summaryExitController: AISummaryEditorExitController(),
            noteModel: DetailNoteModel(
                repoPath: "/tmp/repo",
                noteStore: S135NoopNoteStore(),
                errorMapper: DetailMetaErrorMapper(mapping: .s135Conflict())
            )
        )
        let body = s135MirrorDescription(of: pane.body)

        XCTAssertTrue(body.contains("Change Category..."))
        XCTAssertTrue(body.contains("Correct Classification..."))
        XCTAssertTrue(body.contains("Review AI Suggestion..."))
        pane.onBeginChangeCategoryFile(file.id)
        XCTAssertEqual(model.pendingActionDestination, .changeCategory(fileID: file.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "S1-35")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "Change Category")
        pane.onBeginClassifierCorrectionFile(file.id)
        XCTAssertEqual(model.pendingActionDestination, .changeCategory(fileID: file.id, mode: .classifierCorrection))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "S2-16")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "Correct Classification")
        pane.onBeginAIClassificationSuggestionFile(file.id)
        XCTAssertEqual(model.pendingActionDestination, .aiClassificationSuggestion(fileID: file.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "S3-04")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "AI Category Suggestion")
    }

    @MainActor
    func testS135PageIntegrationRenameFirstReturnsToChangeCategory() async {
        let original = FileEntrySnapshot.s135Fixture(id: 246, name: "contract.pdf")
        let renamed = FileEntrySnapshot.s135Fixture(
            id: 246,
            path: "docs/contracts/contract-renamed.pdf",
            name: "contract-renamed.pdf",
            updatedAt: 1_700_000_700
        )
        let mapping = CoreErrorMappingSnapshot.s135Conflict()
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let mover = S135RecordingMover(
            previewResult: .failure(CoreError.Conflict(path: "finance/contract.pdf"))
        )
        let renamer = S135RecordingRenamer(result: .success(renamed))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(original)),
            fileRenamer: renamer,
            fileCategoryMover: mover,
            errorMapper: mapper
        )

        await model.selectFiles([original.id])
        model.beginChangeCategory()
        await model.loadMoveToCategoryPreview(fileID: original.id, targetCategory: "finance")
        let moveRequests = await mover.recordedRequests()
        let mappedErrors = await mapper.recordedErrors()
        XCTAssertEqual(moveRequests, [
            .preview(repoPath: "/tmp/repo", fileID: original.id, targetCategory: "finance")
        ])
        XCTAssertEqual(mappedErrors, [CoreError.Conflict(path: "finance/contract.pdf")])
        XCTAssertEqual(
            model.changeCategoryState.unresolvedNameConflict(for: original.id, targetCategory: "finance"),
            mapping
        )

        model.beginRenameFromChangeCategory(fileID: original.id, targetCategory: "finance")
        XCTAssertEqual(model.pendingActionDestination, .rename(fileID: original.id))
        XCTAssertEqual(
            model.renameState,
            .returningToChangeCategory(fileID: original.id, targetCategory: "finance")
        )
        XCTAssertEqual(model.files, [original])
        XCTAssertEqual(model.selectedFileDetail, original)
        let didRename = await model.submitRename(fileID: original.id, newName: "contract-renamed.pdf")
        XCTAssertTrue(didRename)
        await assertS135ReturnedToChangeCategory(
            model: model,
            renamer: renamer,
            original: original,
            renamed: renamed
        )
    }

    @MainActor
    func testS135PageIntegrationPermissionDeniedExposesRecoveryEntry() {
        let original = FileEntrySnapshot.s135Fixture(id: 247, name: "blocked.pdf")
        let mapping = CoreErrorMappingSnapshot.s135PermissionDenied()
        var openedPermissionRecovery = false
        let sheet = ChangeCategorySheet(
            file: original,
            categoryRows: .s135Rows,
            state: .failed(
                .init(fileID: original.id, targetCategory: "finance"),
                operation: .preview,
                mapping
            ),
            initialTargetCategory: "finance",
            onCancel: {},
            onPreview: { _, _ in },
            onChangeCategory: { _, _, _, _ in },
            onRenameFirst: { _, _ in },
            onOpenPermissionRecovery: { openedPermissionRecovery = true },
            onCollectDiagnostics: {}
        )
        let body = s135MirrorDescription(of: sheet.body)

        XCTAssertTrue(body.contains("Open folder permissions"))
        XCTAssertTrue(body.contains("Collect Diagnostics..."))
        sheet.onOpenPermissionRecovery()
        XCTAssertTrue(openedPermissionRecovery)
    }
}

@MainActor
private func assertS135ReturnedToChangeCategory(
    model: MainFileListModel,
    renamer: S135RecordingRenamer,
    original: FileEntrySnapshot,
    renamed: FileEntrySnapshot
) async {
    let renameRequests = await renamer.recordedRequests()
    XCTAssertEqual(renameRequests, [
        S135RenameRequest(
            repoPath: "/tmp/repo",
            fileID: original.id,
            newName: "contract-renamed.pdf"
        )
    ])
    XCTAssertEqual(
        model.pendingActionDestination,
        .changeCategory(fileID: original.id, initialTargetCategory: "finance")
    )
    XCTAssertEqual(model.renameState, .idle)
    XCTAssertEqual(model.changeCategoryState, .idle)
    XCTAssertEqual(model.files, [renamed])
    XCTAssertEqual(model.selectedFileDetail, renamed)
}

private struct S135IntegrationContext {
    let repoURL: URL
    let sourceRootURL: URL
    let existingFinanceURL: URL
    let movingDocsURL: URL
    let opening: RepositoryOpeningResult
    let bridge: CoreBridge
    let model: MainFileListModel
    let existingFile: FileEntrySnapshot
    let movingFile: FileEntrySnapshot

    func cleanUp() {
        try? FileManager.default.removeItem(at: repoURL)
        try? FileManager.default.removeItem(at: sourceRootURL)
    }
}

private enum S135MoveRequest: Equatable {
    case preview(repoPath: String, fileID: Int64, targetCategory: String)
    case move(repoPath: String, fileID: Int64, targetCategory: String)
}

private struct S135RenameRequest: Equatable {
    var repoPath: String
    var fileID: Int64
    var newName: String
}

private actor S135RecordingRenamer: CoreFileRenaming {
    private let result: Result<FileEntrySnapshot, Error>
    private var requests: [S135RenameRequest] = []

    init(result: Result<FileEntrySnapshot, Error>) {
        self.result = result
    }

    func renameFile(repoPath: String, fileID: Int64, newName: String) async throws -> FileEntrySnapshot {
        requests.append(S135RenameRequest(repoPath: repoPath, fileID: fileID, newName: newName))
        return try result.get()
    }

    func recordedRequests() -> [S135RenameRequest] {
        requests
    }
}

private actor S135RecordingMover: CoreFileCategoryMoving {
    private let previewResult: Result<MoveToCategoryPreviewSnapshot, Error>
    private let moveResult: Result<FileEntrySnapshot, Error>
    private var requests: [S135MoveRequest] = []

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

    func recordedRequests() -> [S135MoveRequest] {
        requests
    }
}

private actor S135NoopNoteStore: CoreNoteReadingWriting {
    func readNote(repoPath _: String, fileID _: Int64) async throws -> String? {
        nil
    }

    func writeNote(repoPath _: String, fileID _: Int64, contentMarkdown _: String) async throws {}
}

@MainActor
private func makeS135IntegrationContext() async throws -> S135IntegrationContext {
    let repoURL = try makeS135TemporaryDirectory(prefix: "repo")
    let sourceRootURL = try makeS135TemporaryDirectory(prefix: "source")
    let existingSourceURL = sourceRootURL.appendingPathComponent("finance-contract.pdf")
    let movingSourceURL = sourceRootURL.appendingPathComponent("docs-contract.pdf")
    try Data("existing finance bytes".utf8).write(to: existingSourceURL)
    try Data("moving docs bytes".utf8).write(to: movingSourceURL)

    let bridge = CoreBridge()
    try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
    let existing = try await bridge.importCopiedFile(
        repoPath: repoURL.path,
        sourceURL: existingSourceURL,
        overrideCategory: "finance",
        overrideFilename: "contract.pdf",
        duplicateStrategy: .skip
    )
    let moving = try await bridge.importCopiedFile(
        repoPath: repoURL.path,
        sourceURL: movingSourceURL,
        overrideCategory: "docs",
        overrideFilename: "contract.pdf",
        duplicateStrategy: .skip
    )
    let opening = try await makeS135Opening(repoURL: repoURL, bridge: bridge)
    let model = MainFileListModel(
        opening: opening,
        fileLister: bridge,
        fileDetailer: bridge,
        fileCategoryMover: bridge,
        changeLogLister: bridge,
        errorMapper: bridge
    )
    return S135IntegrationContext(
        repoURL: repoURL,
        sourceRootURL: sourceRootURL,
        existingFinanceURL: repoURL.appendingPathComponent(existing.path),
        movingDocsURL: repoURL.appendingPathComponent(moving.path),
        opening: opening,
        bridge: bridge,
        model: model,
        existingFile: existing,
        movingFile: moving
    )
}

private func makeS135Opening(repoURL: URL, bridge: CoreBridge) async throws -> RepositoryOpeningResult {
    let config = try await bridge.loadConfig(repoPath: repoURL.path)
    let tree = try await bridge.listTree(repoPath: repoURL.path, locale: "zh-Hans")
    return RepositoryOpeningResult(config: config, tree: tree, currentCategoryFiles: [])
}

private func assertS135Preview(
    _ preview: MoveToCategoryPreviewSnapshot,
    context: S135IntegrationContext
) throws {
    XCTAssertEqual(preview.fileID, context.movingFile.id)
    XCTAssertEqual(preview.fromCategory, "docs")
    XCTAssertEqual(preview.toCategory, "finance")
    XCTAssertTrue(preview.nameConflictResolved)
    XCTAssertEqual(preview.storageMode, "Copied")
    XCTAssertTrue(preview.willMoveFile)
    XCTAssertFalse(preview.indexOnly)
    XCTAssertNotEqual(preview.targetPath, context.existingFile.path)
    XCTAssertNotEqual(preview.targetName, context.existingFile.currentName)
    XCTAssertTrue(FileManager.default.fileExists(atPath: context.existingFinanceURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: context.movingDocsURL.path))
    XCTAssertEqual(try String(contentsOf: context.existingFinanceURL), "existing finance bytes")
}

@MainActor
private func assertS135CompletedMove(
    _ moved: FileEntrySnapshot,
    changes: [ChangeLogEntrySnapshot],
    plan: CategoryMoveRefreshPlan,
    context: S135IntegrationContext
) throws {
    XCTAssertEqual(moved.id, context.movingFile.id)
    XCTAssertEqual(moved.category, "finance")
    XCTAssertEqual(plan.categoryForFileList, "finance")
    XCTAssertEqual(moved.path, "finance/\(moved.currentName)")
    XCTAssertEqual(plan.selectedSidebarID, "finance")
    XCTAssertEqual(context.model.pendingActionDestination, nil)
    XCTAssertEqual(context.model.changeCategoryState, .idle)
    XCTAssertEqual(context.model.selection, .single(moved.id))
    XCTAssertEqual(context.model.selectedFileDetail, moved)
    XCTAssertEqual(Set(context.model.files.map(\.category)), Set(["finance"]))
    XCTAssertEqual(context.model.files.first { $0.id == moved.id }, moved)
    XCTAssertEqual(context.model.statusBanner, .changedCategory(fileID: moved.id, category: "finance"))
    XCTAssertTrue(changes.contains { $0.fileID == moved.id && $0.action == "moved" })
    XCTAssertTrue(FileManager.default.fileExists(
        atPath: context.repoURL.appendingPathComponent(moved.path).path
    ))
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.movingDocsURL.path))
    XCTAssertEqual(try String(contentsOf: context.existingFinanceURL), "existing finance bytes")
}

private extension FileEntrySnapshot {
    static func s135Fixture(
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
            hashSha256: "s135-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: updatedAt
        )
    }
}

private extension RepositoryTreeNodeSnapshot {
    static func s135Tree(docsCount: Int64, financeCount: Int64) -> RepositoryTreeNodeSnapshot {
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

private extension [RepositorySidebarRowSnapshot] {
    static var s135Rows: [RepositorySidebarRowSnapshot] {
        RepositoryTreeNodeSnapshot.s135Tree(docsCount: 1, financeCount: 0).sidebarRows
    }
}
