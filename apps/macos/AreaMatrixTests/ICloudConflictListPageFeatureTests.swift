@testable import AreaMatrix
import XCTest

final class ICloudConflictListPageFeatureTests: XCTestCase {
    private static let declaredCapabilities: Set<String> = ["icloud-conflicts-core"]
    private static let iCloudConflictVisualDeclaredCapabilities: Set<String> = ["icloud-conflicts-core"]

    func testICloudConflictListDeclaresOnlyICloudConflictCoreAndCoreBridgeBoundary() {
        XCTAssertEqual(Self.declaredCapabilities, ["icloud-conflicts-core"])
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.listICloudConflicts))
        XCTAssertFalse(Self.declaredCapabilities.contains("delete-remove-index"))
        XCTAssertFalse(Self.declaredCapabilities.contains("metadata-repair"))
    }

    func testICloudConflictVisualDeclaresOnlyICloudConflictCoreListBoundary() {
        XCTAssertEqual(Self.iCloudConflictVisualDeclaredCapabilities, ["icloud-conflicts-core"])
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.listICloudConflicts))
        XCTAssertFalse(Self.iCloudConflictVisualDeclaredCapabilities.contains("icloud-conflict-visual"))
        XCTAssertFalse(Self.iCloudConflictVisualDeclaredCapabilities.contains("undo-action-log"))
        XCTAssertEqual(
            ICloudConflictListPageContext.iCloudConflictVisualConflictVisual.accessibilityID,
            "icloud-conflict-review-icloud-conflicts-core-icloud-conflict-list"
        )
    }

    @MainActor
    func testICloudConflictListICloudConflictCoreLoadUsesCoreBridgeListerWithoutOutOfScopeActions() async {
        let conflict = ICloudConflictPairSnapshot.iCloudConflictListFixture()
        let lister = ICloudConflictLister(result: .success([conflict]))
        let model = ICloudConflictListModel(
            repoPath: "/tmp/iCloudConflictList-repo",
            conflictLister: lister,
            errorMapper: ICloudConflictListRecordingErrorMapper(mapping: .iCloudConflictListMapping())
        )

        await model.load()
        let requests = await lister.recordedRequests()

        XCTAssertEqual(requests, ["/tmp/iCloudConflictList-repo"])
        XCTAssertEqual(model.state, .loaded([conflict]))
        XCTAssertEqual(model.conflicts, [conflict])
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testICloudConflictListICloudConflictCoreErrorStateMapsCoreErrorAndKeepsRetryDiagnosticsVisible() async {
        let mapper = ICloudConflictListRecordingErrorMapper(mapping: .iCloudConflictListMapping(
            kind: .iCloudPlaceholder,
            rawContext: "/tmp/iCloudConflictList-repo/docs/report.pdf.icloud"
        ))
        let model = ICloudConflictListModel(
            repoPath: "/tmp/iCloudConflictList-repo",
            conflictLister: ICloudConflictLister(result: .failure(CoreError.ICloudPlaceholder(
                path: "/tmp/iCloudConflictList-repo/docs/report.pdf.icloud"
            ))),
            errorMapper: mapper
        )

        await model.load()
        let body = testMirrorDescription(of: ICloudConflictListView(
            model: model,
            onClose: {},
            onResolve: { _ in },
            onCollectDiagnostics: {}
        ).body)
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(
            mappedErrors,
            [CoreError.ICloudPlaceholder(path: "/tmp/iCloudConflictList-repo/docs/report.pdf.icloud")]
        )
        assertTestDescription(body, contains: [
            "icloud-conflicts-icloud-conflicts-core-error",
            "Unable to list iCloud conflicts",
            "Retry",
            "Collect Diagnostics..."
        ])
    }

    @MainActor
    func testICloudConflictListICloudConflictCoreEmptyAndLoadedViewsExposeRequiredActions() async {
        let emptyModel = ICloudConflictListModel(
            repoPath: "/tmp/iCloudConflictList-repo",
            conflictLister: ICloudConflictLister(result: .success([])),
            errorMapper: ICloudConflictListRecordingErrorMapper(mapping: .iCloudConflictListMapping())
        )
        await emptyModel.load()
        let emptyBody = testMirrorDescription(of: ICloudConflictListView(
            model: emptyModel,
            onClose: {},
            onResolve: { _ in }
        ).body)

        let conflict = ICloudConflictPairSnapshot.iCloudConflictListFixture()
        let loadedModel = ICloudConflictListModel(
            repoPath: "/tmp/iCloudConflictList-repo",
            conflictLister: ICloudConflictLister(result: .success([conflict])),
            errorMapper: ICloudConflictListRecordingErrorMapper(mapping: .iCloudConflictListMapping())
        )
        await loadedModel.load()
        let loadedBody = testMirrorDescription(of: ICloudConflictListView(
            model: loadedModel,
            onClose: {},
            onResolve: { _ in XCTFail("Body inspection must not invoke row actions") }
        ).body)

        assertTestDescription(emptyBody, contains: [
            ICloudConflictListCopy.emptyTitle,
            ICloudConflictListAccessibilityID.emptyRefresh
        ])
        assertTestDescription(loadedBody, contains: [
            ICloudConflictListCopy.title,
            ICloudConflictListCopy.subtitle
        ])
        XCTAssertEqual(loadedModel.conflicts, [conflict])
        XCTAssertEqual(ICloudConflictListCopy.resolveAction, "Resolve...")
        XCTAssertEqual(ICloudConflictListCopy.revealAction, "Reveal")
        XCTAssertEqual(ICloudConflictListCopy.revealRepositoryAction, "Reveal repository in Finder")
        XCTAssertEqual(ICloudConflictListCopy.closeAction, "Close")
        XCTAssertEqual(
            ICloudConflictListAccessibilityID.resolve(conflictID: conflict.conflictID),
            "icloud-conflicts-icloud-conflicts-core-resolve-docs-report--Alice-s-conflicted-copy--pdf"
        )
    }

    @MainActor
    func testICloudConflictListICloudConflictCoreRevealUsesPlatformServicesWithoutCoreWrites() {
        let conflict = ICloudConflictPairSnapshot.iCloudConflictListFixture()
        let finder = ICloudConflictListRecordingFinderOpener()
        let revealer = ICloudConflictListRecordingFileRevealer()
        let model = ICloudConflictListModel(
            repoPath: "/tmp/iCloudConflictList-repo",
            conflictLister: ICloudConflictLister(result: .success([conflict])),
            errorMapper: ICloudConflictListRecordingErrorMapper(mapping: .iCloudConflictListMapping()),
            repositoryFinderOpener: finder,
            fileRevealer: revealer
        )

        model.revealRepositoryInFinder()
        model.revealConflict(conflict)

        XCTAssertEqual(finder.requests, ["/tmp/iCloudConflictList-repo"])
        XCTAssertEqual(revealer.requests, [ICloudConflictListRecordingFileRevealer.Request(
            repoPath: "/tmp/iCloudConflictList-repo",
            relativePath: "docs/report (Alice's conflicted copy).pdf"
        )])
        XCTAssertEqual(model.revealState, .revealed("Conflict copy revealed in Finder."))
    }

    @MainActor
    func testICloudConflictListICloudConflictCoreSettingsEntryOpensReviewConflictsTarget() async {
        let opener = ICloudConflictListRecordingFinderOpener()
        let model = IntegrationsSettingsModel(
            repoPath: "/tmp/iCloudConflictList-repo",
            loader: ICloudConflictListIntegrationsLoader(
                config: .iCloudConflictListIntegrationsFixture(repoPath: "/tmp/stale")
            ),
            updater: NoopIntegrationsUpdater(),
            errorMapper: ICloudConflictListRecordingErrorMapper(mapping: .iCloudConflictListMapping()),
            statusDetector: ICloudConflictListStaticStatusDetector(
                snapshot: IntegrationsICloudSnapshot(repositoryLocation: .iCloudDrive, iCloudStatus: .available)
            ),
            finderOpener: opener,
            helpOpener: ICloudConflictListNoopHelpOpener()
        )

        await model.load()

        XCTAssertEqual(model.summary?.repositoryLocation, .iCloudDrive)
        XCTAssertEqual(
            IntegrationConflictListPresentation.reviewConflictsTitle,
            "Review conflicts"
        )
        XCTAssertEqual(
            IntegrationConflictListPresentation.reviewConflictsAccessibilityID,
            "icloud-conflicts-icloud-conflicts-core-review-conflicts"
        )
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    func testICloudConflictVisualICloudConflictVisualCoreResolveRouteUsesConflictIDAndSupportedPreviewResolution(
    ) async {
        let conflict = ICloudConflictPairSnapshot.iCloudConflictListFixture()
        let listModel = ICloudConflictListModel(
            repoPath: "/tmp/iCloudConflictList-repo",
            conflictLister: ICloudConflictLister(result: .success([conflict])),
            errorMapper: ICloudConflictListRecordingErrorMapper(mapping: .iCloudConflictListMapping())
        )

        await listModel.load()
        listModel.beginResolvingConflict(conflict)

        guard let route = listModel.resolvingRoute else {
            return XCTFail("Expected Resolve to open icloud-conflict-review route context")
        }
        XCTAssertEqual(route.conflict, conflict)
        XCTAssertEqual(route.conflict.conflictID, "docs/report (Alice's conflicted copy).pdf")
        XCTAssertEqual(route.originalVersion.path, "/tmp/iCloudConflictList-repo/docs/report.pdf")
        XCTAssertEqual(
            route.conflictedCopyVersion.path,
            "/tmp/iCloudConflictList-repo/docs/report (Alice's conflicted copy).pdf"
        )
        XCTAssertEqual(route.resolutionCapability, .supported)
        XCTAssertTrue(listModel.isResolving(conflict))

        let validator =
            ICloudConflictListRecordingPathValidator(
                result: .success(.iCloudConflictListValidationFixture(repoPath: route
                        .repoPath))
            )
        let sheetModel = ICloudConflictMinimalModel(
            repoPath: route.repoPath,
            conflictID: route.conflict.conflictID,
            originalVersion: route.originalVersion,
            conflictedCopyVersion: route.conflictedCopyVersion,
            pathValidator: validator,
            conflictReviewer: ICloudConflictReviewer(
                previewResult: .success(.iCloudConflictVisualPreview(conflictID: route.conflict.conflictID)),
                resolveResult: .success(.iCloudConflictVisualResolvedReport(conflictID: route.conflict.conflictID))
            ),
            errorMapper: ICloudConflictListRecordingErrorMapper(mapping: .iCloudConflictListMapping(kind: .internal))
        )
        await sheetModel.validateRepositoryPath()
        await sheetModel.loadPreview()
        let sheetBody = testMirrorDescription(of: ICloudConflictMinimalSheet(
            model: sheetModel,
            resolutionCapability: route.resolutionCapability,
            isTrashAvailable: true,
            onCancel: {},
            onApply: { _ in },
            onCollectDiagnostics: {}
        ).body)
        let validatorRequests = await validator.recordedRequests()

        XCTAssertEqual(validatorRequests, ["/tmp/iCloudConflictList-repo"])
        XCTAssertEqual(sheetModel.previewState.preview?.conflictID, route.conflict.conflictID)
        XCTAssertEqual(sheetModel.previewVersions.map(\.previewStatus), [.available, .available])
        XCTAssertTrue(sheetModel.canApply(strategy: .keepBoth, isTrashAvailable: true, didConfirmSingleVersion: false))
        assertTestDescription(sheetBody, contains: [
            "icloud-conflict-review-icloud-conflict-visual-icloud-conflict-visual",
            "Conflict details loaded",
            "Original preview",
            "Conflicted preview"
        ])
        assertTestDescription(sheetBody, doesNotContain: [
            "icloud-conflict-minimal-core-resolution-blocked"
        ])

        listModel.closeResolvingConflict()
        XCTAssertNil(listModel.resolvingRoute)
    }

    @MainActor
    func testICloudConflictVisualICloudConflictCoreListContextUsesReadOnlyCoreListerWithoutPreviewOrResolve() async {
        let conflict = ICloudConflictPairSnapshot.iCloudConflictListFixture()
        let lister = ICloudConflictLister(result: .success([conflict]))
        let model = ICloudConflictListModel(
            repoPath: "/tmp/iCloudConflictVisual-repo",
            conflictLister: lister,
            errorMapper: ICloudConflictListRecordingErrorMapper(mapping: .iCloudConflictListMapping())
        )

        await model.load()
        let body = testMirrorDescription(of: ICloudConflictListView(
            model: model,
            pageContext: .iCloudConflictVisualConflictVisual,
            onClose: {},
            onResolve: { _ in XCTFail("Body inspection must not invoke icloud-conflict-visual resolution") }
        ).body)
        let requests = await lister.recordedRequests()

        XCTAssertEqual(requests, ["/tmp/iCloudConflictVisual-repo"])
        XCTAssertEqual(model.state, .loaded([conflict]))
        assertTestDescription(body, contains: [
            ICloudConflictListAccessibilityID.iCloudConflictVisualPage,
            ICloudConflictListCopy.iCloudConflictVisualTitle,
            "1 conflict groups found"
        ])
        assertTestDescription(body, doesNotContain: [
            "icloud-conflict-review-icloud-conflict-visual-icloud-conflict-visual"
        ])
    }

    func testICloudConflictListICloudConflictCoreDefaultCoreBridgeListsRealConflictedCopiesReadOnly() async throws {
        let repoURL = try temporaryICloudConflictListRepository()
        defer { removeTestTemporaryItems(repoURL) }
        let docsURL = repoURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        let originalURL = docsURL.appendingPathComponent("report.pdf")
        let conflictedURL = docsURL.appendingPathComponent("report (Alice's conflicted copy).pdf")
        let originalData = Data("original bytes".utf8)
        let conflictedData = Data("conflicted bytes".utf8)
        try originalData.write(to: originalURL)
        try conflictedData.write(to: conflictedURL)

        let conflicts = try await CoreBridge().listICloudConflicts(repoPath: repoURL.path)

        XCTAssertEqual(conflicts.map(\.conflictedCopyPath), ["docs/report (Alice's conflicted copy).pdf"])
        XCTAssertEqual(conflicts.first?.originalPath, "docs/report.pdf")
        XCTAssertEqual(conflicts.first?.status, .needsReview)
        XCTAssertEqual(try Data(contentsOf: originalURL), originalData)
        XCTAssertEqual(try Data(contentsOf: conflictedURL), conflictedData)
    }
}

private actor ICloudConflictLister: CoreICloudConflictListing {
    private let result: Result<[ICloudConflictPairSnapshot], Error>
    private var requests: [String] = []

    init(result: Result<[ICloudConflictPairSnapshot], Error>) {
        self.result = result
    }

    func listICloudConflicts(repoPath: String) async throws -> [ICloudConflictPairSnapshot] {
        requests.append(repoPath)
        return try result.get()
    }

    func recordedRequests() -> [String] {
        requests
    }
}

@MainActor
private final class ICloudConflictListRecordingFinderOpener: RepositoryFinderOpening {
    private(set) var requests: [String] = []

    func openRepositoryInFinder(repoPath: String) throws {
        requests.append(repoPath)
    }
}

@MainActor
private final class ICloudConflictListRecordingFileRevealer: RepositoryFileRevealing {
    struct Request: Equatable {
        var repoPath: String
        var relativePath: String
    }

    private(set) var requests: [Request] = []

    func revealFile(repoPath: String, relativePath: String) throws {
        requests.append(Request(repoPath: repoPath, relativePath: relativePath))
    }
}

private actor ICloudConflictListRecordingErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private var errors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping
    }

    func recordedErrors() -> [CoreError] {
        errors
    }
}

