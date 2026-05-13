@testable import AreaMatrix
import XCTest

final class InitFailedErrorMappingTests: XCTestCase {
    @MainActor
    func testInitializationFailureMapsCoreErrorAndRetryRerunsStoredDraft() async {
        let validation = RepoPathValidationSnapshot.initFailedAdoptExistingFixture(repoPath: "/tmp/adopt")
        let mapping = CoreErrorMappingSnapshot.initFailedPermissionDeniedFixture(rawContext: "/tmp/adopt")
        let initializer = RetryingRepositoryInitializer(firstError: CoreError.PermissionDenied(path: "/tmp/adopt"))
        let errorMapper = InitFailedRecordingErrorMapper(mapping: mapping)
        let writer = InitFailedRecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: InitFailedStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            pathValidator: StaticPathValidator(validation: validation),
            repositoryInitializer: initializer,
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: StaticInitFailedScanSessionReader(),
            errorMapper: errorMapper,
            helpOpener: InitFailedNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/adopt")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
        await model.adoptExistingRepositoryFromConfirmInit()

        let retryDraft = RepositoryInitializationDraft(
            validation: validation,
            mode: .adoptExisting,
            scanSession: nil
        )
        let firstAdoptRequests = await initializer.adoptRequests()
        XCTAssertEqual(firstAdoptRequests, ["/tmp/adopt"])
        XCTAssertEqual(errorMapper.mappedErrors, [CoreError.PermissionDenied(path: "/tmp/adopt")])
        XCTAssertEqual(model.route, .initializationFailed("/tmp/adopt", mapping, retryDraft))

        await model.retryFailedInitialization()

        let retriedAdoptRequests = await initializer.adoptRequests()
        XCTAssertEqual(retriedAdoptRequests, ["/tmp/adopt", "/tmp/adopt"])
        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/adopt"])
        XCTAssertEqual(model.route, .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/adopt",
            mode: .adoptExisting,
            scanSession: nil,
            recoveryReport: nil
        )))
    }

    func testDefaultCoreBridgeMapsPermissionDeniedThroughCoreMappingContract() async {
        let mapping = await CoreBridge().mapCoreError(CoreError.PermissionDenied(path: "/tmp/repo"))

        XCTAssertEqual(mapping.kind, .permissionDenied)
        XCTAssertEqual(mapping.severity, .high)
        XCTAssertEqual(mapping.recoverability, .userActionRequired)
        XCTAssertFalse(mapping.userMessage.isEmpty)
        XCTAssertFalse(mapping.suggestedAction.isEmpty)
        XCTAssertEqual(mapping.rawContext, "/tmp/repo")
    }

    @MainActor
    func testInitializationFailureCollectsDiagnosticsWithoutSavingRepositorySelection() async {
        let snapshot = DiagnosticsSnapshotSnapshot(
            snapshotPath: "/tmp/diagnostics/redacted.zip",
            createdAt: 1_700_000_000,
            warnings: ["paths redacted"]
        )
        let collector = InitFailedRecordingDiagnosticsCollector(result: .success(snapshot))
        let writer = InitFailedRecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: InitFailedStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            diagnosticsCollector: collector,
            helpOpener: InitFailedNoopWelcomeHelpOpener()
        )

        model.route = .initializationFailed("/Users/example/private-repo", nil, nil)
        await model.collectInitializationDiagnostics()

        let requestedRepoPaths = await collector.requestedRepoPaths()
        XCTAssertEqual(requestedRepoPaths, ["/Users/example/private-repo"])
        XCTAssertEqual(model.initializationDiagnostics, .collected(snapshot))
        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertEqual(model.route, .initializationFailed("/Users/example/private-repo", nil, nil))
    }

    @MainActor
    func testInitializationDiagnosticsFailureMapsErrorAndStaysOnFailedPage() async {
        let mapping = CoreErrorMappingSnapshot.initFailedPermissionDeniedFixture(rawContext: "/tmp/repo")
        let collector =
            InitFailedRecordingDiagnosticsCollector(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo")))
        let errorMapper = InitFailedRecordingErrorMapper(mapping: mapping)
        let model = OnboardingModel(
            settingsReader: InitFailedStaticSettingsReader(repoPath: nil),
            diagnosticsCollector: collector,
            errorMapper: errorMapper,
            helpOpener: InitFailedNoopWelcomeHelpOpener()
        )

        model.route = .initializationFailed("/tmp/repo", nil, nil)
        await model.collectInitializationDiagnostics()

        XCTAssertEqual(model.initializationDiagnostics, .failed(mapping))
        XCTAssertEqual(errorMapper.mappedErrors, [CoreError.PermissionDenied(path: "/tmp/repo")])
        XCTAssertEqual(model.route, .initializationFailed("/tmp/repo", nil, nil))
    }
}

private actor RetryingRepositoryInitializer: CoreRepositoryInitializing {
    private let firstError: Error
    private var createPaths: [String] = []
    private var adoptPaths: [String] = []

    init(firstError: Error) {
        self.firstError = firstError
    }

    func initializeEmptyRepository(repoPath: String) async throws {
        createPaths.append(repoPath)
        if createPaths.count == 1 {
            throw firstError
        }
    }

    func adoptExistingRepository(repoPath: String) async throws {
        adoptPaths.append(repoPath)
        if adoptPaths.count == 1 {
            throw firstError
        }
    }

    func adoptRequests() -> [String] {
        adoptPaths
    }
}

private struct InitFailedStaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? {
        repoPath
    }
}

private final class InitFailedRecordingSettingsWriter: AppSettingsWriting {
    private(set) var savedRepoPaths: [String] = []

    func saveConfiguredRepoPath(_ repoPath: String) {
        savedRepoPaths.append(repoPath)
    }
}

private enum InitFailedDiagnosticsResult {
    case success(DiagnosticsSnapshotSnapshot)
    case failure(Error)
}

private actor InitFailedRecordingDiagnosticsCollector: CoreDiagnosticsCollecting {
    private let result: InitFailedDiagnosticsResult
    private var repoPaths: [String] = []

    init(result: InitFailedDiagnosticsResult) {
        self.result = result
    }

    func createDiagnosticsSnapshot(repoPath: String) async throws -> DiagnosticsSnapshotSnapshot {
        repoPaths.append(repoPath)
        switch result {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] {
        repoPaths
    }
}

private actor StaticPathValidator: CoreRepositoryPathValidating {
    private let validation: RepoPathValidationSnapshot

    init(validation: RepoPathValidationSnapshot) {
        self.validation = validation
    }

    func validateRepoPath(repoPath _: String) async throws -> RepoPathValidationSnapshot {
        validation
    }
}

private actor StaticStartupRecoverer: CoreStartupRecovering {
    func recoverOnStartup(repoPath _: String) async throws -> RecoveryReportSnapshot {
        RecoveryReportSnapshot(cleanedStagingFiles: 0, revertedStagingDbRows: 0, warnings: [])
    }
}

private actor StaticInitFailedScanSessionReader: CoreScanSessionReading {
    func latestScanSession(repoPath _: String) async throws -> ScanSessionSnapshot? {
        nil
    }
}

private final class InitFailedRecordingErrorMapper: CoreErrorMapping {
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

private struct InitFailedNoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

private extension RepoPathValidationSnapshot {
    static func initFailedAdoptExistingFixture(repoPath: String) -> RepoPathValidationSnapshot {
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

private extension CoreErrorMappingSnapshot {
    static func initFailedPermissionDeniedFixture(rawContext: String) -> CoreErrorMappingSnapshot {
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
