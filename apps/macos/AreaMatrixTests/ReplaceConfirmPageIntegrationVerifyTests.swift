import XCTest
@testable import AreaMatrix

final class ReplaceConfirmPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS124SingleFileReplaceConfirmCoversC109AndC110WithoutImmediateCoreImport() async throws {
        let importer = S117RecordingImporter()
        let duplicateModel = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: duplicateResult()),
            errorMapper: S117RecordingErrorMapper()
        )
        let nameModel = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: nameConflictResult()),
            errorMapper: S117RecordingErrorMapper()
        )

        await duplicateModel.load(request: .importSingleFileFixture())
        duplicateModel.updateDuplicateResolution(.replace)
        duplicateModel.beginReplaceConfirmation()
        let duplicateContext = try XCTUnwrap(duplicateModel.pendingReplaceConfirmation)

        await nameModel.load(request: .importSingleFileFixture())
        nameModel.updateNameConflictResolution(.replace)
        nameModel.beginReplaceConfirmation()
        let nameContext = try XCTUnwrap(nameModel.pendingReplaceConfirmation)
        let requestsBeforeConfirmation = await importer.recordedRequests()

        XCTAssertEqual(duplicateModel.activeConflictPage, .duplicate)
        XCTAssertEqual(duplicateContext.existingPath, "docs/existing-duplicate.pdf")
        XCTAssertEqual(duplicateContext.targetRelativePath, "docs/source.pdf")
        XCTAssertEqual(nameModel.activeConflictPage, .name)
        XCTAssertEqual(nameContext.existingPath, "docs/source.pdf")
        XCTAssertEqual(nameContext.targetRelativePath, "docs/source.pdf")
        XCTAssertEqual(requestsBeforeConfirmation, [])

        duplicateModel.applyReplaceConfirmation(duplicateContext.decision(understandsReplace: true))
        nameModel.applyReplaceConfirmation(nameContext.decision(understandsReplace: true))

        XCTAssertTrue(duplicateModel.isReplaceConfirmed)
        XCTAssertTrue(nameModel.isReplaceConfirmed)
        XCTAssertEqual(duplicateModel.singleFilePrimaryActionTitle, "Import")
        XCTAssertEqual(nameModel.singleFilePrimaryActionTitle, "Import")
    }

    @MainActor
    func testS124BatchReplaceContextFailureStaysRecoverableAndDoesNotOverwrite() async throws {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let row = ImportBatchPreviewRow.duplicate(
            url: invoiceURL,
            prediction: ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf",
                reason: .keyword,
                confidence: 0.9
            ),
            existingPath: "finance/Invoice_2026Q1.pdf"
        )
        let importer = S118RecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
        )

        model.applyPreviewRows(
            [row],
            request: batchRequest(urls: [invoiceURL]),
            selectedDestination: .autoClassify
        )
        model.updateDuplicateStrategy(for: row.id, strategy: .replace)
        let context = try XCTUnwrap(model.beginReplaceConfirmation(for: row.id))
        let staleContext = ImportSingleFileReplaceConfirmationContext(
            existingPath: "finance/stale.pdf",
            incomingPath: context.incomingPath,
            incomingSizeBytes: context.incomingSizeBytes,
            targetRelativePath: context.targetRelativePath,
            isTrashAvailable: true
        )

        let acceptedStale = model.applyReplaceConfirmation(
            for: row.id,
            decision: staleContext.decision(understandsReplace: true)
        )
        let blockedOutcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let requestsAfterFailure = await importer.recordedRequests()

        XCTAssertFalse(acceptedStale)
        XCTAssertNil(blockedOutcome)
        XCTAssertEqual(requestsAfterFailure, [])
        XCTAssertEqual(model.replaceConfirmationErrorMessage, "Replace confirmation context expired")
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")

        model.collectReplaceConfirmationDiagnostics()
        XCTAssertEqual(
            model.replaceConfirmationDiagnosticsMessage,
            "Diagnostics collected for replace confirmation state. No user file contents included."
        )
        model.retryReplaceConfirmation()
        XCTAssertNil(model.replaceConfirmationErrorMessage)
        XCTAssertNil(model.replaceConfirmationDiagnosticsMessage)

        XCTAssertTrue(model.applyReplaceConfirmation(
            for: row.id,
            decision: context.decision(understandsReplace: true)
        ))
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let requestsAfterSuccess = await importer.recordedRequests()

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(requestsAfterSuccess.map(\.duplicateStrategy), [.overwrite])
    }

    @MainActor
    func testS124FolderReplaceContextFailureStaysRecoverableAndDoesNotOverwrite() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/client-a")
        let sourceURL = rootURL.appendingPathComponent("name.pdf")
        let scanner = S119StaticFolderScanner(result: ImportFolderScanResult(
            rows: [ImportFolderPreviewRow.loading(fileURL: sourceURL, rootURL: rootURL)],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let prechecker = S119StaticConflictPrechecker(results: [
            sourceURL.path: .nameConflict(existingPath: "docs/name.pdf"),
        ])
        let importer = S118RecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: S119RecordingPredictor(results: [.success(.s119Prediction(suggestedName: "name.pdf"))]),
            importer: importer,
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: prechecker,
            scanner: scanner
        )

        await model.load(request: s119FolderRequest(
            rootURL: rootURL,
            allowReplaceDuringImport: true
        ))
        model.updateNameConflictResolution(for: sourceURL.path, resolution: .replace(isConfirmed: false))
        let context = try XCTUnwrap(model.beginReplaceConfirmation(for: sourceURL.path))
        let staleContext = ImportSingleFileReplaceConfirmationContext(
            existingPath: "docs/stale.pdf",
            incomingPath: context.incomingPath,
            incomingSizeBytes: context.incomingSizeBytes,
            targetRelativePath: context.targetRelativePath,
            isTrashAvailable: true
        )

        let acceptedStale = model.applyReplaceConfirmation(
            for: sourceURL.path,
            decision: staleContext.decision(understandsReplace: true)
        )
        let blockedOutcome = await model.importReadyFiles()
        let requestsAfterFailure = await importer.recordedRequests()

        XCTAssertFalse(acceptedStale)
        XCTAssertNil(blockedOutcome)
        XCTAssertEqual(requestsAfterFailure, [])
        XCTAssertEqual(model.replaceConfirmationErrorMessage, "Replace confirmation context expired")
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")

        model.collectReplaceConfirmationDiagnostics()
        XCTAssertEqual(
            model.replaceConfirmationDiagnosticsMessage,
            "Diagnostics collected for replace confirmation state. No user file contents included."
        )
        model.retryReplaceConfirmation()
        XCTAssertNil(model.replaceConfirmationErrorMessage)
        XCTAssertNil(model.replaceConfirmationDiagnosticsMessage)

        XCTAssertTrue(model.applyReplaceConfirmation(
            for: sourceURL.path,
            decision: context.decision(understandsReplace: true)
        ))
        let outcome = await model.importReadyFiles()
        let requestsAfterSuccess = await importer.recordedRequests()

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(requestsAfterSuccess.map(\.duplicateStrategy), [.overwrite])
    }
}

