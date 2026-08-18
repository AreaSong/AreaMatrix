@testable import AreaMatrix
import AreaMatrixCoreBridgeContract
import XCTest

typealias MainListIntegrationDetailer = RecordingFileDetailer

typealias MainListIntegrationDiagnosticsCollector = RecordingDiagnosticsCollector

typealias MainListIntegrationNoopDetailer = RecordingFileDetailer

typealias MainListRecordingFileLister = RecordingFileLister

typealias MainListRecordingSearchQuerying = RecordingSearchQuerying

typealias MainListSearchRequestRecord = SearchQueryRequestRecord

typealias MainListSmartListRequestRecord = SmartListRunRequestRecord

@MainActor
func requireSidebarRow(
    _ tree: RepositoryTreeNodeSnapshot,
    id: String,
    message: String? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) -> RepositorySidebarRowSnapshot? {
    guard let row = tree.sidebarRow(id: id) else {
        XCTFail(message ?? "Expected sidebar row \(id)", file: file, line: line)
        return nil
    }
    return row
}

struct MainListFallbackRequestRecord: Equatable {
    var repoPath: String
    var request: AIFallbackStatusRequestSnapshot
}

private enum MainFileListModelTestDefaults {
    static var dependencies: MainListFeatureDependencies {
        makeTestAppDependencyContainer().feature.mainList
    }
}

@MainActor
extension MainFileListModel {
    func beginClassifierRuleHandoff(
        fileID: Int64,
        targetCategory: String,
        moveFile: Bool,
        destination: ClassifierRuleHandoffDestination
    ) {
        guard canPerformWriteAction(fileID: fileID), let file = actionRoutingFile(for: fileID) else { return }
        fileActionCoordinator.beginClassifierRuleHandoff(
            file: file,
            targetCategory: targetCategory,
            moveFile: moveFile,
            destination: destination
        )
    }

    func completeClassifierRuleSave(_ savedRule: ClassifierRuleSnapshot) {
        fileActionCoordinator.completeClassifierRuleSave(savedRule)
        statusBanner = .savedClassifierRule(category: savedRule.targetCategory)
    }

    func cancelClassifierRuleRoute() {
        fileActionCoordinator.cancelClassifierRuleRoute()
    }

    func loadClassifierCorrectionContext(fileID: Int64, filename: String) async {
        guard canPerformWriteAction(fileID: fileID) else { return }
        await fileActionCoordinator.loadClassifierCorrectionContext(fileID: fileID, filename: filename)
    }

    func loadMoveToCategoryPreview(fileID: Int64, targetCategory: String) async {
        guard canPerformWriteAction(fileID: fileID) else { return }
        await fileActionCoordinator.loadMoveToCategoryPreview(fileID: fileID, targetCategory: targetCategory)
    }

    @discardableResult
    func submitMoveToCategory(
        fileID: Int64,
        targetCategory: String,
        mode: MainFileCategoryMoveMode = .moveToCategory,
        options: MainFileCategoryMoveOptions = MainFileCategoryMoveOptions(moveFile: true, remember: false),
        onMoved: FileActionCoordinator.MoveToCategoryCompletion? = nil
    ) async -> Bool {
        guard canPerformWriteAction(fileID: fileID),
              let outcome = await fileActionCoordinator.submitMoveToCategory(
                  fileID: fileID,
                  targetCategory: targetCategory,
                  mode: mode,
                  options: options,
                  onMoved: onMoved
              ) else { return false }
        await applyCategoryMoveOutcome(outcome)
        return true
    }

    @discardableResult
    func submitAIClassificationSuggestion(_ request: AIClassificationSuggestionApplyRequest) async -> Bool {
        guard canPerformWriteAction(fileID: request.fileID),
              let outcome = await fileActionCoordinator.submitAIClassificationSuggestion(request) else { return false }
        await applyAIClassificationOutcome(outcome, request: request)
        return true
    }