private actor ICloudConflictListRecordingPathValidator: CoreRepositoryPathValidating {
    private let result: Result<RepoPathValidationSnapshot, Error>
    private var requests: [String] = []

    init(result: Result<RepoPathValidationSnapshot, Error>) {
        self.result = result
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        requests.append(repoPath)
        return try result.get()
    }

    func recordedRequests() -> [String] {
        requests
    }
}

private actor ICloudConflictListIntegrationsLoader: CoreConfigurationLoading {
    private let config: RepoConfigSnapshot

    init(config: RepoConfigSnapshot) {
        self.config = config
    }

    func loadConfig(repoPath _: String) async throws -> RepoConfigSnapshot {
        config
    }
}

private actor NoopIntegrationsUpdater: CoreConfigurationUpdating {
    func updateConfig(repoPath _: String, newConfig _: RepoConfigSnapshot) async throws {}
}

private struct ICloudConflictListStaticStatusDetector: ICloudStatusDetecting {
    let snapshot: IntegrationsICloudSnapshot

    func snapshot(repoPath _: String, config _: RepoConfigSnapshot) async -> IntegrationsICloudSnapshot {
        snapshot
    }
}

private struct ICloudConflictListNoopHelpOpener: ICloudHelpOpening {
    func openICloudHelp() throws {}
}

