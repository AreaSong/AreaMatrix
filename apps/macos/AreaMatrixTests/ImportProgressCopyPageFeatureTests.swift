import XCTest
@testable import AreaMatrix

final class ImportProgressCopyPageFeatureTests: XCTestCase {
    @MainActor
    func testS120C106ProgressRouteShowsCopyRowStatesAndStopSemantics() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.updateImportEntryProgress(Self.runningProgress)

        guard case .importProgress(let state) = model.route else {
            return XCTFail("Expected S1-20 import progress route")
        }

        XCTAssertEqual(state.toolbarText, "Importing 1 / 3")
        XCTAssertEqual(state.items.map(\.phase), [.done, .copying, .pending])
    }

    @MainActor
    func testS120C106FailedCopyProgressKeepsFailedRowAndMappedError() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )
        let mapping = CoreErrorMappingSnapshot.s117Error(kind: .permissionDenied)

        model.route = .mainList(opening)
        model.updateImportEntryProgress(Self.failedProgress)
        model.failImportEntry(progress: Self.failedProgress, mapping: mapping)

        guard case .importProgress(let state) = model.route else {
            return XCTFail("Expected S1-20 failed import progress route")
        }

        XCTAssertEqual(state.titleText, "导入已暂停")
        XCTAssertEqual(state.bannerText, "无访问权限")
        XCTAssertEqual(state.items.map(\.phase), [.done, .failed])
        XCTAssertEqual(state.items.last?.errorMessage, "无访问权限")
    }

    @MainActor
    func testS120C107SingleMoveProgressShowsMovingPhase() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.beginImportEntryProgress(currentPath: "docs/moved.pdf", storageMode: .move)

        guard case .importProgress(let state) = model.route else {
            return XCTFail("Expected S1-20 import progress route")
        }

        XCTAssertEqual(state.titleText, "正在导入 1 个文件")
        XCTAssertEqual(state.items, [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "docs/moved.pdf",
                targetPath: "docs/moved.pdf",
                phase: .moving,
                errorMessage: nil
            ),
        ])
    }

    @MainActor
    func testS120C107MoveFailureRequiresRecoveryCheckBeforeRetry() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let context = Self.moveRetryContext(sourcePath: "/tmp/source.pdf")
        let recoverer = MainLoadingRecordingStartupRecoverer(result: .success(RecoveryReportSnapshot(
            cleanedStagingFiles: 1,
            revertedStagingDbRows: 1,
            warnings: []
        )))
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            startupRecoverer: recoverer,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )
        let mapping = CoreErrorMappingSnapshot.s117Error(kind: .io)

        model.route = .mainList(opening)
        model.beginImportEntryProgress(
            currentPath: "docs/moved.pdf",
            sourcePath: context.sourcePath,
            storageMode: .move,
            overrideCategory: context.overrideCategory,
            overrideFilename: context.overrideFilename,
            duplicateStrategy: context.duplicateStrategy.coreStrategy
        )
        model.failImportEntry(
            progress: Self.moveFailedProgress,
            mapping: mapping
        )

        guard case .importProgress(let failedBeforeCheck) = model.route else {
            return XCTFail("Expected failed move import progress route")
        }
        XCTAssertFalse(failedBeforeCheck.canRetryCurrentItem)
        XCTAssertEqual(failedBeforeCheck.retryStatusText, "Checking recovery state...")

        await model.checkImportProgressRecoveryIfNeeded()
        let recovererPaths = await recoverer.requestedRepoPaths()

        guard case .importProgress(let checkedState) = model.route else {
            return XCTFail("Expected checked move import progress route")
        }
        XCTAssertEqual(recovererPaths, ["/tmp/repo"])
        XCTAssertTrue(checkedState.canRetryCurrentItem)
        XCTAssertEqual(checkedState.retryContext, context)
        XCTAssertEqual(
            checkedState.retryStatusText,
            "Recovery checked: cleaned 1, reverted 1."
        )
    }

    @MainActor
    func testS120C107RetryCurrentMoveItemUsesRealImporterAndReturnsToRepository() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let importer = S117RecordingImporter()
        let announcer = S117RecordingAccessibilityAnnouncer()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            importProgressImporter: importer,
            startupRecoverer: MainLoadingStaticStartupRecoverer(),
            accessibilityAnnouncer: announcer,
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.beginImportEntryProgress(
            currentPath: "docs/moved.pdf",
            sourcePath: "/tmp/source.pdf",
            storageMode: .move,
            overrideCategory: "docs",
            overrideFilename: "moved.pdf",
            duplicateStrategy: .ask
        )
        model.failImportEntry(
            progress: Self.moveFailedProgress,
            mapping: CoreErrorMappingSnapshot.s117Error(kind: .io),
            retryContext: Self.moveRetryContext(sourcePath: "/tmp/source.pdf"),
            recoveryCheck: .retryAllowed(nil)
        )

        await model.retryCurrentImportProgressItem()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [
            S117ImportRequest(
                mode: .move,
                overrideCategory: "docs",
                overrideFilename: "moved.pdf",
                duplicateStrategy: .ask
            ),
        ])
        XCTAssertEqual(model.route, .mainEmpty(opening))
        XCTAssertEqual(model.toastMessage, "已导入：moved.pdf")
        XCTAssertEqual(announcer.announcements, ["已导入：moved.pdf"])
    }

    @MainActor
    func testS120C108SingleIndexProgressShowsWritingIndexPhase() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.beginImportEntryProgress(currentPath: "docs/indexed.pdf", storageMode: .indexOnly)

        guard case .importProgress(let state) = model.route else {
            return XCTFail("Expected S1-20 import progress route")
        }

        XCTAssertEqual(state.titleText, "正在导入 1 个文件")
        XCTAssertEqual(state.items, [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "docs/indexed.pdf",
                targetPath: "docs/indexed.pdf",
                phase: .writingIndex,
                errorMessage: nil
            ),
        ])
    }

    @MainActor
    func testS120C108IndexFailureRequiresRecoveryCheckBeforeRetry() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let context = Self.indexRetryContext(sourcePath: "/tmp/external.pdf")
        let recoverer = MainLoadingRecordingStartupRecoverer(result: .success(RecoveryReportSnapshot(
            cleanedStagingFiles: 0,
            revertedStagingDbRows: 0,
            warnings: []
        )))
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            startupRecoverer: recoverer,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.beginImportEntryProgress(
            currentPath: "docs/indexed.pdf",
            sourcePath: context.sourcePath,
            storageMode: .indexOnly,
            overrideCategory: context.overrideCategory,
            overrideFilename: context.overrideFilename,
            duplicateStrategy: context.duplicateStrategy.coreStrategy
        )
        model.failImportEntry(
            progress: Self.indexFailedProgress,
            mapping: CoreErrorMappingSnapshot.s117Error(kind: .fileNotFound)
        )

        guard case .importProgress(let failedBeforeCheck) = model.route else {
            return XCTFail("Expected failed index import progress route")
        }
        XCTAssertFalse(failedBeforeCheck.canRetryCurrentItem)
        XCTAssertEqual(failedBeforeCheck.retryStatusText, "Checking recovery state...")

        await model.checkImportProgressRecoveryIfNeeded()
        let recovererPaths = await recoverer.requestedRepoPaths()

        guard case .importProgress(let checkedState) = model.route else {
            return XCTFail("Expected checked index import progress route")
        }
        XCTAssertEqual(recovererPaths, ["/tmp/repo"])
        XCTAssertTrue(checkedState.canRetryCurrentItem)
        XCTAssertEqual(checkedState.retryContext, context)
        XCTAssertEqual(
            checkedState.retryStatusText,
            "Recovery state checked. Current item can be retried."
        )
    }

    @MainActor
    func testS120C108RetryCurrentIndexItemUsesRealImporterAndReturnsToRepository() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let importer = S117RecordingImporter()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            importProgressImporter: importer,
            startupRecoverer: MainLoadingStaticStartupRecoverer(),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.beginImportEntryProgress(
            currentPath: "docs/indexed.pdf",
            sourcePath: "/tmp/external.pdf",
            storageMode: .indexOnly,
            overrideCategory: "docs",
            overrideFilename: "indexed.pdf",
            duplicateStrategy: .keepBoth
        )
        model.failImportEntry(
            progress: Self.indexFailedProgress,
            mapping: CoreErrorMappingSnapshot.s117Error(kind: .fileNotFound),
            retryContext: Self.indexRetryContext(sourcePath: "/tmp/external.pdf"),
            recoveryCheck: .retryAllowed(nil)
        )

        await model.retryCurrentImportProgressItem()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [
            S117ImportRequest(
                mode: .indexOnly,
                overrideCategory: "docs",
                overrideFilename: "indexed.pdf",
                duplicateStrategy: .keepBoth
            ),
        ])
        XCTAssertEqual(model.route, .mainEmpty(opening))
        XCTAssertEqual(model.toastMessage, "已导入：indexed.pdf")
    }

    @MainActor
    func testS120C107DiagnosticsAndStopActionsStayOnSafeUiPaths() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let snapshot = DiagnosticsSnapshotSnapshot(
            snapshotPath: ".areamatrix/diagnostics/import-fatal.zip",
            createdAt: 1_700_000_100,
            warnings: ["paths redacted"]
        )
        let diagnostics = ShellRecordingDiagnosticsCollector(result: .success(snapshot))
        let finder = ShellRecordingFinderOpener()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            diagnosticsCollector: diagnostics,
            finderOpener: finder,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.beginImportEntryProgress(
            currentPath: "docs/moved.pdf",
            sourcePath: "/tmp/source.pdf",
            storageMode: .move,
            overrideCategory: "docs",
            overrideFilename: "moved.pdf",
            duplicateStrategy: .ask
        )
        model.failImportEntry(
            progress: Self.moveFailedProgress,
            mapping: CoreErrorMappingSnapshot.s117Error(kind: .io),
            retryContext: Self.moveRetryContext(sourcePath: "/tmp/source.pdf"),
            recoveryCheck: .retryAllowed(nil)
        )
        model.requestImportProgressDiagnosticsPrivacyConfirmation()
        await model.collectImportProgressDiagnostics()
        model.openImportProgressRepositoryInFinder()
        model.stopImportProgressAndViewResults()
        let diagnosticPaths = await diagnostics.requestedRepoPaths()

        XCTAssertEqual(diagnosticPaths, ["/tmp/repo"])
        XCTAssertEqual(finder.openedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(model.route, .mainEmpty(opening))
        XCTAssertEqual(model.toastMessage, "Imported 0, failed 1, stopped 0, pending 0.")
    }
}

