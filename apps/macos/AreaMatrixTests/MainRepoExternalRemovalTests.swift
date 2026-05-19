@testable import AreaMatrix
import XCTest

final class MainRepoExternalRemovalTests: XCTestCase {
    func testS201PageIntegrationRendersSearchRouteViews() {
        let request = SearchQueryRequestSnapshot.s201RouteFixture(query: "合同")
        let diagnostic = SearchQueryDiagnosticSnapshot(
            severityDisplayName: "Error",
            message: "Unknown field: owner",
            suggestion: "Use category:"
        )

        let emptyBody = s201RouteMirrorDescription(of: SearchEmptyRouteView(request: request, onClear: {}).body)
        let errorBody = s201RouteMirrorDescription(of: QueryErrorRouteView(
            request: request,
            diagnostic: diagnostic,
            onClear: {}
        ).body)
        let saveBody = s201RouteMirrorDescription(of: SavedSearchSheetRouteView(request: request, onCancel: {}).body)
        let indexingBody = s201RouteMirrorDescription(of: SearchIndexingStatusRouteView(
            request: request,
            indexStatus: .unavailable,
            onRetry: {},
            onClose: {}
        ).body)
        let commandBody = s201RouteMirrorDescription(of: SearchCommandPaletteRouteView(query: "合同", onClose: {}).body)

        XCTAssertTrue(emptyBody.contains("S2-04-search-empty"))
        XCTAssertTrue(errorBody.contains("Unknown field: owner"))
        XCTAssertTrue(errorBody.contains("S2-05-query-error"))
        XCTAssertTrue(saveBody.contains("S2-03-search-route"))
        XCTAssertTrue(indexingBody.contains("S2-01-indexing-status-search-route"))
        XCTAssertTrue(commandBody.contains("S2-15-search-route"))
    }

    @MainActor
    func testMainRepoErrorExternalRemovalSyncsMissingFileThroughCoreBridge() async {
        let result = SyncResultSnapshot.shellDeletedFixture()
        let syncer = ShellRecordingExternalChangesSyncer(result: .success(result))
        let opener = ShellRecordingRepositoryOpener(result: .success(
            .shellFixture(repoPath: "/tmp/repo", fileCount: 0)
        ))
        let initializedValidator = ShellRecordingInitializedPathValidator(
            result: .success(.shellFixture(
                repoPath: "/tmp/repo",
                isInitialized: true,
                recommendedMode: nil
            ))
        )
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            initializedPathValidator: initializedValidator,
            emptyRepositoryOpener: opener,
            startupRecoverer: ShellStaticStartupRecoverer(),
            externalChangesSyncer: syncer,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        await model.updateMainRepoExternalRemoval(
            from: CoreError.FileNotFound(path: "/tmp/repo/docs/gone.pdf"),
            repoPath: "/tmp/repo"
        )
        await model.confirmMainRepositoryExternalRemoval(repoPath: "/tmp/repo")
        let requests = await syncer.recordedRequests()
        let validatedPaths = await initializedValidator.requestedRepoPaths()
        let openedPaths = await opener.requestedConfiguredRepoPaths()

        XCTAssertEqual(requests.map(\.repoPath), ["/tmp/repo"])
        XCTAssertEqual(requests.map(\.relativePath), ["docs/gone.pdf"])
        XCTAssertEqual(validatedPaths, ["/tmp/repo"])
        XCTAssertEqual(openedPaths, ["/tmp/repo"])
        XCTAssertEqual(model.mainRepoExternalRemoval, .synced(result))
        XCTAssertEqual(model.route, .mainEmpty(.shellFixture(repoPath: "/tmp/repo", fileCount: 0)))
        XCTAssertFalse(model.isRetryingMainRepository)
    }

    @MainActor
    func testMainRepoErrorExternalRemovalIgnoresPathOutsideRepository() async {
        let syncer = ShellRecordingExternalChangesSyncer(result: .success(.shellDeletedFixture()))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            startupRecoverer: ShellStaticStartupRecoverer(),
            externalChangesSyncer: syncer,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        await model.updateMainRepoExternalRemoval(
            from: CoreError.FileNotFound(path: "/tmp/other/gone.pdf"),
            repoPath: "/tmp/repo"
        )
        await model.confirmMainRepositoryExternalRemoval(repoPath: "/tmp/repo")
        let requests = await syncer.recordedRequests()

        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.mainRepoExternalRemoval, .unavailable)
        XCTAssertFalse(model.isRetryingMainRepository)
    }

    @MainActor
    func testMainRepoErrorExternalRemovalKeepsErrorStateWhenCoreSyncFails() async {
        let syncer = ShellRecordingExternalChangesSyncer(result: .failure(CoreError.Db(message: "db locked")))
        let opener = ShellRecordingRepositoryOpener(result: .success(
            .shellFixture(repoPath: "/tmp/repo", fileCount: 0)
        ))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            startupRecoverer: ShellStaticStartupRecoverer(),
            externalChangesSyncer: syncer,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        await model.updateMainRepoExternalRemoval(
            from: CoreError.FileNotFound(path: "/tmp/repo/docs/gone.pdf"),
            repoPath: "/tmp/repo"
        )
        await model.confirmMainRepositoryExternalRemoval(repoPath: "/tmp/repo")
        let openedPaths = await opener.requestedConfiguredRepoPaths()

        guard case let .failed(failureMapping) = model.mainRepoExternalRemoval else {
            return XCTFail("expected failed external removal state")
        }
        guard case let .mainRepoError(repoPath, routeMapping) = model.route else {
            return XCTFail("expected main repo error, got \(model.route)")
        }

        XCTAssertEqual(openedPaths, [])
        XCTAssertEqual(repoPath, "/tmp/repo")
        XCTAssertEqual(failureMapping.kind, .db)
        XCTAssertEqual(routeMapping?.kind, .db)
        XCTAssertEqual(model.mainRepoRecoveryErrorMapping?.kind, .db)
        XCTAssertFalse(model.isRetryingMainRepository)
    }
}

private extension SearchQueryRequestSnapshot {
    static func s201RouteFixture(query: String) -> SearchQueryRequestSnapshot {
        SearchQueryRequestSnapshot(
            query: query,
            scope: .current,
            currentPath: "docs/contracts",
            category: "docs",
            filters: .s201RouteFilters,
            sort: .relevance,
            limit: 50,
            offset: 0
        )
    }
}

private extension SearchFilterStateSnapshot {
    static let s201RouteFilters = SearchFilterStateSnapshot(
        category: "docs",
        fileKind: "pdf",
        tags: ["contract"],
        tagMatchMode: .any,
        importedAfter: nil,
        importedBefore: nil,
        modifiedAfter: nil,
        modifiedBefore: nil,
        storageMode: .copied,
        includeDeleted: false
    )
}

private func s201RouteMirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    s201RouteAppendMirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func s201RouteAppendMirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label {
            lines.append(label)
        }
        s201RouteAppendMirrorDescription(of: child.value, to: &lines)
    }
}
