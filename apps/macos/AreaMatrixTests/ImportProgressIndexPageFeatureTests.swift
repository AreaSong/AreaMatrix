@testable import AreaMatrix
import XCTest

final class ImportProgressIndexPageFeatureTests: XCTestCase {
    @MainActor
    func testImportProgressImportIndexFileCoreSingleIndexProgressShowsWritingIndexPhase() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importProgressRepoPath())
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.beginImportEntryProgress(currentPath: "docs/indexed.pdf", storageMode: .indexOnly)

        guard case let .importProgress(state) = model.route else {
            return XCTFail("Expected import-progress import progress route")
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
    func testImportProgressImportIndexFileCoreIndexFailureRequiresRecoveryCheckBeforeRetry() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importProgressRepoPath())
        let context = ImportProgressFixtures.indexRetryContext(sourcePath: importProgressIndexSourcePath())
        let recoverer = RecordingCoreStartupRecoverer(result: .success(RecoveryReportSnapshot(
            cleanedStagingFiles: 0,
            revertedStagingDbRows: 0,
            warnings: []
        )))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            startupRecoverer: recoverer,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.beginImportEntryProgress(
            currentPath: "docs/indexed.pdf",
            retryContext: context
        )
        model.failImportEntry(
            progress: ImportProgressFixtures.indexFailedProgress,
            mapping: CoreErrorMappingSnapshot.importProgressFatalImportError(kind: .fileNotFound)
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
        XCTAssertEqual(recovererPaths, [importProgressRepoPath()])
        XCTAssertTrue(checkedState.canRetryCurrentItem)
        XCTAssertEqual(checkedState.retryContext, context)
        XCTAssertEqual(
            checkedState.retryStatusText,
            "Recovery state checked. Current item can be retried."
        )
    }

    @MainActor
    func testImportProgressImportIndexFileCoreRetryCurrentIndexItemUsesRealImporterAndReturnsToRepository() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importProgressRepoPath())
        let importer = ImportSingleFileRecordingImporter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importProgressImporter: importer,
            startupRecoverer: StaticStartupRecoverer(),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.beginImportEntryProgress(
            currentPath: "docs/indexed.pdf",
            retryContext: ImportProgressFixtures.indexRetryContext(sourcePath: importProgressIndexSourcePath())
        )
        model.failImportEntry(
            progress: ImportProgressFixtures.indexFailedProgress,
            mapping: CoreErrorMappingSnapshot.importProgressFatalImportError(kind: .fileNotFound),
            retryContext: ImportProgressFixtures.indexRetryContext(sourcePath: importProgressIndexSourcePath()),
            recoveryCheck: .retryAllowed(nil)
        )

        await model.retryCurrentImportProgressItem()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [
            ImportSingleFileImportRequest(
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
