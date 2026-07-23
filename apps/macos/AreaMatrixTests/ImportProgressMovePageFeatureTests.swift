@testable import AreaMatrix
import XCTest

final class ImportProgressMovePageFeatureTests: XCTestCase {
    @MainActor
    func testImportProgressImportMoveFileCoreSingleMoveProgressShowsMovingPhase() {
        let model = makeImportProgressMainListFixture().model

        model.beginImportEntryProgress(currentPath: "docs/moved.pdf", storageMode: .move)

        guard let state = requireImportProgressRoute(model) else { return }

        assertSingleImportProgressItem(
            state,
            sourcePath: "docs/moved.pdf",
            targetPath: "docs/moved.pdf",
            phase: .moving
        )
    }

    @MainActor
    func testImportProgressImportMoveFileCoreMoveFailureRequiresRecoveryCheckBeforeRetry() async {
        let context = ImportProgressFixtures.moveRetryContext(sourcePath: importProgressSourcePath())
        let recoverer = RecordingCoreStartupRecoverer(result: .success(.testFixture(
            cleanedStagingFiles: 1,
            revertedStagingDbRows: 1,
            warnings: []
        )))
        let model = makeImportProgressMainListFixture(
            startupRecoverer: recoverer
        ).model
        let mapping = CoreErrorMappingSnapshot.importProgressFatalImportError(kind: .io)

        model.beginImportEntryProgress(
            currentPath: "docs/moved.pdf",
            retryContext: context
        )
        model.failImportEntry(
            progress: ImportProgressFixtures.moveFailedProgress,
            mapping: mapping
        )

        await assertImportProgressRecoveryCheckAllowsRetry(
            model,
            recoverer: recoverer,
            retryContext: context,
            failedRouteMessage: "Expected failed move import progress route",
            checkedRouteMessage: "Expected checked move import progress route",
            checkedStatusText: "Recovery checked: cleaned 1, reverted 1."
        )
    }

    @MainActor
    func testImportProgressImportMoveFileCoreRetryCurrentMoveItemUsesRealImporterAndReturnsToRepository() async {
        let importer = ImportSingleFileRecordingImporter()
        let announcer = RecordingAccessibilityAnnouncer()
        let fixture = makeImportProgressMainListFixture(
            importProgressImporter: importer,
            startupRecoverer: StaticStartupRecoverer(),
            accessibilityAnnouncer: announcer
        )
        let opening = fixture.opening
        let model = fixture.model

        model.beginImportEntryProgress(
            currentPath: "docs/moved.pdf",
            retryContext: ImportProgressFixtures.moveRetryContext(sourcePath: importProgressSourcePath())
        )
        model.failImportEntry(
            progress: ImportProgressFixtures.moveFailedProgress,
            mapping: CoreErrorMappingSnapshot.importProgressFatalImportError(kind: .io),
            retryContext: ImportProgressFixtures.moveRetryContext(sourcePath: importProgressSourcePath()),
            recoveryCheck: .retryAllowed(nil)
        )

        await model.retryCurrentImportProgressItem()

        await importer.assertImportedFiles([
            ImportSingleFileImportRequest(
                mode: .move,
                overrideCategory: "docs",
                overrideFilename: "moved.pdf",
                duplicateStrategy: .ask
            )
        ])
        XCTAssertEqual(model.route, .mainEmpty(opening))
        XCTAssertEqual(
            model.toastMessage,
            L10n.message("import.single.imported-file", arguments: [.string("moved.pdf")])
        )
        announcer.assertAnnouncements(["Imported: moved.pdf"])
    }
}
