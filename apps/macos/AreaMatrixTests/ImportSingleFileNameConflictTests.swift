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

        XCTAssertEqual(model.activeConflictPage, .name)
        XCTAssertEqual(model.nameConflictResolution, .keepBoth)
        XCTAssertEqual(model.progressCurrentPath, "docs/source_1.pdf")
        XCTAssertEqual(imported?.storageMode, "Copied")
        await importer.assertLastImportedFile(ImportSingleFileImportRequest(
            mode: .copy,
            overrideCategory: "docs",
            overrideFilename: "source.pdf",
            duplicateStrategy: .keepBoth
        ))
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
        XCTAssertEqual(model.importDisabledReason, "The new filename still conflicts")

        model.renameIncomingNameConflictFile(to: "renamed.pdf")
        let imported = await model.importSelectedFile()

        XCTAssertEqual(model.nameConflictResolution, .renameIncoming("renamed.pdf"))
        XCTAssertEqual(model.progressCurrentPath, "docs/renamed.pdf")
        XCTAssertEqual(imported?.currentName, "renamed.pdf")
        await importer.assertLastImportedFile(ImportSingleFileImportRequest(
            mode: .copy,
            overrideCategory: "docs",
            overrideFilename: "renamed.pdf",
            duplicateStrategy: .keepBoth
        ))
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
        await importer.assertLastImportedFile(ImportSingleFileImportRequest(
            mode: .copy,
            overrideCategory: "docs",
            overrideFilename: "source.pdf",
            duplicateStrategy: .overwrite
        ))
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

        XCTAssertEqual(model.activeConflictPage, .name)
        await importer.assertNoImportedFiles()
        XCTAssertEqual(context.existingPath, existingFile.path)
        XCTAssertEqual(context.existingSizeBytes, existingFile.sizeBytes)
        XCTAssertEqual(context.incomingPath, importSingleFileSourcePath())
        XCTAssertEqual(context.incomingSizeBytes, 912 * 1024)
        XCTAssertEqual(context.targetRelativePath, existingFile.path)

        model.applyReplaceConfirmation(context.decision(understandsReplace: true))

        XCTAssertTrue(model.isReplaceConfirmed)
        XCTAssertNil(model.pendingReplaceConfirmation)
        XCTAssertEqual(model.replaceConfirmationActionTitle, "Replace Confirmed")
        XCTAssertEqual(model.singleFilePrimaryActionTitle, "Import")

        _ = await model.importSelectedFile()
        await importer.assertImportedFiles([
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

        await importer.assertNoImportedFiles()
        XCTAssertEqual(confirmation?.context.existingPath, existingFile.path)
        XCTAssertEqual(confirmation?.context.targetRelativePath, existingFile.path)
        XCTAssertFalse(model.isReplaceConfirmed)
        XCTAssertEqual(model.singleFilePrimaryActionTitle, "Continue")

        let context = try XCTUnwrap(confirmation?.context)
        model.applyReplaceConfirmation(context.decision(understandsReplace: true))

        XCTAssertNil(ImportEntrySingleFilePrimaryActionGate.pendingReplaceConfirmation(for: model))
        _ = await model.importSelectedFile()
        await importer.assertLastImportedFile(ImportSingleFileImportRequest(
            mode: .copy,
            overrideCategory: "docs",
            overrideFilename: "source.pdf",
            duplicateStrategy: .overwrite
        ))
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

        XCTAssertNil(imported)
        await importer.assertNoImportedFiles()
        XCTAssertEqual(model.importStatus, .blocked("Confirm Replace before continuing"))
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
