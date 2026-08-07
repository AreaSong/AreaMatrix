@testable import AreaMatrix
import XCTest

final class BatchChangeCategoryVerifyTests: XCTestCase {
    @MainActor
    // swiftlint:disable:next function_body_length
    func testBatchChangeCategoryPageIntegrationUsesRealCorePreviewApplyUndoAndExitRefresh() async throws {
        let context = try await makeBatchChangeCategoryIntegrationContext()
        defer { context.cleanUp() }

        await context.model.loadCurrentCategory("docs")
        let selected = try context.selectedFilesInRouteOrder()
        XCTAssertEqual(Set(selected.map(\.id)), Set([context.repoOwned.id, context.indexOnly.id]))
        await context.model.selectFiles(Set(selected.map(\.id)))

        let route = BatchChangeCategoryRoute(
            source: .commandPalette,
            fileIDs: selected.map(\.id),
            selectedFiles: selected,
            selectedCount: selected.count,
            disabledReason: MainFileBatchEntryPolicy.disabledReason(
                selectedFiles: selected,
                isReadOnly: context.model.isReadOnly,
                isLoading: context.model.isLoading,
                writeLockedFileIDs: context.model.writeLockedFileIDs
            )
        )
        XCTAssertEqual(route.fileIDs, [context.repoOwned.id, context.indexOnly.id])
        XCTAssertEqual(route.disabledReason, nil)

        let preview = try await context.bridge.previewBatchMoveToCategory(
            repoPath: context.repoURL.path,
            fileIDs: route.fileIDs,
            targetCategory: "finance",
            moveRepoOwnedFiles: true
        )
        try assertBatchChangeCategoryPreview(preview, context: context)
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.repoOwnedDocsURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.repoOwnedFinanceURL.path))

        let report = try await context.bridge.batchMoveToCategory(
            repoPath: context.repoURL.path,
            fileIDs: route.fileIDs,
            targetCategory: preview.targetCategory,
            moveRepoOwnedFiles: preview.moveRepoOwnedFiles,
            previewToken: preview.previewToken
        )
        try await assertBatchChangeCategoryApplied(report, context: context)

        for updatedFile in report.updatedFiles {
            context.model.files = context.model.files.map { current in
                current.id == updatedFile.id ? updatedFile : current
            }
        }
        XCTAssertEqual(Set(context.model.files.map(\.category)), ["finance"])
        await context.model.retryCurrentCategory()
        let changedCount = report.movedCount + report.metadataOnlyCount
        context.model.statusBanner = .changedBatchCategory(count: changedCount, category: report.targetCategory)
        XCTAssertEqual(context.model.statusBanner, .changedBatchCategory(count: 2, category: "finance"))
        XCTAssertEqual(context.model.files, [])

        let undoState = await BatchChangeCategoryUndoAction.stateAfterBatchApply(
            repoPath: context.repoURL.path,
            report: report,
            failure: nil,
            undoStore: context.bridge,
            errorMapper: context.bridge
        )
        guard case let .ready(action) = undoState else {
            return XCTFail("Expected undo-action-log undo toast to load the real batch category undo action")
        }
        XCTAssertEqual(action.actionID, report.undoToken)
        XCTAssertEqual(action.kind, "batch_change_category")
        XCTAssertTrue(action.canUndo)

        let undo = try await context.bridge.undoAction(repoPath: context.repoURL.path, actionID: action.actionID)
        XCTAssertEqual(undo.status, .executed)
        XCTAssertTrue(undo.refreshTargets.contains("files"))
        XCTAssertTrue(undo.refreshTargets.contains("undo_actions"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.repoOwnedDocsURL.path))
    }

    func testBatchChangeCategoryCreateNewCategorySaveReturnsToSheetWithCreatedCategoryPreviewContext() {
        let context = BatchChangeCategoryReturnContext.batchChangeCategoryFixture()

        let acceptedRoute = BatchChangeCategoryClassifierReturn.acceptedRoute(
            category: " tax ",
            context: context
        )

        XCTAssertEqual(acceptedRoute?.initialTargetCategory, "tax")
        XCTAssertEqual(acceptedRoute?.acceptedCreatedCategory, "tax")
        XCTAssertEqual(acceptedRoute?.fileIDs, [1, 2])
        XCTAssertEqual(acceptedRoute, context.routeSelectingCreatedCategory("tax"))
    }

    func testBatchChangeCategoryCreateNewCategoryCancelReturnsToSheetWithOriginalCategory() {
        let context = BatchChangeCategoryReturnContext.batchChangeCategoryFixture(initialTargetCategory: "docs")

        let cancelledRoute = BatchChangeCategoryClassifierReturn.cancelledRoute(context: context)

        XCTAssertEqual(cancelledRoute.initialTargetCategory, "finance")
        XCTAssertNil(cancelledRoute.acceptedCreatedCategory)
        XCTAssertEqual(cancelledRoute.fileIDs, [1, 2])
        XCTAssertEqual(cancelledRoute, context.routeRestoringOriginalTarget())
    }

    func testBatchChangeCategoryCreateNewCategoryBlankSaveDoesNotSelectCreatedCategory() {
        let context = BatchChangeCategoryReturnContext.batchChangeCategoryFixture()

        let acceptedRoute = BatchChangeCategoryClassifierReturn.acceptedRoute(
            category: "   ",
            context: context
        )

        XCTAssertNil(acceptedRoute)
    }

    func testBatchChangeCategoryClassifierRuleEditorRouteKeepsSettingsEntryAndBatchReturnContextSeparate() {
        let context = BatchChangeCategoryReturnContext.batchChangeCategoryFixture(initialTargetCategory: "finance")
        let settingsRoute = MainSearchDestination.classifierRuleEditor(context: nil)
        let returningRoute = MainSearchDestination.classifierRuleEditor(context: context)

        XCTAssertEqual(settingsRoute.pageID, "classifier-rule-editor")
        XCTAssertEqual(returningRoute.pageID, "classifier-rule-editor")
        XCTAssertEqual(settingsRoute.id, "classifier-rule-editor-classifier-rule-editor-settings")
        XCTAssertTrue(returningRoute.id.contains(context.handoff.id))
        XCTAssertNotEqual(settingsRoute.id, returningRoute.id)
    }

    @MainActor
    func testBatchChangeCategoryClassifierSettingsValidatePublishesSavedCategoryForRealReturnEvent() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "batchChangeCategory-classifier")
        defer { removeTestTemporaryItems(repoURL) }
        var savedCategories: [String] = []
        let initialSnapshot = ClassifierRuleEditorSnapshotState.classifierEditorFixture()
        var updatedSnapshot = initialSnapshot
        updatedSnapshot.rules.append(.testFixture(ruleID: "tax", displayName: "Tax"))
        let ruleEditor = ClassifierSettingsRecordingRuleEditor(listResults: [
            .success(initialSnapshot),
            .success(updatedSnapshot)
        ])
        let model = ClassifierSettingsModel(
            repoPath: repoURL.path,
            loader: StaticConfigurationLoader(config: .classifierSettingsFixture(repoPath: repoURL.path)),
            updater: NoopConfigurationUpdater(),
            predictor: ClassifierSettingsSequencePredictor(),
            ruleEditor: ruleEditor,
            errorMapper: RecordingCoreErrorMapper.classifierSettings(),
            fileOpener: RecordingRepositoryFileOpener(),
            fileRevealer: RecordingRepositoryFileRevealer(),
            finderOpener: RecordingRepositoryFinderOpener(),
            accessibilityAnnouncer: NoopAccessibilityAnnouncer(),
            onSavedCategory: { savedCategories.append($0) }
        )
        await model.load()

        let didValidate = await model.validateClassifierRules()

        let context = BatchChangeCategoryReturnContext.batchChangeCategoryFixture()
        let savedCategory = try XCTUnwrap(savedCategories.first)
        let route = BatchChangeCategoryClassifierReturn.acceptedRoute(
            category: savedCategory,
            context: context
        )

        XCTAssertTrue(didValidate)
        XCTAssertEqual(savedCategories, ["tax"])
        XCTAssertEqual(route, context.routeSelectingCreatedCategory("tax"))
    }
}

