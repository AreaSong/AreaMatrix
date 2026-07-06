@testable import AreaMatrix
import XCTest

final class ImportProgressCopyPageFeatureTests: XCTestCase {
    @MainActor
    func testImportProgressImportCopyFileCoreProgressRouteShowsCopyRowStatesAndStopSemantics() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importProgressRepoPath())
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.updateImportEntryProgress(ImportProgressFixtures.runningCopyProgress)

        guard case let .importProgress(state) = model.route else {
            return XCTFail("Expected import-progress import progress route")
        }

        XCTAssertEqual(state.toolbarText, "Importing 1 / 3")
        XCTAssertEqual(state.items.map(\.phase), [.done, .copying, .pending])
    }

    @MainActor
    func testImportProgressImportCopyFileCoreOrdinaryFailedCopyProgressRoutesToResultSummary() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importProgressRepoPath())
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
        let mapping = CoreErrorMappingSnapshot.importSingleFileError(kind: .permissionDenied)

        model.route = .mainList(opening)
        model.updateImportEntryProgress(ImportProgressFixtures.failedCopyResultProgress)
        model.failImportEntry(progress: ImportProgressFixtures.failedCopyResultProgress, mapping: mapping)

        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }

        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 0, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .failed])
        XCTAssertEqual(result.items.last?.reason, "无访问权限")
    }

    @MainActor
    func testImportProgressImportCopyFileCoreCopyFailureRequiresRecoveryCheckBeforeRetry() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importProgressRepoPath())
        let context = ImportProgressFixtures.copyRetryContext(sourcePath: importProgressSourcePath())
        let recoverer = RecordingCoreStartupRecoverer(result: .success(.testFixture(
            cleanedStagingFiles: 1,
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
            currentPath: "docs/copied.pdf",
            retryContext: context
        )
        model.failImportEntry(
            progress: ImportProgressFixtures.copyFailedProgress,
            mapping: CoreErrorMappingSnapshot.importProgressFatalImportError(kind: .io)
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
        XCTAssertEqual(recovererPaths, [importProgressRepoPath()])
        XCTAssertTrue(checkedState.canRetryCurrentItem)
        XCTAssertEqual(checkedState.retryContext, context)
    }
}
