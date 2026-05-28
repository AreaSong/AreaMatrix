@testable import AreaMatrix
import XCTest

final class S212BatchCategoryVerifyTests: XCTestCase {
    @MainActor
    // swiftlint:disable:next function_body_length
    func testS212PageIntegrationUsesRealCorePreviewApplyUndoAndExitRefresh() async throws {
        let context = try await makeS212IntegrationContext()
        defer { context.cleanUp() }

        await context.model.loadCurrentCategory("docs")
        let selected = context.model.files.filter { file in
            [context.repoOwned.id, context.indexOnly.id].contains(file.id)
        }
        XCTAssertEqual(Set(selected.map(\.id)), Set([context.repoOwned.id, context.indexOnly.id]))
        await context.model.selectFiles(Set(selected.map(\.id)))

        let route = BatchChangeCategoryRoute(
            source: .commandPalette,
            fileIDs: selected.map(\.id),
            selectedFiles: selected,
            selectedCount: selected.count,
            disabledReason: BatchChangeCategoryEntryPolicy.disabledReason(
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
        try assertS212Preview(preview, context: context)
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.repoOwnedDocsURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.repoOwnedFinanceURL.path))

        let report = try await context.bridge.batchMoveToCategory(
            repoPath: context.repoURL.path,
            fileIDs: route.fileIDs,
            targetCategory: preview.targetCategory,
            moveRepoOwnedFiles: preview.moveRepoOwnedFiles,
            previewToken: preview.previewToken
        )
        try await assertS212Applied(report, context: context)

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
            return XCTFail("Expected C2-07 undo toast to load the real batch category undo action")
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

    func testS212CreateNewCategorySaveNotificationReturnsToSheetWithCreatedCategoryPreviewContext() {
        let context = BatchChangeCategoryReturnContext.s212Fixture()
        let notification = ClassifierRuleEditorSaveEvents.notification(savedCategory: " tax ")

        let acceptedRoute = BatchChangeCategoryClassifierReturn.acceptedRoute(
            notification: notification,
            context: context
        )

        XCTAssertEqual(acceptedRoute?.initialTargetCategory, "tax")
        XCTAssertEqual(acceptedRoute?.acceptedCreatedCategory, "tax")
        XCTAssertEqual(acceptedRoute?.fileIDs, [1, 2])
        XCTAssertEqual(acceptedRoute, context.routeSelectingCreatedCategory("tax"))
    }

    func testS212CreateNewCategoryCancelReturnsToSheetWithOriginalCategory() {
        let context = BatchChangeCategoryReturnContext.s212Fixture(initialTargetCategory: "docs")

        let cancelledRoute = BatchChangeCategoryClassifierReturn.cancelledRoute(context: context)

        XCTAssertEqual(cancelledRoute.initialTargetCategory, "finance")
        XCTAssertNil(cancelledRoute.acceptedCreatedCategory)
        XCTAssertEqual(cancelledRoute.fileIDs, [1, 2])
        XCTAssertEqual(cancelledRoute, context.routeRestoringOriginalTarget())
    }

    func testS212CreateNewCategoryBlankSaveNotificationDoesNotSelectCreatedCategory() {
        let context = BatchChangeCategoryReturnContext.s212Fixture()
        let notification = ClassifierRuleEditorSaveEvents.notification(savedCategory: "   ")

        let acceptedRoute = BatchChangeCategoryClassifierReturn.acceptedRoute(
            notification: notification,
            context: context
        )

        XCTAssertNil(acceptedRoute)
    }

    func testS212ClassifierRuleEditorRouteKeepsSettingsEntryAndBatchReturnContextSeparate() {
        let context = BatchChangeCategoryReturnContext.s212Fixture(initialTargetCategory: "finance")
        let settingsRoute = MainSearchDestination.classifierRuleEditor(context: nil)
        let returningRoute = MainSearchDestination.classifierRuleEditor(context: context)

        XCTAssertEqual(settingsRoute.pageID, "S2-19")
        XCTAssertEqual(returningRoute.pageID, "S2-19")
        XCTAssertEqual(settingsRoute.id, "S2-19-classifier-rule-editor-settings")
        XCTAssertTrue(returningRoute.id.contains(context.handoff.id))
        XCTAssertNotEqual(settingsRoute.id, returningRoute.id)
    }

    @MainActor
    func testS212ClassifierSettingsValidatePublishesSavedCategoryForRealReturnEvent() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "s212-classifier")
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let manager = S212ClassifierRulesManager()
        var savedCategories: [String] = []
        try manager.writeClassifier(repoURL: repoURL, slugs: ["docs", "inbox"])
        let model = ClassifierSettingsModel(
            repoPath: repoURL.path,
            loader: S212ClassifierSettingsLoader(repoPath: repoURL.path),
            updater: S212ClassifierSettingsUpdater(),
            predictor: S212ClassifierSettingsPredictor(),
            errorMapper: S212ClassifierSettingsErrorMapper(),
            classifierRulesManager: manager,
            accessibilityAnnouncer: S212ClassifierSettingsAnnouncer(),
            onSavedCategory: { savedCategories.append($0) }
        )
        await model.load()
        try manager.writeClassifier(repoURL: repoURL, slugs: ["docs", "tax", "inbox"])

