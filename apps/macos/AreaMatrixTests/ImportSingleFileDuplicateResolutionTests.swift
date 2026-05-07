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

        _ = await model.importSelectedFile()
        let requests = await importer.recordedRequests()
        XCTAssertEqual(requests.last?.duplicateStrategy, .overwrite)
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
}