private struct BatchChangeCategoryIntegrationContext {
    let repoURL: URL
    let sourceRootURL: URL
    let externalSourceURL: URL
    let repoOwnedDocsURL: URL
    let repoOwnedFinanceURL: URL
    let opening: RepositoryOpeningResult
    let bridge: CoreBridge
    let model: MainFileListModel
    let repoOwned: FileEntrySnapshot
    let indexOnly: FileEntrySnapshot

    func cleanUp() {
        removeTestTemporaryItems(repoURL, sourceRootURL)
    }

    @MainActor
    func selectedFilesInRouteOrder(file: StaticString = #filePath, line: UInt = #line) throws -> [FileEntrySnapshot] {
        let filesByID = Dictionary(uniqueKeysWithValues: model.files.map { ($0.id, $0) })
        return try [repoOwned.id, indexOnly.id].map { fileID in
            try XCTUnwrap(filesByID[fileID], file: file, line: line)
        }
    }
}

@MainActor
private func makeBatchChangeCategoryIntegrationContext() async throws -> BatchChangeCategoryIntegrationContext {
    let context = try await makeRealCoreRepositoryTestContext(named: "AreaMatrixBatchChangeCategory")
    let repoOwnedSourceURL = try context.writeSourceFile(named: "batch-owned.pdf", contents: "repo owned bytes")
    let indexedSourceURL = try context.writeSourceFile(named: "batch-indexed.pdf", contents: "indexed bytes")

    let repoOwned = try await context.bridge.importCopiedFile(
        repoPath: context.repoURL.path,
        sourceURL: repoOwnedSourceURL,
        overrideCategory: "docs",
        overrideFilename: "batch-owned.pdf",
        duplicateStrategy: .skip
    )
    let indexOnly = try await context.bridge.importIndexedFile(
        repoPath: context.repoURL.path,
        sourceURL: indexedSourceURL,
        overrideCategory: "docs",
        overrideFilename: "batch-indexed.pdf",
        duplicateStrategy: .skip
    )
    let opening = try await makeRealCoreRepositoryOpening(context)
    let model = MainFileListModel(
        opening: opening,
        fileLister: context.bridge,
        fileDetailer: context.bridge,
        batchCategoryChanger: context.bridge,
        undoActionStore: context.bridge,
        changeLogLister: context.bridge,
        errorMapper: context.bridge
    )
    return BatchChangeCategoryIntegrationContext(
        repoURL: context.repoURL,
        sourceRootURL: context.sourceRootURL,
        externalSourceURL: indexedSourceURL,
        repoOwnedDocsURL: context.repositoryFileURL(for: repoOwned),
        repoOwnedFinanceURL: context.repoURL.appendingPathComponent("finance/batch-owned.pdf"),
        opening: opening,
        bridge: context.bridge,
        model: model,
        repoOwned: repoOwned,
        indexOnly: indexOnly
    )
}

