@testable import AreaMatrix
import XCTest

final class ImportSingleFileDuplicateResolutionTests: XCTestCase {
    @MainActor
    func testDuplicateConflictDuplicateSkipDoesNotCallImporter() async {
        let result = ImportSingleFilePreflightResult.importDuplicateFixture()
        let importer = ImportSingleFileRecordingImporter()
        let model = makeImportSingleFilePreviewModel(
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: result)
        )

        await model.load(request: .importSingleFileFixture())
        let skipped = await model.importSelectedFile()
        let requests = await importer.recordedRequests()

        XCTAssertNil(skipped)
        XCTAssertEqual(model.activeConflictPage, .duplicate)
        XCTAssertEqual(model.duplicateResolution, .skip)
        XCTAssertEqual(model.importStatus, .skippedDuplicate("docs/existing.pdf"))
        XCTAssertEqual(requests, [])
    }

    @MainActor
    func testDuplicateConflictKeepBothUsesCoreKeepBothStrategyAndPreviewPath() async {
        let importer = ImportSingleFileRecordingImporter()
        let model = makeImportSingleFilePreviewModel(
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: .importDuplicateFixture())
        )

        await model.load(request: .importSingleFileFixture())
        model.updateDuplicateResolution(.keepBoth)
        let imported = await model.importSelectedFile()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(imported?.storageMode, "Copied")
        XCTAssertEqual(model.progressCurrentPath, "docs/source_1.pdf")
        XCTAssertEqual(requests.last?.duplicateStrategy, .keepBoth)
    }

    @MainActor
    func testDuplicateConflictDuplicateResolutionCasesStayWithinPageFeatureScope() {
        XCTAssertEqual(SingleFileDuplicateResolutionStrategy.allCases, [.skip, .keepBoth, .replace])
    }

    @MainActor
    func testDuplicateConflictReplaceRequiresSecondConfirmationBeforeCoreOverwrite() async throws {
        let importer = ImportSingleFileRecordingImporter()
        let model = makeImportSingleFilePreviewModel(
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: .importDuplicateFixture())
        )

        await model.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: true,
            isTrashAvailable: true
        ))

        XCTAssertEqual(model.activeConflictPage, .duplicate)
        XCTAssertEqual(model.duplicateResolution, .skip)
        XCTAssertEqual(model.replaceOptionVisibility, .enabled)

        model.updateDuplicateResolution(.replace)
        XCTAssertEqual(model.singleFilePrimaryActionTitle, "Continue")
        XCTAssertNil(model.primaryActionDisabledReason)
        XCTAssertEqual(model.shouldStartImportProgress, true)

        model.beginReplaceConfirmation()
        let context = try XCTUnwrap(model.pendingReplaceConfirmation)
        model.applyReplaceConfirmation(context.decision(understandsReplace: true))

        XCTAssertTrue(model.isReplaceConfirmed)
        XCTAssertEqual(model.singleFilePrimaryActionTitle, "Import")
        XCTAssertEqual(model.duplicateReplaceConfirmationActionTitle, "Replace confirmed")

        _ = await model.importSelectedFile()
        let requests = await importer.recordedRequests()
        XCTAssertEqual(requests.last?.duplicateStrategy, .overwrite)
    }

    @MainActor
    func testReplaceConfirmDuplicateReplaceConfirmationFailureKeepsSheetRecoverable() async throws {
        let importer = ImportSingleFileRecordingImporter()
        let model = makeImportSingleFilePreviewModel(
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: .importDuplicateFixture())
        )

        await model.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: true,
            isTrashAvailable: true
        ))
        model.updateDuplicateResolution(.replace)
        model.beginReplaceConfirmation()
        let currentContext = try XCTUnwrap(model.pendingReplaceConfirmation)
        let staleContext = SingleFileReplaceConfirmationContext(
            existingPath: "docs/other.pdf",
            incomingPath: currentContext.incomingPath,
            incomingSizeBytes: currentContext.incomingSizeBytes,
            targetRelativePath: currentContext.targetRelativePath,
            isTrashAvailable: true
        )

        model.applyReplaceConfirmation(staleContext.decision(understandsReplace: true))

        XCTAssertFalse(model.isReplaceConfirmed)
        XCTAssertEqual(model.pendingReplaceConfirmation, currentContext)
        XCTAssertEqual(model.replaceConfirmationErrorMessage, "Replace confirmation context expired")
        XCTAssertEqual(model.duplicateReplaceConfirmationActionTitle, "Confirm Replace...")

        model.collectReplaceConfirmationDiagnostics()
        XCTAssertEqual(
            model.replaceConfirmationDiagnosticsMessage,
            "Diagnostics collected for replace confirmation state. No user file contents included."
        )

        model.retryReplaceConfirmation()
        XCTAssertNil(model.replaceConfirmationErrorMessage)
        XCTAssertNil(model.replaceConfirmationDiagnosticsMessage)

        model.applyReplaceConfirmation(currentContext.decision(understandsReplace: true))
        XCTAssertTrue(model.isReplaceConfirmed)
        XCTAssertNil(model.pendingReplaceConfirmation)
    }

    @MainActor
    func testReplaceConfirmDuplicateReplaceConfirmationCarriesCoreDuplicateSummaryWithoutImportSideEffect(
    ) async throws {
        let existingFile = FileEntrySnapshot.importDuplicateReplaceFixture()
        let importer = ImportSingleFileRecordingImporter()
        let model = makeImportSingleFilePreviewModel(
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: .importDuplicateReplaceFixture(
                existingFile: existingFile
            ))
        )

        await model.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: true,
            isTrashAvailable: true
        ))
        model.updateDuplicateResolution(.replace)
        model.beginReplaceConfirmation()
        let context = try XCTUnwrap(model.pendingReplaceConfirmation)
        let requestsBeforeConfirmation = await importer.recordedRequests()

        XCTAssertEqual(requestsBeforeConfirmation, [])
        XCTAssertEqual(context.existingPath, existingFile.path)
        XCTAssertEqual(context.existingSizeBytes, existingFile.sizeBytes)
        XCTAssertEqual(context.existingModifiedAt, existingFile.updatedAt)
        XCTAssertEqual(context.incomingPath, importSingleFileSourcePath())
        XCTAssertEqual(context.incomingSizeBytes, 912 * 1024)
        XCTAssertEqual(context.incomingModifiedAt, 1_777_445_400)
        XCTAssertEqual(context.targetRelativePath, "docs/reports/报告.pdf")
        XCTAssertTrue(context.isTrashAvailable)
    }

    @MainActor
    func testDuplicateConflictReplaceDisabledWhenTrashUnavailableAndHiddenWhenSettingIsOff() async {
        let trashUnavailableModel = makeImportSingleFilePreviewModel(
            importer: ImportSingleFileRecordingImporter(),
            preflight: ImportSingleFileStaticPreflight(result: .importDuplicateFixture())
        )
        await trashUnavailableModel.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: true,
            isTrashAvailable: false
        ))

        trashUnavailableModel.updateDuplicateResolution(.replace)
        XCTAssertEqual(trashUnavailableModel.replaceOptionVisibility, .disabled)
        XCTAssertEqual(trashUnavailableModel.primaryActionDisabledReason, "Replace requires system Trash")

        let hiddenModel = makeImportSingleFilePreviewModel(
            importer: ImportSingleFileRecordingImporter(),
            preflight: ImportSingleFileStaticPreflight(result: .importDuplicateFixture())
        )
        await hiddenModel.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: false,
            isTrashAvailable: true
        ))

        hiddenModel.updateDuplicateResolution(.replace)
        XCTAssertEqual(hiddenModel.replaceOptionVisibility, .hidden)
        XCTAssertEqual(hiddenModel.duplicateResolution, .skip)
    }
}
