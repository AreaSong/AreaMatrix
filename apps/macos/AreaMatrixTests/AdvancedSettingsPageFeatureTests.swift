import XCTest
@testable import AreaMatrix

final class AdvancedSettingsPageFeatureTests: XCTestCase {
    @MainActor
    func testLoadUsesC104ConfigSnapshotForVisibleAdvancedSettings() async {
        let loader = AdvancedSettingsRecordingLoader(result: .success(.advancedSettingsFixture(
            repoPath: "/tmp/repo",
            overviewOutput: "RootAreaMatrixFile",
            allowReplaceDuringImport: true
        )))
        let model = AdvancedSettingsModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: AdvancedSettingsRecordingUpdater(result: .success),
            errorMapper: AdvancedSettingsStaticErrorMapper()
        )

        await model.load()
        let requestedPaths = await loader.requestedPaths()

        XCTAssertEqual(requestedPaths, ["/tmp/repo"])
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.draft?.overviewOutput, .rootAreaMatrixFile)
        XCTAssertEqual(model.draft?.allowReplaceDuringImport, true)
    }

    @MainActor
    func testRecoveryToolsSectionExposesS130C116EntrypointWithoutInlineRecovery() {
        var didOpenRecoveryTools = false
        let section = AdvancedSettingsRecoveryToolsSection {
            didOpenRecoveryTools = true
        }
        let bodyText = advancedSettingsMirrorDescription(of: section.body)

        XCTAssertTrue(bodyText.contains("Recovery tools"))
        XCTAssertTrue(bodyText.contains("Open recovery tools..."))
        XCTAssertTrue(bodyText.contains("S1-30-C1-16-open-recovery-tools"))

        section.onOpenRecoveryTools()
        XCTAssertTrue(didOpenRecoveryTools)
    }

    @MainActor
    func testS130RecoveryToolsEntrypointRoutesToRepairConfirmationWithoutRunningRecovery() async {
        let opening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/repo", fileCount: 1)
        let recoverer = AdvancedSettingsRecordingStartupRecoverer()
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            startupRecoverer: recoverer,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.route = .settingsGeneral(opening)
        model.settingsGeneralSelectedTab = "advanced"
        model.openMainRepositoryRepair(repoPath: opening.config.repoPath)
        let recoveryRequests = await recoverer.requestedRepoPaths()

        XCTAssertEqual(model.route, .dbRepairConfirm(DatabaseRepairRouteState(repoPath: "/tmp/repo", scanSession: nil, mapping: nil, returnRoute: .settingsGeneral(opening, selectedTab: "advanced"))))
        XCTAssertEqual(recoveryRequests, [])
    }

    @MainActor
    func testS137CancelFromAdvancedSettingsReturnsToSourceSettingsPage() async {
        let opening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/repo", fileCount: 1)
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )
        model.route = .settingsGeneral(opening)
        model.settingsGeneralSelectedTab = "advanced"
        model.openMainRepositoryRepair(repoPath: opening.config.repoPath)
        guard case .dbRepairConfirm(let repairRoute) = model.route else {
            return XCTFail("expected db repair route")
        }

        model.returnFromDatabaseRepair(repairRoute)

        XCTAssertEqual(model.route, .settingsGeneral(opening))
        XCTAssertEqual(model.settingsGeneralSelectedTab, "advanced")
    }

    @MainActor
    func testRootOverviewRequiresConfirmationAndDoesNotWriteRootFiles() async throws {
        let repoURL = try temporaryAdvancedSettingsRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        try "user overview\n".write(
            to: repoURL.appendingPathComponent("AREAMATRIX.md"),
            atomically: true,
            encoding: .utf8
        )
        try "user readme\n".write(
            to: repoURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        let updater = AdvancedSettingsRecordingUpdater(result: .success)
        let model = await loadedAdvancedModel(
            updater: updater,
            config: .advancedSettingsFixture(repoPath: repoURL.path),
            inspector: LocalRootOverviewFileInspector()
        )

        await model.requestOverviewOutput(.rootAreaMatrixFile)
        let requestsBeforeConfirmation = await updater.requests()
        XCTAssertEqual(model.pendingRootOverviewStatus, .userContent)
        XCTAssertEqual(requestsBeforeConfirmation, [])

        await model.confirmRootOverview()
        let requests = await updater.requests()

        XCTAssertEqual(requests.map(\.config.overviewOutput), ["RootAreaMatrixFile"])
        XCTAssertEqual(model.draft?.overviewOutput, .rootAreaMatrixFile)
        XCTAssertEqual(try String(contentsOf: repoURL.appendingPathComponent("AREAMATRIX.md")), "user overview\n")
        XCTAssertEqual(try String(contentsOf: repoURL.appendingPathComponent("README.md")), "user readme\n")
    }

    @MainActor
    func testOverviewSaveFailureUsesC120RetryIdentifierAndRollsBack() async {
        let updater = AdvancedSettingsRecordingUpdater(result: .failureThenSuccess(CoreError.Db(message: "locked")))
        let model = await loadedAdvancedModel(updater: updater)

        await model.requestOverviewOutput(.rootAreaMatrixFile)
        await model.confirmRootOverview()

        XCTAssertEqual(model.draft?.overviewOutput, .generatedOnly)
        XCTAssertEqual(model.saveError?.message, "Could not save overview setting")
        XCTAssertEqual(model.retrySaveAccessibilityIdentifier, "S1-30-C1-20-retry-save")
        XCTAssertTrue(model.hasRetryableSave)

        await model.retrySave()
        let requests = await updater.requests()

        XCTAssertEqual(requests.map(\.config.overviewOutput), ["RootAreaMatrixFile", "RootAreaMatrixFile"])
        XCTAssertEqual(model.draft?.overviewOutput, .rootAreaMatrixFile)
        XCTAssertNil(model.saveError)
    }

    @MainActor
    func testOverviewOutputSectionIsTaggedAsS130C120Feature() {
        XCTAssertEqual(AdvancedSettingsOverviewOutput.generatedOnly.label, "Generated only")
        XCTAssertEqual(AdvancedSettingsOverviewOutput.rootAreaMatrixFile.label, "Root AREAMATRIX.md")
        XCTAssertEqual(AdvancedSettingsAccessibilityID.overviewOutput, "S1-30-C1-20-overview-output")
    }

    @MainActor
    func testAllowReplaceRequiresConfirmationAndDisableSavesDirectly() async {
        let updater = AdvancedSettingsRecordingUpdater(result: .success)
        let model = await loadedAdvancedModel(updater: updater)

        await model.requestAllowReplaceDuringImport(true)
        let requestsBeforeConfirmation = await updater.requests()
        XCTAssertTrue(model.isReplaceConfirmationPending)
        XCTAssertEqual(requestsBeforeConfirmation, [])

        model.cancelAllowReplaceDuringImport()
        let requestsAfterCancel = await updater.requests()
        XCTAssertFalse(model.isReplaceConfirmationPending)
        XCTAssertEqual(model.draft?.allowReplaceDuringImport, false)
        XCTAssertEqual(requestsAfterCancel, [])

        await model.requestAllowReplaceDuringImport(true)
        await model.confirmAllowReplaceDuringImport()
        await model.requestAllowReplaceDuringImport(false)
        let requests = await updater.requests()

        XCTAssertEqual(requests.map(\.config.allowReplaceDuringImport), [true, false])
        XCTAssertEqual(model.draft?.allowReplaceDuringImport, false)
    }

    @MainActor
    func testSaveFailureRollsBackAdvancedDraftAndRetryUsesSameCoreConfig() async {
        let updater = AdvancedSettingsRecordingUpdater(result: .failureThenSuccess(CoreError.Db(message: "locked")))
        let model = await loadedAdvancedModel(updater: updater)

        await model.requestAllowReplaceDuringImport(true)
        await model.confirmAllowReplaceDuringImport()

        XCTAssertEqual(model.draft?.allowReplaceDuringImport, false)
        XCTAssertEqual(model.saveError?.message, "Could not save advanced setting")
        XCTAssertEqual(model.saveError?.recovery, "Retry save")
        XCTAssertTrue(model.hasRetryableSave)

        await model.retrySave()
        let requests = await updater.requests()

        XCTAssertEqual(requests.map(\.config.allowReplaceDuringImport), [true, true])
        XCTAssertEqual(model.draft?.allowReplaceDuringImport, true)
        XCTAssertNil(model.saveError)
    }

    @MainActor
    func testDefaultCoreBridgePersistsAdvancedConfigWithoutCreatingRootFiles() async throws {
        let repoURL = try temporaryAdvancedSettingsRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let model = AdvancedSettingsModel(repoPath: repoURL.path, loader: bridge, updater: bridge)

        await model.load()
        await model.requestOverviewOutput(.rootAreaMatrixFile)
        XCTAssertEqual(model.pendingRootOverviewStatus, .missing)
        await model.confirmRootOverview()
        await model.requestAllowReplaceDuringImport(true)
        await model.confirmAllowReplaceDuringImport()
        let reloaded = try await bridge.loadConfig(repoPath: repoURL.path)

        XCTAssertEqual(reloaded.overviewOutput, "RootAreaMatrixFile")
        XCTAssertTrue(reloaded.allowReplaceDuringImport)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
    }

    @MainActor
    func testDefaultCoreBridgeAppliesRootOverviewOnNextRegenerationWithoutTouchingReadme() async throws {
        let repoURL = try temporaryAdvancedSettingsRepo()
        let sourceRootURL = try temporaryAdvancedSettingsRepo()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRootURL)
        }
        let sourceURL = sourceRootURL.appendingPathComponent("overview-source.txt")
        let readmeURL = repoURL.appendingPathComponent("README.md")
        try Data("overview source".utf8).write(to: sourceURL)

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        try "user readme\n".write(to: readmeURL, atomically: true, encoding: .utf8)
        let model = AdvancedSettingsModel(repoPath: repoURL.path, loader: bridge, updater: bridge)

        await model.load()
        await model.requestOverviewOutput(.rootAreaMatrixFile)
        await model.confirmRootOverview()
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))

        _ = try await bridge.importIndexedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: "overview-source.txt"
        )

        let rootOverview = try String(contentsOf: repoURL.appendingPathComponent("AREAMATRIX.md"))
        let generatedOverview = try String(contentsOf: repoURL
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("generated", isDirectory: true)
            .appendingPathComponent("root.md", isDirectory: false))
        XCTAssertTrue(rootOverview.contains("AREAMATRIX:BEGIN"))
        XCTAssertTrue(generatedOverview.contains("AREAMATRIX:BEGIN"))
        XCTAssertEqual(try String(contentsOf: readmeURL), "user readme\n")
    }

    @MainActor
    private func loadedAdvancedModel(
        updater: AdvancedSettingsRecordingUpdater,
        config: RepoConfigSnapshot = .advancedSettingsFixture(repoPath: "/tmp/repo"),
        inspector: any RootOverviewFileInspecting = AdvancedSettingsStaticRootOverviewInspector(status: .missing)
    ) async -> AdvancedSettingsModel {
        let model = AdvancedSettingsModel(
            repoPath: config.repoPath,
            loader: AdvancedSettingsRecordingLoader(result: .success(config)),
            updater: updater,
            rootOverviewInspector: inspector,
            errorMapper: AdvancedSettingsStaticErrorMapper()
        )
        await model.load()
        return model
    }
}

