@testable import AreaMatrix
import XCTest

final class ImportSingleFileNameConflictCoreTests: XCTestCase {
    @MainActor
    func testImportConflictBatchLoadsCoreConflictBatchPreviewWithDefaultSafeStrategies() async {
        let invoiceURL = importBatchInvoiceURL()
        let conflictBatcher = ImportConflictBatcher(previews: [.importConflictBatchDefaultPreview])
        let model = ImportBatchCopyImportModel(
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: RecordingCoreErrorMapper.importSingleFile(),
            conflictBatcher: conflictBatcher
        )

        model.applyPreviewRows(
            [importBatchReadyBatchRow(url: invoiceURL)],
            request: importConflictBatchBatchRequest(urls: [invoiceURL], conflictIDs: ["dup-1", "name-1"]),
            selectedDestination: .autoClassify
        )
        await model.loadImportConflictBatchPreview()

        XCTAssertTrue(model.showsCoreConflictBatchReview)
        await conflictBatcher.assertImportConflictBatchPreviewRequests([
            ImportConflictPreviewRequest(
                repoPath: importSingleFileRepoPath(),
                request: ImportConflictBatchPreviewRequestSnapshot(
                    importSessionID: "session-221",
                    conflictIDs: ["dup-1", "name-1"],
                    duplicateStrategy: .skip,
                    sameNameStrategy: .keepBoth,
                    applyToAllSimilarConflicts: true
                )
            )
        ])
        XCTAssertEqual(model.conflictBatchPreviewReport?.duplicateConflictCount, 1)
        XCTAssertNil(model.conflictBatchFailure)
    }

    @MainActor
    func testImportConflictBatchApplyRequiresReplaceConfirmationBeforeCallingCore() async {
        let invoiceURL = importBatchInvoiceURL()
        let conflictBatcher = ImportConflictBatcher(previews: [.importConflictBatchReplacePreview])
        let model = ImportBatchCopyImportModel(
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: RecordingCoreErrorMapper.importSingleFile(),
            conflictBatcher: conflictBatcher
        )

        model.applyPreviewRows(
            [importBatchReadyBatchRow(url: invoiceURL)],
            request: importConflictBatchBatchRequest(urls: [invoiceURL], conflictIDs: ["dup-1"]),
            selectedDestination: .autoClassify
        )
        model.updateConflictBatchDuplicateStrategy(.replace)
        await model.loadImportConflictBatchPreview()
        let blockedResult = await model.applyImportConflictBatch(replaceConfirmed: false)
        model.confirmConflictBatchReplace()
        let confirmedResult = await model.applyImportConflictBatch(replaceConfirmed: true)

        XCTAssertNil(blockedResult)
        await conflictBatcher.assertImportConflictBatchApplyRequests([
            ImportConflictApplyRequest(
                repoPath: importSingleFileRepoPath(),
                request: .testFixture(),
                previewToken: "token-replace"
            )
        ])
        XCTAssertEqual(confirmedResult?.report?.replacedCount, 1)
    }

    @MainActor
    func testImportConflictBatchPartialBlockedRowsDoNotDisableActionableScope() async {
        let invoiceURL = importBatchInvoiceURL()
        let blockedPreview = ImportConflictBatchPreviewReportSnapshot.importConflictBatchDefaultPreview
            .withBlockedSameNameRow()
        let conflictBatcher = ImportConflictBatcher(previews: [blockedPreview, blockedPreview])
        let model = ImportBatchCopyImportModel(
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: RecordingCoreErrorMapper.importSingleFile(),
            conflictBatcher: conflictBatcher
        )

        model.applyPreviewRows(
            [importBatchReadyBatchRow(url: invoiceURL)],
            request: importConflictBatchBatchRequest(urls: [invoiceURL], conflictIDs: ["dup-1", "name-blocked"]),
            selectedDestination: .autoClassify
        )
        await model.loadImportConflictBatchPreview()
        XCTAssertNil(model.conflictBatchApplyDisabledReason)
        XCTAssertNil(model.conflictBatchAskPerItemDisabledReason)
        XCTAssertEqual(model.conflictBatchPreviewReport?.items.last?.status, .blocked)

        let applyResult = await model.applyImportConflictBatch()
        _ = await model.askConflictBatchPerItem()

        XCTAssertNil(model.conflictBatchAskPerItemDisabledReason)
        XCTAssertEqual(applyResult?.report?.resolvedCount, 2)
        await conflictBatcher.assertFirstApplyRequestConflictIDs(["dup-1", "name-blocked"])
        await conflictBatcher.assertLastApplyRequestDuplicateStrategy(.askPerItem)
    }

    @MainActor
    func testNameConflictRealCoreSameNameDifferentContentDefaultsToNumberedKeepBothImport() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "nameConflict-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "nameConflict-source")
        defer { removeTestTemporaryItems(repoURL, sourceRoot) }
        let existingURL = sourceRoot.appendingPathComponent("existing.pdf")
        let incomingURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("existing bytes".utf8).write(to: existingURL)
        try Data("incoming bytes".utf8).write(to: incomingURL)

