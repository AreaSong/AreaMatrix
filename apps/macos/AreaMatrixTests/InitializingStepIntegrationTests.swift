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
            externalChangesSyncer: RecordingExternalChangesSyncer(result: .success(.createdFixture())),
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
        writer.assertSavedRepoPaths(["/tmp/adopt"])
        XCTAssertEqual(model.route, .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/adopt",
            mode: .adoptExisting,
            scanSession: scanSession,
            recoveryReport: nil
        )))
    }

    @MainActor
    func testSuccessfulInitializationPersistsWatcherCursorAndSavesRepository() async {
        let repoPath = "/tmp/adopt"
        let validation = RepoPathValidationSnapshot.initializingAdoptExistingFixture(repoPath: repoPath)
        let writer = InitializingRecordingSettingsWriter()
        let syncer = RecordingExternalChangesSyncer(result: .success(.createdFixture()), cursor: nil)
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: StaticConfigurationLoader(config: .initializingFixture(repoPath: repoPath)),
            pathValidator: InitializingRecordingPathValidator(validation: validation),
            repositoryInitializer: RecordingRepositoryInitializer(),
            startupRecoverer: StaticStartupRecoverer(),
            externalChangesSyncer: syncer,
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.updateRepositoryPath(repoPath)
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()

        await model.adoptExistingRepositoryFromConfirmInit()

        let cursorWrites = await syncer.recordedCursorWrites()
        XCTAssertEqual(cursorWrites.count, 1)
        XCTAssertGreaterThan(cursorWrites[0], 0)
        writer.assertSavedRepoPaths([repoPath])
        XCTAssertEqual(model.route, .initializationDone(RepositoryInitializationResult(
            repoPath: repoPath,
            mode: .adoptExisting,
            scanSession: nil,
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
        await errorMapper.assertMappedCoreErrors([CoreError.PermissionDenied(path: "/tmp/adopt")])
        XCTAssertEqual(model.route, .initializationFailed(
            "/tmp/adopt",
            mapping,
            RepositoryInitializationDraft(validation: validation, mode: .adoptExisting, scanSession: nil)
        ))
        writer.assertNoSavedRepoPaths()
    }

    @MainActor
    func testInitializingRunsStartupRecoveryBeforeRepositoryWriteAndShowsReport() async {
        let validation = RepoPathValidationSnapshot.initializingAdoptExistingFixture(repoPath: "/tmp/adopt")
        let report = RecoveryReportSnapshot.testFixture(
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
            externalChangesSyncer: RecordingExternalChangesSyncer(result: .success(.createdFixture())),
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
        await startupRecoverer.assertRequestedRepoPaths(["/tmp/adopt"])
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
            externalChangesSyncer: RecordingExternalChangesSyncer(result: .success(.createdFixture())),
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.updateRepositoryPath("/tmp/adopt")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()

        await model.adoptExistingRepositoryFromConfirmInit()

        await startupRecoverer.assertRequestedRepoPaths(["/tmp/adopt"])
        await initializer.assertAdoptedRepoPaths(["/tmp/adopt"])
        XCTAssertNil(model.initializationRecoveryReport)
        writer.assertSavedRepoPaths(["/tmp/adopt"])
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
        await errorMapper.assertMappedCoreErrors([CoreError.Db(message: "recovery db")])
        XCTAssertEqual(model.route, .initializationFailed(
            "/tmp/adopt",
            mapping,
            RepositoryInitializationDraft(validation: validation, mode: .adoptExisting, scanSession: nil)
        ))
        writer.assertNoSavedRepoPaths()
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
            externalChangesSyncer: RecordingExternalChangesSyncer(result: .success(.createdFixture())),
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
        writer.assertNoSavedRepoPaths()
        XCTAssertEqual(model.route, .welcome)
        XCTAssertEqual(
            model.toastMessage,
            "Initialization stopped at a safe point. " +
                "When you choose the same repository again, AreaMatrix will continue or enter recovery."
        )
    }

    @MainActor
    private func waitForInitializationScanSession(on model: OnboardingModel) async {
        _ = await waitForMainActorTestValue(
            delayNanoseconds: 10_000_000,
            failureMessage: { "Timed out waiting for initialization scan session" },
            value: {
                model.initializationScanSession
            }
        )
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
        await scanReader.assertScanSessionResumeRequests([
            ScanSessionResumeRequest(repoPath: "/tmp/adopt", scanSessionId: 42)
        ])
        writer.assertSavedRepoPaths(["/tmp/adopt"])
        XCTAssertEqual(model.route, .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/adopt",
            mode: .adoptExisting,
            scanSession: .testFixture(status: .completed) {
                $0.updatedAt = model.initializationScanSession?.updatedAt ?? 0
                $0.finishedAt = model.initializationScanSession?.finishedAt
            },
            recoveryReport: nil
        )))
    }

    @MainActor
    func testCleanUpInterruptedInitializationRunsRecoveryAndReturnsToConfirmInit() async {
        let validation = RepoPathValidationSnapshot.initializingAdoptExistingFixture(repoPath: "/tmp/adopt")
        let startupRecoverer = RecordingCoreStartupRecoverer(result: .success(.testFixture(
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
        await startupRecoverer.assertRequestedRepoPaths(["/tmp/adopt"])
        XCTAssertEqual(model.initializationRecoveryReport, .testFixture(
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
