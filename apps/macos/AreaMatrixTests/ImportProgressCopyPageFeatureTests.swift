@testable import AreaMatrix
import XCTest

final class ImportProgressCopyPageFeatureTests: XCTestCase {
    @MainActor
    func testImportProgressImportCopyFileCoreProgressRouteShowsCopyRowStatesAndStopSemantics() {
        let model = makeImportProgressMainListFixture().model

        model.updateImportEntryProgress(ImportProgressFixtures.runningCopyProgress)

        guard let state = requireImportProgressRoute(model) else { return }

        XCTAssertEqual(state.toolbarText, "Importing 1 / 3")
        XCTAssertEqual(state.items.map(\.phase), [.done, .copying, .pending])
    }

    @MainActor
    func testImportProgressImportCopyFileCoreOrdinaryFailedCopyProgressRoutesToResultSummary() {
        let model = makeImportProgressMainListFixture().model
        let mapping = CoreErrorMappingSnapshot.importSingleFileError(kind: .permissionDenied)

        model.updateImportEntryProgress(ImportProgressFixtures.failedCopyResultProgress)
        model.failImportEntry(progress: ImportProgressFixtures.failedCopyResultProgress, mapping: mapping)

        guard let result = requireImportResultRoute(model) else { return }

        assertImportResultSummary(
            result,
            summaryText: "Imported 1, failed 1, stopped 0, pending 0.",
            statuses: [.imported, .failed]
        )
        XCTAssertEqual(result.items.last?.reason, "无访问权限")
    }

    @MainActor
    func testImportProgressImportCopyFileCoreCopyFailureRequiresRecoveryCheckBeforeRetry() async {
        let context = ImportProgressFixtures.copyRetryContext(sourcePath: importProgressSourcePath())
        let recoverer = RecordingCoreStartupRecoverer(result: .success(.testFixture(
            cleanedStagingFiles: 1,
            revertedStagingDbRows: 0,
            warnings: []
        )))
        let model = makeImportProgressMainListFixture(
            startupRecoverer: recoverer
        ).model

        model.beginImportEntryProgress(
            currentPath: "docs/copied.pdf",
            retryContext: context
        )
        model.failImportEntry(
            progress: ImportProgressFixtures.copyFailedProgress,
            mapping: CoreErrorMappingSnapshot.importProgressFatalImportError(kind: .io)
        )

        await assertImportProgressRecoveryCheckAllowsRetry(
            model,
            recoverer: recoverer,
            retryContext: context,
            failedRouteMessage: "Expected failed copy import progress route",
            checkedRouteMessage: "Expected checked copy import progress route"
        )
    }
}
