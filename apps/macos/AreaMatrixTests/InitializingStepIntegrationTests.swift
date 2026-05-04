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
            startupRecoverer: StaticStartupRecoverer(),
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
        XCTAssertEqual(model.route, .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/adopt",
            mode: .adoptExisting,
            scanSession: scanSession,
            recoveryReport: nil
        )))
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
            startupRecoverer: StaticStartupRecoverer(),
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
    func testInitializingRunsStartupRecoveryBeforeRepositoryWriteAndShowsReport() async {
        let validation = RepoPathValidationSnapshot.adoptExistingFixture(repoPath: "/tmp/adopt")
        let report = RecoveryReportSnapshot(
            cleanedStagingFiles: 2,
            revertedStagingDbRows: 1,
            warnings: ["Kept recoverable moved staging file"]
        )
        let startupRecoverer = RecordingStartupRecoverer(result: .success(report))
        let initializer = PausingRepositoryInitializer()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: RecordingSettingsWriter(),
            configLoader: RecordingConfigLoader(config: .fixture(repoPath: "/tmp/adopt")),
            pathValidator: RecordingPathValidator(validation: validation),
            repositoryInitializer: initializer,
            startupRecoverer: startupRecoverer,
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.updateRepositoryPath("/tmp/adopt")
        await model.continueFromChoosePath()
        model.continueFromValidatePath()
        let initializationTask = Task {
            await model.adoptExistingRepositoryFromConfirmInit()
        }
        await startupRecoverer.waitUntilRecovered()
        await initializer.waitUntilStarted()
        let recoveredPaths = await startupRecoverer.requestedRepoPaths()
        XCTAssertEqual(recoveredPaths, ["/tmp/adopt"])
        XCTAssertEqual(model.initializationRecoveryReport, report)
        XCTAssertEqual(model.route, .initializing(RepositoryInitializationDraft(
            validation: validation,
            mode: .adoptExisting,
            scanSession: nil
        )))
        await initializationTask.value
    }
    @MainActor
    func testStartupRecoveryErrorRoutesToInitFailedBeforeRepositoryWrite() async {
        let validation = RepoPathValidationSnapshot.adoptExistingFixture(repoPath: "/tmp/adopt")
        let mapping = CoreErrorMappingSnapshot.dbFixture(rawContext: "recovery db")
        let errorMapper = RecordingErrorMapper(mapping: mapping)
        let writer = RecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: RecordingConfigLoader(config: .fixture(repoPath: "/tmp/adopt")),
            pathValidator: RecordingPathValidator(validation: validation),
            repositoryInitializer: PausingRepositoryInitializer(),
            startupRecoverer: RecordingStartupRecoverer(result: .failure(CoreError.Db(message: "recovery db"))),
            errorMapper: errorMapper,
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.updateRepositoryPath("/tmp/adopt")
        await model.continueFromChoosePath()
        model.continueFromValidatePath()
        await model.adoptExistingRepositoryFromConfirmInit()
        XCTAssertEqual(errorMapper.mappedErrors, [CoreError.Db(message: "recovery db")])
        XCTAssertEqual(model.route, .initializationFailed("/tmp/adopt", mapping))
        XCTAssertEqual(writer.savedRepoPaths, [])
    }
    @MainActor
    func testInitializingCancelWaitsForSafePointAndDoesNotSaveRepositoryPath() async {
        let validation = RepoPathValidationSnapshot.adoptExistingFixture(repoPath: "/tmp/adopt")
        let writer = RecordingSettingsWriter()
        let initializer = PausingRepositoryInitializer()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: RecordingConfigLoader(config: .fixture(repoPath: "/tmp/adopt")),
            pathValidator: RecordingPathValidator(validation: validation),
            repositoryInitializer: initializer,
            startupRecoverer: StaticStartupRecoverer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.updateRepositoryPath("/tmp/adopt")
        await model.continueFromChoosePath()
        model.continueFromValidatePath()
        let initializationTask = Task {
            await model.adoptExistingRepositoryFromConfirmInit()
        }
        await initializer.waitUntilStarted()
        model.requestSetupQuit()
        let shouldCloseWindow = model.confirmSetupQuit()
        XCTAssertFalse(shouldCloseWindow)
        XCTAssertTrue(model.isInitializationCancellationRequested)
        XCTAssertEqual(model.route, .initializing(RepositoryInitializationDraft(
            validation: validation,
            mode: .adoptExisting,
            scanSession: nil
        )))
        await initializationTask.value
        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertEqual(model.route, .welcome)
        XCTAssertEqual(
            model.toastMessage,
            "初始化已在安全点停止。下次选择同一资料库时，AreaMatrix 会继续或进入恢复。"
        )
    }
    @MainActor
    func testResumeInterruptedInitializationUsesScanSessionResumeAndShowsDonePage() async {
        let scanSession = ScanSessionSnapshot.adoptRunningFixture()
        let writer = RecordingSettingsWriter()
        let scanReader = RecordingResumeScanSessionReader(
            session: scanSession,
            resumeReport: ReindexReportSnapshot(
                scanSessionId: scanSession.id,
                inserted: 12,
                updated: 2,
                skipped: 1,
                errors: []
            )
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: RecordingConfigLoader(config: .fixture(repoPath: "/tmp/adopt")),
            pathValidator: RecordingPathValidator(validation: .adoptExistingFixture(repoPath: "/tmp/adopt")),
            repositoryInitializer: PausingRepositoryInitializer(),
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: scanReader,
            helpOpener: NoopWelcomeHelpOpener()
        )
        await model.resumeInterruptedInitialization(repoPath: "/tmp/adopt", scanSession: scanSession)
        let resumedRequests = await scanReader.resumedRequests()
        XCTAssertEqual(resumedRequests, ["/tmp/adopt:42"])
        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/adopt"])
        XCTAssertEqual(model.route, .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/adopt",
            mode: .adoptExisting,
            scanSession: ScanSessionSnapshot(
                id: 42,
                kind: .adopt,
                status: .completed,
                lastPath: "docs/plan.md",
                inserted: 12,
                updated: 2,
                skipped: 1,
                startedAt: 1_700_000_000,
                updatedAt: model.initializationScanSession?.updatedAt ?? 0,
                finishedAt: model.initializationScanSession?.finishedAt,
                errors: []
            ),
            recoveryReport: nil
        )))
    }
    @MainActor
    func testCleanUpInterruptedInitializationRunsRecoveryAndReturnsToConfirmInit() async {
        let validation = RepoPathValidationSnapshot.adoptExistingFixture(repoPath: "/tmp/adopt")
        let startupRecoverer = RecordingStartupRecoverer(result: .success(RecoveryReportSnapshot(
            cleanedStagingFiles: 1,
            revertedStagingDbRows: 1,
            warnings: []
        )))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(config: .fixture(repoPath: "/tmp/adopt")),
            pathValidator: RecordingPathValidator(validation: validation),
            repositoryInitializer: PausingRepositoryInitializer(),
            startupRecoverer: startupRecoverer,
            helpOpener: NoopWelcomeHelpOpener()
        )
        await model.cleanUpInterruptedInitialization(repoPath: "/tmp/adopt")
        let recoveredPaths = await startupRecoverer.requestedRepoPaths()
        XCTAssertEqual(recoveredPaths, ["/tmp/adopt"])
        XCTAssertEqual(model.initializationRecoveryReport, RecoveryReportSnapshot(
            cleanedStagingFiles: 1,
            revertedStagingDbRows: 1,
            warnings: []
        ))
        XCTAssertEqual(model.route, .confirmRepositoryInitialization(RepositoryInitializationDraft(
            validation: validation,
            mode: .adoptExisting,
            scanSession: nil
        )))
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
private enum StartupRecoveryResult {
    case success(RecoveryReportSnapshot)
    case failure(Error)
}
private actor StaticStartupRecoverer: CoreStartupRecovering {
    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        RecoveryReportSnapshot(cleanedStagingFiles: 0, revertedStagingDbRows: 0, warnings: [])
    }
}
private actor RecordingStartupRecoverer: CoreStartupRecovering {
    private let result: StartupRecoveryResult
    private var paths: [String] = []
    private var didRecover = false
    init(result: StartupRecoveryResult) {
        self.result = result
    }
    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        paths.append(repoPath)
        didRecover = true
        switch result {
        case .success(let report):
            return report
        case .failure(let error):
            throw error
        }
    }
    func waitUntilRecovered() async {
        while !didRecover {
            await Task.yield()
        }
    }
    func requestedRepoPaths() -> [String] { paths }
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
private actor RecordingResumeScanSessionReader: CoreScanSessionReading {
    private let session: ScanSessionSnapshot
    private let resumeReport: ReindexReportSnapshot
    private var requests: [String] = []
    init(session: ScanSessionSnapshot, resumeReport: ReindexReportSnapshot) {
        self.session = session
        self.resumeReport = resumeReport
    }
    func latestScanSession(repoPath: String) async throws -> ScanSessionSnapshot? {
        session
    }
    func resumeScanSession(repoPath: String, scanSessionId: Int64) async throws -> ReindexReportSnapshot {
        requests.append("\(repoPath):\(scanSessionId)")
        return resumeReport
    }
    func resumedRequests() -> [String] { requests }
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
    static func dbFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "数据库错误",
            severity: .critical,
            suggestedAction: "请检查资料库 metadata 后重试",
            recoverability: .fatal,
            rawContext: rawContext
        )
    }
}