        let model = try await makeImportSingleFileNameConflictCoreModel(
            repoURL: repoURL,
            existingURL: existingURL,
            incomingURL: incomingURL
        )

        XCTAssertEqual(model.activeConflictPage, .name)
        XCTAssertEqual(model.currentPreflightResult?.conflict, .name(path: "docs/source.pdf"))
        XCTAssertEqual(model.currentPreflightResult?.keepBothTargetRelativePath, "docs/source_1.pdf")
        XCTAssertEqual(model.nameConflictResolution, .keepBoth)

        let imported = await model.importSelectedFile()
        let docsURL = repoURL.appendingPathComponent("docs")
        let repoFiles = try FileManager.default.contentsOfDirectory(atPath: docsURL.path)

        XCTAssertEqual(model.progressCurrentPath, "docs/source_1.pdf")
        XCTAssertEqual(imported?.path, "docs/source_1.pdf")
        XCTAssertEqual(repoFiles.sorted(), ["source.pdf", "source_1.pdf"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: incomingURL.path))
    }

    @MainActor
    func testNameConflictRealCoreRenameIncomingUsesEditedSafeName() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "nameConflict-rename-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "nameConflict-rename-source")
        defer { removeTestTemporaryItems(repoURL, sourceRoot) }
        let existingURL = sourceRoot.appendingPathComponent("existing.pdf")
        let incomingURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("existing bytes".utf8).write(to: existingURL)
        try Data("incoming bytes".utf8).write(to: incomingURL)

        let model = try await makeImportSingleFileNameConflictCoreModel(
            repoURL: repoURL,
            existingURL: existingURL,
            incomingURL: incomingURL
        )
        model.renameIncomingNameConflictFile(to: "renamed.pdf")

        let imported = await model.importSelectedFile()

        XCTAssertEqual(model.progressCurrentPath, "docs/renamed.pdf")
        XCTAssertEqual(imported?.path, "docs/renamed.pdf")
        XCTAssertEqual(imported?.currentName, "renamed.pdf")
    }
}

private func importConflictBatchBatchRequest(urls: [URL], conflictIDs: [String]) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: importSingleFileRepoPath(),
        source: .dropZone,
        destination: .autoClassify,
        urls: urls,
        kind: .multipleItems(urls.count),
        availableCategories: ["inbox", "docs", "finance"],
        allowReplaceDuringImport: true,
        isTrashAvailable: true,
        importSessionID: "session-221",
        importConflictIDs: conflictIDs
    )
}

private extension ImportConflictBatchPreviewReportSnapshot {
    static var importConflictBatchDefaultPreview: ImportConflictBatchPreviewReportSnapshot {
        .testFixture(
            previewToken: "token-default",
            requestedConflictCount: 2,
            sameNameConflictCount: 1,
            includedCount: 2,
            replaceCount: 0,
            skipCount: 1,
            keepBothCount: 1,
            replaceConfirmationRequired: false,
            replaceConfirmationSummary: nil,
            items: [.importConflictBatchDuplicate(strategy: .skip), .importConflictBatchSameName(strategy: .keepBoth)]
        )
    }

    static var importConflictBatchReplacePreview: ImportConflictBatchPreviewReportSnapshot {
        .testFixture(
            replaceConfirmationSummary: "1 duplicate conflict",
            items: [.importConflictBatchDuplicate(strategy: .replace)]
        )
    }

    func withBlockedSameNameRow() -> ImportConflictBatchPreviewReportSnapshot {
        var copy = self
        copy.requestedConflictCount = 2
        copy.includedCount = 2
        copy.blockedCount = 1
        copy.skipCount = 1
        copy.keepBothCount = 0
        copy.items = [
            .importConflictBatchDuplicate(conflictID: "dup-1", strategy: .skip),
            .importConflictBatchBlockedSameName(conflictID: "name-blocked")
        ]
        return copy
    }
}

private extension ImportConflictBatchPreviewItemSnapshot {
    static func importConflictBatchDuplicate(
        conflictID: String = "dup-1",
        strategy: ImportConflictBatchStrategySnapshot = .skip
    ) -> ImportConflictBatchPreviewItemSnapshot {
        .testFixture(
            conflictID: conflictID,
            selectedStrategy: strategy
        )
    }

    static func importConflictBatchSameName(
        conflictID: String = "name-1",
        strategy: ImportConflictBatchStrategySnapshot = .keepBoth
    ) -> ImportConflictBatchPreviewItemSnapshot {
        .testFixture(
            conflictID: conflictID,
            conflictType: .sameNameDifferentContent,
            existingPath: "docs/合同.pdf",
            incomingPath: "/tmp/合同.pdf",
            targetPath: "docs/合同 2.pdf",
            selectedStrategy: strategy
        )
    }

    static func importConflictBatchBlockedSameName(conflictID: String) -> ImportConflictBatchPreviewItemSnapshot {
        var item = importConflictBatchSameName(conflictID: conflictID, strategy: .askPerItem)
        item.status = .blocked
        item.willAskPerItem = false
        item.reason = "Index-only target cannot be replaced."
        return item
    }
}
