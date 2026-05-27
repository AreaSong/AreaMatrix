@testable import AreaMatrix
import XCTest

final class ImportSingleFileNameConflictCoreTests: XCTestCase {
    @MainActor
    func testS221LoadsCoreConflictBatchPreviewWithDefaultSafeStrategies() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let conflictBatcher = S221RecordingConflictBatcher()
        let model = ImportBatchCopyImportModel(
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper(),
            conflictBatcher: conflictBatcher
        )

        model.applyPreviewRows(
            [s118ReadyBatchRow(url: invoiceURL)],
            request: s221BatchRequest(urls: [invoiceURL], conflictIDs: ["dup-1", "name-1"]),
            selectedDestination: .autoClassify
        )
        await model.loadImportConflictBatchPreview()
        let previewRequests = await conflictBatcher.previewRequests()

        XCTAssertTrue(model.showsCoreConflictBatchReview)
        XCTAssertEqual(previewRequests, [
            S221PreviewRequest(
                repoPath: "/tmp/repo",
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
    func testS221ApplyRequiresReplaceConfirmationBeforeCallingCore() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let conflictBatcher = S221RecordingConflictBatcher(preview: .s221ReplacePreview)
        let model = ImportBatchCopyImportModel(
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper(),
            conflictBatcher: conflictBatcher
        )

        model.applyPreviewRows(
            [s118ReadyBatchRow(url: invoiceURL)],
            request: s221BatchRequest(urls: [invoiceURL], conflictIDs: ["dup-1"]),
            selectedDestination: .autoClassify
        )
        model.updateConflictBatchDuplicateStrategy(.replace)
        await model.loadImportConflictBatchPreview()
        let blockedResult = await model.applyImportConflictBatch(replaceConfirmed: false)
        model.confirmConflictBatchReplace()
        let confirmedResult = await model.applyImportConflictBatch(replaceConfirmed: true)
        let applyRequests = await conflictBatcher.applyRequests()

        XCTAssertNil(blockedResult)
        XCTAssertEqual(applyRequests, [
            S221ApplyRequest(
                repoPath: "/tmp/repo",
                request: ImportConflictBatchApplyRequestSnapshot(
                    importSessionID: "session-221",
                    conflictIDs: ["dup-1"],
                    duplicateStrategy: .replace,
                    sameNameStrategy: .keepBoth,
                    applyToAllSimilarConflicts: true,
                    replaceConfirmed: true
                ),
                previewToken: "token-replace"
            )
        ])
        XCTAssertEqual(confirmedResult?.report?.replacedCount, 1)
    }

    @MainActor
    func testS221PartialBlockedRowsDoNotDisableActionableScope() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let blockedPreview = ImportConflictBatchPreviewReportSnapshot.s221DefaultPreview
            .withBlockedSameNameRow()
        let conflictBatcher = S221RecordingConflictBatcher(preview: blockedPreview)
        let model = ImportBatchCopyImportModel(
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper(),
            conflictBatcher: conflictBatcher
        )

        model.applyPreviewRows(
            [s118ReadyBatchRow(url: invoiceURL)],
            request: s221BatchRequest(urls: [invoiceURL], conflictIDs: ["dup-1", "name-blocked"]),
            selectedDestination: .autoClassify
        )
        await model.loadImportConflictBatchPreview()
        XCTAssertNil(model.conflictBatchApplyDisabledReason)
        XCTAssertNil(model.conflictBatchAskPerItemDisabledReason)

        let applyResult = await model.applyImportConflictBatch()
        _ = await model.askConflictBatchPerItem()
        let applyRequests = await conflictBatcher.applyRequests()

        XCTAssertNil(model.conflictBatchAskPerItemDisabledReason)
        XCTAssertEqual(applyResult?.report?.resolvedCount, 2)
        XCTAssertEqual(applyRequests.first?.request.conflictIDs, ["dup-1", "name-blocked"])
        XCTAssertEqual(applyRequests.last?.request.duplicateStrategy, .askPerItem)
    }

    @MainActor
    func testS123RealCoreSameNameDifferentContentDefaultsToNumberedKeepBothImport() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "s123-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "s123-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let existingURL = sourceRoot.appendingPathComponent("existing.pdf")
        let incomingURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("existing bytes".utf8).write(to: existingURL)
        try Data("incoming bytes".utf8).write(to: incomingURL)

        let model = try await makeNameConflictModel(
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
    func testS123RealCoreRenameIncomingUsesEditedSafeName() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "s123-rename-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "s123-rename-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let existingURL = sourceRoot.appendingPathComponent("existing.pdf")
        let incomingURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("existing bytes".utf8).write(to: existingURL)
        try Data("incoming bytes".utf8).write(to: incomingURL)

        let model = try await makeNameConflictModel(
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

    @MainActor
    private func makeNameConflictModel(
        repoURL: URL,
        existingURL: URL,
        incomingURL: URL
    ) async throws -> ImportSingleFilePreviewModel {
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        _ = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: existingURL,
            overrideCategory: "docs",
            overrideFilename: "source.pdf"
        )

        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: bridge,
            preflight: CoreImportSingleFilePreflight(),
            errorMapper: S117RecordingErrorMapper()
        )
        await model.load(request: ImportEntryRequest(
            repoPath: repoURL.path,
            source: .filePicker,
            destination: .autoClassify,
            urls: [incomingURL],
            kind: .singleFile
        ))
        return model
    }
}

private func s221BatchRequest(urls: [URL], conflictIDs: [String]) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: "/tmp/repo",
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

private struct S221PreviewRequest: Equatable {
    var repoPath: String
    var request: ImportConflictBatchPreviewRequestSnapshot
}

private struct S221ApplyRequest: Equatable {
    var repoPath: String
    var request: ImportConflictBatchApplyRequestSnapshot
    var previewToken: String
}

private actor S221RecordingConflictBatcher: CoreImportConflictBatching {
    private let preview: ImportConflictBatchPreviewReportSnapshot
    private var recordedPreviewRequests: [S221PreviewRequest] = []
    private var recordedApplyRequests: [S221ApplyRequest] = []

    init(preview: ImportConflictBatchPreviewReportSnapshot = .s221DefaultPreview) {
        self.preview = preview
    }

    func previewImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchPreviewRequestSnapshot
    ) async throws -> ImportConflictBatchPreviewReportSnapshot {
        recordedPreviewRequests.append(S221PreviewRequest(repoPath: repoPath, request: request))
        return preview.withRequest(request)
    }

