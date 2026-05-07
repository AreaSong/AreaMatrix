import XCTest
@testable import AreaMatrix

final class ImportSingleFileDuplicateResolutionTests: XCTestCase {
    @MainActor
    func testS122DuplicateSkipDoesNotCallImporter() async {
        let result = duplicateResult()
        let importer = S117RecordingImporter()
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: result),
            errorMapper: S117RecordingErrorMapper()
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
    func testS122KeepBothUsesCoreKeepBothStrategyAndPreviewPath() async {
        let importer = S117RecordingImporter()
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: duplicateResult()),
            errorMapper: S117RecordingErrorMapper()
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
    func testS122DuplicateResolutionCasesStayWithinPageFeatureScope() {
        XCTAssertEqual(ImportSingleFileDuplicateResolutionStrategy.allCases, [.skip, .keepBoth, .replace])
    }

    @MainActor
    func testS122ReplaceRequiresSecondConfirmationBeforeCoreOverwrite() async throws {
        let importer = S117RecordingImporter()
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: duplicateResult()),
            errorMapper: S117RecordingErrorMapper()
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
    func testS124DuplicateReplaceConfirmationFailureKeepsSheetRecoverable() async throws {
        let importer = S117RecordingImporter()
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: duplicateResult()),
            errorMapper: S117RecordingErrorMapper()
        )

        await model.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: true,
            isTrashAvailable: true
        ))
        model.updateDuplicateResolution(.replace)
        model.beginReplaceConfirmation()
        let currentContext = try XCTUnwrap(model.pendingReplaceConfirmation)
        let staleContext = ImportSingleFileReplaceConfirmationContext(
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
    func testS124DuplicateReplaceConfirmationCarriesCoreDuplicateSummaryWithoutImportSideEffect() async throws {
        let existingFile = FileEntrySnapshot(
            id: 124,
            path: "docs/reports/报告.pdf",
            originalName: "报告.pdf",
            currentName: "报告.pdf",
            category: "docs",
            sizeBytes: 860 * 1_024,
            hashSha256: "duplicate-hash",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_776_660_840
        )
        let importer = S117RecordingImporter()
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: ImportSingleFilePreflightResult(
                sourceSizeBytes: 912 * 1_024,
                sourceModifiedAt: 1_777_445_400,
                hashSha256: "duplicate-hash",
                targetRelativePath: "docs/reports/报告.pdf",
                conflict: .duplicate(existingPath: existingFile.path),
                keepBothTargetRelativePath: "docs/reports/报告_1.pdf",
                existingFile: existingFile
            )),
            errorMapper: S117RecordingErrorMapper()
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
        XCTAssertEqual(context.incomingSizeBytes, 912 * 1_024)
        XCTAssertEqual(context.incomingModifiedAt, 1_777_445_400)
        XCTAssertEqual(context.targetRelativePath, "docs/reports/报告.pdf")
        XCTAssertTrue(context.isTrashAvailable)
    }

    @MainActor
    func testS122ReplaceDisabledWhenTrashUnavailableAndHiddenWhenSettingIsOff() async {
        let trashUnavailableModel = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: S117RecordingImporter(),
            preflight: ImportSingleFileStaticPreflight(result: duplicateResult()),
            errorMapper: S117RecordingErrorMapper()
        )
        await trashUnavailableModel.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: true,
            isTrashAvailable: false
        ))

        trashUnavailableModel.updateDuplicateResolution(.replace)
        XCTAssertEqual(trashUnavailableModel.replaceOptionVisibility, .disabled)
        XCTAssertEqual(trashUnavailableModel.primaryActionDisabledReason, "Replace requires system Trash")

        let hiddenModel = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: S117RecordingImporter(),
            preflight: ImportSingleFileStaticPreflight(result: duplicateResult()),
            errorMapper: S117RecordingErrorMapper()
        )
        await hiddenModel.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: false,
            isTrashAvailable: true
        ))

        hiddenModel.updateDuplicateResolution(.replace)
        XCTAssertEqual(hiddenModel.replaceOptionVisibility, .hidden)
        XCTAssertEqual(hiddenModel.duplicateResolution, .skip)
    }

    @MainActor
    func testS123NameConflictDefaultsToKeepBothAndUsesCoreKeepBothStrategy() async {
        let importer = S117RecordingImporter()
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: nameConflictResult()),
            errorMapper: S117RecordingErrorMapper()
        )

        await model.load(request: .importSingleFileFixture())
        let imported = await model.importSelectedFile()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(model.activeConflictPage, .name)
        XCTAssertEqual(model.nameConflictResolution, .keepBoth)
        XCTAssertEqual(model.progressCurrentPath, "docs/source_1.pdf")
        XCTAssertEqual(imported?.storageMode, "Copied")
        XCTAssertEqual(requests.last?.overrideFilename, "source.pdf")
        XCTAssertEqual(requests.last?.duplicateStrategy, .keepBoth)
    }

    @MainActor
    func testS123RenameIncomingValidatesConflictsAndUsesEditedName() async {
        let importer = S117RecordingImporter()
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: nameConflictResult()),
            errorMapper: S117RecordingErrorMapper()
        )

        await model.load(request: .importSingleFileFixture())
        model.updateNameConflictResolution(.renameIncoming("source.pdf"))
        XCTAssertEqual(model.importDisabledReason, "新文件名仍然冲突")

        model.renameIncomingNameConflictFile(to: "renamed.pdf")
        let imported = await model.importSelectedFile()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(model.nameConflictResolution, .renameIncoming("renamed.pdf"))
        XCTAssertEqual(model.progressCurrentPath, "docs/renamed.pdf")
        XCTAssertEqual(imported?.currentName, "renamed.pdf")
        XCTAssertEqual(requests.last?.overrideFilename, "renamed.pdf")
        XCTAssertEqual(requests.last?.duplicateStrategy, .keepBoth)
    }

    @MainActor
    func testS123ReplaceRequiresS124ConfirmationBeforeCoreOverwrite() async throws {
        let importer = S117RecordingImporter()
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: nameConflictResult()),
            errorMapper: S117RecordingErrorMapper()
        )

        await model.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: true,
            isTrashAvailable: true
        ))
        model.updateNameConflictResolution(.replace)

        XCTAssertEqual(model.singleFilePrimaryActionTitle, "Continue")
        XCTAssertNil(model.primaryActionDisabledReason)

        model.beginReplaceConfirmation()
        let context = try XCTUnwrap(model.pendingReplaceConfirmation)
        model.applyReplaceConfirmation(context.decision(understandsReplace: true))

        XCTAssertTrue(model.isReplaceConfirmed)
        XCTAssertEqual(model.singleFilePrimaryActionTitle, "Import")

        _ = await model.importSelectedFile()
        let requests = await importer.recordedRequests()
        XCTAssertEqual(requests.last?.overrideFilename, "source.pdf")
        XCTAssertEqual(requests.last?.duplicateStrategy, .overwrite)
    }

    @MainActor
    func testS124NameConflictReplaceConfirmationMarksC110ReplaceWithoutImportSideEffect() async throws {
        let existingFile = nameConflictReplaceExistingFile()
        let importer = S117RecordingImporter()
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: nameConflictReplaceResult(existingFile: existingFile)),
            errorMapper: S117RecordingErrorMapper()
        )

        await model.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: true,
            isTrashAvailable: true
        ))
        model.updateNameConflictResolution(.replace)
        model.beginReplaceConfirmation()
        let context = try XCTUnwrap(model.pendingReplaceConfirmation)
        let requestsBeforeConfirmation = await importer.recordedRequests()

        XCTAssertEqual(model.activeConflictPage, .name)
        XCTAssertEqual(requestsBeforeConfirmation, [])
        XCTAssertEqual(context.existingPath, existingFile.path)
        XCTAssertEqual(context.existingSizeBytes, existingFile.sizeBytes)
        XCTAssertEqual(context.incomingPath, "/tmp/source.pdf")
        XCTAssertEqual(context.incomingSizeBytes, 912 * 1_024)
        XCTAssertEqual(context.targetRelativePath, existingFile.path)

        model.applyReplaceConfirmation(context.decision(understandsReplace: true))

        XCTAssertTrue(model.isReplaceConfirmed)
        XCTAssertNil(model.pendingReplaceConfirmation)
        XCTAssertEqual(model.replaceConfirmationActionTitle, "Replace confirmed")
        XCTAssertEqual(model.singleFilePrimaryActionTitle, "Import")

        _ = await model.importSelectedFile()
        let requests = await importer.recordedRequests()
        XCTAssertEqual(requests, [
            S117ImportRequest(
                mode: .copy,
                overrideCategory: "docs",
                overrideFilename: "source.pdf",
                duplicateStrategy: .overwrite
            ),
        ])
    }

    @MainActor
    func testS124NameConflictReplacePrimaryActionOpensConfirmationBeforeCoreOverwrite() async throws {
        let existingFile = nameConflictReplaceExistingFile()
        let importer = S117RecordingImporter()
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: nameConflictReplaceResult(existingFile: existingFile)),
            errorMapper: S117RecordingErrorMapper()
        )

        await model.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: true,
            isTrashAvailable: true
        ))
        model.updateNameConflictResolution(.replace)

        let confirmation = ImportEntrySingleFilePrimaryActionGate.pendingReplaceConfirmation(for: model)
        let requestsBeforeConfirmation = await importer.recordedRequests()

        XCTAssertEqual(requestsBeforeConfirmation, [])
        XCTAssertEqual(confirmation?.context.existingPath, existingFile.path)
        XCTAssertEqual(confirmation?.context.targetRelativePath, existingFile.path)
        XCTAssertFalse(model.isReplaceConfirmed)
        XCTAssertEqual(model.singleFilePrimaryActionTitle, "Continue")

        let context = try XCTUnwrap(confirmation?.context)
        model.applyReplaceConfirmation(context.decision(understandsReplace: true))

        XCTAssertNil(ImportEntrySingleFilePrimaryActionGate.pendingReplaceConfirmation(for: model))
        _ = await model.importSelectedFile()
        let requestsAfterConfirmation = await importer.recordedRequests()

        XCTAssertEqual(requestsAfterConfirmation.last?.duplicateStrategy, .overwrite)
        XCTAssertEqual(requestsAfterConfirmation.last?.overrideFilename, "source.pdf")
    }

    @MainActor
    func testS124NameConflictReplaceCannotBypassConfirmationThroughModelImport() async {
        let importer = S117RecordingImporter()
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: nameConflictReplaceResult(
                existingFile: nameConflictReplaceExistingFile()
            )),
            errorMapper: S117RecordingErrorMapper()
        )

        await model.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: true,
            isTrashAvailable: true
        ))
        model.updateNameConflictResolution(.replace)

        let imported = await model.importSelectedFile()
        let requests = await importer.recordedRequests()

        XCTAssertNil(imported)
        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.importStatus, .blocked("Replace 必须先进入二次确认"))
    }

    @MainActor
    func testS123ReplaceCannotBeSelectedWhenTrashUnavailableOrSettingHidden() async {
        let trashUnavailableModel = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: S117RecordingImporter(),
            preflight: ImportSingleFileStaticPreflight(result: nameConflictResult()),
            errorMapper: S117RecordingErrorMapper()
        )
        await trashUnavailableModel.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: true,
            isTrashAvailable: false
        ))

        trashUnavailableModel.updateNameConflictResolution(.replace)
        XCTAssertEqual(trashUnavailableModel.replaceOptionVisibility, .disabled)
        XCTAssertEqual(trashUnavailableModel.nameConflictResolution, .keepBoth)

        let hiddenModel = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: S117RecordingImporter(),
            preflight: ImportSingleFileStaticPreflight(result: nameConflictResult()),
            errorMapper: S117RecordingErrorMapper()
        )
        await hiddenModel.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: false,
            isTrashAvailable: true
        ))

        hiddenModel.updateNameConflictResolution(.replace)
        XCTAssertEqual(hiddenModel.replaceOptionVisibility, .hidden)
        XCTAssertEqual(hiddenModel.nameConflictResolution, .keepBoth)
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

    private func nameConflictResult() -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: 12,
            hashSha256: "incoming-hash",
            targetRelativePath: "docs/source.pdf",
            conflict: .name(path: "docs/source.pdf"),
            keepBothTargetRelativePath: "docs/source_1.pdf",
            existingPaths: ["docs/source.pdf", "docs/source_1.pdf"]
        )
    }

    private func nameConflictReplaceExistingFile() -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: 125,
            path: "docs/reports/报告.pdf",
            originalName: "报告.pdf",
            currentName: "报告.pdf",
            category: "docs",
            sizeBytes: 860 * 1_024,
            hashSha256: "existing-hash",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_776_660_840
        )
    }

    private func nameConflictReplaceResult(
        existingFile: FileEntrySnapshot
    ) -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: 912 * 1_024,
            sourceModifiedAt: 1_777_445_400,
            hashSha256: "incoming-hash",
            targetRelativePath: existingFile.path,
            conflict: .name(path: existingFile.path),
            keepBothTargetRelativePath: "docs/reports/报告_1.pdf",
            existingPaths: [existingFile.path],
            existingFile: existingFile
        )
    }
}
