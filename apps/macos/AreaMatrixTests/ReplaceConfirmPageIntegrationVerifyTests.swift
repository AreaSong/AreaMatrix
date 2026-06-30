@testable import AreaMatrix
import XCTest

final class ReplaceConfirmPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testReplaceResolutionSyncConflictReplaceConfirmConnectsPreviewConfirmationApplyAndExit() async throws {
        let context = makeReplaceResolutionReplaceContext()

        await context.model.load()
        await context.model.selectResolution(.useIncoming)
        await context.model.applyResolution()
        let unresolvedRequests = await context.resolver.recordedResolveRequests()
        let preview = try XCTUnwrap(context.model.previewState.preview)
        let panelBody = SyncConflictReplaceConfirmationPanel(
            preview: preview,
            confirmation: context.model.replaceConfirmation,
            disabledReason: context.model.replaceConfirmationDisabledReason,
            onConfirm: { _ in }
        ).body

        assertReplaceResolutionReplacePanelBlocksUnconfirmedApply(
            model: context.model,
            unresolvedRequests: unresolvedRequests,
            panelBody: panelBody
        )

        context.model.confirmReplacePlan(understandsReplace: true)
        await context.view.applySelectedResolution()
        let detectRequests = await context.detector.recordedRequests()
        let previewRequests = await context.resolver.recordedPreviewRequests()
        let resolveRequests = await context.resolver.recordedResolveRequests()

