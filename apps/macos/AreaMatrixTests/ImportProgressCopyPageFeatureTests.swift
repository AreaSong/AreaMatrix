@testable import AreaMatrix
import XCTest

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

        guard case let .importProgress(state) = model.route else {
            return XCTFail("Expected S1-20 import progress route")
        }

        XCTAssertEqual(state.toolbarText, "Importing 1 / 3")
        XCTAssertEqual(state.items.map(\.phase), [.done, .copying, .pending])
    }

    @MainActor
    func testS120C106OrdinaryFailedCopyProgressRoutesToResultSummary() {
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

        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }

        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 0, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .failed])
        XCTAssertEqual(result.items.last?.reason, "无访问权限")
    }

    @MainActor
    func testS120C106CopyFailureRequiresRecoveryCheckBeforeRetry() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let context = Self.copyRetryContext(sourcePath: "/tmp/source.pdf")
        let recoverer = MainLoadingRecordingStartupRecoverer(result: .success(RecoveryReportSnapshot(
            cleanedStagingFiles: 1,
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
            currentPath: "docs/copied.pdf",
            retryContext: context
        )
        model.failImportEntry(
            progress: Self.copyFailedProgress,
            mapping: CoreErrorMappingSnapshot.s120FatalImportError(kind: .io)
        )

        guard case let .importProgress(failedBeforeCheck) = model.route else {
            return XCTFail("Expected failed copy import progress route")
        }
        XCTAssertFalse(failedBeforeCheck.canRetryCurrentItem)
        XCTAssertEqual(failedBeforeCheck.retryStatusText, "Checking recovery state...")

        await model.checkImportProgressRecoveryIfNeeded()
        let recovererPaths = await recoverer.requestedRepoPaths()

        guard case let .importProgress(checkedState) = model.route else {
            return XCTFail("Expected checked copy import progress route")
        }
        XCTAssertEqual(recovererPaths, ["/tmp/repo"])
        XCTAssertTrue(checkedState.canRetryCurrentItem)
        XCTAssertEqual(checkedState.retryContext, context)
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

        guard case let .importProgress(state) = model.route else {
            return XCTFail("Expected S1-20 import progress route")
        }

        XCTAssertEqual(state.titleText, "正在导入 1 个文件")
        XCTAssertEqual(state.items, [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "docs/moved.pdf",
                targetPath: "docs/moved.pdf",
                phase: .moving,
                errorMessage: nil
            )
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
        let mapping = CoreErrorMappingSnapshot.s120FatalImportError(kind: .io)

        model.route = .mainList(opening)
        model.beginImportEntryProgress(
            currentPath: "docs/moved.pdf",
            retryContext: context
        )
        model.failImportEntry(
            progress: Self.moveFailedProgress,
            mapping: mapping
        )

        guard case let .importProgress(failedBeforeCheck) = model.route else {
            return XCTFail("Expected failed move import progress route")
        }
        XCTAssertFalse(failedBeforeCheck.canRetryCurrentItem)
        XCTAssertEqual(failedBeforeCheck.retryStatusText, "Checking recovery state...")

        await model.checkImportProgressRecoveryIfNeeded()
        let recovererPaths = await recoverer.requestedRepoPaths()

        guard case let .importProgress(checkedState) = model.route else {
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
            retryContext: Self.moveRetryContext(sourcePath: "/tmp/source.pdf")
        )
        model.failImportEntry(
            progress: Self.moveFailedProgress,
            mapping: CoreErrorMappingSnapshot.s120FatalImportError(kind: .io),
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
            )
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

        guard case let .importProgress(state) = model.route else {
            return XCTFail("Expected S1-20 import progress route")
        }

        XCTAssertEqual(state.titleText, "正在导入 1 个文件")
        XCTAssertEqual(state.items, [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "docs/indexed.pdf",
                targetPath: "docs/indexed.pdf",
                phase: .writingIndex,
                errorMessage: nil
            )
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
            retryContext: context
        )
        model.failImportEntry(
            progress: Self.indexFailedProgress,
            mapping: CoreErrorMappingSnapshot.s120FatalImportError(kind: .fileNotFound)
        )

        guard case let .importProgress(failedBeforeCheck) = model.route else {
            return XCTFail("Expected failed index import progress route")
        }
        XCTAssertFalse(failedBeforeCheck.canRetryCurrentItem)
        XCTAssertEqual(failedBeforeCheck.retryStatusText, "Checking recovery state...")

        await model.checkImportProgressRecoveryIfNeeded()
        let recovererPaths = await recoverer.requestedRepoPaths()

        guard case let .importProgress(checkedState) = model.route else {
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
            retryContext: Self.indexRetryContext(sourcePath: "/tmp/external.pdf")
        )
        model.failImportEntry(
            progress: Self.indexFailedProgress,
            mapping: CoreErrorMappingSnapshot.s120FatalImportError(kind: .fileNotFound),
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
            )
        ])
        XCTAssertEqual(model.route, .mainEmpty(opening))
        XCTAssertEqual(model.toastMessage, "已导入：indexed.pdf")
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
            )
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
            )
        ]
    )

    static let copyFailedProgress = ImportBatchProgressSnapshot(
        completed: 0,
        failed: 1,
        total: 1,
        remaining: 0,
        currentPath: "docs/copied.pdf",
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/source.pdf",
                targetPath: "docs/copied.pdf",
                phase: .failed,
                errorMessage: "文件读写失败"
            )
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
            )
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
            )
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

    static func copyRetryContext(
        sourcePath: String,
        overrideFilename: String = "copied.pdf"
    ) -> ImportProgressRetryContext {
        ImportProgressRetryContext(
            repoPath: "/tmp/repo",
            sourcePath: sourcePath,
            storageMode: .copy,
            overrideCategory: "docs",
            overrideFilename: overrideFilename,
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

private extension CoreErrorMappingSnapshot {
    static func s120FatalImportError(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: importProgressFatalMessage(for: kind),
            severity: .critical,
            suggestedAction: "AreaMatrix 会先确认 staging 状态，再允许重试当前项。",
            recoverability: .fatal,
            rawContext: "S1-20 fatal import progress"
        )
    }

    static func importProgressFatalMessage(for kind: CoreErrorKindSnapshot) -> String {
        switch kind {
        case .io:
            "文件读写失败"
        case .fileNotFound:
            "文件不存在"
        default:
            "导入队列无法继续"
        }
    }
}