    func applyImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchApplyRequestSnapshot,
        previewToken: String
    ) async throws -> ImportConflictBatchApplyReportSnapshot {
        recordedApplyRequests.append(S221ApplyRequest(
            repoPath: repoPath,
            request: request,
            previewToken: previewToken
        ))
        return .s221Report(for: request)
    }

    func previewRequests() -> [S221PreviewRequest] {
        recordedPreviewRequests
    }

    func applyRequests() -> [S221ApplyRequest] {
        recordedApplyRequests
    }
}

private extension ImportConflictBatchPreviewReportSnapshot {
    static var s221DefaultPreview: ImportConflictBatchPreviewReportSnapshot {
        ImportConflictBatchPreviewReportSnapshot(
            importSessionID: "session-221",
            previewToken: "token-default",
            applyToAllSimilarConflicts: true,
            requestedConflictCount: 2,
            duplicateConflictCount: 1,
            sameNameConflictCount: 1,
            includedCount: 2,
            pendingCount: 0,
            blockedCount: 0,
            replaceCount: 0,
            skipCount: 1,
            keepBothCount: 1,
            askPerItemCount: 0,
            trashAvailable: true,
            undoAvailable: true,
            canApply: true,
            applyBlockedReason: nil,
            replaceConfirmationRequired: false,
            replaceConfirmationSummary: nil,
            items: [.s221Duplicate(strategy: .skip), .s221SameName(strategy: .keepBoth)]
        )
    }

    static var s221ReplacePreview: ImportConflictBatchPreviewReportSnapshot {
        ImportConflictBatchPreviewReportSnapshot(
            importSessionID: "session-221",
            previewToken: "token-replace",
            applyToAllSimilarConflicts: true,
            requestedConflictCount: 1,
            duplicateConflictCount: 1,
            sameNameConflictCount: 0,
            includedCount: 1,
            pendingCount: 0,
            blockedCount: 0,
            replaceCount: 1,
            skipCount: 0,
            keepBothCount: 0,
            askPerItemCount: 0,
            trashAvailable: true,
            undoAvailable: true,
            canApply: true,
            applyBlockedReason: nil,
            replaceConfirmationRequired: true,
            replaceConfirmationSummary: "1 duplicate conflict",
            items: [.s221Duplicate(strategy: .replace)]
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
            .s221Duplicate(conflictID: "dup-1", strategy: .skip),
            .s221BlockedSameName(conflictID: "name-blocked")
        ]
        return copy
    }

    func withRequest(
        _ request: ImportConflictBatchPreviewRequestSnapshot
    ) -> ImportConflictBatchPreviewReportSnapshot {
        var copy = self
        copy.importSessionID = request.importSessionID
        copy.applyToAllSimilarConflicts = request.applyToAllSimilarConflicts
        copy.requestedConflictCount = Int64(request.conflictIDs.count)
        copy.includedCount = Int64(request.conflictIDs.count)
        copy.items = request.conflictIDs.map { conflictID in
            let source = items.first { $0.conflictID == conflictID } ?? .s221Duplicate(conflictID: conflictID)
            return source.withStrategies(
                duplicateStrategy: request.duplicateStrategy,
                sameNameStrategy: request.sameNameStrategy
            )
        }
        return copy
    }
}

