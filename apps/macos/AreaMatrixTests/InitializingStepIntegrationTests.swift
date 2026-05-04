import Foundation
import XCTest
@testable import AreaMatrix

final class InitializingStepIntegrationTests: XCTestCase {
    @MainActor
    func testAdoptExistingInitializingPollsLatestScanSession() async {
        let validation = RepoPathValidationSnapshot.adoptExistingFixture(repoPath: "/tmp/adopt")
        let scanSession = ScanSessionSnapshot.adoptRunningFixture()
        let writer = RecordingSettingsWriter()
        let initializer = PausingRepositoryInitializer()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: RecordingConfigLoader(config: .fixture(repoPath: "/tmp/adopt")),
            pathValidator: RecordingPathValidator(validation: validation),
            repositoryInitializer: initializer,
            scanSessionReader: StaticScanSessionReader(session: scanSession),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/adopt")
        await model.continueFromChoosePath()
        model.continueFromValidatePath()
        let initializationTask = Task {
            await model.adoptExistingRepositoryFromConfirmInit()
        }

        await initializer.waitUntilStarted()
        await waitForInitializationScanSession(on: model)

        XCTAssertEqual(model.route, .initializing(RepositoryInitializationDraft(
            validation: validation,
            mode: .adoptExisting,
            scanSession: nil
        )))
        XCTAssertEqual(model.initializationScanSession, scanSession)

        await initializationTask.value

        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/adopt"])
        XCTAssertEqual(model.route, .mainLoading("/tmp/adopt"))
    }

    @MainActor
    func testAdoptExistingFatalErrorRoutesToInitFailed() async {
        let validation = RepoPathValidationSnapshot.adoptExistingFixture(repoPath: "/tmp/adopt")
        let mapping = CoreErrorMappingSnapshot.permissionDeniedFixture(rawContext: "/tmp/adopt")
        let errorMapper = RecordingErrorMapper(mapping: mapping)
        let writer = RecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: RecordingConfigLoader(config: .fixture(repoPath: "/tmp/adopt")),
            pathValidator: RecordingPathValidator(validation: validation),
            repositoryInitializer: FailingRepositoryInitializer(error: CoreError.PermissionDenied(path: "/tmp/adopt")),
            errorMapper: errorMapper,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/adopt")
        await model.continueFromChoosePath()
        model.continueFromValidatePath()
        await model.adoptExistingRepositoryFromConfirmInit()

        XCTAssertEqual(errorMapper.mappedErrors, [CoreError.PermissionDenied(path: "/tmp/adopt")])
        XCTAssertEqual(model.route, .initializationFailed("/tmp/adopt", mapping))
        XCTAssertEqual(writer.savedRepoPaths, [])
    }

    @MainActor
    private func waitForInitializationScanSession(on model: OnboardingModel) async {
        for _ in 0..<100 where model.initializationScanSession == nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private struct StaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? { repoPath }
}

private final class RecordingSettingsWriter: AppSettingsWriting {
    private(set) var savedRepoPaths: [String] = []

    func saveConfiguredRepoPath(_ repoPath: String) {
        savedRepoPaths.append(repoPath)
    }
}

private actor RecordingConfigLoader: CoreConfigurationLoading {
    private let config: RepoConfigSnapshot

    init(config: RepoConfigSnapshot) {
        self.config = config
    }

    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        config
    }
}

private actor RecordingPathValidator: CoreRepositoryPathValidating {
    private let validation: RepoPathValidationSnapshot

    init(validation: RepoPathValidationSnapshot) {
        self.validation = validation
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        validation
    }
}

private actor PausingRepositoryInitializer: CoreRepositoryInitializing {
    private var didStart = false

    func initializeEmptyRepository(repoPath: String) async throws {}

    func adoptExistingRepository(repoPath: String) async throws {
        didStart = true
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    func waitUntilStarted() async {
        while !didStart {
            await Task.yield()
        }
    }
}

private actor FailingRepositoryInitializer: CoreRepositoryInitializing {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func initializeEmptyRepository(repoPath: String) async throws {
        throw error
    }

    func adoptExistingRepository(repoPath: String) async throws {
        throw error
    }
}

private actor StaticScanSessionReader: CoreScanSessionReading {
    private let session: ScanSessionSnapshot

    init(session: ScanSessionSnapshot) {
        self.session = session
    }

    func latestScanSession(repoPath: String) async throws -> ScanSessionSnapshot? {
        session
    }
}

private struct NoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

private final class RecordingErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private(set) var mappedErrors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        mappedErrors.append(error)
        return mapping
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

private extension RepoPathValidationSnapshot {
    static func adoptExistingFixture(repoPath: String) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: false,
            isInitialized: false,
            isInsideAreaMatrix: false,
            isICloudPath: false,
            hasUnfinishedScanSession: false,
            availableCapacityBytes: 1_073_741_824,
            isExternalVolume: false,
            recommendedMode: .adoptExisting,
            issues: [.nonEmptyDirectory]
        )
    }
}

private extension ScanSessionSnapshot {
    static func adoptRunningFixture() -> ScanSessionSnapshot {
        ScanSessionSnapshot(
            id: 42,
            kind: .adopt,
            status: .running,
            lastPath: "docs/plan.md",
            inserted: 11,
            updated: 2,
            skipped: 1,
            startedAt: 1_700_000_000,
            updatedAt: 1_700_000_010,
            finishedAt: nil,
            errors: ["skipped unreadable file: private.tmp"]
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func permissionDeniedFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .permissionDenied,
            userMessage: "无访问权限",
            severity: .high,
            suggestedAction: "请在系统设置中授予权限，或选择其他资料库位置",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }
}
