import XCTest
@testable import AreaMatrix

final class GeneralSettingsPageFeatureTests: XCTestCase {
    @MainActor
    func testLoadUsesC104ConfigSnapshotForVisibleGeneralSettings() async {
        let loader = GeneralSettingsRecordingLoader(result: .success(.generalSettingsFixture(
            repoPath: "/tmp/repo",
            defaultMode: "Indexed",
            overviewOutput: "RootAreaMatrixFile",
            locale: "en"
        )))
        let model = GeneralSettingsModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: GeneralSettingsRecordingUpdater(result: .success),
            rootOverviewInspector: GeneralSettingsStaticRootOverviewInspector(status: .missing),
            errorMapper: GeneralSettingsStaticErrorMapper()
        )

        await model.load()

        let requestedPaths = await loader.requestedPaths()
        XCTAssertEqual(requestedPaths, ["/tmp/repo"])
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.draft?.defaultStorageMode, .indexOnly)
        XCTAssertEqual(model.draft?.overviewOutput, .rootAreaMatrixFile)
        XCTAssertEqual(model.draft?.locale, .en)
    }

    @MainActor
    func testCopyAndLocaleSaveThroughUpdateConfigWithoutMockState() async {
        let updater = GeneralSettingsRecordingUpdater(result: .success)
        let model = await loadedModel(updater: updater, config: .generalSettingsFixture(
            repoPath: "/tmp/repo",
            defaultMode: "Indexed",
            overviewOutput: "GeneratedOnly",
            locale: "en"
        ))

        await model.requestStorageMode(.copy)
        await model.updateLocale(.zhCN)
        await model.updateLocale(.system)
        let requests = await updater.requests()

        XCTAssertEqual(requests.map(\.repoPath), ["/tmp/repo", "/tmp/repo", "/tmp/repo"])
        XCTAssertEqual(requests[0].config.defaultMode, "Copied")
        XCTAssertEqual(requests[1].config.locale, "zh-CN")
        XCTAssertEqual(requests[2].config.locale, "system")
        XCTAssertEqual(model.draft?.defaultStorageMode, .copy)
        XCTAssertEqual(model.draft?.locale, .system)
    }

    @MainActor
    func testLocaleMappingKeepsSystemZhCNAndEnglishAsDistinctRoundTripStates() {
        XCTAssertEqual(GeneralSettingsLocale.system.snapshotValue, "system")
        XCTAssertEqual(GeneralSettingsLocale.zhCN.snapshotValue, "zh-CN")
        XCTAssertEqual(GeneralSettingsLocale.en.snapshotValue, "en")
        XCTAssertEqual(GeneralSettingsLocale(snapshotValue: "system"), .system)
        XCTAssertEqual(GeneralSettingsLocale(snapshotValue: "zh-CN"), .zhCN)
        XCTAssertEqual(GeneralSettingsLocale(snapshotValue: "en"), .en)
        XCTAssertEqual(GeneralSettingsLocale(snapshotValue: "zh-Hans"), .system)
    }

    @MainActor
    func testDangerousStorageModeRequiresConfirmationBeforeUpdateConfig() async {
        let updater = GeneralSettingsRecordingUpdater(result: .success)
        let model = await loadedModel(updater: updater)

        await model.requestStorageMode(.move)
        let requestsBeforeConfirmation = await updater.requests()
        XCTAssertEqual(model.pendingStorageConfirmation, .move)
        XCTAssertEqual(requestsBeforeConfirmation, [])

        model.cancelPendingStorageMode()
        let requestsAfterCancel = await updater.requests()
        XCTAssertNil(model.pendingStorageConfirmation)
        XCTAssertEqual(model.draft?.defaultStorageMode, .copy)
        XCTAssertEqual(requestsAfterCancel, [])

        await model.requestStorageMode(.indexOnly)
        await model.confirmPendingStorageMode()

        let requests = await updater.requests()
        XCTAssertEqual(requests.map(\.config.defaultMode), ["Indexed"])
        XCTAssertEqual(model.draft?.defaultStorageMode, .indexOnly)
    }

    @MainActor
    func testC107MoveDefaultPersistsOnlyAfterRiskConfirmation() async {
        let updater = GeneralSettingsRecordingUpdater(result: .success)
        let model = await loadedModel(updater: updater)

        await model.requestStorageMode(.move)
        let requestsBeforeConfirmation = await updater.requests()
        XCTAssertEqual(model.pendingStorageConfirmation, .move)
        XCTAssertEqual(requestsBeforeConfirmation, [])

        await model.confirmPendingStorageMode()
        let requests = await updater.requests()

        XCTAssertNil(model.pendingStorageConfirmation)
        XCTAssertEqual(requests.map(\.repoPath), ["/tmp/repo"])
        XCTAssertEqual(requests.map(\.config.defaultMode), ["Moved"])
        XCTAssertEqual(model.draft?.defaultStorageMode, .move)
    }

    @MainActor
    func testRootOverviewRequiresConfirmationAndDoesNotWriteFilesDuringSettingsSave() async throws {
        let repoURL = try temporaryGeneralSettingsRepo()
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
        let updater = GeneralSettingsRecordingUpdater(result: .success)
        let model = await loadedModel(
            updater: updater,
            config: .generalSettingsFixture(repoPath: repoURL.path),
            inspector: LocalRootOverviewFileInspector()
        )

        await model.requestOverviewOutput(.rootAreaMatrixFile)
        let requestsBeforeRootConfirmation = await updater.requests()
        XCTAssertEqual(model.pendingRootOverviewStatus, .userContent)
        XCTAssertEqual(requestsBeforeRootConfirmation, [])

        await model.confirmRootOverview()
        let requests = await updater.requests()

        XCTAssertEqual(requests.map(\.config.overviewOutput), ["RootAreaMatrixFile"])
        XCTAssertEqual(try String(contentsOf: repoURL.appendingPathComponent("AREAMATRIX.md")), "user overview\n")
        XCTAssertEqual(try String(contentsOf: repoURL.appendingPathComponent("README.md")), "user readme\n")
    }

    @MainActor
    func testUnsafeRootOverviewOffersFinderRecoveryWithoutUpdatingConfig() async {
        let updater = GeneralSettingsRecordingUpdater(result: .success)
        let revealer = GeneralSettingsRecordingFileRevealer()
        let model = await loadedModel(
            updater: updater,
            inspector: GeneralSettingsStaticRootOverviewInspector(status: .unsafe("Cannot safely update AREAMATRIX.md")),
            revealer: revealer
        )

        await model.requestOverviewOutput(.rootAreaMatrixFile)
        model.revealRootOverviewInFinder()
        let requests = await updater.requests()

        XCTAssertEqual(model.pendingRootOverviewStatus, .unsafe("Cannot safely update AREAMATRIX.md"))
        XCTAssertEqual(revealer.requests, [GeneralSettingsRecordingFileRevealer.Request(
            repoPath: "/tmp/repo",
            relativePath: "AREAMATRIX.md"
        )])
        XCTAssertEqual(requests, [])
    }

    @MainActor
    func testSaveFailureRollsBackToLastSavedValueAndRetryUsesSameCoreConfig() async {
        let updater = GeneralSettingsRecordingUpdater(result: .failureThenSuccess(CoreError.Db(message: "locked")))
        let model = await loadedModel(updater: updater)

        await model.updateLocale(.en)

        XCTAssertEqual(model.draft?.locale, .system)
        XCTAssertEqual(model.saveError?.message, "数据库错误")
        XCTAssertTrue(model.hasRetryableSave)

        await model.retrySave()
        let requests = await updater.requests()

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map(\.config.locale), ["en", "en"])
        XCTAssertEqual(model.draft?.locale, .en)
        XCTAssertNil(model.saveError)
    }

    @MainActor
    func testDefaultCoreBridgeUpdatesRealRepoConfigWithoutCreatingRootFiles() async throws {
        let repoURL = try temporaryGeneralSettingsRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let model = GeneralSettingsModel(repoPath: repoURL.path, loader: bridge, updater: bridge)

        await model.load()
        await model.requestStorageMode(.indexOnly)
        XCTAssertEqual(model.pendingStorageConfirmation, .indexOnly)
        await model.confirmPendingStorageMode()
        await model.updateLocale(.en)
        var reloaded = try await bridge.loadConfig(repoPath: repoURL.path)

        XCTAssertEqual(reloaded.defaultMode, "Indexed")
        XCTAssertEqual(reloaded.locale, "en")
        await model.updateLocale(.system)
        reloaded = try await bridge.loadConfig(repoPath: repoURL.path)
        XCTAssertEqual(reloaded.locale, "system")
        await model.updateLocale(.zhCN)
        reloaded = try await bridge.loadConfig(repoPath: repoURL.path)
        XCTAssertEqual(reloaded.locale, "zh-CN")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
    }

    @MainActor
    func testDefaultCoreBridgePersistsC107MoveDefaultWithoutMovingExternalFiles() async throws {
        let repoURL = try temporaryGeneralSettingsRepo()
        let sourceRoot = try temporaryGeneralSettingsRepo()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let sourceURL = sourceRoot.appendingPathComponent("source.txt")
        try "source".write(to: sourceURL, atomically: true, encoding: .utf8)
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let model = GeneralSettingsModel(repoPath: repoURL.path, loader: bridge, updater: bridge)

        await model.load()
        await model.requestStorageMode(.move)
        XCTAssertEqual(model.pendingStorageConfirmation, .move)
        await model.confirmPendingStorageMode()
        let reloaded = try await bridge.loadConfig(repoPath: repoURL.path)

        XCTAssertEqual(reloaded.defaultMode, "Moved")
        XCTAssertEqual(model.draft?.defaultStorageMode, .move)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("source.txt").path))
    }

    @MainActor
    func testOnboardingRoutesSettingsEntryToS126GeneralSettingsWithoutRepositoryPathFlow() {
        let opening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/repo", fileCount: 1)
        let model = OnboardingModel(settingsReader: ShellStaticSettingsReader(repoPath: nil))

        model.showGeneralSettings(opening: opening)

        XCTAssertEqual(model.route, .settingsGeneral(opening))
        XCTAssertFalse(model.validatePathReturnRouteIsSettings)
    }

    @MainActor
    private func loadedModel(
        updater: GeneralSettingsRecordingUpdater,
        config: RepoConfigSnapshot = .generalSettingsFixture(repoPath: "/tmp/repo"),
        inspector: any RootOverviewFileInspecting = GeneralSettingsStaticRootOverviewInspector(status: .missing),
        revealer: (any RepositoryFileRevealing)? = nil
    ) async -> GeneralSettingsModel {
        let model = GeneralSettingsModel(
            repoPath: config.repoPath,
            loader: GeneralSettingsRecordingLoader(result: .success(config)),
            updater: updater,
            rootOverviewInspector: inspector,
            rootOverviewRevealer: revealer ?? GeneralSettingsRecordingFileRevealer(),
            errorMapper: GeneralSettingsStaticErrorMapper()
        )
        await model.load()
        return model
    }
}

