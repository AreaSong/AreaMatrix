@testable import AreaMatrix
import XCTest

final class ErrorRecoveryPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS308C309SemanticIndexChecksPrivacyRulesBeforeCoreBuild() async {
        let request = SearchQueryRequestSnapshot.s308SemanticPrivacyFixture()
        let semantic = S308PrivacySemanticSearcher()
        let privacy = S308PrivacyRulesBridge(report: .s308Allowed())
        let model = MainFileListModel(
            opening: .initDoneFixture(repoPath: "/tmp/repo", fileCount: 0),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(.deleteFixture(
                id: 680,
                name: "invoice.pdf",
                storageMode: "Copied"
            ))),
            semanticSearching: semantic,
            aiPrivacyRules: privacy,
            errorMapper: S308PrivacyErrorMapper()
        )
        model.searchState = .loaded(request: request, page: .s308SemanticPrivacyPage(route: .remote))

        await model.buildSemanticIndexForCurrentSearch()

        let privacyRequests = await privacy.requests()
        let indexRequests = await semantic.indexRequests()
        XCTAssertEqual(privacyRequests.loadCount, 1)
        XCTAssertEqual(privacyRequests.evaluations.first?.feature, .semanticSearch)
        XCTAssertEqual(privacyRequests.evaluations.first?.route, .remote)
        XCTAssertEqual(privacyRequests.evaluations.first?.context.repoRelativePath, "finance/invoices")
        XCTAssertEqual(privacyRequests.evaluations.first?.context.fileName, "客户合同")
        XCTAssertEqual(privacyRequests.evaluations.first?.context.category, "finance")
        XCTAssertEqual(privacyRequests.evaluations.first?.context.extension, "pdf")
        XCTAssertEqual(privacyRequests.evaluations.first?.context.tags, ["confidential"])
        XCTAssertEqual(indexRequests, [request])
        XCTAssertTrue(model.semanticPrivacyGateState.allowsIndexBuild)
    }

    @MainActor
    func testS308C309PrivacyRuleBlockPreventsSemanticIndexBuild() async {
        let request = SearchQueryRequestSnapshot.s308SemanticPrivacyFixture()
        let semantic = S308PrivacySemanticSearcher()
        let privacy = S308PrivacyRulesBridge(report: .s308Blocked())
        let model = MainFileListModel(
            opening: .initDoneFixture(repoPath: "/tmp/repo", fileCount: 0),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(.deleteFixture(
                id: 681,
                name: "confidential.pdf",
                storageMode: "Copied"
            ))),
            semanticSearching: semantic,
            aiPrivacyRules: privacy,
            errorMapper: S308PrivacyErrorMapper()
        )
        model.searchState = .loaded(request: request, page: .s308SemanticPrivacyPage(route: .remote))

        await model.buildSemanticIndexForCurrentSearch()

        let indexRequests = await semantic.indexRequests()
        XCTAssertEqual(indexRequests, [])
        XCTAssertEqual(model.semanticPrivacyGateState.matchedRuleID, "rule-confidential")
        XCTAssertFalse(model.semanticIndexBuildState.isBuilding)
    }

    @MainActor
    func testS132PageIntegrationConnectsStartupRecoveryMappingEntryExitAndTreeState() async throws {
        let mapping = CoreErrorMappingSnapshot.s132IntegrationMapping(
            userMessage: "Startup recovery could not finish",
            severity: .medium,
            recoverability: .retryable,
            rawContext: "database is locked"
        )
        let recoverer = MainLoadingRecordingStartupRecoverer(results: [
            .failure(CoreError.Db(message: "database is locked")),
            .success(RecoveryReportSnapshot(cleanedStagingFiles: 1, revertedStagingDbRows: 1, warnings: []))
        ])
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: "/tmp/s132-repo", fileCount: 1)
        )
        let treeLister = MainLoadingRecordingTreeLister(result: .success(.mainLoadingTreeFixture()))
        let model = OnboardingModel(
            settingsReader: MainLoadingStaticSettingsReader(repoPath: nil),
            settingsWriter: MainLoadingRecordingSettingsWriter(),
            pathValidator: S132IntegrationPathValidator(),
            initializedPathValidator: S132IntegrationInitializedPathValidator(),
            emptyRepositoryOpener: opener,
            mainLoadingTreeLister: treeLister,
            startupRecoverer: recoverer,
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(nil)),
            errorMapper: S132IntegrationErrorMapper(mapping: mapping),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        await model.openExistingRepository(
            RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: "/tmp/s132-repo")
        )
        let failedState = try requireS132MainLoadingState(model)

        let initialRecoveryRequests = await recoverer.requestedRepoPaths()
        let initialOpenRequests = await opener.requestedConfiguredRepoPaths()
        XCTAssertEqual(initialRecoveryRequests, ["/tmp/s132-repo"])
        XCTAssertEqual(initialOpenRequests, [])
        assertS132StartupRecoveryFailureState(failedState, mapping: mapping)

        let retryTask = await assertS132RetryingState(model: model, opener: opener, recoverer: recoverer)

        await opener.finishOpen()
        await retryTask.value

        let treeRequests = await treeLister.requestedRepoPaths()
        XCTAssertEqual(treeRequests, ["/tmp/s132-repo"])
        XCTAssertEqual(
            model.route,
            OnboardingModel.Route.mainList(.mainLoadingFixture(repoPath: "/tmp/s132-repo", fileCount: 1))
        )
    }

    @MainActor
    func testS132PageIntegrationRoutesFatalDbMappingToRepairWithoutRunningRepair() async {
        let mapping = CoreErrorMappingSnapshot.s132IntegrationMapping(
            userMessage: "Repository metadata needs repair",
            severity: .critical,
            recoverability: .fatal,
            rawContext: "database corrupted"
        )
        let recoverer = MainLoadingRecordingStartupRecoverer(
            result: .failure(CoreError.Db(message: "database corrupted"))
        )
        let model = OnboardingModel(
            settingsReader: MainLoadingStaticSettingsReader(repoPath: nil),
            pathValidator: S132IntegrationPathValidator(),
            initializedPathValidator: S132IntegrationInitializedPathValidator(),
            emptyRepositoryOpener: MainLoadingFailingRepositoryOpener(
                error: CoreError.Internal(message: "should not open")
            ),
            startupRecoverer: recoverer,
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(nil)),
            errorMapper: S132IntegrationErrorMapper(mapping: mapping),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        await model.openExistingRepository(
            RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: "/tmp/s132-corrupt")
        )

        let recoveryRequests = await recoverer.requestedRepoPaths()
        XCTAssertEqual(recoveryRequests, ["/tmp/s132-corrupt"])
        XCTAssertEqual(model.route, OnboardingModel.Route.mainRepoError("/tmp/s132-corrupt", mapping))
        model.openMainRepositoryRepair(repoPath: "/tmp/s132-corrupt")
        XCTAssertEqual(
            model.route,
            OnboardingModel.Route.dbRepairConfirm(DatabaseRepairRouteState(
                repoPath: "/tmp/s132-corrupt",
                scanSession: nil,
                mapping: mapping,
                returnRoute: .mainRepoError(mapping)
            ))
        )
    }
}