private func assertBatchChangeCategoryPreview(
    _ preview: BatchCategoryPreviewReportSnapshot,
    context: BatchChangeCategoryIntegrationContext
) throws {
    XCTAssertTrue(preview.canApply)
    XCTAssertEqual(preview.requestedFileCount, 2)
    XCTAssertEqual(preview.targetCategory, "finance")
    XCTAssertTrue(preview.moveRepoOwnedFiles)
    XCTAssertEqual(preview.willMoveCount, 1)
    XCTAssertEqual(preview.metadataOnlyCount, 1)
    XCTAssertEqual(preview.blockedCount, 0)
    let itemsByID = Dictionary(uniqueKeysWithValues: preview.items.map { ($0.fileID, $0) })
    let repoOwned = try XCTUnwrap(itemsByID[context.repoOwned.id])
    let indexOnly = try XCTUnwrap(itemsByID[context.indexOnly.id])
    XCTAssertEqual(repoOwned.status, .willMove)
    XCTAssertEqual(repoOwned.targetPath, "finance/batch-owned.pdf")
    XCTAssertEqual(indexOnly.status, .metadataOnly)
    XCTAssertTrue(indexOnly.indexOnly)
    XCTAssertFalse(indexOnly.willMoveFile)
}

private func assertBatchChangeCategoryApplied(
    _ report: BatchCategoryChangeReportSnapshot,
    context: BatchChangeCategoryIntegrationContext
) async throws {
    XCTAssertEqual(report.movedCount, 1)
    XCTAssertEqual(report.metadataOnlyCount, 1)
    XCTAssertEqual(report.failedCount, 0)
    XCTAssertNotNil(report.undoToken)
    XCTAssertTrue(FileManager.default.fileExists(atPath: context.repoOwnedFinanceURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.repoOwnedDocsURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: context.externalSourceURL.path))
    let financeFiles = try await context.bridge.listFiles(
        repoPath: context.repoURL.path,
        filter: .currentCategory("finance")
    )
    XCTAssertEqual(Set(financeFiles.map(\.id)), Set([context.repoOwned.id, context.indexOnly.id]))
    let actions = try await context.bridge.listUndoActions(repoPath: context.repoURL.path)
    XCTAssertEqual(actions.first?.actionID, report.undoToken)
}