private enum GeneralSettingsLoaderResult {
    case success(RepoConfigSnapshot)
    case failure(Error)
}

private actor GeneralSettingsRecordingLoader: CoreConfigurationLoading {
    private let result: GeneralSettingsLoaderResult
    private var paths: [String] = []

    init(result: GeneralSettingsLoaderResult) {
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

private enum GeneralSettingsUpdateResult {
    case success
    case failureThenSuccess(Error)
}

private actor GeneralSettingsRecordingUpdater: CoreConfigurationUpdating {
    struct Request: Equatable {
        var repoPath: String
        var config: RepoConfigSnapshot
    }

    private let result: GeneralSettingsUpdateResult
    private var recordedRequests: [Request] = []

    init(result: GeneralSettingsUpdateResult) {
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

private struct GeneralSettingsStaticRootOverviewInspector: RootOverviewFileInspecting {
    let status: RootOverviewFileStatus

    func status(repoPath: String) -> RootOverviewFileStatus {
        status
    }
}

@MainActor
private final class GeneralSettingsRecordingFileRevealer: RepositoryFileRevealing {
    struct Request: Equatable {
        var repoPath: String
        var relativePath: String
    }

    private(set) var requests: [Request] = []

    func revealFile(repoPath: String, relativePath: String) throws {
        requests.append(Request(repoPath: repoPath, relativePath: relativePath))
    }
}

private actor GeneralSettingsStaticErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        switch error {
        case .Db:
            return .generalSettingsMapping(kind: .db, userMessage: "数据库错误")
        case .Config:
            return .generalSettingsMapping(kind: .config, userMessage: "配置错误")
        case .PermissionDenied:
            return .generalSettingsMapping(kind: .permissionDenied, userMessage: "无访问权限")
        default:
            return .generalSettingsMapping(kind: .internal, userMessage: "保存失败")
        }
    }
}

private extension RepoConfigSnapshot {
    static func generalSettingsFixture(
        repoPath: String,
        defaultMode: String = "Copied",
        overviewOutput: String = "GeneratedOnly",
        locale: String = "system"
    ) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: defaultMode,
            overviewOutput: overviewOutput,
            aiEnabled: false,
            locale: locale,
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func generalSettingsMapping(
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

private func temporaryGeneralSettingsRepo() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixGeneralSettings-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
