@testable import AreaMatrix
import XCTest

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

    func testDefaultCoreBridgeMapsDbLockedAndCorruptedToDistinctRecoveryActions() async {
        let bridge = CoreBridge()
        let locked = await bridge.mapCoreError(CoreError.Db(message: "database is locked"))
        let corrupted = await bridge.mapCoreError(CoreError.Db(message: "database disk image is malformed"))

        XCTAssertEqual(locked.kind, .db)
        XCTAssertEqual(locked.severity, .medium)
        XCTAssertEqual(locked.recoverability, .retryable)
        XCTAssertEqual(RepositoryErrorPresentation.mainRepo(mapping: locked).primaryAction, .retry)
        XCTAssertEqual(corrupted.kind, .db)
        XCTAssertEqual(corrupted.severity, .critical)
        XCTAssertEqual(corrupted.recoverability, .fatal)
        XCTAssertEqual(RepositoryErrorPresentation.mainRepo(mapping: corrupted).primaryAction, .openRepair)
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

        guard case let .mainRepoError(repoPath, routeMapping) = model.route else {
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

        XCTAssertEqual(
            model.route,
            .dbRepairConfirm(DatabaseRepairRouteState(
                repoPath: "/tmp/repo",
                scanSession: nil,
                mapping: mapping,
                returnRoute: .mainRepoError(mapping)
            ))
        )
        XCTAssertNil(model.mainRepoRecoveryErrorMapping)
    }

    @MainActor
    func testCancelRepairFromMainRepoErrorReturnsToSourceErrorPage() {
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
        model.openMainRepositoryRepair(repoPath: "/tmp/repo")
        guard case let .dbRepairConfirm(repairRoute) = model.route else {
            return XCTFail("expected db repair route")
        }

        model.returnFromDatabaseRepair(repairRoute)

        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", mapping))
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
            emptyRepositoryOpener: ShellRecordingRepositoryOpener(result: .failure(CoreError
                    .Db(message: "db corrupt"))),
            startupRecoverer: ShellStaticStartupRecoverer(),
            errorMapper: errorMapper,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()

        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", mapping))
        XCTAssertEqual(model.mainRepoRecoveryErrorMapping, mapping)
    }

    @MainActor
    func testMainRepoErrorDiagnosticsRequirePrivacyConfirmationAndUseCoreSnapshot() async {
        let snapshot = DiagnosticsSnapshotSnapshot(
            snapshotPath: "/tmp/repo/.areamatrix/diagnostics/main-repo.zip",
            createdAt: 1_778_000_000,
            warnings: ["paths redacted"]
        )
        let collector = ShellRecordingDiagnosticsCollector(result: .success(snapshot))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            diagnosticsCollector: collector,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )
        model.route = .mainRepoError("/tmp/repo", nil)

        await model.collectMainRepositoryDiagnostics(repoPath: "/tmp/repo")
        XCTAssertEqual(model.mainRepoDiagnostics, .idle)

        model.requestMainRepositoryDiagnosticsPrivacyConfirmation(repoPath: "/tmp/repo")
        await model.collectMainRepositoryDiagnostics(repoPath: "/tmp/repo")
        let repoPaths = await collector.requestedRepoPaths()

        XCTAssertEqual(repoPaths, ["/tmp/repo"])
        XCTAssertEqual(model.mainRepoDiagnostics, .collected(snapshot))
        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", nil))
    }

    @MainActor
    func testMainRepoErrorDiagnosticsFailureMapsCoreErrorWithoutLeavingPage() async {
        let collector = ShellRecordingDiagnosticsCollector(
            result: .failure(CoreError.PermissionDenied(path: "/tmp/repo"))
        )
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            diagnosticsCollector: collector,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )
        model.route = .mainRepoError("/tmp/repo", nil)

        model.requestMainRepositoryDiagnosticsPrivacyConfirmation(repoPath: "/tmp/repo")
        await model.collectMainRepositoryDiagnostics(repoPath: "/tmp/repo")

        guard case let .failed(mapping) = model.mainRepoDiagnostics else {
            return XCTFail("expected failed diagnostics state")
        }

        XCTAssertEqual(mapping.kind, .permissionDenied)
        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", nil))
    }

    @MainActor
    func testMainRepoErrorUsesPersistedLastSuccessfulOpenTime() {
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(
                repoPath: nil,
                lastOpenedAtByRepoPath: ["/tmp/repo": 1_777_000_000]
            ),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.routeMainRepositoryError(repoPath: "/tmp/repo", mapping: nil)

        XCTAssertEqual(model.mainRepoLastOpenedAt, 1_777_000_000)
        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", nil))
    }

    @MainActor
    func testMainRepoErrorReconnectFolderUsesPickerAndValidatedSelectedPath() async {
        let selectedPath = "/tmp/repo-reconnected"
        let validation = RepoPathValidationSnapshot.shellFixture(
            repoPath: selectedPath,
            isEmpty: false,
            isInitialized: true,
            issues: [.alreadyInitialized],
            recommendedMode: nil
        )
        let picker = ShellRecordingDirectoryPicker(selectedURL: URL(fileURLWithPath: selectedPath, isDirectory: true))
        let initializedValidator = ShellRecordingInitializedPathValidator(result: .success(validation))
        let opening = RepositoryOpeningResult.shellFixture(repoPath: selectedPath, fileCount: 1)
        let opener = ShellRecordingRepositoryOpener(result: .success(opening))
        let writer = ShellRecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            initializedPathValidator: initializedValidator,
            emptyRepositoryOpener: opener,
            startupRecoverer: ShellStaticStartupRecoverer(),
            existingRepositoryMetadataReader: ShellExistingRepoMetadataReader(
                schemaVersion: 1,
                configuredRepoPath: "/tmp/repo"
            ),
            helpOpener: ShellNoopWelcomeHelpOpener(),
            directoryPicker: picker
        )
        model.route = OnboardingModel.Route.mainRepoError(
            "/tmp/repo",
            CoreErrorMappingSnapshot.mainRepoFixture(kind: .invalidPath, rawContext: "/tmp/repo")
        )

        await model.reconnectMainRepositoryFolder(from: "/tmp/repo")
        let validatedPaths = await initializedValidator.requestedRepoPaths()
        let openedPaths = await opener.requestedConfiguredRepoPaths()

        XCTAssertEqual(picker.chooseCount, 1)
        XCTAssertEqual(validatedPaths, [selectedPath])
        XCTAssertEqual(openedPaths, [selectedPath])
        XCTAssertEqual(writer.savedRepoPaths, [selectedPath])
        XCTAssertEqual(model.route, OnboardingModel.Route.mainList(opening))
    }

    @MainActor
    func testMainRepoErrorReconnectFolderRejectsDifferentInitializedRepo() async {
        let selectedPath = "/tmp/other-repo"
        let validation = RepoPathValidationSnapshot.shellFixture(
            repoPath: selectedPath,
            isEmpty: false,
            isInitialized: true,
            issues: [.alreadyInitialized],
            recommendedMode: nil
        )
        let picker = ShellRecordingDirectoryPicker(selectedURL: URL(fileURLWithPath: selectedPath, isDirectory: true))
        let initializedValidator = ShellRecordingInitializedPathValidator(result: .success(validation))
        let opener = ShellRecordingRepositoryOpener(result: .success(.shellFixture(
            repoPath: selectedPath,
            fileCount: 1
        )))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            initializedPathValidator: initializedValidator,
            emptyRepositoryOpener: opener,
            startupRecoverer: ShellStaticStartupRecoverer(),
            existingRepositoryMetadataReader: ShellExistingRepoMetadataReader(
                schemaVersion: 1,
                configuredRepoPath: "/tmp/some-other-repo"
            ),
            helpOpener: ShellNoopWelcomeHelpOpener(),
            directoryPicker: picker
        )
        model.route = OnboardingModel.Route.mainRepoError(
            "/tmp/repo",
            CoreErrorMappingSnapshot.mainRepoFixture(kind: .invalidPath, rawContext: "/tmp/repo")
        )

        await model.reconnectMainRepositoryFolder(from: "/tmp/repo")
        let openedPaths = await opener.requestedConfiguredRepoPaths()

        XCTAssertEqual(openedPaths, [])
        XCTAssertEqual(model.mainRepoRecoveryErrorMapping?.kind, .invalidPath)
        XCTAssertEqual(
            model.route,
            OnboardingModel.Route.mainRepoError("/tmp/repo", model.mainRepoRecoveryErrorMapping)
        )
        XCTAssertFalse(model.isRetryingMainRepository)
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
