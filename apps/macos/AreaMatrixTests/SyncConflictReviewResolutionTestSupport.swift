@testable import AreaMatrix
import Foundation
import XCTest

actor SyncConflictReviewResolver: CoreSyncConflictResolving {
    private let previewResults: [
        SyncConflictResolutionStrategySnapshot: Result<SyncConflictResolutionPreviewSnapshot, Error>
    ]
    private let resolveResult: Result<SyncConflictResolveReportSnapshot, Error>
    private var previewRequests: [SyncConflictPreviewRequest] = []
    private var resolveRequests: [SyncConflictResolveRequest] = []

    init(
        previewResults: [SyncConflictResolutionStrategySnapshot: Result<SyncConflictResolutionPreviewSnapshot, Error>],
        resolveResult: Result<SyncConflictResolveReportSnapshot, Error> = .success(.syncConflictReviewResolveFixture())
    ) {
        self.previewResults = previewResults
        self.resolveResult = resolveResult
    }

    func previewSyncConflictResolution(
        repoPath: String,
        conflictID: String,
        resolution: SyncConflictResolutionStrategySnapshot
    ) async throws -> SyncConflictResolutionPreviewSnapshot {
        previewRequests.append(SyncConflictPreviewRequest(
            repoPath: repoPath,
            conflictID: conflictID,
            resolution: resolution
        ))
        return try (previewResults[resolution] ?? .success(.syncConflictReviewPreviewFixture(resolution: resolution)))
            .get()
    }

    func resolveSyncConflict(
        repoPath: String,
        conflictID: String,
        request: SyncConflictResolutionRequestSnapshot
    ) async throws -> SyncConflictResolveReportSnapshot {
        resolveRequests.append(SyncConflictResolveRequest(
            repoPath: repoPath,
            conflictID: conflictID,
            request: request
        ))
        return try resolveResult.get()
    }

    func assertResolutionPreviewRequests(
        _ expectedRequests: [SyncConflictPreviewRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(previewRequests, expectedRequests, file: file, line: line)
    }

    func assertPreviewedResolutionStrategies(
        _ expectedResolutions: [SyncConflictResolutionStrategySnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(previewRequests.map(\.resolution), expectedResolutions, file: file, line: line)
    }

    func assertResolutionApplyRequests(
        _ expectedRequests: [SyncConflictResolveRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(resolveRequests, expectedRequests, file: file, line: line)
    }

    func assertResolutionApplyRequestCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(resolveRequests.count, expectedCount, file: file, line: line)
    }
}

actor SyncConflictReviewDetector: CoreSyncConflictDetecting {
    private let result: Result<[SyncConflictSnapshot], Error>
    private var requests: [String] = []

    init(result: Result<[SyncConflictSnapshot], Error>) {
        self.result = result
    }

    func detectSyncConflicts(repoPath: String) async throws -> [SyncConflictSnapshot] {
        requests.append(repoPath)
        return try result.get()
    }

    func assertDetectedSyncConflictRepos(
        _ expectedRequests: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests, expectedRequests, file: file, line: line)
    }

    func assertNoSyncConflictDetections(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertDetectedSyncConflictRepos([], file: file, line: line)
    }
}

struct SyncConflictReplaceContext {
    let detector: SyncConflictReviewDetector
    let resolver: SyncConflictReviewResolver
    let model: SyncConflictReviewModel
    let view: SyncConflictReviewView
    let resolvedReports: SyncConflictReplaceReports
}

final class SyncConflictReplaceReports {
    var reports: [SyncConflictResolveReportSnapshot] = []
}

@MainActor
func makeSyncConflictReplaceContext() -> SyncConflictReplaceContext {
    let detector = SyncConflictReviewDetector(result: .success([.syncConflictReviewFixture()]))
    let resolver = SyncConflictReviewResolver(
        previewResults: [
            .keepBoth: .success(.syncConflictReviewPreviewFixture()),
            .useIncoming: .success(.syncConflictReviewPreviewFixture(
                resolution: .useIncoming,
                canApply: false,
                requiresReplaceConfirmation: true,
                blockedReason: "Replace confirmation required",
                previewToken: "preview-token-use-incoming"
            ))
        ],
        resolveResult: .success(.syncConflictReviewResolveFixture(resolution: .useIncoming))
    )
    let model = SyncConflictReviewModel(
        repoPath: "/tmp/syncConflictReview-repo",
        conflictDetector: detector,
        conflictResolver: resolver,
        errorMapper: StaticCoreErrorMapper(mapping: .syncConflictReviewMapping())
    )
    let resolvedReports = SyncConflictReplaceReports()
    let view = SyncConflictReviewView(
        model: model,
        onBackToNeedsReview: {},
        onClose: {},
        onResolved: { resolvedReports.reports.append($0) }
    )
    return SyncConflictReplaceContext(
        detector: detector,
        resolver: resolver,
        model: model,
        view: view,
        resolvedReports: resolvedReports
    )
}

@MainActor
func assertSyncConflictReplaceResolutionBlocksUnconfirmedApply(
    model: SyncConflictReviewModel,
    panelBody: Any
) {
    XCTAssertFalse(model.canApplyResolution)
    XCTAssertTrue(model.canConfirmReplacePlan)
    assertTestMirrorDescription(of: panelBody, contains: [
        "Confirm Replace",
        "Old file path",
        "Old version will be kept at",
        "Affected record",
        "Change log",
        "Recovery note"
    ])
}

@MainActor
func assertSyncConflictReplaceResolutionApplyExit(
    model: SyncConflictReviewModel,
    resolvedReports: [SyncConflictResolveReportSnapshot]
) {
    XCTAssertEqual(resolvedReports, [.syncConflictReviewResolveFixture(resolution: .useIncoming)])
    XCTAssertEqual(model.applyDisabledReason, "Resolution has already been applied.")
}

@MainActor
func makeMainRepositoryContentViewForTests(
    opening: RepositoryOpeningResult,
    state: MainRepositoryContentState,
    fileLister: any CoreFileListing,
    fileDetailer: any CoreFileDetailing,
    errorMapper: any CoreErrorMapping
) -> MainRepositoryContentView {
    let dependencies = AppDependencyContainer.live
    let supporting = makeMainRepositorySupportDependencies(
        dependencies: dependencies,
        errorMapper: errorMapper
    )
    let list = makeMainRepositoryListDependencies(
        dependencies: dependencies,
        fileLister: fileLister,
        fileDetailer: fileDetailer,
        errorMapper: errorMapper
    )
    let features = MainRepositoryContentFeatureDependencies(
        aiFeature: dependencies.feature.aiFeature,
        fileActions: dependencies.feature.fileActions,
        settings: dependencies.feature.settings,
        syncConflicts: dependencies.feature.syncConflicts
    )
    return MainRepositoryContentView(
        opening: opening,
        state: state,
        assembly: .make(opening: opening, supporting: supporting, list: list, features: features),
        commandRouter: .shared,
        onImport: {},
        onDropImport: { _, _ in }
    )
}

@MainActor
private func makeMainRepositorySupportDependencies(
    dependencies: AppDependencyContainer,
    errorMapper: any CoreErrorMapping
) -> MainRepositoryContentSupportDeps {
    let core = dependencies.mainList
    return MainRepositoryContentSupportDeps(
        treeLister: core.treeLister,
        savedSearchStore: core.savedSearchStore,
        batchRenamer: core.batchRenamer,
        systemCapabilityChecker: dependencies.onboarding.systemCapabilityChecker,
        errorMapper: errorMapper,
        syncConflictDetector: core.syncConflictDetector,
        noteStore: core.noteStore,
        inFlightFileChangeTracker: dependencies.platform.inFlightFileChangeTracker,
        dropCategoryPredictor: core.categoryPredictor
    )
}

@MainActor
private func makeMainRepositoryListDependencies(
    dependencies: AppDependencyContainer,
    fileLister: any CoreFileListing,
    fileDetailer: any CoreFileDetailing,
    errorMapper: any CoreErrorMapping
) -> MainRepositoryContentListDependencies {
    let core = dependencies.mainList
    return MainRepositoryContentListDependencies(
        fileLister: fileLister,
        fileDetailer: fileDetailer,
        missingFileRecoverer: core.missingFileRecoverer,
        missingFilePicker: dependencies.platform.missingFilePicker,
        searchQuerying: core.searchQuerying,
        semanticSearching: core.semanticSearching,
        semanticFallbackReader: core.semanticFallbackReader,
        searchFiltering: core.searchFiltering,
        commandIndexer: core.commandIndexer,
        fileRenamer: core.fileRenamer,
        fileDeleter: core.fileDeleter,
        fileCategoryMover: core.fileCategoryMover,
        categoryPredictor: core.categoryPredictor,
        batchDeleter: core.batchDeleter,
        batchCategoryChanger: core.batchCategoryChanger,
        iCloudConflictResolver: core.iCloudConflictResolver,
        tagStore: core.tagStore,
        aiSettingsLoader: core.aiSettingsLoader,
        aiTagSuggestionStore: core.aiTagSuggestionStore,
        aiPrivacyRules: core.aiPrivacyRules,
        undoActionStore: core.undoActionStore,
        redoActionStore: core.redoActionStore,
        changeLogLister: core.changeLogLister,
        externalChangesSyncer: core.externalChangesSyncer,
        repositoryWriteCoordinator: dependencies.onboarding.repositoryWriteCoordinator,
        errorMapper: errorMapper,
        diagnosticsCollector: core.diagnosticsCollector,
        fileResourceAccess: dependencies.feature.import.fileResourceAccess
    )
}