    /// Keeps existing tests focused on the collaborators they override while
    /// production construction requires one explicit feature dependency scope.
    convenience init(
        opening: RepositoryOpeningResult,
        fileLister: any CoreFileListing,
        fileDetailer: any CoreFileDetailing,
        fileResourceAccess: any ImportFileResourceAccessing =
            MainFileListModelTestDefaults.dependencies.fileResourceAccess,
        missingFileRecoverer: any CoreMissingFileRecovering =
            MainFileListModelTestDefaults.dependencies.missingFileRecoverer,
        missingFilePicker: any RepositoryMissingFilePicking =
            MainFileListModelTestDefaults.dependencies.missingFilePicker,
        searchQuerying: any CoreSearchQuerying =
            MainFileListModelTestDefaults.dependencies.searchQuerying,
        semanticSearching: any CoreSemanticSearching =
            MainFileListModelTestDefaults.dependencies.semanticSearching,
        semanticFallbackReader: any CoreSemanticFallbackStatusReading =
            MainFileListModelTestDefaults.dependencies.semanticFallbackReader,
        searchFiltering: any CoreSearchFiltering =
            MainFileListModelTestDefaults.dependencies.searchFiltering,
        fileRenamer: any CoreFileRenaming =
            MainFileListModelTestDefaults.dependencies.fileRenamer,
        fileDeleter: any CoreFileDeleting =
            MainFileListModelTestDefaults.dependencies.fileDeleter,
        fileCategoryMover: any CoreFileCategoryMoving =
            MainFileListModelTestDefaults.dependencies.fileCategoryMover,
        categoryPredictor: any CoreCategoryPredicting =
            MainFileListModelTestDefaults.dependencies.categoryPredictor,
        batchDeleter: any CoreBatchDeleting =
            MainFileListModelTestDefaults.dependencies.batchDeleter,
        batchCategoryChanger: any CoreBatchCategoryChanging =
            MainFileListModelTestDefaults.dependencies.batchCategoryChanger,
        iCloudConflictResolver: any ICloudConflictResolving =
            MainFileListModelTestDefaults.dependencies.iCloudConflictResolver,
        tagStore: any CoreTagCRUD = MainFileListModelTestDefaults.dependencies.tagStore,
        aiSettingsLoader: any CoreAISettingsLoading =
            MainFileListModelTestDefaults.dependencies.aiSettingsLoader,
        aiTagSuggestionStore: any CoreAITagSuggestionManaging =
            MainFileListModelTestDefaults.dependencies.aiTagSuggestionStore,
        aiPrivacyRules: any CoreAIPrivacyEvaluating =
            MainFileListModelTestDefaults.dependencies.aiPrivacyRules,
        undoActionStore: any CoreUndoActionLogging =
            MainFileListModelTestDefaults.dependencies.undoActionStore,
        redoActionStore: any CoreRedoActionLogging =
            MainFileListModelTestDefaults.dependencies.redoActionStore,
        changeLogLister: any CoreChangeLogListing =
            MainFileListModelTestDefaults.dependencies.changeLogLister,
        externalChangesSyncer: any CoreExternalChangesSyncing =
            MainFileListModelTestDefaults.dependencies.externalChangesSyncer,
        repositoryWriteCoordinator: RepositoryWriteCoordinator =
            MainFileListModelTestDefaults.dependencies.repositoryWriteCoordinator,
        errorMapper: any CoreErrorMapping,
        diagnosticsCollector: any CoreDiagnosticsCollecting =
            MainFileListModelTestDefaults.dependencies.diagnosticsCollector
    ) {
        self.init(
            opening: opening,
            dependencies: MainListFeatureDependencies(
                fileResourceAccess: fileResourceAccess,
                fileLister: fileLister,
                fileDetailer: fileDetailer,
                aiPrivacyRules: aiPrivacyRules,
                aiSettingsLoader: aiSettingsLoader,
                aiTagSuggestionStore: aiTagSuggestionStore,
                batchCategoryChanger: batchCategoryChanger,
                batchDeleter: batchDeleter,
                categoryPredictor: categoryPredictor,
                changeLogLister: changeLogLister,
                externalChangesSyncer: externalChangesSyncer,
                fileCategoryMover: fileCategoryMover,
                fileDeleter: fileDeleter,
                fileRenamer: fileRenamer,
                iCloudConflictResolver: iCloudConflictResolver,
                missingFileRecoverer: missingFileRecoverer,
                missingFilePicker: missingFilePicker,
                redoActionStore: redoActionStore,
                searchFiltering: searchFiltering,
                searchQuerying: searchQuerying,
                semanticFallbackReader: semanticFallbackReader,
                semanticSearching: semanticSearching,
                tagStore: tagStore,
                undoActionStore: undoActionStore,
                repositoryWriteCoordinator: repositoryWriteCoordinator,
                errorMapper: errorMapper,
                diagnosticsCollector: diagnosticsCollector
            )
        )
    }
}

extension MainListFallbackRequestRecord {
    static func semanticSearchIndexNotReady(repoPath: String, callLogID: Int64) -> MainListFallbackRequestRecord {
        MainListFallbackRequestRecord(
            repoPath: repoPath,
            request: AIFallbackStatusRequestSnapshot(
                operation: .semanticSearch,
                route: .remote,
                providerError: nil,
                providerErrorCode: nil,
                privacyDecision: nil,
                privacySkippedReason: nil,
                categorySkippedReason: nil,
                semanticFallbackReason: .semanticIndexNotReady,
                callLogStatus: .failed,
                callLogID: callLogID,
                privacyRuleID: nil,
                retryAfter: nil
            )
        )
    }
}

actor MainListRecordingSemanticSearcher: CoreSemanticSearching {
    private let page: SearchResultPageSnapshot

    init(page: SearchResultPageSnapshot) {
        self.page = page
    }

    func semanticSearch(repoPath _: String,
                        request _: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        page
    }

    func buildEmbeddingIndex(
        repoPath _: String,
        request _: SearchQueryRequestSnapshot
    ) async throws -> SemanticIndexBuildReportSnapshot {
        throw CoreError.Internal(message: "semantic-search ai-fallback-core test does not build the semantic index")
    }
}

actor MainListRecordingSemanticFallbackReader: CoreSemanticFallbackStatusReading {
    private let status: AIFallbackStatusSnapshot
    private var requests: [MainListFallbackRequestRecord] = []

    init(status: AIFallbackStatusSnapshot) {
        self.status = status
    }

    func semanticFallbackStatus(repoPath: String,
                                request: AIFallbackStatusRequestSnapshot) async throws -> AIFallbackStatusSnapshot {
        requests.append(MainListFallbackRequestRecord(repoPath: repoPath, request: request))
        return status
    }

    func assertSemanticFallbackStatusRequests(
        _ expectedRequests: [MainListFallbackRequestRecord],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests, expectedRequests, file: file, line: line)
    }
}

actor MainListIntegrationSuspendedLister: CoreFileListing {
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
        _ = await waitForActorTestValue(
            on: self,
            failureMessage: { "Timed out waiting for main list request" },
            value: {
                didReceiveRequest ? true : nil
            }
        )
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}