private extension ImportProgressCopyPageFeatureTests {
    static let runningProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 0,
        total: 3,
        remaining: 2,
        currentPath: "docs/contract.pdf",
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/invoice.pdf",
                targetPath: "finance/invoice.pdf",
                phase: .done,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/contract.pdf",
                targetPath: "docs/contract.pdf",
                phase: .copying,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/later.pdf",
                targetPath: "docs/later.pdf",
                phase: .pending,
                errorMessage: nil
            ),
        ]
    )

    static let failedProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 1,
        total: 2,
        remaining: 0,
        currentPath: "docs/contract.pdf",
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/invoice.pdf",
                targetPath: "finance/invoice.pdf",
                phase: .done,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/contract.pdf",
                targetPath: "docs/contract.pdf",
                phase: .failed,
                errorMessage: "无访问权限"
            ),
        ]
    )

    static let moveFailedProgress = ImportBatchProgressSnapshot(
        completed: 0,
        failed: 1,
        total: 1,
        remaining: 0,
        currentPath: "docs/moved.pdf",
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/source.pdf",
                targetPath: "docs/moved.pdf",
                phase: .failed,
                errorMessage: "文件读写失败"
            ),
        ]
    )

    static let indexFailedProgress = ImportBatchProgressSnapshot(
        completed: 0,
        failed: 1,
        total: 1,
        remaining: 0,
        currentPath: "docs/indexed.pdf",
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/external.pdf",
                targetPath: "docs/indexed.pdf",
                phase: .failed,
                errorMessage: "文件不存在"
            ),
        ]
    )

    static func moveRetryContext(sourcePath: String) -> ImportProgressRetryContext {
        ImportProgressRetryContext(
            repoPath: "/tmp/repo",
            sourcePath: sourcePath,
            storageMode: .move,
            overrideCategory: "docs",
            overrideFilename: "moved.pdf",
            duplicateStrategy: .ask
        )
    }

    static func indexRetryContext(sourcePath: String) -> ImportProgressRetryContext {
        ImportProgressRetryContext(
            repoPath: "/tmp/repo",
            sourcePath: sourcePath,
            storageMode: .indexOnly,
            overrideCategory: "docs",
            overrideFilename: "indexed.pdf",
            duplicateStrategy: .keepBoth
        )
    }
}
