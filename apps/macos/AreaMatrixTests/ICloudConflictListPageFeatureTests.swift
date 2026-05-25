@testable import AreaMatrix
import XCTest

final class ICloudConflictListPageFeatureTests: XCTestCase {
    private static let declaredCapabilities: Set<String> = ["C1-25"]
    private static let s220DeclaredCapabilities: Set<String> = ["C1-25"]

    func testS136DeclaresOnlyC125AndCoreBridgeBoundary() {
        XCTAssertEqual(Self.declaredCapabilities, ["C1-25"])
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.listICloudConflicts))
        XCTAssertFalse(Self.declaredCapabilities.contains("C1-23"))
        XCTAssertFalse(Self.declaredCapabilities.contains("C1-26"))
    }

    func testS220DeclaresOnlyC125ListBoundary() {
        XCTAssertEqual(Self.s220DeclaredCapabilities, ["C1-25"])
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.listICloudConflicts))
        XCTAssertFalse(Self.s220DeclaredCapabilities.contains("C2-16"))
        XCTAssertFalse(Self.s220DeclaredCapabilities.contains("C2-07"))
        XCTAssertEqual(
            ICloudConflictListPageContext.s220ConflictVisual.accessibilityID,
            "S2-20-C1-25-icloud-conflict-list"
        )
    }

    @MainActor
    func testS136C125LoadUsesCoreBridgeListerWithoutOutOfScopeActions() async {
        let conflict = ICloudConflictPairSnapshot.s136Fixture()
        let lister = S136RecordingConflictLister(result: .success([conflict]))
        let model = ICloudConflictListModel(
            repoPath: "/tmp/s136-repo",
            conflictLister: lister,
            errorMapper: S136RecordingErrorMapper(mapping: .s136Mapping())
        )

        await model.load()
        let requests = await lister.recordedRequests()

        XCTAssertEqual(requests, ["/tmp/s136-repo"])
        XCTAssertEqual(model.state, .loaded([conflict]))
        XCTAssertEqual(model.conflicts, [conflict])
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testS136C125ErrorStateMapsCoreErrorAndKeepsRetryDiagnosticsVisible() async {
        let mapper = S136RecordingErrorMapper(mapping: .s136Mapping(
            kind: .iCloudPlaceholder,
            rawContext: "/tmp/s136-repo/docs/report.pdf.icloud"
        ))
        let model = ICloudConflictListModel(
            repoPath: "/tmp/s136-repo",
            conflictLister: S136RecordingConflictLister(result: .failure(CoreError.ICloudPlaceholder(
                path: "/tmp/s136-repo/docs/report.pdf.icloud"
            ))),
            errorMapper: mapper
        )

        await model.load()
        let body = s136MirrorDescription(of: ICloudConflictListView(
            model: model,
            onClose: {},
            onResolve: { _ in },
            onCollectDiagnostics: {}
        ).body)
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.ICloudPlaceholder(path: "/tmp/s136-repo/docs/report.pdf.icloud")])
        XCTAssertTrue(body.contains("S1-36-C1-25-error"))
        XCTAssertTrue(body.contains("Unable to list iCloud conflicts"))
        XCTAssertTrue(body.contains("Retry"))
        XCTAssertTrue(body.contains("Collect Diagnostics..."))
    }

    @MainActor
    func testS136C125EmptyAndLoadedViewsExposeRequiredActions() async {
        let emptyModel = ICloudConflictListModel(
            repoPath: "/tmp/s136-repo",
            conflictLister: S136RecordingConflictLister(result: .success([])),
            errorMapper: S136RecordingErrorMapper(mapping: .s136Mapping())
        )
        await emptyModel.load()
        let emptyBody = s136MirrorDescription(of: ICloudConflictListView(
            model: emptyModel,
            onClose: {},
            onResolve: { _ in }
        ).body)

        let conflict = ICloudConflictPairSnapshot.s136Fixture()
        let loadedModel = ICloudConflictListModel(
            repoPath: "/tmp/s136-repo",
            conflictLister: S136RecordingConflictLister(result: .success([conflict])),
            errorMapper: S136RecordingErrorMapper(mapping: .s136Mapping())
        )
        await loadedModel.load()
        let loadedBody = s136MirrorDescription(of: ICloudConflictListView(
            model: loadedModel,
            onClose: {},
            onResolve: { _ in XCTFail("Body inspection must not invoke row actions") }
        ).body)

        XCTAssertTrue(emptyBody.contains(ICloudConflictListCopy.emptyTitle))
        XCTAssertTrue(emptyBody.contains(ICloudConflictListAccessibilityID.emptyRefresh))
        XCTAssertTrue(loadedBody.contains(ICloudConflictListCopy.title))
        XCTAssertTrue(loadedBody.contains(ICloudConflictListCopy.subtitle))
        XCTAssertEqual(loadedModel.conflicts, [conflict])
        XCTAssertEqual(ICloudConflictListCopy.resolveAction, "Resolve...")
        XCTAssertEqual(ICloudConflictListCopy.revealAction, "Reveal")
        XCTAssertEqual(ICloudConflictListCopy.revealRepositoryAction, "Reveal repository in Finder")
        XCTAssertEqual(ICloudConflictListCopy.closeAction, "Close")
        XCTAssertEqual(
            ICloudConflictListAccessibilityID.resolve(conflictID: conflict.conflictID),
            "S1-36-C1-25-resolve-docs-report--Alice-s-conflicted-copy--pdf"
        )
    }

    @MainActor
    func testS136C125RevealUsesPlatformServicesWithoutCoreWrites() {
        let conflict = ICloudConflictPairSnapshot.s136Fixture()
        let finder = S136RecordingFinderOpener()
        let revealer = S136RecordingFileRevealer()
        let model = ICloudConflictListModel(
            repoPath: "/tmp/s136-repo",
            conflictLister: S136RecordingConflictLister(result: .success([conflict])),
            errorMapper: S136RecordingErrorMapper(mapping: .s136Mapping()),
            repositoryFinderOpener: finder,
            fileRevealer: revealer
        )

        model.revealRepositoryInFinder()
        model.revealConflict(conflict)

        XCTAssertEqual(finder.requests, ["/tmp/s136-repo"])
        XCTAssertEqual(revealer.requests, [S136RecordingFileRevealer.Request(
            repoPath: "/tmp/s136-repo",
            relativePath: "docs/report (Alice's conflicted copy).pdf"
        )])
        XCTAssertEqual(model.revealState, .revealed("Conflict copy revealed in Finder."))
    }

    @MainActor
    func testS136C125SettingsEntryOpensReviewConflictsTarget() async {
        let opener = S136RecordingFinderOpener()
        let model = IntegrationsSettingsModel(
            repoPath: "/tmp/s136-repo",
            loader: S136IntegrationsLoader(config: .s136IntegrationsFixture(repoPath: "/tmp/stale")),
            updater: S136NoopIntegrationsUpdater(),
            errorMapper: S136RecordingErrorMapper(mapping: .s136Mapping()),
            statusDetector: S136StaticStatusDetector(
                snapshot: IntegrationsICloudSnapshot(repositoryLocation: .iCloudDrive, iCloudStatus: .available)
            ),
            finderOpener: opener,
            helpOpener: S136NoopHelpOpener()
        )

        await model.load()

        XCTAssertEqual(model.summary?.repositoryLocation, .iCloudDrive)
        XCTAssertEqual(
            IntegrationConflictListPresentation.reviewConflictsTitle,
            "Review conflicts"
        )
        XCTAssertEqual(
            IntegrationConflictListPresentation.reviewConflictsAccessibilityID,
            "S1-36-C1-25-review-conflicts"
        )
    }

    @MainActor
    func testS220C216ResolveRouteUsesConflictIDAndSupportedPreviewResolution() async {
        let conflict = ICloudConflictPairSnapshot.s136Fixture()
        let listModel = ICloudConflictListModel(
            repoPath: "/tmp/s136-repo",
            conflictLister: S136RecordingConflictLister(result: .success([conflict])),
            errorMapper: S136RecordingErrorMapper(mapping: .s136Mapping())
        )

        await listModel.load()
        listModel.beginResolvingConflict(conflict)

        guard let route = listModel.resolvingRoute else {
            return XCTFail("Expected Resolve to open S2-20 route context")
        }
        XCTAssertEqual(route.conflict, conflict)
        XCTAssertEqual(route.conflict.conflictID, "docs/report (Alice's conflicted copy).pdf")
        XCTAssertEqual(route.originalVersion.path, "/tmp/s136-repo/docs/report.pdf")
        XCTAssertEqual(route.conflictedCopyVersion.path, "/tmp/s136-repo/docs/report (Alice's conflicted copy).pdf")
        XCTAssertEqual(route.resolutionCapability, .supported)
        XCTAssertTrue(listModel.isResolving(conflict))

        let validator = S136RecordingPathValidator(result: .success(.s136ValidationFixture(repoPath: route.repoPath)))
        let sheetModel = ICloudConflictMinimalModel(
            repoPath: route.repoPath,
            conflictID: route.conflict.conflictID,
            originalVersion: route.originalVersion,
            conflictedCopyVersion: route.conflictedCopyVersion,
            pathValidator: validator,
            conflictReviewer: S220RecordingConflictReviewer(
                previewResult: .success(.s220Preview(conflictID: route.conflict.conflictID)),
                resolveResult: .success(.s220ResolvedReport(conflictID: route.conflict.conflictID))
            ),
            errorMapper: S136RecordingErrorMapper(mapping: .s136Mapping(kind: .internal))
        )
        await sheetModel.validateRepositoryPath()
        await sheetModel.loadPreview()
        let sheetBody = s136MirrorDescription(of: ICloudConflictMinimalSheet(
            model: sheetModel,
            resolutionCapability: route.resolutionCapability,
            isTrashAvailable: true,
            onCancel: {},
            onApply: { _, _, _ in },
            onCollectDiagnostics: {}
        ).body)
        let validatorRequests = await validator.recordedRequests()

        XCTAssertEqual(validatorRequests, ["/tmp/s136-repo"])
        XCTAssertEqual(sheetModel.previewState.preview?.conflictID, route.conflict.conflictID)
        XCTAssertEqual(sheetModel.previewVersions.map(\.previewStatus), [.available, .available])
        XCTAssertTrue(sheetModel.canApply(strategy: .keepBoth, isTrashAvailable: true, didConfirmSingleVersion: false))
        XCTAssertTrue(sheetBody.contains("S2-20-C2-16-icloud-conflict-visual"))
        XCTAssertTrue(sheetBody.contains("Conflict details loaded"))
        XCTAssertTrue(sheetBody.contains("Original preview"))
        XCTAssertTrue(sheetBody.contains("Conflicted preview"))
        XCTAssertFalse(sheetBody.contains("S1-25-core-resolution-blocked"))

        listModel.closeResolvingConflict()
        XCTAssertNil(listModel.resolvingRoute)
    }

    @MainActor
    func testS220C125ListContextUsesReadOnlyCoreListerWithoutPreviewOrResolve() async {
        let conflict = ICloudConflictPairSnapshot.s136Fixture()
        let lister = S136RecordingConflictLister(result: .success([conflict]))
        let model = ICloudConflictListModel(
            repoPath: "/tmp/s220-repo",
            conflictLister: lister,
            errorMapper: S136RecordingErrorMapper(mapping: .s136Mapping())
        )

        await model.load()
        let body = s136MirrorDescription(of: ICloudConflictListView(
            model: model,
            pageContext: .s220ConflictVisual,
            onClose: {},
            onResolve: { _ in XCTFail("Body inspection must not invoke C2-16 resolution") }
        ).body)
        let requests = await lister.recordedRequests()

        XCTAssertEqual(requests, ["/tmp/s220-repo"])
        XCTAssertEqual(model.state, .loaded([conflict]))
        XCTAssertTrue(body.contains(ICloudConflictListAccessibilityID.s220Page))
        XCTAssertTrue(body.contains(ICloudConflictListCopy.s220Title))
        XCTAssertTrue(body.contains("1 conflict groups found"))
        XCTAssertFalse(body.contains("S2-20-C2-16-icloud-conflict-visual"))
    }

    func testS136C125DefaultCoreBridgeListsRealConflictedCopiesReadOnly() async throws {
        let repoURL = try temporaryS136Repository()
        defer { try? FileManager.default.removeItem(at: repoURL) }
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

private actor S136RecordingConflictLister: CoreICloudConflictListing {
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
private final class S136RecordingFinderOpener: RepositoryFinderOpening {
    private(set) var requests: [String] = []

    func openRepositoryInFinder(repoPath: String) throws {
        requests.append(repoPath)
    }
}

@MainActor
private final class S136RecordingFileRevealer: RepositoryFileRevealing {
    struct Request: Equatable {
        var repoPath: String
        var relativePath: String
    }

    private(set) var requests: [Request] = []

    func revealFile(repoPath: String, relativePath: String) throws {
        requests.append(Request(repoPath: repoPath, relativePath: relativePath))
    }
}

private actor S136RecordingErrorMapper: CoreErrorMapping {
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

private actor S136RecordingPathValidator: CoreRepositoryPathValidating {
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

private actor S136IntegrationsLoader: CoreConfigurationLoading {
    private let config: RepoConfigSnapshot

    init(config: RepoConfigSnapshot) {
        self.config = config
    }

    func loadConfig(repoPath _: String) async throws -> RepoConfigSnapshot {
        config
    }
}

private actor S136NoopIntegrationsUpdater: CoreConfigurationUpdating {
    func updateConfig(repoPath _: String, newConfig _: RepoConfigSnapshot) async throws {}
}

private struct S136StaticStatusDetector: ICloudStatusDetecting {
    let snapshot: IntegrationsICloudSnapshot

    func snapshot(repoPath _: String, config _: RepoConfigSnapshot) async -> IntegrationsICloudSnapshot {
        snapshot
    }
}

private struct S136NoopHelpOpener: ICloudHelpOpening {
    func openICloudHelp() throws {}
}

private extension ICloudConflictPairSnapshot {
    static func s136Fixture(
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
    static func s136IntegrationsFixture(repoPath: String) -> RepoConfigSnapshot {
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
    static func s136ValidationFixture(repoPath: String) -> RepoPathValidationSnapshot {
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
    static func s136Mapping(
        kind: CoreErrorKindSnapshot = .iCloudPlaceholder,
        rawContext: String = "/tmp/s136-repo/docs/report.pdf.icloud"
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

private func temporaryS136Repository() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixS136-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func s136MirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    appendS136MirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func appendS136MirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label {
            lines.append(label)
        }
        appendS136MirrorDescription(of: child.value, to: &lines)
    }
}
