@testable import AreaMatrix
import XCTest

final class ImportSingleFileNameConflictTests: XCTestCase {
    @MainActor
    func testNameConflictNameConflictDefaultsToKeepBothAndUsesCoreKeepBothStrategy() async {
        let importer = ImportSingleFileRecordingImporter()
        let model = makeImportSingleFilePreviewModel(
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: .importNameConflictFixture())
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
    func testNameConflictRenameIncomingValidatesConflictsAndUsesEditedName() async {
        let importer = ImportSingleFileRecordingImporter()
        let model = makeImportSingleFilePreviewModel(
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: .importNameConflictFixture())
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
    func testNameConflictReplaceRequiresReplaceConfirmConfirmationBeforeCoreOverwrite() async throws {
        let importer = ImportSingleFileRecordingImporter()
        let model = makeImportSingleFilePreviewModel(
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: .importNameConflictFixture())
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
    func testReplaceConfirmNameConflictReplaceConfirmationMarksResolveNameConflictCoreReplaceWithoutImportSideEffect(
    ) async throws {
        let existingFile = FileEntrySnapshot.importNameConflictReplaceFixture()
        let importer = ImportSingleFileRecordingImporter()
        let model = makeImportSingleFilePreviewModel(
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: .importNameConflictReplaceFixture(
                existingFile: existingFile
            ))
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
        XCTAssertEqual(context.incomingPath, importSingleFileSourcePath())
        XCTAssertEqual(context.incomingSizeBytes, 912 * 1024)
        XCTAssertEqual(context.targetRelativePath, existingFile.path)

        model.applyReplaceConfirmation(context.decision(understandsReplace: true))

        XCTAssertTrue(model.isReplaceConfirmed)
        XCTAssertNil(model.pendingReplaceConfirmation)
        XCTAssertEqual(model.replaceConfirmationActionTitle, "Replace confirmed")
        XCTAssertEqual(model.singleFilePrimaryActionTitle, "Import")

        _ = await model.importSelectedFile()
        let requests = await importer.recordedRequests()
        XCTAssertEqual(requests, [
            ImportSingleFileImportRequest(
                mode: .copy,
                overrideCategory: "docs",
                overrideFilename: "source.pdf",
                duplicateStrategy: .overwrite
            )
        ])
    }

    @MainActor
    func testReplaceConfirmNameConflictReplacePrimaryActionOpensConfirmationBeforeCoreOverwrite() async throws {
        let existingFile = FileEntrySnapshot.importNameConflictReplaceFixture()
        let importer = ImportSingleFileRecordingImporter()
        let model = makeImportSingleFilePreviewModel(
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: .importNameConflictReplaceFixture(
                existingFile: existingFile
            ))
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
    func testReplaceConfirmNameConflictReplaceCannotBypassConfirmationThroughModelImport() async {
        let importer = ImportSingleFileRecordingImporter()
        let model = makeImportSingleFilePreviewModel(
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: .importNameConflictReplaceFixture())
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
    func testNameConflictReplaceCannotBeSelectedWhenTrashUnavailableOrSettingHidden() async {
        let trashUnavailableModel = makeImportSingleFilePreviewModel(
            importer: ImportSingleFileRecordingImporter(),
            preflight: ImportSingleFileStaticPreflight(result: .importNameConflictFixture())
        )
        await trashUnavailableModel.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: true,
            isTrashAvailable: false
        ))

        trashUnavailableModel.updateNameConflictResolution(.replace)
        XCTAssertEqual(trashUnavailableModel.replaceOptionVisibility, .disabled)
        XCTAssertEqual(trashUnavailableModel.nameConflictResolution, .keepBoth)

        let hiddenModel = makeImportSingleFilePreviewModel(
            importer: ImportSingleFileRecordingImporter(),
            preflight: ImportSingleFileStaticPreflight(result: .importNameConflictFixture())
        )
        await hiddenModel.load(request: .importSingleFileFixture(
            allowReplaceDuringImport: false,
            isTrashAvailable: true
        ))

        hiddenModel.updateNameConflictResolution(.replace)
        XCTAssertEqual(hiddenModel.replaceOptionVisibility, .hidden)
        XCTAssertEqual(hiddenModel.nameConflictResolution, .keepBoth)
    }
}