        assertReplaceResolutionReplaceApplyExit(
            model: context.model,
            detectRequests: detectRequests,
            previewRequests: previewRequests,
            resolveRequests: resolveRequests,
            resolvedReports: context.resolvedReports.reports
        )
    }

    @MainActor
    func testReplaceResolutionCoreSafetyBackupAllowsReplaceWhenTrashUnavailable() async throws {
        let resolver = SyncConflictReviewResolver(previewResults: [
            .keepBoth: .success(.syncConflictReviewPreviewFixture()),
            .useIncoming: .success(.syncConflictReviewPreviewFixture(
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
            repoPath: "/tmp/syncConflictReview-repo",
            conflictDetector: SyncConflictReviewDetector(
                result: .success([.syncConflictReviewFixture()])
            ),
            conflictResolver: resolver,
            errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
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

        XCTAssertEqual(resolveRequests, [.useIncomingConfirmedRequest])
    }

    @MainActor
    func testReplaceConfirmSingleFileCoversDuplicateAndNameConflictWithoutImmediateCoreImport(
    ) async throws {
        let importer = ImportSingleFileRecordingImporter()
        let duplicateModel = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(result: .importSingleFileFixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: duplicateResult()),
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )
        let nameModel = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(result: .importSingleFileFixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: nameConflictResult()),
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
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
    func testReplaceConfirmBatchReplaceContextFailureStaysRecoverableAndDoesNotOverwrite() async throws {
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
        let importer = ImportBatchRecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
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
    func testReplaceConfirmFolderReplaceContextFailureStaysRecoverableAndDoesNotOverwrite() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/client-a")
        let sourceURL = rootURL.appendingPathComponent("name.pdf")
        let importer = ImportBatchRecordingBatchImporter()
        let model = makeFolderReplaceConfirmationModel(
            rootURL: rootURL,
            sourceURL: sourceURL,
            importer: importer
        )

        await model.load(request: importFolderFolderRequest(
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

private struct ReplaceResolutionReplaceContext {
    let detector: SyncConflictReviewDetector
    let resolver: SyncConflictReviewResolver
    let model: SyncConflictReviewModel
    let view: SyncConflictReviewView
    let resolvedReports: ReplaceResolutionResolvedReports
}

private final class ReplaceResolutionResolvedReports {
    var reports: [SyncConflictResolveReportSnapshot] = []
}

@MainActor
private func makeReplaceResolutionReplaceContext() -> ReplaceResolutionReplaceContext {
    let detector = SyncConflictReviewDetector(result: .success([.syncConflictReviewFixture()]))
    let resolver = SyncConflictReviewResolver(
        previewResults: [
            .keepBoth: .success(.syncConflictReviewPreviewFixture()),
            .useIncoming: .success(.syncConflictReviewPreviewFixture(
                resolution: .useIncoming,
                canApply: false,
                requiresReplaceConfirmation: true,
                blockedReason: "Replace confirmation required",
                previewToken: "preview-token-use-incoming"
            ))
        ],
        resolveResult: .success(.syncConflictReviewResolveFixture(resolution: .useIncoming))
    )
    let model = SyncConflictReviewModel(
        repoPath: "/tmp/syncConflictReview-repo",
        conflictDetector: detector,
        conflictResolver: resolver,
        errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
    )
    let resolvedReports = ReplaceResolutionResolvedReports()
    let view = SyncConflictReviewView(
        model: model,
        onBackToNeedsReview: {},
        onClose: {},
        onResolved: { resolvedReports.reports.append($0) }
    )
    return ReplaceResolutionReplaceContext(
        detector: detector,
        resolver: resolver,
        model: model,
        view: view,
        resolvedReports: resolvedReports
    )
}

@MainActor
private func assertReplaceResolutionReplacePanelBlocksUnconfirmedApply(
    model: SyncConflictReviewModel,
    unresolvedRequests: [SyncConflictResolveRequest],
    panelBody: Any
) {
    XCTAssertEqual(unresolvedRequests, [])
    XCTAssertFalse(model.canApplyResolution)
    XCTAssertTrue(model.canConfirmReplacePlan)
    assertTestMirrorDescription(of: panelBody, contains: [
        "Confirm Replace",
        "Old file path",
        "Old version will be kept at",
        "Affected record",
        "Change log",
        "Recovery note"
    ])
}

@MainActor
private func assertReplaceResolutionReplaceApplyExit(
    model: SyncConflictReviewModel,
    detectRequests: [String],
    previewRequests: [SyncConflictPreviewRequest],
    resolveRequests: [SyncConflictResolveRequest],
    resolvedReports: [SyncConflictResolveReportSnapshot]
) {
    XCTAssertEqual(detectRequests, ["/tmp/syncConflictReview-repo"])
    XCTAssertEqual(previewRequests.map(\.resolution), [.keepBoth, .useIncoming])
    XCTAssertEqual(resolveRequests, [.useIncomingConfirmedRequest])
    XCTAssertEqual(resolvedReports, [.syncConflictReviewResolveFixture(resolution: .useIncoming)])
    XCTAssertEqual(model.applyDisabledReason, "Resolution has already been applied.")
}

@MainActor
private func makeFolderReplaceConfirmationModel(
    rootURL: URL,
    sourceURL: URL,
    importer: ImportBatchRecordingBatchImporter
) -> ImportFolderPreviewModel {
    let scanner = ImportFolderStaticFolderScanner(result: ImportFolderScanResult(
        rows: [ImportFolderPreviewRow.loading(fileURL: sourceURL, rootURL: rootURL)],
        folderCount: 0,
        skippedRules: [],
        errors: []
    ))
    let prechecker = ImportFolderStaticConflictPrechecker(results: [
        sourceURL.path: .nameConflict(existingPath: "docs/name.pdf")
    ])
    return ImportFolderPreviewModel(
        predictor: ImportFolderRecordingPredictor(
            results: [.success(.importFolderPrediction(suggestedName: "name.pdf"))]
        ),
        importer: importer,
        errorMapper: RecordingCoreErrorMapper.importSingleFile(),
        conflictPrechecker: prechecker,
        scanner: scanner
    )
}

@MainActor
private func assertReplaceConfirmationFailure(
    acceptedStale: Bool,
    blockedOutcome: ImportBatchImportResult?,
    requestsAfterFailure: [ImportBatchBatchImportRequest],
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
    requestsAfterFailure: [ImportBatchBatchImportRequest],
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
