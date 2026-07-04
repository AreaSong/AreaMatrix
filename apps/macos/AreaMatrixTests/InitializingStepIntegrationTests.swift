@testable import AreaMatrix
import Foundation
import XCTest

final class InitializingStepIntegrationTests: XCTestCase {
    @MainActor
    func testAdoptExistingInitializingPollsLatestScanSession() async {
        let validation = RepoPathValidationSnapshot.initializingAdoptExistingFixture(repoPath: "/tmp/adopt")
        let scanSession = ScanSessionSnapshot.adoptRunningFixture()
        let writer = InitializingRecordingSettingsWriter()
        let initializer = PausingRepositoryInitializer()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: StaticConfigurationLoader(config: .initializingFixture(repoPath: "/tmp/adopt")),
            pathValidator: InitializingRecordingPathValidator(validation: validation),
            repositoryInitializer: initializer,
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: StaticScanSessionReader(session: scanSession),
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.updateRepositoryPath("/tmp/adopt")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
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
        let validation = RepoPathValidationSnapshot.initializingAdoptExistingFixture(repoPath: "/tmp/adopt")
        let mapping = CoreErrorMappingSnapshot.initializingPermissionDeniedFixture(rawContext: "/tmp/adopt")
        let errorMapper = StaticCoreErrorMapper(mapping: mapping)
        let writer = InitializingRecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: StaticConfigurationLoader(config: .initializingFixture(repoPath: "/tmp/adopt")),
            pathValidator: InitializingRecordingPathValidator(validation: validation),
            repositoryInitializer: RecordingRepositoryInitializer(
                error: CoreError.PermissionDenied(path: "/tmp/adopt")
            ),
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: StaticScanSessionReader(session: nil),
            errorMapper: errorMapper,
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.updateRepositoryPath("/tmp/adopt")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
        await model.adoptExistingRepositoryFromConfirmInit()
        let mappedErrors = await errorMapper.recordedErrors()
        XCTAssertEqual(mappedErrors, [CoreError.PermissionDenied(path: "/tmp/adopt")])
        XCTAssertEqual(model.route, .initializationFailed(
            "/tmp/adopt",
            mapping,
            RepositoryInitializationDraft(validation: validation, mode: .adoptExisting, scanSession: nil)
        ))
        XCTAssertEqual(writer.savedRepoPaths, [])
    }