private enum AdvancedSettingsLoaderResult {
    case success(RepoConfigSnapshot)
    case failure(Error)
}

private actor AdvancedSettingsRecordingLoader: CoreConfigurationLoading {
    private let result: AdvancedSettingsLoaderResult
    private var paths: [String] = []

    init(result: AdvancedSettingsLoaderResult) {
        self.result = result
    }

    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        paths.append(repoPath)
        switch result {
        case .success(let config):
            return config
        case .failure(let error):
            throw error
        }
    }

    func requestedPaths() -> [String] { paths }
}

private enum AdvancedSettingsUpdateResult {
    case success
    case failureThenSuccess(Error)
}

private actor AdvancedSettingsRecordingUpdater: CoreConfigurationUpdating {
    struct Request: Equatable {
        var repoPath: String
        var config: RepoConfigSnapshot
    }

    private let result: AdvancedSettingsUpdateResult
    private var recordedRequests: [Request] = []

    init(result: AdvancedSettingsUpdateResult) {
        self.result = result
    }

    func updateConfig(repoPath: String, newConfig: RepoConfigSnapshot) async throws {
        recordedRequests.append(Request(repoPath: repoPath, config: newConfig))
        switch result {
        case .success:
            return
        case .failureThenSuccess(let error) where recordedRequests.count == 1:
            throw error
        case .failureThenSuccess:
            return
        }
    }

    func requests() -> [Request] { recordedRequests }
}