        let didValidate = await model.validateClassifierRules()

        let context = BatchChangeCategoryReturnContext.s212Fixture()
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

private struct S212IntegrationContext {
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
        try? FileManager.default.removeItem(at: repoURL)
        try? FileManager.default.removeItem(at: sourceRootURL)
    }
}

@MainActor
private func makeS212IntegrationContext() async throws -> S212IntegrationContext {
    let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "s212-repo")
    let sourceRootURL = try makeImportSingleFileTemporaryDirectory(prefix: "s212-source")
    let repoOwnedSourceURL = sourceRootURL.appendingPathComponent("batch-owned.pdf")
    let indexedSourceURL = sourceRootURL.appendingPathComponent("batch-indexed.pdf")
    try Data("repo owned bytes".utf8).write(to: repoOwnedSourceURL)
    try Data("indexed bytes".utf8).write(to: indexedSourceURL)

    let bridge = CoreBridge()
    try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
    let repoOwned = try await bridge.importCopiedFile(
        repoPath: repoURL.path,
        sourceURL: repoOwnedSourceURL,
        overrideCategory: "docs",
        overrideFilename: "batch-owned.pdf",
        duplicateStrategy: .skip
    )
    let indexOnly = try await bridge.importIndexedFile(
        repoPath: repoURL.path,
        sourceURL: indexedSourceURL,
        overrideCategory: "docs",
        overrideFilename: "batch-indexed.pdf",
        duplicateStrategy: .skip
    )
    let opening = try await makeS212Opening(repoURL: repoURL, bridge: bridge)
    let model = MainFileListModel(
        opening: opening,
        fileLister: bridge,
        fileDetailer: bridge,
        batchCategoryChanger: bridge,
        undoActionStore: bridge,
        changeLogLister: bridge,
        errorMapper: bridge
    )
    return S212IntegrationContext(
        repoURL: repoURL,
        sourceRootURL: sourceRootURL,
        externalSourceURL: indexedSourceURL,
        repoOwnedDocsURL: repoURL.appendingPathComponent(repoOwned.path),
        repoOwnedFinanceURL: repoURL.appendingPathComponent("finance/batch-owned.pdf"),
        opening: opening,
        bridge: bridge,
        model: model,
        repoOwned: repoOwned,
        indexOnly: indexOnly
    )
}

private func makeS212Opening(repoURL: URL, bridge: CoreBridge) async throws -> RepositoryOpeningResult {
    let config = try await bridge.loadConfig(repoPath: repoURL.path)
    let tree = try await bridge.listTree(repoPath: repoURL.path, locale: "zh-Hans")
    return RepositoryOpeningResult(config: config, tree: tree, currentCategoryFiles: [])
}

private actor S212ClassifierSettingsLoader: CoreConfigurationLoading {
    private let repoPath: String

    init(repoPath: String) {
        self.repoPath = repoPath
    }

    func loadConfig(repoPath _: String) async throws -> RepoConfigSnapshot {
        RepoConfigSnapshot.s212ClassifierFixture(repoPath: repoPath)
    }
}

private actor S212ClassifierSettingsUpdater: CoreConfigurationUpdating {
    func updateConfig(repoPath _: String, newConfig _: RepoConfigSnapshot) async throws {}
}

