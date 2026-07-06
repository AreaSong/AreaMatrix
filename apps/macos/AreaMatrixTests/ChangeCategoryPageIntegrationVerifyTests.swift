@testable import AreaMatrix
import XCTest

final class ChangeCategoryPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testChangeCategoryPageIntegrationUsesRealCorePreviewMoveConflictAndRefreshesExit() async throws {
        let context = try await makeChangeCategoryIntegrationContext()
        defer { context.cleanUp() }
        await context.model.loadCurrentCategory("docs")
        let moving = try XCTUnwrap(context.model.files.first { $0.id == context.movingFile.id })
        await context.model.selectFiles([moving.id])
        context.model.beginChangeCategory()
        XCTAssertEqual(context.model.pendingActionDestination?.pageID, "change-category")

        await context.model.loadMoveToCategoryPreview(fileID: moving.id, targetCategory: "finance")
        let request = MainFileCategoryMovePreviewRequest(fileID: moving.id, targetCategory: "finance")
        let preview = try XCTUnwrap(context.model.changeCategoryState.preview(for: request))
        try assertChangeCategoryPreview(preview, context: context)

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
        try assertChangeCategoryCompletedMove(moved, changes: changes, plan: plan, context: context)
    }

    @MainActor
    func testChangeCategoryPageIntegrationPreviewErrorKeepsSheetOpenWithoutMovingFile() async throws {
        let context = try await makeChangeCategoryIntegrationContext()
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
            return XCTFail("Expected change-category preview failure to keep the sheet in recoverable error state")
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
    func testChangeCategoryPageIntegrationDetailMetaMenuRoutesToChangeCategorySheet() async {
        let file = FileEntrySnapshot.changeCategoryFixture(id: 249, name: "detail.pdf")
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            errorMapper: StaticCoreErrorMapper(mapping: .changeCategoryConflict())
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
            categoryRows: .changeCategoryRows,
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
            canPerformWriteAction: model.canPerformWriteAction,
            summaryExitController: AISummaryEditorExitController(),
            noteModel: DetailNoteModel(
                repoPath: "/tmp/repo",
                noteStore: NoopNoteStore(),
                errorMapper: StaticCoreErrorMapper(mapping: .changeCategoryConflict())
            )
        )
        assertChangeCategoryDetailActions(of: pane.body, detail: file)
        pane.onBeginChangeCategoryFile(file.id)
        XCTAssertEqual(model.pendingActionDestination, .changeCategory(fileID: file.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "change-category")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "Change Category")
        pane.onBeginClassifierCorrectionFile(file.id)
        XCTAssertEqual(model.pendingActionDestination, .changeCategory(fileID: file.id, mode: .classifierCorrection))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "classifier-correction")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "Correct Classification")
        pane.onBeginAIClassificationSuggestionFile(file.id)
        XCTAssertEqual(model.pendingActionDestination, .aiClassificationSuggestion(fileID: file.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "ai-category-suggestion")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "AI Category Suggestion")
    }

    @MainActor
    func testChangeCategoryPageIntegrationRenameFirstReturnsToChangeCategory() async {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 246, name: "contract.pdf")
        let renamed = FileEntrySnapshot.changeCategoryFixture(
            id: 246,
            path: "docs/contracts/contract-renamed.pdf",
            name: "contract-renamed.pdf",
            updatedAt: 1_700_000_700
        )
        let mapping = CoreErrorMappingSnapshot.changeCategoryConflict()
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let mover = ChangeCategoryRecordingMover(
            previewResult: .failure(CoreError.Conflict(path: "finance/contract.pdf"))
        )
        let renamer = ChangeCategoryRecordingRenamer(result: .success(renamed))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: NoopFileLister(),
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
        await assertChangeCategoryReturnedToChangeCategory(
            model: model,
            renamer: renamer,
            original: original,
            renamed: renamed
        )
    }

    @MainActor
    func testChangeCategoryPageIntegrationPermissionDeniedExposesRecoveryEntry() {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 247, name: "blocked.pdf")
        let mapping = CoreErrorMappingSnapshot.changeCategoryPermissionDenied()
        var openedPermissionRecovery = false
        let sheet = ChangeCategorySheet(
            file: original,
            categoryRows: .changeCategoryRows,
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
        assertChangeCategoryPermissionRecovery(of: sheet.body)
        sheet.onOpenPermissionRecovery()
        XCTAssertTrue(openedPermissionRecovery)
    }
}