private func duplicateResult() -> ImportSingleFilePreflightResult {
    ImportSingleFilePreflightResult(
        sourceSizeBytes: 912 * 1_024,
        sourceModifiedAt: 1_777_445_400,
        hashSha256: "duplicate-hash",
        targetRelativePath: "docs/source.pdf",
        conflict: .duplicate(existingPath: "docs/existing-duplicate.pdf"),
        keepBothTargetRelativePath: "docs/source_1.pdf",
        existingFile: existingFile(path: "docs/existing-duplicate.pdf", hash: "duplicate-hash")
    )
}

private func nameConflictResult() -> ImportSingleFilePreflightResult {
    ImportSingleFilePreflightResult(
        sourceSizeBytes: 912 * 1_024,
        sourceModifiedAt: 1_777_445_400,
        hashSha256: "incoming-hash",
        targetRelativePath: "docs/source.pdf",
        conflict: .name(path: "docs/source.pdf"),
        keepBothTargetRelativePath: "docs/source_1.pdf",
        existingPaths: ["docs/source.pdf"],
        existingFile: existingFile(path: "docs/source.pdf", hash: "existing-hash")
    )
}

private func existingFile(path: String, hash: String) -> FileEntrySnapshot {
    FileEntrySnapshot(
        id: 124,
        path: path,
        originalName: (path as NSString).lastPathComponent,
        currentName: (path as NSString).lastPathComponent,
        category: (path as NSString).deletingLastPathComponent,
        sizeBytes: 860 * 1_024,
        hashSha256: hash,
        storageMode: "Copied",
        origin: "Imported",
        sourcePath: nil,
        importedAt: 1_700_000_000,
        updatedAt: 1_776_660_840
    )
}

private func batchRequest(urls: [URL]) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: "/tmp/repo",
        source: .dropZone,
        destination: .autoClassify,
        urls: urls,
        kind: .multipleItems(urls.count),
        availableCategories: ["inbox", "docs", "finance"],
        allowReplaceDuringImport: true,
        isTrashAvailable: true
    )
}