private actor S212ClassifierSettingsPredictor: CoreCategoryPredicting {
    func predictCategory(repoPath _: String, filename: String) async throws -> ClassifyResultSnapshot {
        ClassifyResultSnapshot(category: "inbox", suggestedName: filename, reason: .default, confidence: 0)
    }
}

private actor S212ClassifierSettingsErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "\(error)",
            severity: .medium,
            suggestedAction: "Retry",
            recoverability: .retryable,
            rawContext: "\(error)"
        )
    }
}

private struct S212ClassifierSettingsAnnouncer: AccessibilityAnnouncing {
    @MainActor
    func announce(_: String) {}
}

private final class S212ClassifierRulesManager: ClassifierRulesManaging {
    private let fileManager = FileManager.default

    func classifierFileExists(repoPath: String) -> Bool {
        fileManager.fileExists(atPath: classifierURL(repoPath: repoPath).path)
    }

    func classifierCategorySlugs(repoPath: String) throws -> [String] {
        let yaml = try String(contentsOf: classifierURL(repoPath: repoPath), encoding: .utf8)
        return ClassifierRulesCategorySlugParser.slugs(in: yaml)
    }

    func lastValidBackupExists(repoPath: String) -> Bool {
        fileManager.fileExists(atPath: backupURL(repoPath: repoPath).path)
    }

    func createDefaultClassifier(repoPath _: String) throws {}

    func storeLastValidBackup(repoPath: String) throws {
        let yaml = try String(contentsOf: classifierURL(repoPath: repoPath), encoding: .utf8)
        try yaml.write(to: backupURL(repoPath: repoPath), atomically: true, encoding: .utf8)
    }

    func restoreLastValidBackup(repoPath: String) throws {
        let yaml = try String(contentsOf: backupURL(repoPath: repoPath), encoding: .utf8)
        try yaml.write(to: classifierURL(repoPath: repoPath), atomically: true, encoding: .utf8)
    }

    func writeClassifier(repoURL: URL, slugs: [String]) throws {
        let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
        try fileManager.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        let yaml = """
        version: 1
        default: inbox
        categories:
        \(slugs.map { "  - slug: \($0)" }.joined(separator: "\n"))
        """
        try yaml.write(to: classifierURL(repoPath: repoURL.path), atomically: true, encoding: .utf8)
    }

    private func classifierURL(repoPath: String) -> URL {
        URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("classifier.yaml", isDirectory: false)
    }

    private func backupURL(repoPath: String) -> URL {
        URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("classifier.last-valid.yaml", isDirectory: false)
    }
}

private extension RepoConfigSnapshot {
    static func s212ClassifierFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "system",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}

private extension BatchChangeCategoryReturnContext {
    static func s212Fixture(
        initialTargetCategory: String? = nil
    ) -> BatchChangeCategoryReturnContext {
        let route = BatchChangeCategoryRoute.s212Route(initialTargetCategory: initialTargetCategory)
        return BatchChangeCategoryReturnContext(
            route: route,
            handoff: BatchChangeCategoryNewCategoryHandoff(
                selectedFileIDs: route.fileIDs,
                currentTargetCategory: "finance"
            )
        )
    }
}

private extension BatchChangeCategoryRoute {
    static func s212Route(initialTargetCategory: String? = nil) -> BatchChangeCategoryRoute {
        BatchChangeCategoryRoute(
            source: .commandPalette,
            fileIDs: [1, 2],
            selectedFiles: [
                .s212RouteFixture(id: 1, currentName: "a.pdf"),
                .s212RouteFixture(id: 2, currentName: "b.pdf")
            ],
            selectedCount: 2,
            disabledReason: nil,
            initialTargetCategory: initialTargetCategory
        )
    }
}

private extension FileEntrySnapshot {
    static func s212RouteFixture(id: Int64, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 128,
            hashSha256: "s212-route-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

private func assertS212Preview(
    _ preview: BatchCategoryPreviewReportSnapshot,
    context: S212IntegrationContext
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

private func assertS212Applied(
    _ report: BatchCategoryChangeReportSnapshot,
    context: S212IntegrationContext
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

@MainActor
private func waitForS212CategoryRefresh(
    _ model: MainFileListModel,
    expectedCategory: String,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0 ..< 100 {
        if Set(model.files.map(\.category)) == [expectedCategory] {
            return
        }
        await Task.yield()
    }
    XCTFail("Timed out waiting for S2-12 category refresh", file: file, line: line)
}