@MainActor
private func assertChangeCategoryDetailActions(
    of value: Any,
    detail: FileEntrySnapshot,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertTestMirrorDescription(
        of: value,
        contains: "MainRepositorySelectedFileDetailPane",
        maxDepth: 8,
        file: file,
        line: line
    )
    assertMainRepositoryDetailFileActionMenu(for: detail, contains: [
        "Change Category...",
        "Correct Classification...",
        "Review AI Suggestion..."
    ], file: file, line: line)
}

private func assertChangeCategoryPermissionRecovery(
    of value: Any,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertTestMirrorDescription(of: value, contains: [
        "Open folder permissions",
        "Collect Diagnostics..."
    ], maxDepth: 8, file: file, line: line)
}

@MainActor
private func assertChangeCategoryReturnedToChangeCategory(
    model: MainFileListModel,
    renamer: ChangeCategoryRecordingRenamer,
    original: FileEntrySnapshot,
    renamed: FileEntrySnapshot
) async {
    let renameRequests = await renamer.recordedRequests()
    XCTAssertEqual(renameRequests, [
        ChangeCategoryRenameRequest(
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

private struct ChangeCategoryIntegrationContext {
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
        removeTestTemporaryItems(repoURL, sourceRootURL)
    }
}

private struct ChangeCategoryRenameRequest: Equatable {
    var repoPath: String
    var fileID: Int64
    var newName: String
}

private actor ChangeCategoryRecordingRenamer: CoreFileRenaming {
    private let result: Result<FileEntrySnapshot, Error>
    private var requests: [ChangeCategoryRenameRequest] = []

    init(result: Result<FileEntrySnapshot, Error>) {
        self.result = result
    }

    func renameFile(repoPath: String, fileID: Int64, newName: String) async throws -> FileEntrySnapshot {
        requests.append(ChangeCategoryRenameRequest(repoPath: repoPath, fileID: fileID, newName: newName))
        return try result.get()
    }

    func recordedRequests() -> [ChangeCategoryRenameRequest] {
        requests
    }
}

@MainActor
private func makeChangeCategoryIntegrationContext() async throws -> ChangeCategoryIntegrationContext {
    let context = try await makeRealCoreRepositoryTestContext(named: "AreaMatrixChangeCategoryIntegration")
    let existingSourceURL = try context.writeSourceFile(
        named: "finance-contract.pdf",
        contents: "existing finance bytes"
    )
    let movingSourceURL = try context.writeSourceFile(named: "docs-contract.pdf", contents: "moving docs bytes")

    let existing = try await context.bridge.importCopiedFile(
        repoPath: context.repoURL.path,
        sourceURL: existingSourceURL,
        overrideCategory: "finance",
        overrideFilename: "contract.pdf",
        duplicateStrategy: .skip
    )
    let moving = try await context.bridge.importCopiedFile(
        repoPath: context.repoURL.path,
        sourceURL: movingSourceURL,
        overrideCategory: "docs",
        overrideFilename: "contract.pdf",
        duplicateStrategy: .skip
    )
    let opening = try await makeRealCoreRepositoryOpening(context)
    let model = MainFileListModel(
        opening: opening,
        fileLister: context.bridge,
        fileDetailer: context.bridge,
        fileCategoryMover: context.bridge,
        changeLogLister: context.bridge,
        errorMapper: context.bridge
    )
    return ChangeCategoryIntegrationContext(
        repoURL: context.repoURL,
        sourceRootURL: context.sourceRootURL,
        existingFinanceURL: context.repositoryFileURL(for: existing),
        movingDocsURL: context.repositoryFileURL(for: moving),
        opening: opening,
        bridge: context.bridge,
        model: model,
        existingFile: existing,
        movingFile: moving
    )
}

private func assertChangeCategoryPreview(
    _ preview: MoveToCategoryPreviewSnapshot,
    context: ChangeCategoryIntegrationContext
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
private func assertChangeCategoryCompletedMove(
    _ moved: FileEntrySnapshot,
    changes: [ChangeLogEntrySnapshot],
    plan: CategoryMoveRefreshPlan,
    context: ChangeCategoryIntegrationContext
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

private extension [RepositorySidebarRowSnapshot] {
    static var changeCategoryRows: [RepositorySidebarRowSnapshot] {
        RepositoryTreeNodeSnapshot.changeCategoryTree(docsCount: 1, financeCount: 0).sidebarRows
    }
}
