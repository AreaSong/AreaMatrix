@testable import AreaMatrix

extension ClassifyResultSnapshot {
    static func importBatchPrediction(
        category: String,
        suggestedName: String,
        confidence: Float = 0.9
    ) -> ClassifyResultSnapshot {
        .testFixture(
            category: category,
            suggestedName: suggestedName,
            reason: .keyword,
            confidence: confidence
        )
    }
}

extension ImportConflictBatchPreviewReportSnapshot {
    static func testFixture(
        importSessionID: String = "session-221",
        previewToken: String = "token-replace",
        applyToAllSimilarConflicts: Bool = true,
        requestedConflictCount: Int64 = 1,
        duplicateConflictCount: Int64 = 1,
        sameNameConflictCount: Int64 = 0,
        includedCount: Int64 = 1,
        pendingCount: Int64 = 0,
        blockedCount: Int64 = 0,
        replaceCount: Int64 = 1,
        skipCount: Int64 = 0,
        keepBothCount: Int64 = 0,
        askPerItemCount: Int64 = 0,
        trashAvailable: Bool = true,
        undoAvailable: Bool = true,
        canApply: Bool = true,
        applyBlockedReason: String? = nil,
        replaceConfirmationRequired: Bool = true,
        replaceConfirmationSummary: String? = "Replace 1 existing file?",
        items: [ImportConflictBatchPreviewItemSnapshot] = [
            .testFixture(selectedStrategy: .replace, status: .needsConfirmation)
        ]
    ) -> ImportConflictBatchPreviewReportSnapshot {
        ImportConflictBatchPreviewReportSnapshot(
            importSessionID: importSessionID,
            previewToken: previewToken,
            applyToAllSimilarConflicts: applyToAllSimilarConflicts,
            requestedConflictCount: requestedConflictCount,
            duplicateConflictCount: duplicateConflictCount,
            sameNameConflictCount: sameNameConflictCount,
            includedCount: includedCount,
            pendingCount: pendingCount,
            blockedCount: blockedCount,
            replaceCount: replaceCount,
            skipCount: skipCount,
            keepBothCount: keepBothCount,
            askPerItemCount: askPerItemCount,
            trashAvailable: trashAvailable,
            undoAvailable: undoAvailable,
            canApply: canApply,
            applyBlockedReason: applyBlockedReason,
            replaceConfirmationRequired: replaceConfirmationRequired,
            replaceConfirmationSummary: replaceConfirmationSummary,
            items: items
        )
    }

    static func importConflictBatchPreview(canApply: Bool) -> ImportConflictBatchPreviewReportSnapshot {
        let status: ImportConflictBatchPreviewStatusSnapshot = canApply ? .needsConfirmation : .blocked
        return .testFixture(
            previewToken: canApply ? "token-replace" : "token-blocked",
            blockedCount: canApply ? 0 : 1,
            trashAvailable: canApply,
            undoAvailable: canApply,
            canApply: canApply,
            applyBlockedReason: canApply ? nil : "Blocked: Trash unavailable",
            items: [.importConflictBatchItem(
                conflictID: canApply ? "dup-1" : "dup-blocked",
                strategy: .replace,
                status: status
            )]
        )
    }

    func withImportConflictBatchRequest(_ request: ImportConflictBatchPreviewRequestSnapshot)
        -> ImportConflictBatchPreviewReportSnapshot {
        var copy = self
        copy.importSessionID = request.importSessionID
        copy.applyToAllSimilarConflicts = request.applyToAllSimilarConflicts
        copy.requestedConflictCount = Int64(request.conflictIDs.count)
        copy.includedCount = Int64(request.conflictIDs.count)
        copy.items = request.conflictIDs.map { conflictID in
            let source = items.first { $0.conflictID == conflictID }
            if let source, source.status == .blocked {
                return source
            }
            let type = source?.conflictType ?? .duplicateHash
            let strategy = type == .duplicateHash ? request.duplicateStrategy : request.sameNameStrategy
            let status = copy.previewStatusForImportConflictBatchRequest(strategy: strategy)
            return .importConflictBatchItem(conflictID: conflictID, strategy: strategy, status: status)
                .withConflictType(type)
        }
        return copy
    }

