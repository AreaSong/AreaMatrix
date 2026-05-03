import XCTest
@testable import AreaMatrix

final class AreaMatrixShellTests: XCTestCase {
    func testBridgeUsesGeneratedBindings() {
        XCTAssertEqual(CoreBridge().state, .generatedBindings)
        XCTAssertEqual(CoreBridge().coreAvailability(), "generated-bindings")
    }

    func testAppShellModelUsesPhaseZeroStatus() {
        XCTAssertEqual(AppShellModel().statusText, "Onboarding configuration router")
    }

    @MainActor
    func testOnboardingShowsWelcomeWhenNoRepoPathIsConfigured() async {
        let loader = RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo")))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: loader,
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()
        let requestedRepoPaths = await loader.requestedRepoPaths()

        XCTAssertEqual(model.route, .welcome)
        XCTAssertEqual(requestedRepoPaths, [])
    }

    @MainActor
    func testOnboardingLoadsConfiguredRepoThroughCoreBridgeBoundary() async {
        let config = RepoConfigSnapshot.fixture(repoPath: "/tmp/repo")
        let loader = RecordingConfigLoader(result: .success(config))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: "/tmp/repo"),
            configLoader: loader,
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()
        let requestedRepoPaths = await loader.requestedRepoPaths()

        XCTAssertEqual(model.route, .repositoryReady(config))
        XCTAssertEqual(requestedRepoPaths, ["/tmp/repo"])
    }

    @MainActor
    func testOnboardingLoadsConfiguredRepoThroughDefaultCoreBridge() async throws {
        let repoURL = try makeTemporaryRepoURL()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
        }

        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: repoURL.path),
            configLoader: CoreBridge(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()

        let expectedConfig = RepoConfigSnapshot(
            repoPath: repoURL.path,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "zh-Hans",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )

        XCTAssertEqual(model.route, .repositoryReady(expectedConfig))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(".areamatrix").path))
    }

    func testCoreBridgePropagatesRealConfigError() async throws {
        do {
            _ = try await CoreBridge().loadConfig(repoPath: "")
            XCTFail("expected CoreError.Config")
        } catch let error as CoreError {
            guard case .Config = error else {
                return XCTFail("expected Config, got \(error)")
            }
        }
    }

    @MainActor
    func testOnboardingMapsConfigLoadFailureWithoutShowingWelcomeAsSuccess() async {
        let loader = RecordingConfigLoader(result: .failure(CoreBridgeError.generatedBindingsUnavailable(
            boundary: .loadConfig,
            state: .phase0
        )))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: "/tmp/repo"),
            configLoader: loader,
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()
        let requestedRepoPaths = await loader.requestedRepoPaths()

        guard case .configurationError(let failure) = model.route else {
            return XCTFail("expected configuration error")
        }

        XCTAssertEqual(failure.repoPath, "/tmp/repo")
        XCTAssertTrue(failure.message.contains("load_config"))
        XCTAssertEqual(requestedRepoPaths, ["/tmp/repo"])
    }

    func testConfigLoadFailureMapsCoreErrors() {
        let config = ConfigLoadFailure.map(
            repoPath: "/tmp/repo",
            error: CoreError.Config(reason: "configuration error")
        )
        let permission = ConfigLoadFailure.map(
            repoPath: "/tmp/repo",
            error: CoreError.PermissionDenied(path: "/tmp/repo/.areamatrix/index.db")
        )
        let io = ConfigLoadFailure.map(
            repoPath: "/tmp/repo",
            error: CoreError.Io(message: "io error")
        )
        let db = ConfigLoadFailure.map(
            repoPath: "/tmp/repo",
            error: CoreError.Db(message: "database error")
        )

        XCTAssertEqual(config.title, "Repository settings are invalid")
        XCTAssertEqual(permission.title, "Repository settings need permission")
        XCTAssertEqual(io.title, "Repository settings are unavailable")
        XCTAssertEqual(db.title, "Repository metadata cannot be opened")
    }

    @MainActor
    func testWelcomeLearnMoreFailureIsNonBlockingToast() {
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            helpOpener: FailingWelcomeHelpOpener()
        )

        model.openLearnMore()

        XCTAssertEqual(model.toastMessage, "Learn more is unavailable right now.")
        XCTAssertEqual(model.route, .loadingConfiguration)
    }
}

private func makeTemporaryRepoURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixShellTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private struct StaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? {
        repoPath
    }
}

private enum RecordingResult {
    case success(RepoConfigSnapshot)
    case failure(Error)
}

private actor RecordingConfigLoader: CoreConfigurationLoading {
    private let result: RecordingResult
    private var paths: [String] = []

    init(result: RecordingResult) {
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

    func requestedRepoPaths() -> [String] {
        paths
    }
}

private struct NoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

private struct FailingWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {
        throw WelcomeHelpError.helpDocumentUnavailable
    }
}

private extension RepoConfigSnapshot {
    static func fixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "zh-Hans",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}
