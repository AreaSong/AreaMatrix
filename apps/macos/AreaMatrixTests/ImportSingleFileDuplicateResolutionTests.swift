@testable import AreaMatrix
import XCTest

final class ImportSingleFileDuplicateResolutionTests: XCTestCase {
    @MainActor
    func testDuplicateConflictDuplicateSkipDoesNotCallImporter() async {
        let result = duplicateResult()
        let importer = ImportSingleFileRecordingImporter()
        let model = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(result: .importSingleFileFixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: result),
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
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
        let model = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(result: .importSingleFileFixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: duplicateResult()),
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
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
        let model = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(result: .importSingleFileFixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: duplicateResult()),
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
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
        let model = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(result: .importSingleFileFixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: duplicateResult()),
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
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
        let existingFile = FileEntrySnapshot(
            id: 124,
            path: "docs/reports/报告.pdf",
            originalName: "报告.pdf",
            currentName: "报告.pdf",
            category: "docs",
            sizeBytes: 860 * 1024,
            hashSha256: "duplicate-hash",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_776_660_840
        )
        let importer = ImportSingleFileRecordingImporter()
        let model = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(result: .importSingleFileFixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: ImportSingleFilePreflightResult(
                sourceSizeBytes: 912 * 1024,
                sourceModifiedAt: 1_777_445_400,
                hashSha256: "duplicate-hash",
                targetRelativePath: "docs/reports/报告.pdf",
                conflict: .duplicate(existingPath: existingFile.path),
                keepBothTargetRelativePath: "docs/reports/报告_1.pdf",
                existingFile: existingFile
            )),
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
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
        XCTAssertEqual(context.incomingPath, "/tmp/source.pdf")
        XCTAssertEqual(context.incomingSizeBytes, 912 * 1024)
        XCTAssertEqual(context.incomingModifiedAt, 1_777_445_400)
        XCTAssertEqual(context.targetRelativePath, "docs/reports/报告.pdf")
        XCTAssertTrue(context.isTrashAvailable)
    }

    @MainActor
    func testDuplicateConflictReplaceDisabledWhenTrashUnavailableAndHiddenWhenSettingIsOff() async {
        let trashUnavailableModel = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(result: .importSingleFileFixture()),
            importer: ImportSingleFileRecordingImporter(),
            preflight: ImportSingleFileStaticPreflight(result: duplicateResult()),
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )
        await trashUnavailableModel.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: true,
            isTrashAvailable: false
        ))

        trashUnavailableModel.updateDuplicateResolution(.replace)
        XCTAssertEqual(trashUnavailableModel.replaceOptionVisibility, .disabled)
        XCTAssertEqual(trashUnavailableModel.primaryActionDisabledReason, "Replace requires system Trash")

        let hiddenModel = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(result: .importSingleFileFixture()),
            importer: ImportSingleFileRecordingImporter(),
            preflight: ImportSingleFileStaticPreflight(result: duplicateResult()),
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
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

private func duplicateResult() -> ImportSingleFilePreflightResult {
    ImportSingleFilePreflightResult(
        sourceSizeBytes: 12,
        hashSha256: "duplicate-hash",
        targetRelativePath: "docs/source.pdf",
        conflict: .duplicate(existingPath: "docs/existing.pdf"),
        keepBothTargetRelativePath: "docs/source_1.pdf"
    )
}