    private func previewStatusForImportConflictBatchRequest(
        strategy: ImportConflictBatchStrategySnapshot
    ) -> ImportConflictBatchPreviewStatusSnapshot {
        guard canApply else { return .blocked }
        return strategy == .replace ? .needsConfirmation : .ready
    }
}

extension ImportConflictBatchPreviewItemSnapshot {
    static func testFixture(
        conflictID: String = "dup-1",
        conflictType: ImportConflictBatchConflictTypeSnapshot = .duplicateHash,
        existingFileID: Int64? = 42,
        existingPath: String? = "finance/existing-invoice.pdf",
        incomingPath: String = "/tmp/Invoice_2026Q1.pdf",
        targetPath: String? = "finance/Invoice_2026Q1.pdf",
        selectedStrategy: ImportConflictBatchStrategySnapshot = .skip,
        status: ImportConflictBatchPreviewStatusSnapshot? = nil,
        indexOnly: Bool = false,
        riskSummary: String = "Existing file remains unless Replace is confirmed.",
        reason: String? = nil
    ) -> ImportConflictBatchPreviewItemSnapshot {
        let effectiveStatus = status ?? (selectedStrategy == .replace ? .needsConfirmation : .ready)
        return ImportConflictBatchPreviewItemSnapshot(
            conflictID: conflictID,
            conflictType: conflictType,
            existingFileID: existingFileID,
            existingPath: existingPath,
            incomingPath: incomingPath,
            targetPath: targetPath,
            selectedStrategy: selectedStrategy,
            status: effectiveStatus,
            willReplace: selectedStrategy == .replace,
            willKeepBoth: selectedStrategy == .keepBoth,
            willSkip: selectedStrategy == .skip,
            willAskPerItem: selectedStrategy == .askPerItem,
            indexOnly: indexOnly,
            riskSummary: riskSummary,
            reason: reason
        )
    }

    static func importConflictBatchItem(
        conflictID: String,
        strategy: ImportConflictBatchStrategySnapshot,
        status: ImportConflictBatchPreviewStatusSnapshot
    ) -> ImportConflictBatchPreviewItemSnapshot {
        .testFixture(
            conflictID: conflictID,
            selectedStrategy: strategy,
            status: status,
            reason: status == .blocked ? "Trash unavailable" : nil
        )
    }
}

extension ImportConflictBatchApplyRequestSnapshot {
    static func testFixture(
        importSessionID: String = "session-221",
        conflictIDs: [String] = ["dup-1"],
        duplicateStrategy: ImportConflictBatchStrategySnapshot = .replace,
        sameNameStrategy: ImportConflictBatchStrategySnapshot = .keepBoth,
        applyToAllSimilarConflicts: Bool = true,
        replaceConfirmed: Bool = true
    ) -> ImportConflictBatchApplyRequestSnapshot {
        ImportConflictBatchApplyRequestSnapshot(
            importSessionID: importSessionID,
            conflictIDs: conflictIDs,
            duplicateStrategy: duplicateStrategy,
            sameNameStrategy: sameNameStrategy,
            applyToAllSimilarConflicts: applyToAllSimilarConflicts,
            replaceConfirmed: replaceConfirmed
        )
    }
}

