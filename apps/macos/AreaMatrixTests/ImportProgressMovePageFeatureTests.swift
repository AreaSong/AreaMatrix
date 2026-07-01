@testable import AreaMatrix
import XCTest

final class ImportProgressMovePageFeatureTests: XCTestCase {
    @MainActor
    func testImportProgressImportMoveFileCoreSingleMoveProgressShowsMovingPhase() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importProgressRepoPath())
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.beginImportEntryProgress(currentPath: "docs/moved.pdf", storageMode: .move)

        guard case let .importProgress(state) = model.route else {
            return XCTFail("Expected import-progress import progress route")
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
    func testImportProgressImportMoveFileCoreMoveFailureRequiresRecoveryCheckBeforeRetry() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importProgressRepoPath())
        let context = ImportProgressTestFixtures.moveRetryContext(sourcePath: importProgressSourcePath())
        let recoverer = RecordingCoreStartupRecoverer(result: .success(RecoveryReportSnapshot(
            cleanedStagingFiles: 1,
            revertedStagingDbRows: 1,
            warnings: []
        )))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            startupRecoverer: recoverer,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
        let mapping = CoreErrorMappingSnapshot.importProgressFatalImportError(kind: .io)

        model.route = .mainList(opening)
        model.beginImportEntryProgress(
            currentPath: "docs/moved.pdf",
            retryContext: context
        )
        model.failImportEntry(
            progress: ImportProgressTestFixtures.moveFailedProgress,
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
        XCTAssertEqual(recovererPaths, [importProgressRepoPath()])
        XCTAssertTrue(checkedState.canRetryCurrentItem)
        XCTAssertEqual(checkedState.retryContext, context)
        XCTAssertEqual(
            checkedState.retryStatusText,
            "Recovery checked: cleaned 1, reverted 1."
        )
    }

    @MainActor
    func testImportProgressImportMoveFileCoreRetryCurrentMoveItemUsesRealImporterAndReturnsToRepository() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importProgressRepoPath())
        let importer = ImportSingleFileRecordingImporter()
        let announcer = RecordingAccessibilityAnnouncer()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importProgressImporter: importer,
            startupRecoverer: StaticStartupRecoverer(),
            accessibilityAnnouncer: announcer,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.beginImportEntryProgress(
            currentPath: "docs/moved.pdf",
            retryContext: ImportProgressTestFixtures.moveRetryContext(sourcePath: importProgressSourcePath())
        )
        model.failImportEntry(
            progress: ImportProgressTestFixtures.moveFailedProgress,
            mapping: CoreErrorMappingSnapshot.importProgressFatalImportError(kind: .io),
            retryContext: ImportProgressTestFixtures.moveRetryContext(sourcePath: importProgressSourcePath()),
            recoveryCheck: .retryAllowed(nil)
        )

        await model.retryCurrentImportProgressItem()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [
            ImportSingleFileImportRequest(
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
}
