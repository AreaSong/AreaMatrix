import XCTest
@testable import AreaMatrix

final class IntegrationsSettingsPageFeatureTests: XCTestCase {
    @MainActor
    func testLoadUsesC104ConfigForVisibleICloudIntegrationState() async {
        let loader = IntegrationsSettingsRecordingLoader(results: [
            .success(.integrationsFixture(repoPath: "/tmp/repo", iCloudWarn: false)),
        ])
        let model = IntegrationsSettingsModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: IntegrationsSettingsRecordingUpdater(results: [.success]),
            errorMapper: IntegrationsSettingsStaticErrorMapper(),
            statusDetector: IntegrationsSettingsStaticStatusDetector(
                snapshot: IntegrationsICloudSnapshot(repositoryLocation: .iCloudDrive, iCloudStatus: .available)
            )
        )

        await model.load()

        let requestedPaths = await loader.requestedPaths()
        XCTAssertEqual(requestedPaths, ["/tmp/repo"])
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.summary?.repositoryLocation, .iCloudDrive)
        XCTAssertEqual(model.summary?.iCloudStatus, .available)
        XCTAssertEqual(model.summary?.iCloudWarningsEnabled, false)
        XCTAssertFalse(model.summary?.canRetryStatus ?? true)
    }

    @MainActor
    func testICloudWarningsSaveThroughUpdateConfigWithoutStaticState() async {
        let updater = IntegrationsSettingsRecordingUpdater(results: [.success])
        let model = await loadedModel(updater: updater, iCloudWarn: true)

        await model.setICloudWarningsEnabled(false)
        let requests = await updater.requests()

        XCTAssertEqual(requests.map(\.repoPath), ["/tmp/repo"])
        XCTAssertEqual(requests.map(\.config.iCloudWarn), [false])
        XCTAssertEqual(requests.map(\.config.repoPath), ["/tmp/repo"])
        XCTAssertEqual(model.summary?.iCloudWarningsEnabled, false)
        XCTAssertNil(model.saveError)
    }

    @MainActor
    func testSaveFailureRollsBackAndRetryUsesSameCoreConfig() async {
        let updater = IntegrationsSettingsRecordingUpdater(results: [
            .failure(CoreError.Db(message: "locked")),
            .success,
        ])
        let mapper = IntegrationsSettingsStaticErrorMapper()
        let model = await loadedModel(updater: updater, errorMapper: mapper, iCloudWarn: true)

        await model.setICloudWarningsEnabled(false)

        XCTAssertEqual(model.summary?.iCloudWarningsEnabled, true)
        XCTAssertEqual(model.saveError?.message, "数据库错误")
        XCTAssertTrue(model.hasRetryableSave)

        await model.retrySave()
        let requests = await updater.requests()
        let mappedErrors = await mapper.mappedErrors()

        XCTAssertEqual(requests.map(\.config.iCloudWarn), [false, false])
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "locked")])
        XCTAssertEqual(model.summary?.iCloudWarningsEnabled, false)
        XCTAssertNil(model.saveError)
    }

    @MainActor
    func testLoadFailureUsesCoreErrorMappingAndKeepsRetryAvailable() async {
        let loader = IntegrationsSettingsRecordingLoader(results: [
            .failure(CoreError.Config(reason: "invalid repo_config")),
        ])
        let mapper = IntegrationsSettingsStaticErrorMapper()
        let model = IntegrationsSettingsModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: IntegrationsSettingsRecordingUpdater(results: [.success]),
            errorMapper: mapper,
            statusDetector: IntegrationsSettingsStaticStatusDetector(
                snapshot: IntegrationsICloudSnapshot(repositoryLocation: .unknown, iCloudStatus: .unknown)
            )
        )

        await model.load()
        let mappedErrors = await mapper.mappedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.Config(reason: "invalid repo_config")])
        XCTAssertEqual(model.loadState, .failed(IntegrationsSettingsError(
            message: "配置错误",
            recovery: "Retry status"
        )))
        XCTAssertNil(model.summary)
    }

    @MainActor
    func testPlatformActionsStayInMacLayerWithoutConfigWrites() async {
        let finderOpener = IntegrationsSettingsRecordingFinderOpener()
        let helpOpener = IntegrationsSettingsRecordingHelpOpener()
        let updater = IntegrationsSettingsRecordingUpdater(results: [.success])
        let model = await loadedModel(
            updater: updater,
            finderOpener: finderOpener,
            helpOpener: helpOpener
        )

        model.openICloudHelp()
        model.revealRepositoryInFinder()
        let requests = await updater.requests()

        XCTAssertEqual(helpOpener.openCount, 1)
        XCTAssertEqual(finderOpener.requests, ["/tmp/repo"])
        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.actionFeedback, .success("Repository folder revealed in Finder."))
    }

    @MainActor
    func testDefaultCoreBridgePersistsICloudWarningsWithoutCreatingUserRootFiles() async throws {
        let repoURL = try temporaryIntegrationsSettingsRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let current = try await bridge.loadConfig(repoPath: repoURL.path)
        let targetWarningState = !current.iCloudWarn
        let model = IntegrationsSettingsModel(
            repoPath: repoURL.path,
            loader: bridge,
            updater: bridge,
            errorMapper: bridge,
            statusDetector: IntegrationsSettingsStaticStatusDetector(
                snapshot: IntegrationsICloudSnapshot(repositoryLocation: .localFolder, iCloudStatus: .unavailable)
            )
        )

        await model.load()
        await model.setICloudWarningsEnabled(targetWarningState)
        let reloaded = try await bridge.loadConfig(repoPath: repoURL.path)

        XCTAssertEqual(reloaded.iCloudWarn, targetWarningState)
        XCTAssertEqual(model.summary?.iCloudWarningsEnabled, targetWarningState)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path
        ))
    }

    @MainActor
    private func loadedModel(
        updater: IntegrationsSettingsRecordingUpdater,
        errorMapper: any CoreErrorMapping = IntegrationsSettingsStaticErrorMapper(),
        finderOpener: (any RepositoryFinderOpening)? = nil,
        helpOpener: (any ICloudHelpOpening)? = nil,
        iCloudWarn: Bool = true
    ) async -> IntegrationsSettingsModel {
        let model = IntegrationsSettingsModel(
            repoPath: "/tmp/repo",
            loader: IntegrationsSettingsRecordingLoader(results: [
                .success(.integrationsFixture(repoPath: "/tmp/stale-repo", iCloudWarn: iCloudWarn)),
            ]),
            updater: updater,
            errorMapper: errorMapper,
            statusDetector: IntegrationsSettingsStaticStatusDetector(
                snapshot: IntegrationsICloudSnapshot(repositoryLocation: .localFolder, iCloudStatus: .unavailable)
            ),
            finderOpener: finderOpener ?? IntegrationsSettingsRecordingFinderOpener(),
            helpOpener: helpOpener ?? IntegrationsSettingsRecordingHelpOpener()
        )
        await model.load()
        return model
    }
}

