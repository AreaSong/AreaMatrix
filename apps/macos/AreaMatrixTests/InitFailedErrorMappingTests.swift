import XCTest
@testable import AreaMatrix

final class InitFailedErrorMappingTests: XCTestCase {
    @MainActor
    func testInitializationFailureMapsCoreErrorAndRetryRerunsStoredDraft() async {
        let validation = RepoPathValidationSnapshot.adoptExistingFixture(repoPath: "/tmp/adopt")
        let mapping = CoreErrorMappingSnapshot.permissionDeniedFixture(rawContext: "/tmp/adopt")
        let initializer = RetryingRepositoryInitializer(firstError: CoreError.PermissionDenied(path: "/tmp/adopt"))
        let errorMapper = RecordingErrorMapper(mapping: mapping)
        let writer = RecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            pathValidator: StaticPathValidator(validation: validation),
            repositoryInitializer: initializer,
            startupRecoverer: StaticStartupRecoverer(),
            errorMapper: errorMapper,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/adopt")
        await model.continueFromChoosePath()
        model.continueFromValidatePath()
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

    func adoptRequests() -> [String] { adoptPaths }
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

private actor StaticPathValidator: CoreRepositoryPathValidating {
    private let validation: RepoPathValidationSnapshot

    init(validation: RepoPathValidationSnapshot) {
        self.validation = validation
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        validation
    }
}

private actor StaticStartupRecoverer: CoreStartupRecovering {
    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        RecoveryReportSnapshot(cleanedStagingFiles: 0, revertedStagingDbRows: 0, warnings: [])
    }
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

private struct NoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
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