@MainActor
private func assertS132RetryingState(
    model: OnboardingModel,
    opener: MainLoadingPausingRepositoryOpener,
    recoverer: MainLoadingRecordingStartupRecoverer
) async -> Task<Void, Never> {
    let retryTask = Task {
        await model.retryMainRepositoryFromError(repoPath: "/tmp/s132-repo")
    }
    await opener.waitUntilStarted()
    let expectedRecoveryReport = RecoveryReportSnapshot(
        cleanedStagingFiles: 1,
        revertedStagingDbRows: 1,
        warnings: []
    )
    let retryingState = await waitForS132IntegrationMainLoadingState(model) { state in
        state.startupRecovery == .completed(expectedRecoveryReport) &&
            state.treeLoading?.loadedTree != nil
    }
    let retryingRecoveryView = StartupRecoveryErrorRecoveryView(
        state: retryingState.startupRecovery ?? .checking,
        isRetrying: true,
        onRetry: {}
    )

    let retryRecoveryRequests = await recoverer.requestedRepoPaths()
    let retryOpenRequests = await opener.requestedConfiguredRepoPaths()
    XCTAssertEqual(retryRecoveryRequests, ["/tmp/s132-repo", "/tmp/s132-repo"])
    XCTAssertEqual(retryOpenRequests, ["/tmp/s132-repo"])
    XCTAssertEqual(retryingState.recoveryVisibleReport?.cleanedStagingFiles, 1)
    XCTAssertEqual(retryingRecoveryView.retryButtonTitle, "Retrying...")
    XCTAssertTrue(retryingRecoveryView.retryButtonIsDisabled)
    return retryTask
}

