@testable import AreaMatrix
import XCTest

final class ImportProgressIndexPageFeatureTests: XCTestCase {
    @MainActor
    func testImportProgressImportIndexFileCoreSingleIndexProgressShowsWritingIndexPhase() {
        let model = makeImportProgressMainListFixture().model

        model.beginImportEntryProgress(currentPath: "docs/indexed.pdf", storageMode: .indexOnly)

        guard let state = requireImportProgressRoute(model) else { return }

        assertSingleImportProgressItem(
            state,
            sourcePath: "docs/indexed.pdf",
            targetPath: "docs/indexed.pdf",
            phase: .writingIndex
        )
    }

    @MainActor
    func testImportProgressImportIndexFileCoreIndexFailureRequiresRecoveryCheckBeforeRetry() async {
        let context = ImportProgressFixtures.indexRetryContext(sourcePath: importProgressIndexSourcePath())
        let recoverer = RecordingCoreStartupRecoverer(result: .success(.testFixture()))
        let model = makeImportProgressMainListFixture(
            startupRecoverer: recoverer
        ).model

        model.beginImportEntryProgress(
            currentPath: "docs/indexed.pdf",
            retryContext: context
        )
        model.failImportEntry(
            progress: ImportProgressFixtures.indexFailedProgress,
            mapping: CoreErrorMappingSnapshot.importProgressFatalImportError(kind: .fileNotFound)
        )

        await assertImportProgressRecoveryCheckAllowsRetry(
            model,
            recoverer: recoverer,
            retryContext: context,
            failedRouteMessage: "Expected failed index import progress route",
            checkedRouteMessage: "Expected checked index import progress route",
            checkedStatusText: "Recovery state checked. Current item can be retried."
        )
    }

    @MainActor
    func testImportProgressImportIndexFileCoreRetryCurrentIndexItemUsesRealImporterAndReturnsToRepository() async {
        let importer = ImportSingleFileRecordingImporter()
        let fixture = makeImportProgressMainListFixture(
            importProgressImporter: importer,
            startupRecoverer: StaticStartupRecoverer()
        )
        let opening = fixture.opening
        let model = fixture.model

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

        await importer.assertImportedFiles([
            ImportSingleFileImportRequest(
                mode: .indexOnly,
                overrideCategory: "docs",
                overrideFilename: "indexed.pdf",
                duplicateStrategy: .keepBoth
            )
        ])
        XCTAssertEqual(model.route, .mainEmpty(opening))
        XCTAssertEqual(
            model.toastMessage,
            L10n.message("import.single.imported-file", arguments: [.string("indexed.pdf")])
        )
    }
}
