@testable import AreaMatrix
import XCTest

final class ReplaceConfirmPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testReplaceResolutionSyncConflictReplaceConfirmConnectsPreviewConfirmationApplyAndExit() async throws {
        let context = makeSyncConflictReplaceContext()

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

        assertSyncConflictReplaceResolutionBlocksUnconfirmedApply(
            model: context.model,
            unresolvedRequests: unresolvedRequests,
            panelBody: panelBody
        )

        context.model.confirmReplacePlan(understandsReplace: true)
        await context.view.applySelectedResolution()
        let detectRequests = await context.detector.recordedRequests()
        let previewRequests = await context.resolver.recordedPreviewRequests()
        let resolveRequests = await context.resolver.recordedResolveRequests()

        assertSyncConflictReplaceResolutionApplyExit(
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
            errorMapper: StaticCoreErrorMapper(mapping: .syncConflictReviewMapping())
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
        let duplicateModel = makeImportSingleFilePreviewModel(
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: .importDuplicateReplaceFixture(
                targetRelativePath: "docs/source.pdf",
                existingPath: "docs/existing-duplicate.pdf",
                keepBothTargetRelativePath: "docs/source_1.pdf",
                existingFile: .importReplaceExistingFileFixture(
                    path: "docs/existing-duplicate.pdf",
                    hashSha256: "duplicate-hash"
                )
            ))
        )
        let nameModel = makeImportSingleFilePreviewModel(
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: .importNameConflictReplaceFixture(
                targetRelativePath: "docs/source.pdf",
                existingPath: "docs/source.pdf",
                keepBothTargetRelativePath: "docs/source_1.pdf",
                existingPaths: ["docs/source.pdf"],
                existingFile: .importReplaceExistingFileFixture(
                    path: "docs/source.pdf",
                    hashSha256: "existing-hash"
                )
            ))
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
        let invoiceURL = importBatchInvoiceURL()
        let row = importBatchDuplicateInvoiceRow(url: invoiceURL)
        let importer = ImportBatchRecordingBatchImporter()
        let model = importBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )

        model.applyPreviewRows(
            [row],
            request: importConflictBatchRequest(urls: [invoiceURL]),
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
        let model = importFolderReplaceConfirmationModel(
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

@MainActor
private func assertReplaceConfirmationFailure(
    acceptedStale: Bool,
    blockedOutcome: ImportBatchImportResult?,
    requestsAfterFailure: [ImportBatchBatchImportRequest],
    model: some ReplaceConfirmationRecoverableModel
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
private protocol ReplaceConfirmationRecoverableModel: AnyObject {
    var replaceConfirmationErrorMessage: String? { get }
    var replaceConfirmationDiagnosticsMessage: String? { get }
    var importDisabledReason: String? { get }

    func collectReplaceConfirmationDiagnostics()
    func retryReplaceConfirmation()
}

extension ImportBatchCopyImportModel: ReplaceConfirmationRecoverableModel {}
extension ImportFolderPreviewModel: ReplaceConfirmationRecoverableModel {}