@MainActor
private func requireS132MainLoadingState(
    _ model: OnboardingModel,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> MainLoadingState {
    guard case let .mainLoading(state) = model.route else {
        XCTFail(
            "Expected startup recovery failure to remain on S1-32 main loading error recovery",
            file: file,
            line: line
        )
        throw CoreError.Internal(message: "expected main loading")
    }
    return state
}

private func assertS132StartupRecoveryFailureState(
    _ state: MainLoadingState,
    mapping: CoreErrorMappingSnapshot
) {
    let recoveryView = StartupRecoveryErrorRecoveryView(
        state: state.startupRecovery ?? .checking,
        isRetrying: false,
        onRetry: {}
    )
    let mainBody = s132IntegrationMirrorDescription(of: MainLoadingView(
        state: state,
        isRetryingStartupRecovery: false,
        onCancelOpening: {},
        onRetryStartupRecovery: {},
        onRetryTree: {},
        onRetryOpening: {}
    ).body)

    XCTAssertEqual(state.recoveryErrorMapping, mapping)
    XCTAssertTrue(state.recoveryStatusText?.contains("Startup recovery could not finish") == true)
    XCTAssertEqual(recoveryView.retryButtonTitle, "Retry startup recovery")
    XCTAssertFalse(recoveryView.retryButtonIsDisabled)
    XCTAssertTrue(mainBody.contains("Cancel opening"))
    XCTAssertFalse(RepositoryErrorPresentation.mainRepo(mapping: mapping).primaryAction == .openRepair)
}

private actor S132IntegrationPathValidator: CoreRepositoryPathValidating {
    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        .mainLoadingInitializedFixture(repoPath: repoPath)
    }
}

private actor S132IntegrationInitializedPathValidator: CoreInitializedRepositoryPathValidating {
    func validateInitializedRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        .mainLoadingInitializedFixture(repoPath: repoPath)
    }
}

private actor S132IntegrationErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        mapping
    }
}

private actor S308PrivacySemanticSearcher: CoreSemanticSearching {
    private var recordedIndexRequests: [SearchQueryRequestSnapshot] = []

    func semanticSearch(repoPath _: String,
                        request _: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        throw CoreError.Internal(message: "S3-08 C3-09 test does not execute semantic search")
    }

    func buildEmbeddingIndex(
        repoPath _: String,
        request: SearchQueryRequestSnapshot
    ) async throws -> SemanticIndexBuildReportSnapshot {
        recordedIndexRequests.append(request)
        return SemanticIndexBuildReportSnapshot(
            status: .ready,
            route: .remote,
            totalCount: 1,
            processedCount: 1,
            skippedCount: 0,
            failedCount: 0,
            privacySkippedCount: 0,
            providerName: "OpenAI",
            callLogID: 680,
            fallbackReason: nil,
            message: nil
        )
    }

    func indexRequests() -> [SearchQueryRequestSnapshot] {
        recordedIndexRequests
    }
}

private actor S308PrivacyRulesBridge: CoreAIPrivacyEvaluating {
    struct Requests: Equatable {
        var loadCount = 0
        var evaluations: [AiPrivacyEvaluationRequest] = []
    }

    private let report: AiPrivacyEvaluationReport
    private var recorded = Requests()

    init(report: AiPrivacyEvaluationReport) {
        self.report = report
    }

    func loadAIPrivacyRules(repoPath _: String) async throws -> AiPrivacyRulesSnapshot {
        recorded.loadCount += 1
        return .s308PrivacyRules()
    }

    func evaluateAIPrivacy(
        repoPath _: String,
        request: AiPrivacyEvaluationRequest
    ) async throws -> AiPrivacyEvaluationReport {
        recorded.evaluations.append(request)
        return report
    }

    func requests() -> Requests {
        recorded
    }
}

private struct S308PrivacyErrorMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "Semantic privacy rules could not be checked.",
            severity: .high,
            suggestedAction: "Retry privacy check.",
            recoverability: .retryable,
            rawContext: "S3-08 C3-09"
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func s132IntegrationMapping(
        userMessage: String,
        severity: CoreErrorSeveritySnapshot,
        recoverability: CoreErrorRecoverabilitySnapshot,
        rawContext: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: userMessage,
            severity: severity,
            suggestedAction: "Retry startup recovery before opening the repository.",
            recoverability: recoverability,
            rawContext: rawContext
        )
    }
}