    @MainActor
    func testInitializingRunsStartupRecoveryBeforeRepositoryWriteAndShowsReport() async {
        let validation = RepoPathValidationSnapshot.initializingAdoptExistingFixture(repoPath: "/tmp/adopt")
        let report = RecoveryReportSnapshot(
            cleanedStagingFiles: 2,
            revertedStagingDbRows: 1,
            warnings: ["Kept recoverable moved staging file"]
        )
        let startupRecoverer = RecordingCoreStartupRecoverer(result: .success(report))
        let initializer = PausingRepositoryInitializer()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: InitializingRecordingSettingsWriter(),
            configLoader: StaticConfigurationLoader(config: .initializingFixture(repoPath: "/tmp/adopt")),
            pathValidator: InitializingRecordingPathValidator(validation: validation),
            repositoryInitializer: initializer,
            startupRecoverer: startupRecoverer,
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.updateRepositoryPath("/tmp/adopt")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
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
    func testInitializingIgnoresRepoNotInitializedStartupRecoveryBeforeRepositoryWrite() async {
        let validation = RepoPathValidationSnapshot.initializingAdoptExistingFixture(repoPath: "/tmp/adopt")
        let startupRecoverer = RecordingCoreStartupRecoverer(
            result: .failure(CoreError.RepoNotInitialized(path: "/tmp/adopt"))
        )
        let initializer = RecordingRepositoryInitializer()
        let writer = InitializingRecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: StaticConfigurationLoader(config: .initializingFixture(repoPath: "/tmp/adopt")),
            pathValidator: InitializingRecordingPathValidator(validation: validation),
            repositoryInitializer: initializer,
            startupRecoverer: startupRecoverer,
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.updateRepositoryPath("/tmp/adopt")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()

        await model.adoptExistingRepositoryFromConfirmInit()
        let recoveredPaths = await startupRecoverer.requestedRepoPaths()
        let adoptedPaths = await initializer.adoptedRepoPaths()

        XCTAssertEqual(recoveredPaths, ["/tmp/adopt"])
        XCTAssertEqual(adoptedPaths, ["/tmp/adopt"])
        XCTAssertNil(model.initializationRecoveryReport)
        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/adopt"])
        XCTAssertEqual(model.route, .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/adopt",
            mode: .adoptExisting,
            scanSession: nil,
            recoveryReport: nil
        )))
    }

    @MainActor
    func testStartupRecoveryErrorRoutesToInitFailedBeforeRepositoryWrite() async {
        let validation = RepoPathValidationSnapshot.initializingAdoptExistingFixture(repoPath: "/tmp/adopt")
        let mapping = CoreErrorMappingSnapshot.initializingDbFixture(rawContext: "recovery db")
        let errorMapper = StaticCoreErrorMapper(mapping: mapping)
        let writer = InitializingRecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: StaticConfigurationLoader(config: .initializingFixture(repoPath: "/tmp/adopt")),
            pathValidator: InitializingRecordingPathValidator(validation: validation),
            repositoryInitializer: PausingRepositoryInitializer(),
            startupRecoverer: RecordingCoreStartupRecoverer(result: .failure(CoreError.Db(message: "recovery db"))),
            errorMapper: errorMapper,
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.updateRepositoryPath("/tmp/adopt")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
        await model.adoptExistingRepositoryFromConfirmInit()
        let mappedErrors = await errorMapper.recordedErrors()
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "recovery db")])
        XCTAssertEqual(model.route, .initializationFailed(
            "/tmp/adopt",
            mapping,
            RepositoryInitializationDraft(validation: validation, mode: .adoptExisting, scanSession: nil)
        ))
        XCTAssertEqual(writer.savedRepoPaths, [])
    }

    @MainActor
    func testInitializingCancelWaitsForSafePointAndDoesNotSaveRepositoryPath() async {
        let validation = RepoPathValidationSnapshot.initializingAdoptExistingFixture(repoPath: "/tmp/adopt")
        let writer = InitializingRecordingSettingsWriter()
        let initializer = PausingRepositoryInitializer()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: StaticConfigurationLoader(config: .initializingFixture(repoPath: "/tmp/adopt")),
            pathValidator: InitializingRecordingPathValidator(validation: validation),
            repositoryInitializer: initializer,
            startupRecoverer: StaticStartupRecoverer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.updateRepositoryPath("/tmp/adopt")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
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
    private func waitForInitializationScanSession(on model: OnboardingModel) async {
        for _ in 0 ..< 100 where model.initializationScanSession == nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

final class InterruptedInitializationRecoveryTests: XCTestCase {
    @MainActor
    func testResumeInterruptedInitializationUsesScanSessionResumeAndShowsDonePage() async {
        let scanSession = ScanSessionSnapshot.adoptRunningFixture()
        let writer = InitializingRecordingSettingsWriter()
        let scanReader = RecordingScanSessionReader(
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
            configLoader: StaticConfigurationLoader(config: .initializingFixture(repoPath: "/tmp/adopt")),
            pathValidator: InitializingRecordingPathValidator(
                validation: .initializingAdoptExistingFixture(repoPath: "/tmp/adopt")
            ),
            repositoryInitializer: PausingRepositoryInitializer(),
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: scanReader,
            helpOpener: NoopWelcomeHelpOpener()
        )
        await model.resumeInterruptedInitialization(repoPath: "/tmp/adopt", scanSession: scanSession)
        let resumedRequests = await scanReader.recordedResumeRequests()
        XCTAssertEqual(resumedRequests, [ScanSessionResumeRequest(repoPath: "/tmp/adopt", scanSessionId: 42)])
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
        let validation = RepoPathValidationSnapshot.initializingAdoptExistingFixture(repoPath: "/tmp/adopt")
        let startupRecoverer = RecordingCoreStartupRecoverer(result: .success(RecoveryReportSnapshot(
            cleanedStagingFiles: 1,
            revertedStagingDbRows: 1,
            warnings: []
        )))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: StaticConfigurationLoader(config: .initializingFixture(repoPath: "/tmp/adopt")),
            pathValidator: InitializingRecordingPathValidator(validation: validation),
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
}

private typealias InitializingRecordingSettingsWriter = RecordingAppSettingsWriter

private typealias InitializingRecordingPathValidator = RecordingRepositoryPathValidator