extension ImportConflictBatchApplyReportSnapshot {
    static func testFixture(
        importSessionID: String = "session-221",
        requestedConflictCount: Int64 = 1,
        resolvedCount: Int64 = 1,
        skippedCount: Int64 = 0,
        keptBothCount: Int64 = 0,
        replacedCount: Int64 = 1,
        queuedForPerItemCount: Int64 = 0,
        pendingCount: Int64 = 0,
        failedCount: Int64 = 0,
        itemResults: [ImportConflictBatchItemResultSnapshot] = [.testFixture()],
        affectedFileIDs: [Int64] = [42],
        undoToken: String? = "undo-import-conflict-batch",
        changeLogActions: [String] = ["import_conflict_batch"],
        failureSummary: String? = nil
    ) -> ImportConflictBatchApplyReportSnapshot {
        ImportConflictBatchApplyReportSnapshot(
            importSessionID: importSessionID,
            requestedConflictCount: requestedConflictCount,
            resolvedCount: resolvedCount,
            skippedCount: skippedCount,
            keptBothCount: keptBothCount,
            replacedCount: replacedCount,
            queuedForPerItemCount: queuedForPerItemCount,
            pendingCount: pendingCount,
            failedCount: failedCount,
            itemResults: itemResults,
            affectedFileIDs: affectedFileIDs,
            undoToken: undoToken,
            changeLogActions: changeLogActions,
            failureSummary: failureSummary
        )
    }

    static func importConflictBatchIntegrationReport(
        for request: ImportConflictBatchApplyRequestSnapshot
    ) -> ImportConflictBatchApplyReportSnapshot {
        let itemResults = request.conflictIDs.map { conflictID in
            let type: ImportConflictBatchConflictTypeSnapshot = conflictID.hasPrefix("name")
                ? .sameNameDifferentContent
                : .duplicateHash
            let strategy = type == .duplicateHash ? request.duplicateStrategy : request.sameNameStrategy
            return ImportConflictBatchItemResultSnapshot.testFixture(
                conflictID: conflictID,
                conflictType: type,
                appliedStrategy: strategy,
                status: importConflictBatchResultStatus(for: strategy),
                fileID: strategy == .askPerItem ? nil : 42,
                finalPath: "finance/Invoice_2026Q1.pdf"
            )
        }
        let skippedCount = Int64(itemResults.filter { $0.status == .skipped }.count)
        let keptBothCount = Int64(itemResults.filter { $0.status == .keptBoth }.count)
        let replacedCount = Int64(itemResults.filter { $0.status == .replaced }.count)
        let queuedCount = Int64(itemResults.filter { $0.status == .queuedForPerItem }.count)
        let resolvedCount = skippedCount + keptBothCount + replacedCount
        let count = Int64(request.conflictIDs.count)
        return .testFixture(
            importSessionID: request.importSessionID,
            requestedConflictCount: count,
            resolvedCount: resolvedCount,
            skippedCount: skippedCount,
            keptBothCount: keptBothCount,
            replacedCount: replacedCount,
            queuedForPerItemCount: queuedCount,
            itemResults: itemResults,
            affectedFileIDs: resolvedCount == 0 ? [] : [42],
            undoToken: replacedCount == 0 ? nil : "undo-import-conflict-batch",
            changeLogActions: resolvedCount == 0 ? [] : ["import_conflict_batch"]
        )
    }

    private static func importConflictBatchResultStatus(
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

extension ImportConflictBatchItemResultSnapshot {
    static func testFixture(
        conflictID: String = "dup-1",
        conflictType: ImportConflictBatchConflictTypeSnapshot = .duplicateHash,
        appliedStrategy: ImportConflictBatchStrategySnapshot = .replace,
        status: ImportConflictBatchResultStatusSnapshot = .replaced,
        fileID: Int64? = 42,
        finalPath: String? = "finance/Invoice_2026Q1.pdf",
        error: String? = nil
    ) -> ImportConflictBatchItemResultSnapshot {
        ImportConflictBatchItemResultSnapshot(
            conflictID: conflictID,
            conflictType: conflictType,
            appliedStrategy: appliedStrategy,
            status: status,
            fileID: fileID,
            finalPath: finalPath,
            error: error
        )
    }
}

extension UndoActionRecordSnapshot {
    static func importConflictBatchIntegrationAction() -> UndoActionRecordSnapshot {
        importConflictBatchUndoAction()
    }
}

extension UndoActionResultSnapshot {
    static func importConflictBatchIntegrationResult() -> UndoActionResultSnapshot {
        importConflictBatchUndoResult()
    }
}