private extension ICloudConflictPairSnapshot {
    static func iCloudConflictListFixture(
        conflictID: String = "docs/report (Alice's conflicted copy).pdf",
        uncertaintyReason: String? = nil
    ) -> ICloudConflictPairSnapshot {
        ICloudConflictPairSnapshot(
            conflictID: conflictID,
            originalPath: "docs/report.pdf",
            conflictedCopyPath: "docs/report (Alice's conflicted copy).pdf",
            originalModifiedAt: 1_775_020_800,
            conflictedModifiedAt: 1_775_020_860,
            status: .needsReview,
            uncertaintyReason: uncertaintyReason
        )
    }
}

private extension RepoConfigSnapshot {
    static func iCloudConflictListIntegrationsFixture(repoPath: String) -> RepoConfigSnapshot {
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

private extension RepoPathValidationSnapshot {
    static func iCloudConflictListValidationFixture(repoPath: String) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: false,
            isInitialized: true,
            isInsideAreaMatrix: false,
            isICloudPath: true,
            hasUnfinishedScanSession: false,
            availableCapacityBytes: 1_000_000_000,
            isExternalVolume: false,
            recommendedMode: .adoptExisting,
            issues: [.iCloudPath]
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func iCloudConflictListMapping(
        kind: CoreErrorKindSnapshot = .iCloudPlaceholder,
        rawContext: String = "/tmp/iCloudConflictList-repo/docs/report.pdf.icloud"
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "AreaMatrix cannot inspect this iCloud conflict.",
            severity: .high,
            suggestedAction: "Download the iCloud item in Finder or retry after sync finishes.",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }
}

private func temporaryICloudConflictListRepository() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixICloudConflictList")
}
