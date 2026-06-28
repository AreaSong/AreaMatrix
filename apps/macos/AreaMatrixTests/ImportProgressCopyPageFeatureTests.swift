@testable import AreaMatrix
import XCTest

final class ImportProgressCopyPageFeatureTests: XCTestCase {
    @MainActor
    func testImportProgressImportCopyFileCoreProgressRouteShowsCopyRowStatesAndStopSemantics() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.updateImportEntryProgress(ImportProgressTestFixtures.runningCopyProgress)

        guard case let .importProgress(state) = model.route else {
            return XCTFail("Expected import-progress import progress route")
        }

        XCTAssertEqual(state.toolbarText, "Importing 1 / 3")
        XCTAssertEqual(state.items.map(\.phase), [.done, .copying, .pending])
    }

    @MainActor
    func testImportProgressImportCopyFileCoreOrdinaryFailedCopyProgressRoutesToResultSummary() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
        let mapping = CoreErrorMappingSnapshot.importSingleFileError(kind: .permissionDenied)

        model.route = .mainList(opening)
        model.updateImportEntryProgress(ImportProgressTestFixtures.failedCopyResultProgress)
        model.failImportEntry(progress: ImportProgressTestFixtures.failedCopyResultProgress, mapping: mapping)

        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }

        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 0, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .failed])
        XCTAssertEqual(result.items.last?.reason, "无访问权限")
    }

    @MainActor
    func testImportProgressImportCopyFileCoreCopyFailureRequiresRecoveryCheckBeforeRetry() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let context = ImportProgressTestFixtures.copyRetryContext(sourcePath: "/tmp/source.pdf")
        let recoverer = MainLoadingRecordingStartupRecoverer(result: .success(RecoveryReportSnapshot(
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
            progress: ImportProgressTestFixtures.copyFailedProgress,
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
        XCTAssertEqual(recovererPaths, ["/tmp/repo"])
        XCTAssertTrue(checkedState.canRetryCurrentItem)
        XCTAssertEqual(checkedState.retryContext, context)
    }
}
