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
        let databasePresentation = RepositoryErrorPresentation.mainRepo(mapping: .mainRepoFixture(
            kind: .db,
            severity: .critical,
            recoverability: .fatal,
            rawContext: "db corrupt"
        ))
        let config = RepositoryErrorPresentation.mainRepo(mapping: .mainRepoFixture(
            kind: .config,
            rawContext: "schema mismatch"
        ))

        XCTAssertEqual(databasePresentation.title, "Repository metadata needs repair")
        XCTAssertEqual(databasePresentation.primaryAction, .openRepair)
        XCTAssertEqual(databasePresentation.primaryActionTitle, "Open repair")
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

    func testCoreErrorMappingRecoveryTextUsesSuggestedActionBeforeFallbacks() {
        let mapped = CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "数据库错误",
            severity: .medium,
            suggestedAction: "请稍后重试",
            recoverability: .retryable,
            rawContext: "database is locked"
        )
        let fallbackOnly = CoreErrorMappingSnapshot.testFixture(
            kind: .internal,
            userMessage: "应用内部错误",
            severity: .critical,
            suggestedAction: "",
            recoverability: .fatal,
            rawContext: "missing action"
        )

        XCTAssertEqual(mapped.recoveryText, "请稍后重试")
        XCTAssertEqual(mapped.recoveryText(fallback: "Retry"), "请稍后重试")
        XCTAssertEqual(fallbackOnly.recoveryText, "应用内部错误")
        XCTAssertEqual(fallbackOnly.recoveryText(fallback: "Retry"), "Retry")
    }
}

final class MainRepoErrorRouteTests: XCTestCase {
    @MainActor
    func testConfiguredRepoOpenFailureRoutesMappedErrorMappingCoreErrorToMainRepoError() async {
        let error = CoreError.PermissionDenied(path: "/tmp/repo")
        let mapping = CoreErrorMappingSnapshot.mainRepoFixture(kind: .permissionDenied, rawContext: "/tmp/repo")
        let errorMapper = StaticCoreErrorMapper(mapping: mapping)
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: "/tmp/repo"),
            emptyRepositoryOpener: ShellRecordingRepositoryOpener(result: .failure(error)),
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: StaticScanSessionReader(),
            errorMapper: errorMapper,
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()

        guard let route = requireMainRepoErrorRoute(model, message: "expected main repo error") else { return }

        XCTAssertEqual(route.repoPath, "/tmp/repo")
        XCTAssertEqual(route.mapping, mapping)
        await errorMapper.assertMappedCoreErrors([error])
        XCTAssertEqual(
            RepositoryErrorPresentation.mainRepo(mapping: route.mapping).primaryAction,
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
            helpOpener: NoopWelcomeHelpOpener()
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
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.route = .mainRepoError("/tmp/repo", mapping)
        model.openMainRepositoryRepair(repoPath: "/tmp/repo")
        guard let repairRoute = requireDatabaseRepairRoute(model, message: "expected db repair route") else { return }

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
        let errorMapper = StaticCoreErrorMapper(mapping: mapping)
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: "/tmp/repo"),
            emptyRepositoryOpener: ShellRecordingRepositoryOpener(result: .failure(CoreError
                    .Db(message: "db corrupt"))),
            startupRecoverer: StaticStartupRecoverer(),
            errorMapper: errorMapper,
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()

        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", mapping))
        XCTAssertEqual(model.mainRepoRecoveryErrorMapping, mapping)
    }
}

final class MainRepoReconnectFolderTests: XCTestCase {
    @MainActor
    func testMainRepoErrorUsesPersistedLastSuccessfulOpenTime() {
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(
                repoPath: nil,
                lastOpenedAtByRepoPath: ["/tmp/repo": 1_777_000_000]
            ),
            helpOpener: NoopWelcomeHelpOpener()
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
            startupRecoverer: StaticStartupRecoverer(),
            existingRepositoryMetadataReader: ShellExistingRepoMetadataReader(
                schemaVersion: 1,
                configuredRepoPath: "/tmp/repo"
            ),
            helpOpener: NoopWelcomeHelpOpener(),
            directoryPicker: picker
        )
        model.route = OnboardingModel.Route.mainRepoError(
            "/tmp/repo",
            CoreErrorMappingSnapshot.mainRepoFixture(kind: .invalidPath, rawContext: "/tmp/repo")
        )

        await model.reconnectMainRepositoryFolder(from: "/tmp/repo")

        picker.assertChooseCount(1)
        await initializedValidator.assertRequestedRepoPaths([selectedPath])
        await opener.assertRequestedConfiguredRepoPaths([selectedPath])
        writer.assertSavedRepoPaths([selectedPath])
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
            startupRecoverer: StaticStartupRecoverer(),
            existingRepositoryMetadataReader: ShellExistingRepoMetadataReader(
                schemaVersion: 1,
                configuredRepoPath: "/tmp/some-other-repo"
            ),
            helpOpener: NoopWelcomeHelpOpener(),
            directoryPicker: picker
        )
        model.route = OnboardingModel.Route.mainRepoError(
            "/tmp/repo",
            CoreErrorMappingSnapshot.mainRepoFixture(kind: .invalidPath, rawContext: "/tmp/repo")
        )

        await model.reconnectMainRepositoryFolder(from: "/tmp/repo")
        let expectedMapping = CoreErrorMappingSnapshot.invalidPath(rawContext: selectedPath)

        await opener.assertNoConfiguredRepoPaths()
        XCTAssertEqual(model.mainRepoRecoveryErrorMapping, expectedMapping)
        XCTAssertEqual(
            model.route,
            OnboardingModel.Route.mainRepoError("/tmp/repo", model.mainRepoRecoveryErrorMapping)
        )
        XCTAssertFalse(model.isRetryingMainRepository)
    }

    @MainActor
    func testMainRepoErrorReconnectFolderRejectsInitializedRepoWithoutConfiguredPath() async {
        let selectedPath = "/tmp/repo-without-configured-path"
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
            startupRecoverer: StaticStartupRecoverer(),
            existingRepositoryMetadataReader: ShellExistingRepoMetadataReader(schemaVersion: 1),
            helpOpener: NoopWelcomeHelpOpener(),
            directoryPicker: picker
        )
        model.route = OnboardingModel.Route.mainRepoError(
            "/tmp/repo",
            CoreErrorMappingSnapshot.mainRepoFixture(kind: .invalidPath, rawContext: "/tmp/repo")
        )

        await model.reconnectMainRepositoryFolder(from: "/tmp/repo")

        await opener.assertNoConfiguredRepoPaths()
        XCTAssertEqual(model.mainRepoRecoveryErrorMapping, .invalidPath(rawContext: selectedPath))
        XCTAssertEqual(
            model.route,
            OnboardingModel.Route.mainRepoError("/tmp/repo", model.mainRepoRecoveryErrorMapping)
        )
        XCTAssertFalse(model.isRetryingMainRepository)
    }
}

private extension CoreErrorMappingSnapshot {
    static func mainRepoFixture(
        kind: CoreErrorKindSnapshot,
        severity: CoreErrorSeveritySnapshot = .high,
        recoverability: CoreErrorRecoverabilitySnapshot = .userActionRequired,
        rawContext: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: kind,
            userMessage: "mapped \(kind.rawValue)",
            severity: severity,
            suggestedAction: "mapped action",
            recoverability: recoverability,
            rawContext: rawContext
        )
    }
}