private extension ImportConflictBatchPreviewItemSnapshot {
    static func s221Duplicate(
        conflictID: String = "dup-1",
        strategy: ImportConflictBatchStrategySnapshot = .skip
    ) -> ImportConflictBatchPreviewItemSnapshot {
        ImportConflictBatchPreviewItemSnapshot(
            conflictID: conflictID,
            conflictType: .duplicateHash,
            existingFileID: 42,
            existingPath: "finance/existing-invoice.pdf",
            incomingPath: "/tmp/Invoice_2026Q1.pdf",
            targetPath: "finance/Invoice_2026Q1.pdf",
            selectedStrategy: strategy,
            status: strategy == .replace ? .needsConfirmation : .ready,
            willReplace: strategy == .replace,
            willKeepBoth: strategy == .keepBoth,
            willSkip: strategy == .skip,
            willAskPerItem: strategy == .askPerItem,
            indexOnly: false,
            riskSummary: "Existing file remains unless Replace is confirmed.",
            reason: nil
        )
    }

    static func s221SameName(
        conflictID: String = "name-1",
        strategy: ImportConflictBatchStrategySnapshot = .keepBoth
    ) -> ImportConflictBatchPreviewItemSnapshot {
        var item = s221Duplicate(conflictID: conflictID, strategy: strategy)
        item.conflictType = .sameNameDifferentContent
        item.existingPath = "docs/合同.pdf"
        item.incomingPath = "/tmp/合同.pdf"
        item.targetPath = "docs/合同 2.pdf"
        return item
    }

    static func s221BlockedSameName(conflictID: String) -> ImportConflictBatchPreviewItemSnapshot {
        var item = s221SameName(conflictID: conflictID, strategy: .askPerItem)
        item.status = .blocked
        item.willAskPerItem = false
        item.reason = "Index-only target cannot be replaced."
        return item
    }

    func withStrategies(
        duplicateStrategy: ImportConflictBatchStrategySnapshot,
        sameNameStrategy: ImportConflictBatchStrategySnapshot
    ) -> ImportConflictBatchPreviewItemSnapshot {
        switch conflictType {
        case .duplicateHash:
            .s221Duplicate(conflictID: conflictID, strategy: duplicateStrategy)
        case .sameNameDifferentContent:
            .s221SameName(conflictID: conflictID, strategy: sameNameStrategy)
        }
    }
}

private extension ImportConflictBatchApplyReportSnapshot {
    static func s221Report(
        for request: ImportConflictBatchApplyRequestSnapshot
    ) -> ImportConflictBatchApplyReportSnapshot {
        let isAskPerItem = request.duplicateStrategy == .askPerItem && request.sameNameStrategy == .askPerItem
        let isReplace = request.duplicateStrategy == .replace || request.sameNameStrategy == .replace
        let count = Int64(request.conflictIDs.count)
        return ImportConflictBatchApplyReportSnapshot(
            importSessionID: request.importSessionID,
            requestedConflictCount: count,
            resolvedCount: count,
            skippedCount: request.duplicateStrategy == .skip ? count : 0,
            keptBothCount: request.sameNameStrategy == .keepBoth ? count : 0,
            replacedCount: isReplace ? count : 0,
            queuedForPerItemCount: isAskPerItem ? count : 0,
            pendingCount: 0,
            failedCount: 0,
            itemResults: request.conflictIDs.map { conflictID in
                .s221Result(conflictID: conflictID, request: request)
            },
            affectedFileIDs: isAskPerItem ? [] : [42],
            undoToken: isReplace ? "undo-replace" : nil,
            changeLogActions: isAskPerItem ? [] : ["import_conflict_batch"],
            failureSummary: nil
        )
    }
}

private extension ImportConflictBatchItemResultSnapshot {
    static func s221Result(
        conflictID: String,
        request: ImportConflictBatchApplyRequestSnapshot
    ) -> ImportConflictBatchItemResultSnapshot {
        let strategy = conflictID.hasPrefix("dup") ? request.duplicateStrategy : request.sameNameStrategy
        return ImportConflictBatchItemResultSnapshot(
            conflictID: conflictID,
            conflictType: conflictID.hasPrefix("dup") ? .duplicateHash : .sameNameDifferentContent,
            appliedStrategy: strategy,
            status: resultStatus(for: strategy),
            fileID: strategy == .askPerItem ? nil : 42,
            finalPath: "finance/Invoice_2026Q1.pdf",
            error: nil
        )
    }

    private static func resultStatus(
        for strategy: ImportConflictBatchStrategySnapshot
    ) -> ImportConflictBatchResultStatusSnapshot {
        switch strategy {
        case .skip:
            .skipped
        case .keepBoth:
            .keptBoth
        case .replace:
            .replaced
        case .askPerItem:
            .queuedForPerItem
        }
    }
}
