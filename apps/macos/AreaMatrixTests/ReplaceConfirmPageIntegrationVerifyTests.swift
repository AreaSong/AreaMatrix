@testable import AreaMatrix
import XCTest

final class ReplaceConfirmPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS4X09SyncConflictReplaceConfirmConnectsPreviewConfirmationApplyAndExit() async throws {
        let detector = S4X01RecordingSyncConflictDetector(result: .success([.s4x01Fixture()]))
        let resolver = S4X01RecordingSyncConflictResolver(
            previewResults: [
                .keepBoth: .success(.s4x01PreviewFixture()),
                .useIncoming: .success(.s4x01PreviewFixture(
                    resolution: .useIncoming,
                    canApply: false,
                    requiresReplaceConfirmation: true,
                    blockedReason: "Replace confirmation required",
                    previewToken: "preview-token-use-incoming"
                ))
            ],
            resolveResult: .success(.s4x01ResolveFixture(resolution: .useIncoming))
        )
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/s4x01-repo",
            conflictDetector: detector,
            conflictResolver: resolver,
            errorMapper: S4X01RecordingErrorMapper(mapping: .s4x01Mapping())
        )
        var resolvedReports: [SyncConflictResolveReportSnapshot] = []
        let view = SyncConflictReviewView(
            model: model,
            onBackToNeedsReview: {},
            onClose: {},
            onResolved: { resolvedReports.append($0) }
        )

        await model.load()
        await model.selectResolution(.useIncoming)
        await model.applyResolution()
        let unresolvedRequests = await resolver.recordedResolveRequests()
        let preview = try XCTUnwrap(model.previewState.preview)
        let panelBody = s4x01MirrorDescription(of: SyncConflictReplaceConfirmationPanel(
            preview: preview,
            confirmation: model.replaceConfirmation,
            disabledReason: model.replaceConfirmationDisabledReason,
            onConfirm: { _ in }
        ).body)

        XCTAssertEqual(unresolvedRequests, [])
        XCTAssertFalse(model.canApplyResolution)
        XCTAssertTrue(model.canConfirmReplacePlan)
        XCTAssertTrue(panelBody.contains("Confirm Replace"))
        XCTAssertTrue(panelBody.contains("Old file path"))
        XCTAssertTrue(panelBody.contains("Old version will be kept at"))
        XCTAssertTrue(panelBody.contains("Affected record"))
        XCTAssertTrue(panelBody.contains("Change log"))
        XCTAssertTrue(panelBody.contains("Recovery note"))

        model.confirmReplacePlan(understandsReplace: true)
        await view.applySelectedResolution()
        let detectRequests = await detector.recordedRequests()
        let previewRequests = await resolver.recordedPreviewRequests()
        let resolveRequests = await resolver.recordedResolveRequests()

        XCTAssertEqual(detectRequests, ["/tmp/s4x01-repo"])
        XCTAssertEqual(previewRequests.map(\.resolution), [.keepBoth, .useIncoming])
        XCTAssertEqual(resolveRequests, [.s4x01UseIncomingConfirmedRequest])
        XCTAssertEqual(resolvedReports, [.s4x01ResolveFixture(resolution: .useIncoming)])
        XCTAssertEqual(model.applyDisabledReason, "Resolution has already been applied.")
    }

    @MainActor
    func testS4X09CoreSafetyBackupAllowsReplaceWhenTrashUnavailable() async throws {
        let resolver = S4X01RecordingSyncConflictResolver(previewResults: [
            .keepBoth: .success(.s4x01PreviewFixture()),
            .useIncoming: .success(.s4x01PreviewFixture(
                resolution: .useIncoming,
                canApply: false,
                requiresReplaceConfirmation: true,
                trashAvailable: false,
                backupTarget: ".areamatrix/staging/safety-backups/report.pdf",
                blockedReason: "Replace confirmation required",
                previewToken: "preview-token-use-incoming"
            ))
        ])
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/s4x01-repo",
            conflictDetector: S4X01RecordingSyncConflictDetector(result: .success([.s4x01Fixture()])),
            conflictResolver: resolver,
            errorMapper: S4X01RecordingErrorMapper(mapping: .s4x01Mapping())
        )

        await model.load()
        await model.selectResolution(.useIncoming)
        let preview = try XCTUnwrap(model.previewState.preview)

        XCTAssertTrue(preview.hasRecoverableOldVersion)
        XCTAssertNil(model.replaceConfirmationDisabledReason)
        XCTAssertTrue(model.canConfirmReplacePlan)

        model.confirmReplacePlan(understandsReplace: true)
        await model.applyResolution()
        let resolveRequests = await resolver.recordedResolveRequests()

        XCTAssertEqual(resolveRequests, [.s4x01UseIncomingConfirmedRequest])
    }

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
        let staleContext = SingleFileReplaceConfirmationContext(
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

        assertReplaceConfirmationFailure(
            acceptedStale: acceptedStale,
            blockedOutcome: blockedOutcome,
            requestsAfterFailure: requestsAfterFailure,
            model: model
        )

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
        let importer = S118RecordingBatchImporter()
        let model = makeFolderReplaceConfirmationModel(
            rootURL: rootURL,
            sourceURL: sourceURL,
            importer: importer
        )

        await model.load(request: s119FolderRequest(
            rootURL: rootURL,
            allowReplaceDuringImport: true
        ))
        model.updateNameConflictResolution(for: sourceURL.path, resolution: .replace(isConfirmed: false))
        let context = try XCTUnwrap(model.beginReplaceConfirmation(for: sourceURL.path))
        let staleContext = SingleFileReplaceConfirmationContext(
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

        assertReplaceConfirmationFailure(
            acceptedStale: acceptedStale,
            blockedOutcome: blockedOutcome,
            requestsAfterFailure: requestsAfterFailure,
            model: model
        )

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

@MainActor
private func makeFolderReplaceConfirmationModel(
    rootURL: URL,
    sourceURL: URL,
    importer: S118RecordingBatchImporter
) -> ImportFolderPreviewModel {
    let scanner = S119StaticFolderScanner(result: ImportFolderScanResult(
        rows: [ImportFolderPreviewRow.loading(fileURL: sourceURL, rootURL: rootURL)],
        folderCount: 0,
        skippedRules: [],
        errors: []
    ))
    let prechecker = S119StaticConflictPrechecker(results: [
        sourceURL.path: .nameConflict(existingPath: "docs/name.pdf")
    ])
    return ImportFolderPreviewModel(
        predictor: S119RecordingPredictor(results: [.success(.s119Prediction(suggestedName: "name.pdf"))]),
        importer: importer,
        errorMapper: S117RecordingErrorMapper(),
        conflictPrechecker: prechecker,
        scanner: scanner
    )
}

@MainActor
private func assertReplaceConfirmationFailure(
    acceptedStale: Bool,
    blockedOutcome: ImportBatchImportResult?,
    requestsAfterFailure: [S118BatchImportRequest],
    model: ImportBatchCopyImportModel
) {
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
}

@MainActor
private func assertReplaceConfirmationFailure(
    acceptedStale: Bool,
    blockedOutcome: ImportBatchImportResult?,
    requestsAfterFailure: [S118BatchImportRequest],
    model: ImportFolderPreviewModel
) {
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
}

private func duplicateResult() -> ImportSingleFilePreflightResult {
    ImportSingleFilePreflightResult(
        sourceSizeBytes: 912 * 1024,
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
        sourceSizeBytes: 912 * 1024,
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
        sizeBytes: 860 * 1024,
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