private enum IntegrationsSettingsLoaderResult {
    case success(RepoConfigSnapshot)
    case failure(Error)
}

private actor IntegrationsSettingsRecordingLoader: CoreConfigurationLoading {
    private var results: [IntegrationsSettingsLoaderResult]
    private var paths: [String] = []

    init(results: [IntegrationsSettingsLoaderResult]) {
        self.results = results
    }

    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        paths.append(repoPath)
        let result = results.isEmpty ? .failure(CoreError.Internal(message: "missing config")) : results.removeFirst()
        switch result {
        case .success(let config):
            return config
        case .failure(let error):
            throw error
        }
    }

    func requestedPaths() -> [String] { paths }
}

private enum IntegrationsSettingsUpdateResult {
    case success
    case failure(Error)
}

private actor IntegrationsSettingsRecordingUpdater: CoreConfigurationUpdating {
    struct Request: Equatable {
        var repoPath: String
        var config: RepoConfigSnapshot
    }

    private var results: [IntegrationsSettingsUpdateResult]
    private var recordedRequests: [Request] = []

    init(results: [IntegrationsSettingsUpdateResult]) {
        self.results = results
    }

    func updateConfig(repoPath: String, newConfig: RepoConfigSnapshot) async throws {
        recordedRequests.append(Request(repoPath: repoPath, config: newConfig))
        let result = results.isEmpty ? .success : results.removeFirst()
        if case .failure(let error) = result {
            throw error
        }
    }

    func requests() -> [Request] { recordedRequests }
}

private struct IntegrationsSettingsStaticStatusDetector: ICloudStatusDetecting {
    let snapshot: IntegrationsICloudSnapshot

    func snapshot(repoPath: String, config: RepoConfigSnapshot) async -> IntegrationsICloudSnapshot {
        snapshot
    }
}

private actor IntegrationsSettingsStaticErrorMapper: CoreErrorMapping {
    private var errors: [CoreError] = []

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        let message: String
        let kind: CoreErrorKindSnapshot
        switch error {
        case .Db:
            message = "数据库错误"
            kind = .db
        case .PermissionDenied:
            message = "权限错误"
            kind = .permissionDenied
        default:
            message = "配置错误"
            kind = .config
        }

        return CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: message,
            severity: .medium,
            suggestedAction: kind == .db ? "Retry save" : "Retry status",
            recoverability: .retryable,
            rawContext: "S1-29 C1-04"
        )
    }

    func mappedErrors() -> [CoreError] { errors }
}

@MainActor
private final class IntegrationsSettingsRecordingFinderOpener: RepositoryFinderOpening {
    private(set) var requests: [String] = []

    func openRepositoryInFinder(repoPath: String) throws {
        requests.append(repoPath)
    }
}

@MainActor
private final class IntegrationsSettingsRecordingHelpOpener: ICloudHelpOpening {
    private(set) var openCount = 0

    func openICloudHelp() throws {
        openCount += 1
    }
}

private extension RepoConfigSnapshot {
    static func integrationsFixture(repoPath: String, iCloudWarn: Bool = true) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "system",
            iCloudWarn: iCloudWarn,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}

private func temporaryIntegrationsSettingsRepo() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixIntegrationsSettings-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
