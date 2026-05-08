import XCTest
@testable import AreaMatrix

final class ICloudConflictListPageFeatureTests: XCTestCase {
    private static let declaredCapabilities: Set<String> = ["C1-25"]

    func testS136DeclaresOnlyC125AndCoreBridgeBoundary() {
        XCTAssertEqual(Self.declaredCapabilities, ["C1-25"])
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.listICloudConflicts))
        XCTAssertFalse(Self.declaredCapabilities.contains("C1-23"))
        XCTAssertFalse(Self.declaredCapabilities.contains("C1-26"))
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
            IntegrationsSettingsConflictListPresentation.reviewConflictsTitle,
            "Review conflicts"
        )
        XCTAssertEqual(
            IntegrationsSettingsConflictListPresentation.reviewConflictsAccessibilityID,
            "S1-36-C1-25-review-conflicts"
        )
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

    func recordedRequests() -> [String] { requests }
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

    func recordedErrors() -> [CoreError] { errors }
}

private actor S136IntegrationsLoader: CoreConfigurationLoading {
    private let config: RepoConfigSnapshot

    init(config: RepoConfigSnapshot) {
        self.config = config
    }

    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        config
    }
}

private actor S136NoopIntegrationsUpdater: CoreConfigurationUpdating {
    func updateConfig(repoPath: String, newConfig: RepoConfigSnapshot) async throws {}
}

private struct S136StaticStatusDetector: ICloudStatusDetecting {
    let snapshot: IntegrationsICloudSnapshot

    func snapshot(repoPath: String, config: RepoConfigSnapshot) async -> IntegrationsICloudSnapshot {
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
