import XCTest
@testable import AreaMatrix

final class MainRepoErrorMappingTests: XCTestCase {
    func testMissingPathUsesReconnectFolderCopy() {
        let presentation = RepositoryErrorPresentation.mainRepo(mapping: .mainRepoFixture(
            kind: .invalidPath,
            rawContext: "/tmp/missing-repo"
        ))

        XCTAssertEqual(presentation.title, "Folder is missing")
        XCTAssertEqual(
            presentation.message,
            "AreaMatrix cannot find this folder. It may have been moved, renamed, or disconnected."
        )
        XCTAssertEqual(presentation.primaryAction, .reconnectFolder)
        XCTAssertEqual(presentation.primaryActionTitle, "Reconnect folder")
    }

    func testICloudPlaceholderUsesDownloadRetryCopy() {
        let presentation = RepositoryErrorPresentation.mainRepo(mapping: .mainRepoFixture(
            kind: .iCloudPlaceholder,
            rawContext: "/Users/me/Library/Mobile Documents/repo.icloud"
        ))

        XCTAssertEqual(presentation.title, "iCloud file is not downloaded")
        XCTAssertEqual(presentation.primaryAction, .downloadAndRetry)
        XCTAssertEqual(presentation.primaryActionTitle, "Download and retry")
    }

    func testDbAndConfigErrorsUseRepairCopyWithoutRetryAction() {
        let db = RepositoryErrorPresentation.mainRepo(mapping: .mainRepoFixture(
            kind: .db,
            severity: .critical,
            recoverability: .fatal,
            rawContext: "db corrupt"
        ))
        let config = RepositoryErrorPresentation.mainRepo(mapping: .mainRepoFixture(
            kind: .config,
            rawContext: "schema mismatch"
        ))

        XCTAssertEqual(db.title, "Repository metadata needs repair")
        XCTAssertEqual(db.primaryAction, .openRepair)
        XCTAssertEqual(db.primaryActionTitle, "Open repair")
        XCTAssertEqual(config.primaryAction, .openRepair)
    }

    func testRetryableDbErrorUsesInlineRetryCopyInsteadOfRepairCopy() {
        let presentation = RepositoryErrorPresentation.mainRepo(mapping: .mainRepoFixture(
            kind: .db,
            severity: .medium,
            recoverability: .retryable,
            rawContext: "database is locked"
        ))

        XCTAssertEqual(presentation.title, "Repository is temporarily unavailable")
        XCTAssertEqual(presentation.primaryAction, .retry)
        XCTAssertEqual(presentation.primaryActionTitle, "Retry")
    }

    @MainActor
    func testConfiguredRepoOpenFailureRoutesMappedC121ErrorToMainRepoError() async {
        let error = CoreError.PermissionDenied(path: "/tmp/repo")
        let mapping = CoreErrorMappingSnapshot.mainRepoFixture(kind: .permissionDenied, rawContext: "/tmp/repo")
        let errorMapper = MainRepoRecordingErrorMapper(mapping: mapping)
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: "/tmp/repo"),
            emptyRepositoryOpener: ShellRecordingRepositoryOpener(result: .failure(error)),
            startupRecoverer: ShellStaticStartupRecoverer(),
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(nil)),
            errorMapper: errorMapper,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()

        guard case .mainRepoError(let repoPath, let routeMapping) = model.route else {
            return XCTFail("expected main repo error, got \(model.route)")
        }

        XCTAssertEqual(repoPath, "/tmp/repo")
        XCTAssertEqual(routeMapping, mapping)
        XCTAssertEqual(errorMapper.mappedErrors.first, error)
        XCTAssertTrue(errorMapper.mappedErrors.contains(error))
        XCTAssertEqual(
            RepositoryErrorPresentation.mainRepo(mapping: routeMapping).primaryAction,
            .reconnectFolder
        )
    }

    @MainActor
    func testOpenRepairRoutesDbErrorToRepairConfirmationWithoutRunningCoreRepair() {
        let mapping = CoreErrorMappingSnapshot.mainRepoFixture(
            kind: .db,
            severity: .critical,
            recoverability: .fatal,
            rawContext: "db corrupt"
        )
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )
        model.route = .mainRepoError("/tmp/repo", mapping)
        model.mainRepoRecoveryErrorMapping = mapping

        model.openMainRepositoryRepair(repoPath: "/tmp/repo")

        XCTAssertEqual(model.route, .dbRepairConfirm("/tmp/repo", nil, mapping))
        XCTAssertNil(model.mainRepoRecoveryErrorMapping)
    }

    @MainActor
    func testCriticalDbOpenFailureStillRoutesToMainRepoError() async {
        let mapping = CoreErrorMappingSnapshot.mainRepoFixture(
            kind: .db,
            severity: .critical,
            recoverability: .fatal,
            rawContext: "db corrupt"
        )
        let errorMapper = MainRepoRecordingErrorMapper(mapping: mapping)
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: "/tmp/repo"),
            emptyRepositoryOpener: ShellRecordingRepositoryOpener(result: .failure(CoreError.Db(message: "db corrupt"))),
            startupRecoverer: ShellStaticStartupRecoverer(),
            errorMapper: errorMapper,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()

        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", mapping))
        XCTAssertEqual(model.mainRepoRecoveryErrorMapping, mapping)
    }
}

private final class MainRepoRecordingErrorMapper: CoreErrorMapping {
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

private extension CoreErrorMappingSnapshot {
    static func mainRepoFixture(
        kind: CoreErrorKindSnapshot,
        severity: CoreErrorSeveritySnapshot = .high,
        recoverability: CoreErrorRecoverabilitySnapshot = .userActionRequired,
        rawContext: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "mapped \(kind.rawValue)",
            severity: severity,
            suggestedAction: "mapped action",
            recoverability: recoverability,
            rawContext: rawContext
        )
    }
}