private extension SearchQueryRequestSnapshot {
    static func s308SemanticPrivacyFixture() -> SearchQueryRequestSnapshot {
        var filters = SearchFilterStateSnapshot.empty
        filters.category = "finance"
        filters.fileKind = ".pdf"
        filters.tags = [" confidential ", ""]
        return SearchQueryRequestSnapshot(
            query: "客户合同",
            scope: .current,
            currentPath: "finance/invoices",
            category: nil,
            filters: filters,
            sort: .relevance,
            limit: 50,
            offset: 0,
            mode: .semantic
        )
    }
}

private extension SearchResultPageSnapshot {
    static func s308SemanticPrivacyPage(route: SemanticSearchRouteSnapshot) -> SearchResultPageSnapshot {
        let semanticPage = SemanticSearchResultPageSnapshot(
            query: "客户合同",
            semanticTotalCount: 0,
            normalTotalCount: 0,
            semanticMatches: [],
            normalMatches: [],
            dedupedNormalCount: 0,
            indexStatus: .notReady,
            route: route,
            fallbackReason: .semanticIndexNotReady,
            fallbackMessage: nil,
            callLogID: nil,
            privacyRuleID: nil,
            lowConfidence: false
        )
        return SearchResultPageSnapshot(
            query: "客户合同",
            totalCount: 0,
            results: [],
            diagnostics: [],
            indexStatus: .unavailable,
            semanticPage: semanticPage
        )
    }
}

private extension AiPrivacyRulesSnapshot {
    static func s308PrivacyRules() -> AiPrivacyRulesSnapshot {
        AiPrivacyRulesSnapshot(
            privacyGateEnabled: true,
            rules: [],
            remoteAllowedFields: [
                AiPrivacyFieldState(field: .fileName, allowRemote: true, lastMatchedCount: 0),
                AiPrivacyFieldState(field: .repoRelativePath, allowRemote: true, lastMatchedCount: 0),
                AiPrivacyFieldState(field: .extension, allowRemote: true, lastMatchedCount: 0)
            ],
            providerScope: AiPrivacyProviderScopeSnapshot(
                providerConfigured: true,
                providerVerified: true,
                remoteProviderEnabled: true,
                featureScope: [.semanticSearch]
            ),
            updatedAt: 1_700_000_300,
            remoteBlockedByDefault: true
        )
    }
}

private extension AiPrivacyEvaluationReport {
    static func s308Allowed() -> AiPrivacyEvaluationReport {
        AiPrivacyEvaluationReport(
            decision: .allowed,
            skippedReason: nil,
            providerGateReason: nil,
            matchedRules: [],
            matchedFieldType: nil,
            allowedFields: [.fileName, .repoRelativePath, .extension],
            blockedFields: [.extractedTextExcerpt],
            sentFields: [.fileName, .repoRelativePath],
            message: "Privacy rules allow semantic index metadata."
        )
    }

    static func s308Blocked() -> AiPrivacyEvaluationReport {
        AiPrivacyEvaluationReport(
            decision: .skipped,
            skippedReason: .privacyRule,
            providerGateReason: nil,
            matchedRules: [
                AiPrivacyRuleMatch(
                    ruleId: "rule-confidential",
                    name: "Block confidential",
                    kind: .keyword,
                    pattern: "confidential",
                    appliesTo: .remoteAi,
                    matchedField: .fileName
                )
            ],
            matchedFieldType: .fileName,
            allowedFields: [],
            blockedFields: [.fileName, .repoRelativePath, .extractedTextExcerpt],
            sentFields: [],
            message: "A privacy rule blocked semantic index input."
        )
    }
}

@MainActor
private func waitForS132IntegrationMainLoadingState(
    _ model: OnboardingModel,
    matching predicate: (MainLoadingState) -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> MainLoadingState {
    if let state = await waitForMainLoadingState(model, matching: predicate, file: file, line: line) {
        return state
    }

    return MainLoadingState(repoPath: "")
}

private func s132IntegrationMirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    appendS132IntegrationMirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func appendS132IntegrationMirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label {
            lines.append(label)
        }
        appendS132IntegrationMirrorDescription(of: child.value, to: &lines)
    }
}