private struct AdvancedSettingsStaticRootOverviewInspector: RootOverviewFileInspecting {
    let status: RootOverviewFileStatus

    func status(repoPath: String) -> RootOverviewFileStatus {
        status
    }
}

private actor AdvancedSettingsStaticErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        switch error {
        case .Db:
            return .advancedSettingsMapping(kind: .db, userMessage: "Database error")
        case .Config:
            return .advancedSettingsMapping(kind: .config, userMessage: "Configuration error")
        case .PermissionDenied:
            return .advancedSettingsMapping(kind: .permissionDenied, userMessage: "Permission denied")
        default:
            return .advancedSettingsMapping(kind: .internal, userMessage: "Save failed")
        }
    }
}

private actor AdvancedSettingsRecordingStartupRecoverer: CoreStartupRecovering {
    private var paths: [String] = []

    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        paths.append(repoPath)
        return RecoveryReportSnapshot(cleanedStagingFiles: 0, revertedStagingDbRows: 0, warnings: [])
    }

    func requestedRepoPaths() -> [String] {
        paths
    }
}

private extension RepoConfigSnapshot {
    static func advancedSettingsFixture(
        repoPath: String,
        overviewOutput: String = "GeneratedOnly",
        allowReplaceDuringImport: Bool = false
    ) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: overviewOutput,
            aiEnabled: false,
            locale: "system",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: allowReplaceDuringImport
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func advancedSettingsMapping(
        kind: CoreErrorKindSnapshot,
        userMessage: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: userMessage,
            severity: .medium,
            suggestedAction: "Retry save",
            recoverability: .retryable,
            rawContext: kind.rawValue
        )
    }
}

private func temporaryAdvancedSettingsRepo() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixAdvancedSettings-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func advancedSettingsMirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    appendAdvancedSettingsMirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func appendAdvancedSettingsMirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label {
            lines.append(label)
        }
        appendAdvancedSettingsMirrorDescription(of: child.value, to: &lines)
    }
}
